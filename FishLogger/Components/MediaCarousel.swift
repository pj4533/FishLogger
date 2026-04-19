import SwiftUI

/// Pageable gallery showing every photo/video attached to a catch.
/// Used as the hero block on `CatchDetailView`.
struct MediaCarousel: View {
    let assets: [MediaAsset]
    var height: CGFloat = 280

    var body: some View {
        if assets.isEmpty {
            EmptyView()
        } else {
            TabView {
                ForEach(assets) { asset in
                    MediaCarouselPage(asset: asset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: assets.count > 1 ? .always : .never))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))
            .frame(height: height)
            .background(Color.waterDeep.opacity(0.2))
        }
    }
}

private struct MediaCarouselPage: View {
    let asset: MediaAsset

    var body: some View {
        switch asset.kind {
        case .photo:
            AsyncImageFromURL(url: asset.url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        case .video:
            VideoPlayerInline(url: asset.url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
