import SwiftUI
import AVKit
import AVFoundation

/// Lets the user scrub a video and pick a frame to use as its still thumbnail.
/// The AVKit VideoPlayer provides the scrubber; we just read `currentTime()`
/// when the user taps "Use this frame."
struct ThumbnailPickerView: View {
    let assetURL: URL
    let initialSeconds: Double
    let onConfirm: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var duration: Double = 0
    @State private var isScrubbing = false
    @State private var snapshotSeconds: Double
    @State private var snapshot: UIImage?

    init(assetURL: URL, initialSeconds: Double, onConfirm: @escaping (Double) -> Void) {
        self.assetURL = assetURL
        self.initialSeconds = initialSeconds
        self.onConfirm = onConfirm
        _snapshotSeconds = State(initialValue: max(0, initialSeconds))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                videoArea
                livePreviewStrip
                captureButton
                Text("Scrub to the moment you want, then lock it in.")
                    .font(.cozyCaption)
                    .foregroundStyle(Color.inkFaded)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle("Pick Thumbnail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await setupPlayer() }
            .onDisappear {
                player?.pause()
                player = nil
            }
        }
    }

    // MARK: - Subviews

    private var videoArea: some View {
        ZStack {
            Color.black
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView().tint(.white)
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.bark, lineWidth: 2)
        )
        .padding(.horizontal, 16)
    }

    private var livePreviewStrip: some View {
        VStack(spacing: 6) {
            Text("CURRENT FRAME")
                .font(.fieldLabel)
                .foregroundStyle(Color.inkFaded)
            HStack(spacing: 12) {
                VideoThumbnailView(
                    url: assetURL,
                    atSeconds: snapshotSeconds,
                    showPlayIcon: false
                )
                .frame(width: 96, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.bark.opacity(0.5), lineWidth: 1.5)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(format(snapshotSeconds))
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.ink)
                    Text("of \(format(duration))")
                        .font(.cozyCaption)
                        .foregroundStyle(Color.inkFaded)
                }
                Spacer()
                Button {
                    Task { await snapshotCurrentPlayerTime() }
                } label: {
                    Label("Snapshot", systemImage: "camera.viewfinder")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.moss))
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.paperDeep)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.bark.opacity(0.5), lineWidth: 1.5)
            )
        }
        .padding(.horizontal, 16)
    }

    private var captureButton: some View {
        Button {
            onConfirm(snapshotSeconds)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "photo.on.rectangle.angled")
                Text("Use this frame")
                    .font(.system(.title3, design: .rounded, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Capsule(style: .continuous).fill(Color.sunset))
        }
        .padding(.horizontal, 16)
        .sensoryFeedback(.success, trigger: snapshotSeconds)
    }

    // MARK: - Helpers

    private func setupPlayer() async {
        let urlAsset = AVURLAsset(url: assetURL)
        if let cm = try? await urlAsset.load(.duration) {
            duration = CMTimeGetSeconds(cm)
        }
        let p = AVPlayer(url: assetURL)
        let seekTime = CMTime(seconds: max(0, initialSeconds), preferredTimescale: 600)
        await p.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
        p.pause()
        player = p
    }

    private func snapshotCurrentPlayerTime() async {
        guard let player else { return }
        player.pause()
        let t = CMTimeGetSeconds(player.currentTime())
        if t.isFinite { snapshotSeconds = max(0, t) }
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
