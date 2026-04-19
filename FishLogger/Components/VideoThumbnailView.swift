import SwiftUI
import AVFoundation

/// Generates a thumbnail for a video at ~0.5s in and overlays a play icon.
struct VideoThumbnailView: View {
    let url: URL
    var iconSize: Font = .title2

    @State private var image: UIImage?

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
            Image(systemName: "play.circle.fill")
                .font(iconSize)
                .foregroundStyle(.white.opacity(0.95))
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
        }
        .task(id: url) {
            image = await Self.generate(url)
        }
    }

    private static func generate(_ url: URL) async -> UIImage? {
        await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 512, height: 512)
            let time = CMTime(seconds: 0.5, preferredTimescale: 600)
            do {
                let (cgImage, _) = try await generator.image(at: time)
                return UIImage(cgImage: cgImage)
            } catch {
                return nil
            }
        }.value
    }
}
