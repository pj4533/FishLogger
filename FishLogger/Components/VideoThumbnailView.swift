import SwiftUI
import AVFoundation

/// Generates a thumbnail for a video at ~0.5s in and overlays a play icon.
struct VideoThumbnailView: View {
    let url: URL
    var atSeconds: Double = 0.5
    var iconSize: Font = .title2
    var showPlayIcon: Bool = true

    @State private var image: UIImage?

    private var taskKey: String {
        "\(url.absoluteString)|\(atSeconds)"
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.waterLight.opacity(0.5)
                    .overlay(ProgressView())
            }
            if showPlayIcon {
                Image(systemName: "play.circle.fill")
                    .font(iconSize)
                    .foregroundStyle(.white.opacity(0.95))
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
            }
        }
        .task(id: taskKey) {
            image = await Self.generate(url, atSeconds: atSeconds)
        }
    }

    private static func generate(_ url: URL, atSeconds: Double) async -> UIImage? {
        await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 512, height: 512)
            let time = CMTime(seconds: max(0, atSeconds), preferredTimescale: 600)
            do {
                let (cgImage, _) = try await generator.image(at: time)
                return UIImage(cgImage: cgImage)
            } catch {
                return nil
            }
        }.value
    }
}
