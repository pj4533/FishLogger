import Foundation
import AVFoundation
import OSLog

/// Captures microphone audio as PCM16 mono @ 24 kHz for the Realtime API and
/// plays back the model's PCM16 responses. Pure AVFoundation — no dependencies.
/// `.voiceChat` mode gives hardware echo cancellation so the model doesn't hear
/// itself.
///
/// The capture tap runs on an audio thread, so the handful of fields it touches
/// are `nonisolated(unsafe)` (the standard escape hatch for real-time audio).
@MainActor
final class RealtimeAudioEngine {
    enum AudioError: Error { case micPermissionDenied }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    /// 24 kHz mono float buffers feed the player; the mixer resamples to hardware.
    private let playbackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                               sampleRate: Double(RealtimeClient.sampleRate),
                                               channels: 1, interleaved: false)!

    nonisolated(unsafe) private var captureConverter: AVAudioConverter?
    nonisolated(unsafe) private var captureFormat: AVAudioFormat?
    nonisolated(unsafe) private var sink: (@Sendable (Data) -> Void)?
    nonisolated(unsafe) private var muted = false

    private let log = Logger.assistant

    var isMuted: Bool {
        get { muted }
        set { muted = newValue }
    }

    /// Starts capture + playback. Throws if mic permission is denied.
    func start(sink: @escaping @Sendable (Data) -> Void) async throws {
        guard await Self.requestMicPermission() else { throw AudioError.micPermissionDenied }
        self.sink = sink
        self.muted = false

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .voiceChat,
                                     options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true)

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        captureFormat = inputFormat
        let target = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                   sampleRate: Double(RealtimeClient.sampleRate),
                                   channels: 1, interleaved: true)!
        captureConverter = AVAudioConverter(from: inputFormat, to: target)

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processCapturedBuffer(buffer, target: target)
        }

        engine.prepare()
        try engine.start()
        player.play()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        player.stop()
        engine.stop()
        sink = nil
        captureConverter = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    /// Schedules a PCM16 (24 kHz mono) chunk from the server for playback.
    func enqueue(_ pcm16: Data) {
        // Ignore audio that arrives before/after the engine is running (e.g. the
        // text-only debug path never starts capture/playback).
        guard engine.isRunning, player.engine != nil, !pcm16.isEmpty else { return }
        let frameCount = pcm16.count / 2
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: AVAudioFrameCount(frameCount)),
              let channel = buffer.floatChannelData else { return }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        pcm16.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            let out = channel[0]
            for i in 0..<frameCount {
                out[i] = Float(Int16(littleEndian: samples[i])) / 32_768.0
            }
        }
        player.scheduleBuffer(buffer, completionHandler: nil)
    }

    // MARK: - Capture (audio thread)

    nonisolated private func processCapturedBuffer(_ buffer: AVAudioPCMBuffer, target: AVAudioFormat) {
        guard !muted, let converter = captureConverter, let sink else { return }

        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }

        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        if error != nil || out.frameLength == 0 { return }

        guard let int16 = out.int16ChannelData else { return }
        let byteCount = Int(out.frameLength) * 2
        let data = Data(bytes: int16[0], count: byteCount)
        sink(data)
    }

    private static func requestMicPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in cont.resume(returning: granted) }
        }
    }
}
