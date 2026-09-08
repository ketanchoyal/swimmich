import XCTest
import MapKit
@testable import ImmichSwiftUI

final class RoadTripSmoothPathTests: XCTestCase {

    /// Straight eastward route along lat 48.85.
    private func makeRoute(east distanceMeters: Double = 30_000, lat: Double = 48.85) -> [RoutePoint] {
        let degPerMeter = 1.0 / (111_320.0 * cos(lat * .pi / 180))
        let count = 30
        return (0..<count).map { i in
            RoutePoint(
                latitude: lat,
                longitude: 2.29 + Double(i) / Double(count - 1) * distanceMeters * degPerMeter
            )
        }
    }

    /// Serpentine: ±50 m lateral zigzag every ~100 m along an eastward climb.
    private func makeSerpentine() -> [RoutePoint] {
        let metersPerPoint = 100.0
        let degPerMeter = 1.0 / (111_320.0 * cos(48.85 * .pi / 180))
        let lateralDeg = 50.0 / 111_320.0
        return (0..<60).map { i in
            let zig = i % 2 == 0 ? lateralDeg : -lateralDeg
            return RoutePoint(
                latitude: 48.85 + zig,
                longitude: 2.29 + Double(i) * metersPerPoint * degPerMeter
            )
        }
    }

    /// 90° corner: east, then north.
    private func makeCorner() -> [RoutePoint] {
        var route: [RoutePoint] = []
        for i in 0..<20 { route.append(RoutePoint(latitude: 48.85, longitude: 2.29 + Double(i) * 0.001)) }
        for i in 1..<20 { route.append(RoutePoint(latitude: 48.85 + Double(i) * 0.001, longitude: 2.309)) }
        return route
    }

    private func maxHeadingStep(_ rail: RoadTripSmoothPath, sample: Double = 0.005) -> Double {
        var prev = rail.heading(at: 0)
        var m = 0.0
        var f = 0.0
        while f <= 1.0 {
            let h = rail.heading(at: f)
            var d = abs(h - prev).truncatingRemainder(dividingBy: 2 * .pi)
            if d > .pi { d = 2 * .pi - d }
            m = max(m, d)
            prev = h
            f += sample
        }
        return m
    }

    // MARK: - Heading

    func test_headingStraightPointsForward() {
        let rail = RoadTripSmoothPath.make(route: makeRoute(), sigma: 120)
        for f in stride(from: 0.0, through: 1.0, by: 0.05) {
            var d = abs(rail.heading(at: f) - .pi / 2).truncatingRemainder(dividingBy: 2 * .pi)
            if d > .pi { d = 2 * .pi - d }
            XCTAssertLessThan(d, 0.01, "heading must track the straight road")
        }
    }

    func test_headingGlidesThroughSerpentine() {
        // Raw segment bearings alternate ±~0.9 rad; the smoothed tangent must
        // glide without stepping at the vertices.
        let rail = RoadTripSmoothPath.make(route: makeSerpentine(), sigma: RoadTripDriveCamera.carSigma)
        XCTAssertLessThan(maxHeadingStep(rail), 0.25, "tangent must glide, not step")
    }

    func test_smoothingRoundsCorners() {
        let raw = RoadTripSmoothPath.make(route: makeCorner(), sigma: 0)
        let smooth = RoadTripSmoothPath.make(route: makeCorner(), sigma: RoadTripDriveCamera.cameraSigma)
        XCTAssertLessThan(maxHeadingStep(smooth), maxHeadingStep(raw) * 0.8, "smoothing must round the corner")
    }

    // MARK: - Geometry

    func test_zeroSigmaPreservesRoute() {
        let route = makeRoute(east: 2_000)
        let rail = RoadTripSmoothPath.make(route: route, sigma: 0, spacing: 10)
        XCTAssertEqual(rail.point(at: 0).latitude, route.first!.latitude, accuracy: 1e-9)
        XCTAssertEqual(rail.point(at: 0).longitude, route.first!.longitude, accuracy: 1e-9)
        XCTAssertEqual(rail.point(at: 1).longitude, route.last!.longitude, accuracy: 1e-9)
        XCTAssertEqual(rail.total, RoadTripTravelTiming.cumulativeLengths(route).last!, accuracy: 1)
    }

    func test_pointMatchesInterpolateForStraightRoute() {
        let route = makeRoute()
        let rail = RoadTripSmoothPath.make(route: route, sigma: 120)
        for f in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let p = rail.point(at: f)
            let exact = RoadTripTravelTiming.interpolate(route, fraction: f)
            XCTAssertEqual(p.latitude, exact.latitude, accuracy: 1e-6)
            XCTAssertEqual(p.longitude, exact.longitude, accuracy: 1e-6)
        }
    }

    func test_deterministic() {
        let a = RoadTripSmoothPath.make(route: makeSerpentine(), sigma: 120)
        let b = RoadTripSmoothPath.make(route: makeSerpentine(), sigma: 120)
        XCTAssertEqual(a.points, b.points)
    }

    // MARK: - Adaptive sigma (hairpins)

    /// Tight 180° switchback (radius ~15 m): east approach, a north loop, then
    /// a west exit — a mountain-road hairpin.
    private func makeSwitchback() -> [RoutePoint] {
        let latDeg = 1.0 / 111_320.0
        let lonDeg = 1.0 / (111_320.0 * cos(48.85 * .pi / 180))
        let r = 15.0
        let lat0 = 48.85, lon0 = 2.29
        var route: [RoutePoint] = []
        for i in 0..<12 { route.append(RoutePoint(latitude: lat0, longitude: lon0 - Double(12 - i) * 25 * lonDeg)) }
        let steps = 24
        for k in 0...steps {
            let theta = .pi * Double(k) / Double(steps)
            route.append(RoutePoint(latitude: lat0 + r * (1 - cos(theta)) * latDeg, longitude: lon0 + r * sin(theta) * lonDeg))
        }
        let exitLat = lat0 + 2 * r * latDeg
        for i in 1..<12 { route.append(RoutePoint(latitude: exitLat, longitude: lon0 - Double(i) * 25 * lonDeg)) }
        return route
    }

    /// Sum of |heading change| along the rail — a measure of how much the rail
    /// actually turns through a hairpin.
    private func totalTurn(_ rail: RoadTripSmoothPath) -> Double {
        var prev = rail.heading(at: 0)
        var total = 0.0
        var f = 0.005
        while f <= 1.0 {
            let h = rail.heading(at: f)
            var d = abs(h - prev)
            if d > .pi { d = 2 * .pi - d }
            total += d
            prev = h
            f += 0.005
        }
        return total
    }

    func test_adaptiveSigma_preservesSwitchback() {
        let route = makeSwitchback()
        let raw = RoadTripSmoothPath.make(route: route, sigma: 0)
        let smooth = RoadTripSmoothPath.make(route: route, sigma: RoadTripDriveCamera.carSigma)
        let rawTurn = totalTurn(raw)
        let smoothTurn = totalTurn(smooth)
        // The switchback is ~180°; adaptive smoothing must keep most of the
        // turn instead of cutting straight across it (a fixed 150 m sigma
        // would collapse the hairpin).
        XCTAssertGreaterThan(rawTurn, 2.5, "the raw switchback should turn close to 180°")
        XCTAssertGreaterThan(smoothTurn, rawTurn * 0.5, "adaptive sigma must hug the switchback, not cut it")
    }
}
