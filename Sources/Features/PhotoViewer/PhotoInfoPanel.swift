import SwiftUI
import MapKit

/// Slide-up EXIF info panel (Photos-style): drag handle, date/location header,
/// scrollable EXIF rows + map. Anchored to the viewer's bottom edge at
/// `heightFactor` of the screen; PhotoViewer owns the slide/close animation
/// and the per-asset `AssetDetailViewModel` (refetched on page change).
struct PhotoInfoPanel: View {
    /// Panel height as a fraction of the screen (Photos uses ~70%).
    static let heightFactor: CGFloat = 0.7

    let asset: AssetReactItem
    let client: any ImmichClient
    let vm: AssetDetailViewModel?
    let panelHeight: CGFloat
    /// True while the panel is on screen (open or mid-drag) — the top shadow
    /// is dropped when it rests fully below the screen edge so no artefact
    /// pokes above it.
    let isPresented: Bool
    var onClose: () -> Void = {}
    var onSnapBack: () -> Void = {}
    var onDragChange: (CGFloat) -> Void = { _ in }

    var body: some View {
        VStack(spacing: PVSpacing.s0) {
            handle
                .padding(.top, PVSpacing.s8)
            header
                .padding(.horizontal, PVSpacing.s16)
                .padding(.vertical, PVSpacing.s8)
            content
        }
        .background(.regularMaterial)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: PVRadius.lg,
                bottomLeadingRadius: PVRadius.none,
                bottomTrailingRadius: PVRadius.none,
                topTrailingRadius: PVRadius.lg,
                style: .continuous
            )
        )
        .modifier(InfoShadowModifier(isPresented: isPresented))
    }

    /// Grab handle — dragging it down closes the panel (thresholds shared with
    /// the viewer's own swipe-down close).
    private var handle: some View {
        Capsule()
            .fill(Color.white.opacity(0.4))
            .frame(width: 36, height: 5)
            .gesture(
                DragGesture()
                    .onChanged { onDragChange($0.translation.height) }
                    .onEnded { value in
                        let progress = value.translation.height / panelHeight
                        let velocity = value.predictedEndTranslation.height - value.translation.height
                        if PhotoViewerSwipeDecision.shouldClose(progress: progress, velocity: velocity) {
                            onClose()
                        } else {
                            onSnapBack()
                        }
                    }
            )
            .accessibilityLabel("Details")
    }

    private var header: some View {
        HStack(spacing: PVSpacing.s16) {
            VStack(alignment: .leading, spacing: 2) {
                if let exif = vm?.detail?.exifInfo, let place = placeLabel(exif: exif) {
                    Text(place)
                        .font(.pvH6)
                        .foregroundStyle(Color.textPrimaryPV)
                        .lineLimit(1)
                }
                Text(headerDate)
                    .font(.pvSubhead)
                    .foregroundStyle(Color.textSecondaryPV)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "chevron.down")
                    .font(.pvHeadline)
                    .foregroundStyle(Color.textPrimaryPV)
                    .frame(width: 40, height: 40)
                    .glassEffect(.regular, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close details")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let detail = vm?.detail, let exif = detail.exifInfo {
            ScrollView {
                ExifInfoPanel(
                    exif: exif,
                    placeName: placeLabel(exif: exif),
                    fallbackLatitude: asset.latitude,
                    fallbackLongitude: asset.longitude
                )
                .padding(.horizontal, PVSpacing.s16)
                .padding(.bottom, PVSpacing.s24)
            }
        } else if let error = vm?.errorMessage {
            Text(error)
                .font(.pvCaption)
                .foregroundStyle(Color.immichError)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Photos-style header date: EXIF date + time when available ("1 août 2026,
    /// 14:32"), else the long-form file creation date.
    private var headerDate: String {
        vm?.detail?.exifInfo?.dateFormatted ?? dateLabel
    }

    /// Reverse-geocoded place, else EXIF place, else the list item's place.
    private func placeLabel(exif: ExifResponseDto) -> String? {
        if let place = vm?.placeName, !place.isEmpty { return place }
        if let city = exif.city ?? asset.city, !city.isEmpty { return city }
        if let country = exif.country ?? asset.country, !country.isEmpty { return country }
        return nil
    }

    /// Long-form localized date for the current photo ("July 29, 2024").
    private var dateLabel: String {
        LongDateFormatter.format(isoPrefix: asset.fileCreatedAt)
    }
}

/// Applies the top shadow only while the panel is presented — a resting
/// (fully off-screen) panel must cast nothing above the screen edge.
private struct InfoShadowModifier: ViewModifier {
    let isPresented: Bool

    func body(content: Content) -> some View {
        if isPresented {
            content.shadow(color: .black.opacity(0.35), radius: 16, y: -4)
        } else {
            content
        }
    }
}

/// EXIF info grouped into Photos-style rounded cards. Each card holds an
/// adaptive icon+value grid (wrap-around automatic; long values truncate
/// with "…"). Cards with no data are dropped entirely. AC-202: ≥12 rows
/// covered.
struct ExifInfoPanel: View {
    let exif: ExifResponseDto
    let placeName: String?
    let fallbackLatitude: Double?
    let fallbackLongitude: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: PVSpacing.s12) {
            if !cameraItems.isEmpty { InfoCard { InfoGrid(items: cameraItems) } }
            if !fileItems.isEmpty { InfoCard { InfoGrid(items: fileItems) } }
            if !whenItems.isEmpty { InfoCard { InfoGrid(items: whenItems) } }
            whereCard
            descriptionCard
        }
    }

    private var cameraItems: [(symbol: String, value: String)] {
        [
            ("camera.fill", exif.cameraFormatted),
            ("scope", exif.focalLengthFormatted),
            ("camera.aperture", exif.apertureFormatted),
            ("speedometer", exif.isoFormatted),
            ("timer", exif.exposureFormatted),
        ].compactMap { symbol, value in value.map { (symbol, $0) } }
    }

    private var fileItems: [(symbol: String, value: String)] {
        [
            ("photo", exif.dimensionsFormatted),
            ("internaldrive.fill", exif.fileSizeFormatted),
            ("aspectratio", exif.orientation),
            ("viewfinder", exif.projectionType),
            ("star.fill", exif.rating.map { String($0) }),
        ].compactMap { symbol, value in value.map { (symbol, $0) } }
    }

    private var whenItems: [(symbol: String, value: String)] {
        [
            ("calendar", exif.dateFormatted),
            ("globe", exif.timeZone),
        ].compactMap { symbol, value in value.map { (symbol, $0) } }
    }

    private var whereItems: [(symbol: String, value: String)] {
        [("location.fill", placeName ?? exif.city ?? exif.country)]
            .compactMap { symbol, value in value.map { (symbol, $0) } }
    }

    /// Where card — location grid + embedded map. The map uses EXIF coords
    /// first, else the list item's (bucket response), else none.
    @ViewBuilder
    private var whereCard: some View {
        let lat = exif.latitude ?? fallbackLatitude
        let lon = exif.longitude ?? fallbackLongitude
        if !whereItems.isEmpty || lat != nil {
            InfoCard {
                VStack(spacing: 0) {
                    if !whereItems.isEmpty {
                        InfoGrid(items: whereItems)
                    }
                    if let lat, let lon {
                        if !whereItems.isEmpty {
                            InfoCardDivider()
                        }
                        MiniMapView(latitude: lat, longitude: lon)
                            .frame(height: 180)
                    }
                }
            }
        }
    }

    /// Free-text description on its own card (Photos-style), when present.
    @ViewBuilder
    private var descriptionCard: some View {
        if let desc = exif.description {
            InfoCard {
                VStack(alignment: .leading, spacing: PVSpacing.s4) {
                    Label("Description", systemImage: "doc.text")
                        .font(.pvBody)
                        .foregroundStyle(Color.textSecondaryPV)
                    Text(desc)
                        .font(.pvBody)
                        .foregroundStyle(Color.textPrimaryPV)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(PVSpacing.s16)
            }
        }
    }
}

/// A rounded group (gray translucent background, Photos-style) wrapping any
/// content — grid, map, or text. Cards with no data are not rendered at all.
private struct InfoCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .background(Color.gray.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: PVRadius.md, style: .continuous))
    }
}

/// Icon + value grid: items spread evenly ("space evenly"), wrap-around
/// automatic, long values truncated with "…". Single-line sections render as
/// a natural-size centered HStack; multiline sections use a plain leading
/// grid (wrap stays aligned with the row above — no lopsided centering).
private struct InfoGrid: View {
    let items: [(symbol: String, value: String)]

    /// Min item width + spacing — mirrors the `GridItem(.adaptive(minimum:))`
    /// math so the computed column count matches the rendered grid.
    private static let minItemWidth: CGFloat = 96
    private static let columnSpacing: CGFloat = PVSpacing.s8
    /// Panel horizontal padding (16 + 16) applied to the grid's parent card.
    private static let panelInsets: CGFloat = PVSpacing.s16 * 2

    private var columnCount: Int {
        let available = UIScreen.main.bounds.width - Self.panelInsets
        return max(1, Int((available + Self.columnSpacing) / (Self.minItemWidth + Self.columnSpacing)))
    }

    @ViewBuilder
    var body: some View {
        if items.count <= columnCount {
            // Single line — natural-size items spread across the FULL width
            // (flexible spacers), so a short section doesn't cluster in the
            // middle with cramped gaps: one item centers, two go to the edges.
            HStack(spacing: 0) {
                Spacer(minLength: PVSpacing.s8)
                ForEach(items.indices, id: \.self) { i in
                    if i > 0 { Spacer(minLength: PVSpacing.s24) }
                    InfoGridItem(symbol: items[i].symbol, value: items[i].value)
                        .fixedSize()
                }
                Spacer(minLength: PVSpacing.s8)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, PVSpacing.s16)
            .padding(.vertical, PVSpacing.s8)
        } else {
            // Multiline — plain leading grid; wrapped rows align with the row
            // above (standard grid look, no phantom-cell shuffling).
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Self.columnSpacing), count: columnCount),
                alignment: .leading,
                spacing: PVSpacing.s12
            ) {
                ForEach(items.indices, id: \.self) { i in
                    InfoGridItem(symbol: items[i].symbol, value: items[i].value)
                }
            }
            .padding(.horizontal, PVSpacing.s16)
            .padding(.vertical, PVSpacing.s8)
        }
    }
}

/// Icon above value — the icon carries the meaning (no label), the value is
/// the anchor: medium-weight primary text, one line, "…" when too long.
private struct InfoGridItem: View {
    let symbol: String
    let value: String

    var body: some View {
        VStack(spacing: PVSpacing.s4) {
            Image(systemName: symbol)
                .font(.pvBody)
                .foregroundStyle(Color.immichPrimary)
            Text(value)
                .font(.pvCaption.weight(.medium))
                .foregroundStyle(Color.textPrimaryPV)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PVSpacing.s4)
    }
}

/// Hairline separator inside an info card (e.g. between the location grid and
/// the map).
private struct InfoCardDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(height: 0.5)
            .padding(.horizontal, PVSpacing.s16)
    }
}

/// Non-interactive MapKit snapshot view (VM-1) with a branded pin.
///
/// UIKit-backed (`MKMapView` + `MKMarkerAnnotationView`, same mechanism as the
/// search map): the SwiftUI `Map` silently drops its annotations when
/// hit-testing is disabled (panel context), while the UIKit renderer always
/// draws the pin. cornerRadius 0 per Timeline tweak consistency (NOT 12pt).
struct MiniMapView: UIViewRepresentable {
    let latitude: Double
    let longitude: Double

    private static let reuseID = "miniMapPin"

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let map = MKMapView()
        map.delegate = context.coordinator
        map.mapType = .satellite
        map.isScrollEnabled = false
        map.isZoomEnabled = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.isUserInteractionEnabled = false
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Self.reuseID)
        map.setRegion(
            MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ),
            animated: false
        )
        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        map.addAnnotation(annotation)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        // Static snapshot — nothing to update.
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: MiniMapView.reuseID, for: annotation) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: MiniMapView.reuseID)
            view.annotation = annotation
            view.markerTintColor = UIColor(Color.immichPrimary)
            view.glyphImage = UIImage(systemName: "mappin")
            return view
        }
    }
}
