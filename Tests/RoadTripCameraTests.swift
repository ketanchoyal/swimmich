import XCTest
import CoreGraphics
import MapKit
@testable import ImmichSwiftUI

final class RoadTripCameraTests: XCTestCase {

    /// Eastward route along lat 48.85 (~73 km per degree of longitude here).
    private func makeTravel(distanceMeters: Double = 30_000, duration: TimeInterval = 4) -> RoadTripTimeline.Travel {
        let lat = 48.85
        let degPerMeter = 1.0 / (111_320.0 * cos(lat * .pi / 180))
        let count = 30
        let route = (0..<count).map { i in
            RoutePoint(
                latitude: lat,
                longitude: 2.29 + Double(i) / Double(count - 1) * distanceMeters * degPerMeter
            )
        }
        return RoadTripTimeline.Travel(
            fromClusterID: "a", toClusterID: "b",
            distanceMeters: distanceMeters, route: route, duration: duration
        )
    }

    /// Serpentine: zigzag of ±50 m lateral every ~100 m along an eastward climb.
    private func makeSerpentine() -> RoadTripTimeline.Travel {
        let metersPerPoint = 100.0
        let degPerMeter = 1.0 / (111_320.0 * cos(48.85 * .pi / 180))
        let lateralDeg = 50.0 / 111_320.0
        var route: [RoutePoint] = []
        for i in 0..<60 {
            let zig = i % 2 == 0 ? lateralDeg : -lateralDeg
            route.append(RoutePoint(
                latitude: 48.85 + zig,
                longitude: 2.29 + Double(i) * metersPerPoint * degPerMeter
            ))
        }
        return RoadTripTimeline.Travel(
            fromClusterID: "a", toClusterID: "b",
            distanceMeters: 6000, route: route, duration: 4
        )
    }

    /// Straight east, a hairpin turning 150° within ~500 m, then straight again.
    private func makeHairpin() -> RoadTripTimeline.Travel {
        let lonDeg = 1.0 / (111_320.0 * cos(48.85 * .pi / 180))
        let latDeg = 1.0 / 111_320.0
        var route: [RoutePoint] = []
        for i in 0..<6 {
            route.append(RoutePoint(latitude: 48.85, longitude: 2.29 + Double(i) * 150 * lonDeg))
        }
        var lat = 48.85
        var lon = 2.29 + 5 * 150 * lonDeg
        for k in 0..<6 {
            let theta = Double(k + 1) * 25.0 * .pi / 180
            lat -= 80 * sin(theta) * latDeg
            lon += 80 * cos(theta) * lonDeg
            route.append(RoutePoint(latitude: lat, longitude: lon))
        }
        for _ in 0..<8 {
            lat -= 75 * latDeg
            lon -= 130 * lonDeg
            route.append(RoutePoint(latitude: lat, longitude: lon))
        }
        return RoadTripTimeline.Travel(
            fromClusterID: "a", toClusterID: "b",
            distanceMeters: 2600, route: route, duration: 4
        )
    }

    private let canvas = CGSize(width: 1080, height: 1920)

    // MARK: - Homography

    func test_homography_mapsSourceCornersExactly() {
        let src = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 50),
            CGPoint(x: 0, y: 50)
        ]
        let dst = [
            CGPoint(x: 10, y: 20),
            CGPoint(x: 110, y: 20),
            CGPoint(x: 120, y: 80),
            CGPoint(x: 0, y: 80)
        ]
        let h = RoadTripMatrix3.homography(from: src, to: dst)
        for i in 0..<4 {
            let p = h.transformed(src[i])
            XCTAssertEqual(p.x, dst[i].x, accuracy: 1e-6)
            XCTAssertEqual(p.y, dst[i].y, accuracy: 1e-6)
        }
    }

    func test_homography_preservesCollinearity() {
        let src = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 50),
            CGPoint(x: 0, y: 50)
        ]
        let dst = RoadTripDriveCamera.trapezoidCorners(canvas: canvas, lookAheadMeters: RoadTripDriveCamera.zoomShortMeters)
        let h = RoadTripMatrix3.homography(from: src, to: dst)

        // Three collinear source points on the top edge stay collinear.
        let a = h.transformed(CGPoint(x: 0, y: 0))
        let b = h.transformed(CGPoint(x: 50, y: 0))
        let c = h.transformed(CGPoint(x: 100, y: 0))
        let area = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        XCTAssertLessThan(abs(area), 1e-3)
    }

    func test_homography_affineCaseIsExact() {
        let src = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 200, y: 0),
            CGPoint(x: 200, y: 100),
            CGPoint(x: 0, y: 100)
        ]
        let dst = [
            CGPoint(x: 30, y: 40),
            CGPoint(x: 230, y: 40),
            CGPoint(x: 230, y: 140),
            CGPoint(x: 30, y: 140)
        ]
        let h = RoadTripMatrix3.homography(from: src, to: dst)
        let p = h.transformed(CGPoint(x: 50, y: 25))
        XCTAssertEqual(p.x, 80, accuracy: 1e-6)
        XCTAssertEqual(p.y, 65, accuracy: 1e-6)
    }

    // MARK: - Drive frame

    func test_driveFrame_deterministic() {
        let travel = makeTravel()
        let a = RoadTripDriveCamera.frame(travel: travel, localTime: 1.0, canvas: canvas)
        let b = RoadTripDriveCamera.frame(travel: travel, localTime: 1.0, canvas: canvas)
        XCTAssertEqual(a, b)
    }

    func test_driveFrame_lookAheadBounded() {
        // Look-ahead is clamped to the zoom range whatever the leg speed.
        let short = makeTravel(distanceMeters: 1_000)
        let long = makeTravel(distanceMeters: 400_000)
        for travel in [short, long] {
            let lookAhead = RoadTripDriveCamera.lookAheadMeters(travel: travel)
            XCTAssertGreaterThanOrEqual(lookAhead, RoadTripDriveCamera.zoomInMeters - 1e-9)
            XCTAssertLessThanOrEqual(lookAhead, RoadTripDriveCamera.maxFitLookAheadMeters + 1e-9)
            for t in [0.0, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0] {
                let frame = RoadTripDriveCamera.frame(travel: travel, localTime: t, canvas: canvas)
                XCTAssertEqual(frame.lookAheadMeters, lookAhead, accuracy: 1e-9)
            }
        }
    }

    func test_driveFrame_lookAheadConstantDuringLeg() {
        // The zoom is set once per leg and never animates mid-leg.
        let travel = makeTravel(distanceMeters: 100_000)
        let reference = RoadTripDriveCamera.lookAheadMeters(travel: travel)
        for _ in 0..<5 {
            XCTAssertEqual(RoadTripDriveCamera.lookAheadMeters(travel: travel), reference, accuracy: 1e-9)
        }
    }

    func test_driveFrame_zoomProportionalToDistance() {
        // Short/medium legs chase at street level; long legs pull back so the
        // whole leg fits on screen (look-ahead ≈ chord × margin).
        let short = makeTravel(distanceMeters: 2_000)
        let mid = makeTravel(distanceMeters: 20_000)
        let grand = makeTravel(distanceMeters: 50_000)
        let long = makeTravel(distanceMeters: 400_000)
        XCTAssertLessThan(RoadTripDriveCamera.lookAheadMeters(travel: short), RoadTripDriveCamera.lookAheadMeters(travel: mid))
        XCTAssertLessThan(RoadTripDriveCamera.lookAheadMeters(travel: mid), RoadTripDriveCamera.lookAheadMeters(travel: grand))

        // Short regime (d ≤ 2 km): street level.
        XCTAssertEqual(RoadTripDriveCamera.lookAheadMeters(travel: short), RoadTripDriveCamera.zoomShortMeters, accuracy: 1e-9)
        // Medium regime (chord ≤ 30 km): piecewise linear by arc distance.
        let expectedMid = RoadTripDriveCamera.zoomShortMeters
            + (RoadTripDriveCamera.zoomMediumMeters - RoadTripDriveCamera.zoomShortMeters)
            * ((mid.distanceMeters - RoadTripDriveCamera.shortTripMeters) / (RoadTripDriveCamera.mediumTripMeters - RoadTripDriveCamera.shortTripMeters))
        XCTAssertEqual(RoadTripDriveCamera.lookAheadMeters(travel: mid), expectedMid, accuracy: 1e-9)

        // Fit regime: the whole leg is on screen (look-ahead ≥ chord).
        let grandChord = RoadTripDriveCamera.chordMeters(grand.route)
        XCTAssertGreaterThanOrEqual(RoadTripDriveCamera.lookAheadMeters(travel: grand), grandChord)
        XCTAssertEqual(RoadTripDriveCamera.lookAheadMeters(travel: grand), grandChord * RoadTripDriveCamera.fitMarginFactor, accuracy: 1e-9)
        // Very long legs clamp at the fit cap.
        XCTAssertEqual(RoadTripDriveCamera.lookAheadMeters(travel: long), RoadTripDriveCamera.maxFitLookAheadMeters, accuracy: 1e-9)
    }

    func test_driveFrame_windingRoadZoomsIn() {
        // A winding leg pulls the zoom back in relative to a straight leg of the
        // same distance.
        let straight = makeTravel(distanceMeters: 10_000)
        let winding = makeHairpin()
        let straightZoom = RoadTripDriveCamera.lookAheadMeters(travel: straight)
        let windingZoom = RoadTripDriveCamera.lookAheadMeters(travel: winding)
        XCTAssertLessThan(windingZoom, straightZoom, "a winding road must zoom in to hug the corners")
        XCTAssertGreaterThanOrEqual(windingZoom, RoadTripDriveCamera.zoomInMeters - 1e-9)
    }

    func test_driveFrame_cameraFollowsSmoothedRail() {
        // The car stays on the exact GPS route while the camera rides the
        // smoothed rail at the same arc progress (identical on a straight road,
        // decoupled laterally on curves).
        let travel = makeTravel()
        let rail = RoadTripSmoothPath.make(route: travel.route, sigma: RoadTripDriveCamera.cameraSigma)
        for i in 0...40 {
            let t = travel.duration * Double(i) / 40
            let frame = RoadTripDriveCamera.frame(travel: travel, localTime: t, canvas: canvas)
            let exact = RoadTripTravelTiming.interpolate(travel.route, fraction: frame.progress)
            XCTAssertEqual(frame.carCoordinate.latitude, exact.latitude, accuracy: 1e-9)
            XCTAssertEqual(frame.carCoordinate.longitude, exact.longitude, accuracy: 1e-9)
            let expected = rail.point(at: frame.progress)
            XCTAssertEqual(frame.cameraCoordinate.latitude, expected.latitude, accuracy: 1e-6)
            XCTAssertEqual(frame.cameraCoordinate.longitude, expected.longitude, accuracy: 1e-6)
        }
    }

    func test_driveFrame_carAlwaysVisible() {
        // The car and its street-level look-ahead window always project inside
        // the canvas: the rect is centered on the car every frame.
        let travels = [makeTravel(), makeSerpentine(), makeHairpin()]
        for travel in travels {
            for i in 0...60 {
                let t = travel.duration * Double(i) / 60
                let frame = RoadTripDriveCamera.frame(travel: travel, localTime: t, canvas: canvas)
                let carMP = MKMapPoint(frame.carCoordinate.coordinate)
                let p = frame.matrix.transformed(CGPoint(x: carMP.x, y: carMP.y))
                XCTAssertGreaterThan(p.x, -1, "car x clipped at t=\(t)")
                XCTAssertLessThan(p.x, canvas.width + 1, "car x clipped at t=\(t)")
                XCTAssertGreaterThan(p.y, -1, "car y clipped at t=\(t)")
                XCTAssertLessThan(p.y, canvas.height + 1, "car y clipped at t=\(t)")
            }
        }
    }

    func test_driveFrame_carHoldsFixedScreenPosition() {
        // Street chase: the car holds a fixed screen position in the lower
        // half for the whole leg — it no longer glides bottom→top.
        let travel = makeTravel(distanceMeters: 5_000)
        var ys: [CGFloat] = []
        var xs: [CGFloat] = []
        for i in 0...40 {
            let t = travel.duration * Double(i) / 40
            let frame = RoadTripDriveCamera.frame(travel: travel, localTime: t, canvas: canvas)
            let carMP = MKMapPoint(frame.carCoordinate.coordinate)
            let c = frame.matrix.transformed(CGPoint(x: carMP.x, y: carMP.y))
            xs.append(c.x)
            ys.append(c.y)
        }
        for x in xs {
            XCTAssertGreaterThan(x, canvas.width * 0.2)
            XCTAssertLessThan(x, canvas.width * 0.8)
        }
        let minY = ys.min()!, maxY = ys.max()!
        XCTAssertGreaterThan(minY, canvas.height * 0.5, "car must stay in the lower half")
        XCTAssertLessThan(maxY, canvas.height * 0.98)
        // The car holds its position: nearly constant screen y across the leg.
        XCTAssertLessThan(maxY - minY, canvas.height * 0.05, "car must hold its screen position")
    }

    func test_driveFrame_backEdgeMapsToBottomEdge() {
        let travel = makeTravel()
        let frame = RoadTripDriveCamera.frame(travel: travel, localTime: 2, canvas: canvas)
        // Midpoint of the source rect's back edge projects to the midpoint of
        // the destination trapezoid's bottom edge (projective on the axis).
        let backMid = CGPoint(
            x: (frame.sourceCorners[2].x + frame.sourceCorners[3].x) / 2,
            y: (frame.sourceCorners[2].y + frame.sourceCorners[3].y) / 2
        )
        let p = frame.matrix.transformed(backMid)
        XCTAssertEqual(p.x, canvas.width / 2, accuracy: 2)
        XCTAssertEqual(p.y, canvas.height * RoadTripDriveCamera.groundFractionY, accuracy: 2)
    }

    // MARK: - Camera bearing (road-following)

    func test_camera_bearingFollowsRoad() {
        // The camera heading follows the smoothed road direction — it rotates
        // with the road instead of freezing on the leg chord.
        let travel = makeSerpentine()
        var prev = RoadTripDriveCamera.cameraHeading(travel: travel, localTime: 0)
        var maxStep = 0.0
        for i in 1...40 {
            let t = travel.duration * Double(i) / 40
            let h = RoadTripDriveCamera.cameraHeading(travel: travel, localTime: t)
            var d = abs(h - prev).truncatingRemainder(dividingBy: 2 * .pi)
            if d > .pi { d = 2 * .pi - d }
            maxStep = max(maxStep, d)
            prev = h
        }
        XCTAssertLessThan(maxStep, 0.3, "camera heading must rotate smoothly with the road")
    }

    func test_camera_lookAheadHeading_dampsHairpin() {
        // The look-ahead blend must cut the peak rotation of the camera facing
        // through the hairpin vs. the raw under-car rail tangent — the camera
        // turns before the car reaches the corner instead of whipping.
        let travel = makeHairpin()
        let rail = RoadTripSmoothPath.make(
            route: travel.route,
            sigma: RoadTripDriveCamera.cameraSigma,
            minSigma: RoadTripDriveCamera.cameraSigmaMin
        )
        var rawPrev = 0.0
        var rawMax = 0.0
        var camPrev = 0.0
        var camMax = 0.0
        for i in 0...120 {
            let t = travel.duration * Double(i) / 120
            let timing = RoadTripTravelTiming.frame(travel: travel, localTime: t)
            let raw = rail.heading(at: min(max(timing.progress, 0), 1))
            let cam = RoadTripDriveCamera.cameraHeading(travel: travel, localTime: t)
            if i > 0 {
                var dr = abs(raw - rawPrev)
                if dr > .pi { dr = 2 * .pi - dr }
                var dc = abs(cam - camPrev)
                if dc > .pi { dc = 2 * .pi - dc }
                rawMax = max(rawMax, dr)
                camMax = max(camMax, dc)
            }
            rawPrev = raw
            camPrev = cam
        }
        XCTAssertLessThan(camMax, rawMax, "the look-ahead blend must anticipate the hairpin turn")
    }

    func test_camera_lookAheadHeading_keepsStraightRoadExact() {
        // On a straight the ahead tangent equals the under-car tangent, so the
        // blend never drifts the heading off the road.
        let travel = makeTravel(distanceMeters: 30_000)
        for i in 0...40 {
            let t = travel.duration * Double(i) / 40
            let h = RoadTripDriveCamera.cameraHeading(travel: travel, localTime: t)
            var d = abs(h - .pi / 2).truncatingRemainder(dividingBy: 2 * .pi)
            if d > .pi { d = 2 * .pi - d }
            XCTAssertLessThan(d, 0.01, "the blend must keep the straight road heading")
        }
    }

    func test_camera_bearingStraightRoadPointsForward() {
        // Straight east route: the camera faces along the road (≈ π/2).
        let travel = makeTravel(distanceMeters: 30_000)
        for i in 0...40 {
            let t = travel.duration * Double(i) / 40
            let h = RoadTripDriveCamera.cameraHeading(travel: travel, localTime: t)
            var d = abs(h - .pi / 2).truncatingRemainder(dividingBy: 2 * .pi)
            if d > .pi { d = 2 * .pi - d }
            XCTAssertLessThan(d, 0.01, "camera heading must track the straight road")
        }
    }

    func test_camera_bearingIsLegChord() {
        // Straight east route: bearing ≈ π/2.
        let travel = makeTravel()
        var d = abs(RoadTripDriveCamera.legBearing(route: travel.route) - .pi / 2)
        if d > .pi { d = 2 * .pi - d }
        XCTAssertLessThan(d, 0.01)
        // L-shaped route: chord points northeast.
        var route: [RoutePoint] = []
        for i in 0..<20 { route.append(RoutePoint(latitude: 48.85, longitude: 2.29 + Double(i) * 0.001)) }
        for i in 1..<20 { route.append(RoutePoint(latitude: 48.85 + Double(i) * 0.001, longitude: 2.309)) }
        let chord = RoadTripDriveCamera.legBearing(route: route)
        XCTAssertGreaterThan(chord, 0)
        XCTAssertLessThan(chord, .pi / 2)
    }

    // MARK: - Car heading (smoothed, for the sprite)

    private func carHeadingSteps(_ travel: RoadTripTimeline.Travel, samples: Int = 120) -> (maxStep: Double, maxSecondStep: Double) {
        var prev = 0.0
        var prevStep = 0.0
        var maxStep = 0.0
        var maxSecondStep = 0.0
        for i in 0...samples {
            let t = travel.duration * Double(i) / Double(samples)
            let heading = RoadTripDriveCamera.carHeading(travel: travel, localTime: t)
            if i > 0 {
                var d = abs(heading - prev).truncatingRemainder(dividingBy: 2 * .pi)
                if d > .pi { d = 2 * .pi - d }
                maxStep = max(maxStep, d)
                if i > 1 { maxSecondStep = max(maxSecondStep, abs(d - prevStep)) }
                prevStep = d
            }
            prev = heading
        }
        return (maxStep, maxSecondStep)
    }

    func test_carHeading_smoothThroughSerpentine() {
        // The car's heading follows the road more tightly than the camera but
        // must never step at the route vertices (the raw segment bearing
        // alternates ±~0.9 rad).
        let travel = makeSerpentine()
        let (maxStep, maxSecondStep) = carHeadingSteps(travel)
        XCTAssertLessThan(maxStep, 0.25, "car heading must glide, not step at vertices")
        XCTAssertLessThan(maxSecondStep, 0.08, "car steering stays smooth through the serpentine")
    }

    func test_carHeading_straightRoadPointsForward() {
        let travel = makeTravel(distanceMeters: 30_000)
        for i in 0...40 {
            let t = travel.duration * Double(i) / 40
            let heading = RoadTripDriveCamera.carHeading(travel: travel, localTime: t)
            var d = abs(heading - .pi / 2).truncatingRemainder(dividingBy: 2 * .pi)
            if d > .pi { d = 2 * .pi - d }
            XCTAssertLessThan(d, 0.01, "car heading must track the straight road")
        }
    }

    // MARK: - Windows

    func test_windows_coverWholeRoute() {
        let travel = makeTravel(distanceMeters: 50_000)
        let windows = RoadTripDriveCamera.windows(travel: travel, canvas: canvas)
        XCTAssertFalse(windows.isEmpty)
        for fraction in stride(from: 0.0, through: 1.0, by: 0.05) {
            let covered = windows.contains { fraction >= $0.startFraction - 0.001 && fraction <= $0.endFraction + 0.001 }
            XCTAssertTrue(covered, "fraction \(fraction) not covered by any window")
        }
    }

    func test_windows_capped() {
        let travel = makeTravel(distanceMeters: 400_000)
        let windows = RoadTripDriveCamera.windows(travel: travel, canvas: canvas)
        XCTAssertLessThanOrEqual(windows.count, RoadTripDriveCamera.maxWindows)
        XCTAssertGreaterThanOrEqual(windows.count, 1)
    }

    func test_windows_shortLegSingleSnapshot() {
        // A short leg fits in one street-level window.
        let travel = makeTravel(distanceMeters: 2000)
        let windows = RoadTripDriveCamera.windows(travel: travel, canvas: canvas)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].startFraction, 0)
        XCTAssertEqual(windows[0].endFraction, 1)
    }

    func test_windows_longLegChainsSnapshots() {
        // A medium leg (still street-level) chains overlapping windows so the
        // view stays crisp from start to end.
        let travel = makeTravel(distanceMeters: 8_000)
        let windows = RoadTripDriveCamera.windows(travel: travel, canvas: canvas)
        XCTAssertGreaterThan(windows.count, 1)
        XCTAssertEqual(windows.first?.startFraction ?? 1, 0)
        XCTAssertEqual(windows.last?.endFraction ?? 0, 1)
        for i in 1..<windows.count {
            XCTAssertLessThan(windows[i].startFraction, windows[i - 1].endFraction, "windows must overlap for the crossfade")
        }
    }

    func test_windows_aerialLegSingleSnapshot() {
        // A long (aerial) leg needs just one full-leg snapshot — the whole route
        // is visible in a single frame at that zoom.
        let travel = makeTravel(distanceMeters: 120_000)
        let windows = RoadTripDriveCamera.windows(travel: travel, canvas: canvas)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].startFraction, 0)
        XCTAssertEqual(windows[0].endFraction, 1)
    }

    func test_region_fitsCanvasAspect() {
        let travel = makeTravel(distanceMeters: 30_000)
        let windows = RoadTripDriveCamera.windows(travel: travel, canvas: canvas)
        XCTAssertFalse(windows.isEmpty)
        for window in windows {
            let aspect = window.region.span.latitudeDelta / window.region.span.longitudeDelta
            // Portrait canvas: latitude span ≥ longitude span, roughly.
            XCTAssertGreaterThan(aspect, 0.4)
            XCTAssertLessThan(aspect, 2.5)
        }
    }
}
