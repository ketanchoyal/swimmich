import SwiftUI
import MapKit

/// Map leg of the live preview: a real 3D MapKit navigation-style chase camera
/// — pitched low toward the horizon, heading following the road, street-level
/// zoom — with the 3D car riding the route ahead of it. The camera geometry is
/// shared with the export (`RoadTripDriveCamera`), which simulates the same
/// driving perspective from 2D snapshots, so the car's position and motion
/// match the exported film.
///
/// Transitions also match the export: the outgoing photo fades out over the
/// first moments of the leg, and the arrival dive (pin pop + destination
/// thumbnail growing to full screen) plays over the leg's tail.
struct RoadTripMapSegment: View {
    let travel: RoadTripTimeline.Travel
    let localTime: TimeInterval
    var token: String?
    /// First photo of the destination stop — dives up from the arrival pin.
    var divePhotoURL: URL?
    /// Last photo of the previous stop — fades out over the map's opening.
    var outgoingPhotoURL: URL?

    /// Densified route polyline (cached per leg — rebuilt when routes upgrade).
    @State private var denseRoute: (count: Int, coords: [CLLocationCoordinate2D])?
    /// Last MapCamera applied, for the dead-zone that stops MapKit re-projecting
    /// every 30 Hz frame (the main source of live-player micro-jitter).
    @State private var cachedCamera: MapCamera?

    var body: some View {
        let timing = RoadTripTravelTiming.frame(travel: travel, localTime: localTime)
        let bearing = RoadTripDriveCamera.carHeading(travel: travel, localTime: localTime)
        let state = RoadTripDriveCamera.cameraState(travel: travel, localTime: localTime)

        ZStack(alignment: .top) {
            mapView(
                car: timing.carCoordinate,
                camera: state.cameraCoordinate,
                bearing: bearing,
                heading: state.bearing,
                lookAhead: state.lookAheadMeters,
                carFraction: timing.routeDrawnFraction
            )
        }
        .background(Color.black)
        .onAppear { refreshDenseRoute() }
        .onChange(of: travel.route.count) { _, _ in refreshDenseRoute() }
        .onChange(of: travel.fromClusterID) { _, _ in cachedCamera = nil }
        .onChange(of: travel.toClusterID) { _, _ in cachedCamera = nil }
    }

    @ViewBuilder
    private func mapView(car: RoutePoint, camera: RoutePoint, bearing: Double, heading: Double, lookAhead: Double, carFraction: Double) -> some View {
        // Street-level chase: distance tracks the look-ahead (constant per
        // leg), heading follows the smoothed road direction, pitched low.
        let cameraPosition = chaseCamera(center: camera.coordinate, heading: heading, lookAhead: lookAhead)
        let coords = routeCoordinates
        let n = coords.count
        let split = n > 1 ? min(max(Int(carFraction * Double(n - 1)), 0), n - 1) : 0
        let traveled = n > 1 ? Array(coords.prefix(split + 1)) : []
        let upcoming = n > 1 ? Array(coords.dropFirst(split)) : []

        MapReader { proxy in
            GeometryReader { geo in
                ZStack {
                    Map(position: Binding(get: { .camera(cameraPosition) }, set: { _ in })) {
                        if traveled.count >= 2 {
                            MapPolyline(coordinates: traveled)
                                .stroke(.black.opacity(0.35), lineWidth: 9)
                            MapPolyline(coordinates: traveled)
                                .stroke(routeBlue.opacity(0.4), lineWidth: 5)
                        }
                        if upcoming.count >= 2 {
                            MapPolyline(coordinates: upcoming)
                                .stroke(.black.opacity(0.35), lineWidth: 9)
                            MapPolyline(coordinates: upcoming)
                                .stroke(.gray.opacity(0.6), lineWidth: 5)
                        }
                        Annotation("", coordinate: car.coordinate) {
                            chaseCar(bearing: bearing, heading: heading, lookAhead: lookAhead)
                        }
                    }
                    .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
                    .id(travel.fromClusterID + travel.toClusterID)

                    overlayMarkers(proxy: proxy, canvas: geo.size)
                }
            }
        }
    }

    /// Start pulse, arrival pin, dive thumbnail and outgoing-photo fade —
    /// projected onto the map via `MapReader` so they follow the live camera.
    @ViewBuilder
    private func overlayMarkers(proxy: MapProxy, canvas: CGSize) -> some View {
        let dive = RoadTripSegue.diveProgress(localTime: localTime, legDuration: travel.duration)

        if let start = travel.route.first, let p = clamp(proxy.convert(start.coordinate, to: .local), canvas: canvas) {
            let pulse = 0.5 + 0.5 * sin(2 * .pi * localTime * 1.2)
            Circle()
                .fill(.white.opacity(0.25 + 0.3 * pulse))
                .frame(width: 32 + pulse * 10, height: 32 + pulse * 10)
                .position(p)
                .allowsHitTesting(false)
            Circle()
                .fill(.white)
                .frame(width: 20, height: 20)
                .position(p)
                .allowsHitTesting(false)
        }

        if dive > 0, let destination = travel.route.last, let p = clamp(proxy.convert(destination.coordinate, to: .local), canvas: canvas) {
            let pop = RoadTripSegue.pinPop(dive)
            ZStack {
                Color.black.opacity(RoadTripSegue.mapFade(dive) * 0.92)
                Circle()
                    .fill(.white)
                    .frame(width: 32 * pop, height: 32 * pop)
                    .position(p)
                Circle()
                    .fill(Color(red: 0.95, green: 0.25, blue: 0.22))
                    .frame(width: 20 * pop, height: 20 * pop)
                    .position(p)
                if let divePhotoURL {
                    let size = CGSize(width: canvas.width * RoadTripSegue.thumbSizeFraction,
                                      height: canvas.width * RoadTripSegue.thumbSizeFraction * 0.75)
                    let rect = RoadTripSegue.thumbnailRect(pinCenter: p, pinSize: size, canvas: canvas, dive: dive)
                    AuthenticatedAsyncImage(url: divePhotoURL, token: token, contentMode: .fill)
                        .frame(width: rect.width, height: rect.height)
                        .clipShape(RoundedRectangle(cornerRadius: dive >= 0.99 ? 0 : 18 * (1 - dive), style: .continuous))
                        .position(x: rect.midX, y: rect.midY)
                        .opacity(RoadTripSegue.thumbnailAlpha(dive))
                }
            }
            .allowsHitTesting(false)
        }

        if let outgoingPhotoURL {
            let alpha = RoadTripSegue.outgoingPhotoAlpha(localTime: localTime)
            if alpha > 0 {
                AuthenticatedAsyncImage(url: outgoingPhotoURL, token: token, contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(alpha)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Clamps a projected map point into the canvas (with the same margins as
    /// the export) so the markers never pop at the screen edge.
    private func clamp(_ point: CGPoint?, canvas: CGSize) -> CGPoint? {
        guard let point, canvas.width > 0 else { return nil }
        return CGPoint(
            x: min(max(point.x, canvas.width * 0.12), canvas.width * 0.88),
            y: min(max(point.y, canvas.height * 0.15), canvas.height * 0.85)
        )
    }

    private var routeBlue: Color { Color(red: 0.10, green: 0.42, blue: 0.90) }

    /// Builds the chase camera, but only updates it when it moved/turned enough
    /// to matter (~5 m / 0.25°) — otherwise MapKit re-projects and stutters.
    /// The pitch blends from street (60°) to top-down (0°) as the leg zooms
    /// out, matching the export's aerial trapezoid.
    private func chaseCamera(center: CLLocationCoordinate2D, heading: Double, lookAhead: Double) -> MapCamera {
        let distance = min(max(lookAhead * 2.0, RoadTripDriveCamera.zoomInMeters * 2.0), RoadTripDriveCamera.maxFitLookAheadMeters * 2.0)
        let pitch = 60.0 * (1.0 - RoadTripDriveCamera.aerialBlend(lookAheadMeters: lookAhead))
        let candidate = MapCamera(
            centerCoordinate: center,
            distance: distance,
            heading: heading * 180 / .pi,
            pitch: pitch
        )
        guard let last = cachedCamera else {
            cachedCamera = candidate
            return candidate
        }
        let dLat = abs(last.centerCoordinate.latitude - candidate.centerCoordinate.latitude)
        let dLon = abs(last.centerCoordinate.longitude - candidate.centerCoordinate.longitude)
        let dHead = abs(last.heading - candidate.heading)
        let dDist = abs(last.distance - candidate.distance)
        let moved = dLat > 0.00005 || dLon > 0.00005
        let turned = dHead > 0.25
        let zoomed = dDist > 25
        guard moved || turned || zoomed else { return last }
        cachedCamera = candidate
        return candidate
    }

    /// Route polyline: densified once per leg (~40 m spacing) so the road
    /// looks smooth at the driving view's zoom.
    private var routeCoordinates: [CLLocationCoordinate2D] {
        if let denseRoute, denseRoute.count == travel.route.count { return denseRoute.coords }
        return travel.route.map(\.coordinate)
    }

    private func refreshDenseRoute() {
        let cumulative = RoadTripTravelTiming.cumulativeLengths(travel.route)
        let total = cumulative.last ?? 0
        let fractions = cumulative.map { total > 0 ? $0 / total : 0 }
        let dense = RoadTripDriveCamera.densified(route: travel.route, fractions: fractions, spacing: 40)
        denseRoute = (travel.route.count, dense.points.map { $0.coordinate })
    }

    /// Rear 3/4 view of the 3D car with a soft ground shadow, anchored so its
    /// ground contact sits on the map coordinate. Map annotations stay
    /// screen-aligned, so the sprite's yaw compensates the perspective
    /// compression of the RELATIVE bearing (true bearing minus the camera
    /// heading) — nose + body end up exactly on the road as seen on screen.
    private func chaseCar(bearing: Double, heading: Double, lookAhead: Double) -> some View {
        let contact = RoadTripCar3D.chaseContactFraction
        let scale = RoadTripDriveCamera.carSpriteScale(lookAheadMeters: lookAhead)
        let height: CGFloat = 164 * scale
        let yaw = RoadTripCar3D.chaseYaw(forScreenAngle: bearing - heading)
        let frameYaw = RoadTripCar3D.chaseNearestYaw(yaw)
        return ZStack {
            Ellipse()
                .fill(.black.opacity(0.26))
                .frame(width: 120 * scale, height: 22 * scale)
                .blur(radius: 3)
                .offset(y: 4 * scale)
            Image(decorative: RoadTripCar3D.chaseSprite(forBearing: frameYaw), scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 164 * scale, height: height)
                .offset(y: (0.5 - contact) * height)
                .rotationEffect(.radians(yaw - frameYaw))
        }
    }
}
