import SwiftUI
import MapKit

/// Map segment for the Search tab — MKMapView with real marker clustering
/// (MKMarkerAnnotationView.clusteringIdentifier) + a bottom photo sheet of the
/// assets inside the currently visible region.
///
/// Clustering handled by MapKit because SwiftUI's `Map` (iOS 17) has no
/// native clustering; large libraries can reach thousands of markers.
///
/// Performance: the wrapper only ever displays the *culled* subset
/// (`vm.visibleAnnotations`), so MapKit never receives the full library.
struct MapSegmentView: View {
    @Bindable var vm: MapViewModel
    @State private var isPhotosSheetPresented = false

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let msg = vm.errorMessage, vm.markers.isEmpty {
                    errorView(msg)
                } else {
                    mapContent
                }
            }
            .task {
                // AC-710: load markers once per VM lifetime.
                await vm.loadMarkers()
            }
            .onChange(of: vm.visiblePhotos.isEmpty) { _, isEmpty in
                isPhotosSheetPresented = !isEmpty
            }
            .sheet(isPresented: $isPhotosSheetPresented) {
                MapPhotosSheet(vm: vm)
                    // Fixed height: exactly one third of the screen. Single
                    // detent → no grabber expansion, stays out of the map's way.
                    .presentationDetents([.height(proxy.size.height / 3), .medium])
                    .presentationBackgroundInteraction(.enabled)
                    .presentationBackground(.regularMaterial)
            }
        }
    }

    private var mapContent: some View {
        ZStack(alignment: .top) {
            ClusteredMapView(
                markers: vm.markers,
                annotations: vm.visibleAnnotations,
                onVisibleRectChanged: { rect in
                    // MKMapView delegate callbacks are non-isolated; hop to
                    // the MainActor ViewModel.
                    Task { @MainActor in vm.setVisibleRect(rect) }
                }
            )
            .ignoresSafeArea(edges: .bottom)

            if vm.isLoading && vm.markers.isEmpty {
                HStack(spacing: PVSpacing.s8) {
                    ProgressView()
                    Text("Loading photos…")
                        .font(.pvSubhead)
                        .foregroundStyle(Color.textSecondaryPV)
                }
                .padding(.horizontal, PVSpacing.s16)
                .padding(.vertical, PVSpacing.s8)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, PVSpacing.s12)
            }
        }
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: PVSpacing.s12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.pvTitle)
                .foregroundStyle(Color.statusPending)
            Text(msg)
                .font(.pvBody)
                .foregroundStyle(Color.textSecondaryPV)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await vm.reload() }
            }
            .buttonStyle(PVPrimaryButtonStyle())
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Bottom sheet showing the photos inside the current map region as a
/// vertically scrollable 3-column grid. Works at every detent (collapsed =
/// header + one row, large = full-screen browsing).
struct MapPhotosSheet: View {
    let vm: MapViewModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: PVSpacing.s2), count: 3)

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: PVSpacing.s12) {
                HStack(spacing: PVSpacing.s8) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(Color.brandIndigo)
                    Text(placeName)
                        .font(.pvHeadline)
                        .lineLimit(1)
                    Spacer()
                    Text("\(vm.visiblePhotos.count) photos")
                        .font(.pvSubhead)
                        .foregroundStyle(Color.textSecondaryPV)
                }
                .padding(.horizontal)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: PVSpacing.s2) {
                        ForEach(vm.visiblePhotos) { photo in
                            NavigationLink {
                                AssetDetailView(asset: photo.asAssetItem)
                            } label: {
                                MapThumb(photo: photo)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(photo.placeName.isEmpty ? "Photo" : "Photo at \(photo.placeName)")
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, PVSpacing.s12)
                }
            }
            .padding(.top, PVSpacing.s12)
        }
    }

    /// First non-empty place name among the visible photos, else a generic label.
    private var placeName: String {
        vm.visiblePhotos.lazy.compactMap(\.placeName).first { !$0.isEmpty } ?? "This area"
    }
}

/// Square thumbnail for a map photo, filling its grid column width.
/// Authenticated via bearer token like the timeline grid cells.
private struct MapThumb: View {
    let photo: MapPhoto
    @Environment(AuthViewModel.self) private var auth

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                AuthenticatedAsyncImage(
                    url: photo.asAssetItem.thumbnailURL(base: auth.baseURL ?? URL(string: "https://example.com")!),
                    token: auth.accessToken
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: PVRadius.md, style: .continuous))
    }
}

/// `MKAnnotation` carrier wrapping a `MapPhoto` (non-Sendable, UIKit-owned).
private final class PhotoAnnotation: NSObject, MKAnnotation {
    let photo: MapPhoto
    init(photo: MapPhoto) {
        self.photo = photo
        super.init()
    }
    var coordinate: CLLocationCoordinate2D { photo.coordinate }
    var title: String? { photo.placeName.isEmpty ? nil : photo.placeName }
}

/// UIViewRepresentable MKMapView with MKMarkerAnnotationView clustering.
///
/// Displays only the culled `annotations` (diffed against the live MKMapView
/// annotation set), fits to all markers once on first load, and reports the
/// visible region to SwiftUI via `onVisibleRectChanged` (the ViewModel
/// debounces + filters).
struct ClusteredMapView: UIViewRepresentable {
    /// Full marker set — used once to compute the initial fit.
    let markers: [MapPhoto]
    /// Culled subset to display (region + margin), produced by the ViewModel.
    let annotations: [MapPhoto]
    let onVisibleRectChanged: (MKMapRect) -> Void

    private static let photoReuseID = "photoMarker"
    private static let clusterReuseID = "photoCluster"

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.mapType = .standard
        map.showsUserLocation = false
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Self.photoReuseID)
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Self.clusterReuseID)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        // Fit to all markers once (first load). Then force a region callback
        // so culling kicks in even if the programmatic fit doesn't fire the
        // delegate's visible-region change.
        if !coordinator.didFitInitial, !markers.isEmpty {
            let rect = markers.reduce(MKMapRect.null) { partial, photo in
                let pt = MKMapPoint(photo.coordinate)
                return partial.union(MKMapRect(x: pt.x - 1, y: pt.y - 1, width: 2, height: 2))
            }
            map.setVisibleMapRect(
                rect,
                edgePadding: UIEdgeInsets(top: 60, left: 60, bottom: 60, right: 60),
                animated: false
            )
            coordinator.didFitInitial = true
            context.coordinator.parent.onVisibleRectChanged(map.visibleMapRect)
        }

        // Diff the live annotation set against the desired (culled) set.
        let current = Set(map.annotations.compactMap { ($0 as? PhotoAnnotation)?.photo.id })
        let desired = Set(annotations.map(\.id))
        guard current != desired else { return }

        let toRemove = map.annotations.filter { annotation in
            guard let photoAnno = annotation as? PhotoAnnotation else { return false }
            return !desired.contains(photoAnno.photo.id)
        }
        if !toRemove.isEmpty {
            map.removeAnnotations(toRemove)
        }
        let toAdd = annotations.filter { !current.contains($0.id) }
        if !toAdd.isEmpty {
            map.addAnnotations(toAdd.map(PhotoAnnotation.init(photo:)))
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: ClusteredMapView
        var didFitInitial = false

        init(_ parent: ClusteredMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: ClusteredMapView.clusterReuseID,
                    for: cluster
                ) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: cluster, reuseIdentifier: ClusteredMapView.clusterReuseID)
                view.annotation = cluster
                view.clusteringIdentifier = ClusteredMapView.photoReuseID
                view.markerTintColor = .systemIndigo
                view.glyphText = "\(cluster.memberAnnotations.count)"
                view.displayPriority = .required
                view.canShowCallout = true
                return view
            }
            if let photoAnno = annotation as? PhotoAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: ClusteredMapView.photoReuseID,
                    for: photoAnno
                ) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: photoAnno, reuseIdentifier: ClusteredMapView.photoReuseID)
                view.annotation = photoAnno
                view.clusteringIdentifier = ClusteredMapView.photoReuseID
                view.markerTintColor = .systemIndigo
                view.glyphImage = UIImage(systemName: "photo")
                view.canShowCallout = true
                return view
            }
            return nil
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            parent.onVisibleRectChanged(mapView.visibleMapRect)
        }
    }
}
