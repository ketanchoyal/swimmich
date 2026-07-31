import SwiftUI
import MapKit

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
        // AC-613: editor entry. AssetDetailView had no `.toolbar` before — added after .navigationBarTitleDisplayMode.
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    PhotoEditorView(vm: DependencyContainer.shared.makePhotoEditorViewModel(asset: asset))
                } label: {
                    Label("Edit", systemImage: "slider.horizontal.3")
                }
                .accessibilityIdentifier("editButton")
            }
        }
    }

    @ViewBuilder
    private func content(vm: AssetDetailViewModel) -> some View {
        @Bindable var auth = auth
        // VM-3: scroll so tall EXIF panels (≥12 rows) never overflow.
        ScrollView {
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
                    ExifInfoPanel(exif: exif, placeName: vm.placeName).padding(.horizontal)
                }
                if let err = vm.errorMessage {
                    Text(err).foregroundStyle(Color.statusError).padding()
                }
            }
        }
    }
}

/// Full EXIF panel. AC-202: ≥12 `LabeledContent`. AC-203: MiniMapView conditional on lat/lon.
struct ExifInfoPanel: View {
    let exif: ExifResponseDto
    let placeName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: PVSpacing.s8) {
            if let camera = exif.cameraFormatted { LabeledContent("Camera", value: camera) }
            if let lens = exif.lensModel { LabeledContent("Lens", value: lens) }
            if let fl = exif.focalLengthFormatted { LabeledContent("Focal Length", value: fl) }
            if let ap = exif.apertureFormatted { LabeledContent("Aperture", value: ap) }
            if let iso = exif.isoFormatted { LabeledContent("ISO", value: iso) }
            if let exp = exif.exposureFormatted { LabeledContent("Exposure", value: exp) }
            if let dims = exif.dimensionsFormatted { LabeledContent("Dimensions", value: dims) }
            if let size = exif.fileSizeFormatted { LabeledContent("File Size", value: size) }
            if let orient = exif.orientation { LabeledContent("Orientation", value: orient) }
            if let date = exif.dateFormatted { LabeledContent("Date", value: date) }
            if let tz = exif.timeZone { LabeledContent("Time Zone", value: tz) }
            if let proj = exif.projectionType { LabeledContent("Projection", value: proj) }
            if let rating = exif.rating { LabeledContent("Rating", value: "\(rating)") }
            if let desc = exif.description { LabeledContent("Description", value: desc) }
            if let loc = placeName ?? exif.city ?? exif.country { LabeledContent("Location", value: loc) }

            // AC-203: Map shown only when both coordinates present.
            if let lat = exif.latitude, let lon = exif.longitude {
                MiniMapView(latitude: lat, longitude: lon)
                if let place = placeName {
                    Text(place)
                        .font(.pvCaption)
                        .foregroundStyle(Color.textSecondaryPV)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// Non-interactive MapKit snapshot view (VM-1).
/// cornerRadius 0 per Timeline tweak consistency (NOT 12pt).
struct MiniMapView: View {
    let latitude: Double
    let longitude: Double

    var body: some View {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        Map(initialPosition: .region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))) {
            Marker("", coordinate: coordinate)
        }
        .mapStyle(.imagery(elevation: .realistic))
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: PVRadius.none))
        .allowsHitTesting(false)
    }
}
