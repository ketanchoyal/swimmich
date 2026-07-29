import SwiftUI

struct AssetDetailView: View {
    let asset: AssetReactItem
    let client: any ImmichClient
    @Environment(AuthViewModel.self) private var auth
    @State private var vm: AssetDetailViewModel?

    init(asset: AssetReactItem, client: any ImmichClient = DependencyContainer.shared.client) {
        self.asset = asset
        self.client = client
    }

    var body: some View {
        Group {
            if let vm {
                content(vm: vm)
            } else {
                ProgressView()
                    .task {
                        let new = AssetDetailViewModel(asset: asset, client: client)
                        vm = new
                        await new.loadDetail()
                    }
            }
        }
        .navigationTitle(asset.fileCreatedAt.prefix(10).description)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(vm: AssetDetailViewModel) -> some View {
        @Bindable var auth = auth
        VStack {
            AuthenticatedAsyncImage(
                url: asset.thumbnailURL(base: auth.baseURL ?? URL(string: "https://example.com")!, size: .preview),
                token: auth.accessToken
            )
            .aspectRatio(CGFloat(asset.aspectRatio), contentMode: .fit)

            HStack(spacing: 24) {
                Button {
                    Task { await vm.toggleFavorite() }
                } label: {
                    Label("Favorite", systemImage: vm.isFavorite ? "heart.fill" : "heart")
                }
            }
            .padding()

            if let detail = vm.detail, let exif = detail.exifInfo {
                MetadataSheet(exif: exif, asset: asset).padding(.horizontal)
            }
            if let err = vm.errorMessage {
                Text(err).foregroundStyle(.red).padding()
            }
        }
    }
}

struct MetadataSheet: View {
    let exif: ExifResponseDto
    let asset: AssetReactItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let make = exif.make { LabeledContent("Camera", value: "\(make) \(exif.model ?? "")") }
            if let lens = exif.lensModel { LabeledContent("Lens", value: lens) }
            if let f = exif.fNumber { LabeledContent("Aperture", value: String(format: "f/%.1f", f)) }
            if let iso = exif.iso { LabeledContent("ISO", value: "\(iso)") }
            if let exp = exif.exposureTime { LabeledContent("Exposure", value: exp) }
            if let city = exif.city ?? asset.city { LabeledContent("Location", value: city) }
        }
    }
}
