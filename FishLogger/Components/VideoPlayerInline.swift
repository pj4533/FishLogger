import SwiftUI
import AVKit

/// In-app video player. Uses AVKit's `VideoPlayer` so you get the standard
/// controls (play/pause, scrub, full-screen, AirPlay) for free. Pauses and
/// releases the player when the view disappears so it doesn't keep decoding
/// off-screen.
struct VideoPlayerInline: View {
    let url: URL

    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.waterDeep
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .onAppear {
            if player == nil { player = AVPlayer(url: url) }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
