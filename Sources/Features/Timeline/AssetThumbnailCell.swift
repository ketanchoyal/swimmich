import SwiftUI

/// Thumbnail image cell. Renders at the asset's aspect ratio using the
/// authenticated thumbnail endpoint.
struct AssetThumbnailCell: View {
    let asset: AssetReactItem
    let baseURL: URL
    let token: String?

    var body: some View {
        let url = asset.thumbnailURL(base: baseURL)
        AuthenticatedAsyncImage(url: url, token: token)
            .aspectRatio(CGFloat(asset.aspectRatio), contentMode: .fill)
            .clipped()
            .overlay(alignment: .topTrailing) {
                if asset.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .shadow(radius: 1)
                        .padding(4)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if asset.isVideo {
                    Image(systemName: "play.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .shadow(radius: 1)
                        .padding(4)
                }
            }
    }
}
