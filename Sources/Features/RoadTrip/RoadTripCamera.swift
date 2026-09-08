import Foundation
import CoreGraphics
import CoreLocation
import MapKit

// MARK: - Projective matrix

/// 3×3 row-major projective matrix — the homography behind the chase camera.
struct RoadTripMatrix3: Equatable, Sendable {
    var m00: Double, m01: Double, m02: Double
    var m10: Double, m11: Double, m12: Double
    var m20: Double, m21: Double, m22: Double

    static let identity = RoadTripMatrix3(1, 0, 0, 0, 1, 0, 0, 0, 1)

    init(_ m00: Double, _ m01: Double, _ m02: Double,
         _ m10: Double, _ m11: Double, _ m12: Double,
         _ m20: Double, _ m21: Double, _ m22: Double) {
        self.m00 = m00; self.m01 = m01; self.m02 = m02
        self.m10 = m10; self.m11 = m11; self.m12 = m12
        self.m20 = m20; self.m21 = m21; self.m22 = m22
    }

    /// Projects a point through the matrix (perspective divide).
    func transformed(_ point: CGPoint) -> CGPoint {
        let x = m00 * point.x + m01 * point.y + m02
        let y = m10 * point.x + m11 * point.y + m12
        let w = m20 * point.x + m21 * point.y + m22
        guard abs(w) > 1e-9 else { return point }
        return CGPoint(x: x / w, y: y / w)
    }

    /// `self` applied after `other` (result maps p → self(other(p))).
    func multiplied(by other: RoadTripMatrix3) -> RoadTripMatrix3 {
        RoadTripMatrix3(
            m00 * other.m00 + m01 * other.m10 + m02 * other.m20,
            m00 * other.m01 + m01 * other.m11 + m02 * other.m21,
            m00 * other.m02 + m01 * other.m12 + m02 * other.m22,
            m10 * other.m00 + m11 * other.m10 + m12 * other.m20,
            m10 * other.m01 + m11 * other.m11 + m12 * other.m21,
            m10 * other.m02 + m11 * other.m12 + m12 * other.m22,
            m20 * other.m00 + m21 * other.m10 + m22 * other.m20,
            m20 * other.m01 + m21 * other.m11 + m22 * other.m21,
            m20 * other.m02 + m21 * other.m12 + m22 * other.m22
        )
    }

    /// Homography mapping `src[i]` → `dst[i]` (m22 fixed to 1). Deterministic
    /// 8×8 DLT solve with partial pivoting, normalized by centroid so the
    /// solver stays stable with absolute map coordinates (~1e8 — raw values
    /// produce products up to 1e11 and a numerically wrong projective map).
    static func homography(from src: [CGPoint], to dst: [CGPoint]) -> RoadTripMatrix3 {
        precondition(src.count == 4 && dst.count == 4)
        let srcC = CGPoint(x: src.reduce(0) { $0 + $1.x } / 4, y: src.reduce(0) { $0 + $1.y } / 4)
        let dstC = CGPoint(x: dst.reduce(0) { $0 + $1.x } / 4, y: dst.reduce(0) { $0 + $1.y } / 4)
        let ns = src.map { CGPoint(x: $0.x - srcC.x, y: $0.y - srcC.y) }
        let nd = dst.map { CGPoint(x: $0.x - dstC.x, y: $0.y - dstC.y) }

        var matrix = [[Double]](repeating: [Double](repeating: 0, count: 8), count: 8)
        var rhs = [Double](repeating: 0, count: 8)
        for i in 0..<4 {
            let x = ns[i].x, y = ns[i].y
            let X = nd[i].x, Y = nd[i].y
            matrix[i * 2] = [x, y, 1, 0, 0, 0, -X * x, -X * y]
            matrix[i * 2 + 1] = [0, 0, 0, x, y, 1, -Y * x, -Y * y]
            rhs[i * 2] = X
            rhs[i * 2 + 1] = Y
        }
        for col in 0..<8 {
            var pivot = col
            for row in (col + 1)..<8 where abs(matrix[row][col]) > abs(matrix[pivot][col]) {
                pivot = row
            }
            if abs(matrix[pivot][col]) < 1e-12 { return .identity }
            if pivot != col {
                matrix.swapAt(pivot, col)
                rhs.swapAt(pivot, col)
            }
            let inv = 1.0 / matrix[col][col]
            for j in col..<8 { matrix[col][j] *= inv }
            rhs[col] *= inv
            for row in 0..<8 where row != col {
                let factor = matrix[row][col]
                if abs(factor) < 1e-14 { continue }
                for j in col..<8 { matrix[row][j] -= factor * matrix[col][j] }
                rhs[row] -= factor * rhs[col]
            }
        }
        let normalized = RoadTripMatrix3(rhs[0], rhs[1], rhs[2], rhs[3], rhs[4], rhs[5], rhs[6], rhs[7], 1)
        // Compose back: H = T_dst ∘ H_normalized ∘ T_src⁻¹.
        let toDst = RoadTripMatrix3(1, 0, dstC.x, 0, 1, dstC.y, 0, 0, 1)
        let fromSrc = RoadTripMatrix3(1, 0, -srcC.x, 0, 1, -srcC.y, 0, 0, 1)
        return toDst.multiplied(by: normalized).multiplied(by: fromSrc)
    }
}

// MARK: - Driving (chase) camera

/// Exact affine map-point → snapshot-pixel conversion for one snapshot window.
struct RoadTripAffine: Equatable, Sendable {
    let scaleX: Double
    let scaleY: Double
    let offsetX: Double
    let offsetY: Double

    func point(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * scaleX + offsetX, y: p.y * scaleY + offsetY)
    }
}

/// One pre-computed map "window" of a travel leg: a snapshot region wide enough
/// to contain the car's look-ahead view for any frame whose progress falls
/// inside `startFraction...endFraction` (fractions of the route arc length).
struct RoadTripDriveWindow {
    let startFraction: Double
    let endFraction: Double
    let region: MKCoordinateRegion

    var midFraction: Double { (startFraction + endFraction) / 2 }
}

/// A projective camera frame for a chase ("driving") map view of a travel leg.
///
/// The camera is anchored ON the car (exact GPS route) and faces a smoothed
/// route heading: the ground plane ahead — a rectangle in map space centered
/// on the car and rotated to the smoothed bearing — is projected onto a
/// trapezoid in canvas space (full width at the bottom, a narrow horizon edge
/// at the top). The same geometry drives the live preview and the export so
/// the camera motion is identical; only the imagery differs.
struct RoadTripDriveFrame: Equatable, Sendable {
    let progress: Double
    /// Exact position on the route (the car — and the camera anchor).
    let carCoordinate: RoutePoint
    /// Camera anchor position — identical to `carCoordinate`.
    let cameraCoordinate: RoutePoint
    /// Camera heading — smoothed route bearing (continuous).
    let bearing: Double
    let lookAheadMeters: Double
    /// Rotated source rect corners in MKMapPoint space: front-left, front-right,
    /// back-right, back-left.
    let sourceCorners: [CGPoint]
    /// Destination trapezoid in canvas points: top-left, top-right, bottom-right,
    /// bottom-left.
    let destinationCorners: [CGPoint]
    let matrix: RoadTripMatrix3

    func transformed(_ point: CGPoint) -> CGPoint { matrix.transformed(point) }
}

/// The camera's state at a moment: where it looks from, where it looks toward.
struct RoadTripCameraState: Equatable, Sendable {
    let progress: Double
    let carCoordinate: RoutePoint
    let cameraCoordinate: RoutePoint
    let bearing: Double
    let lookAheadMeters: Double
}

enum RoadTripDriveCamera {

    static let maxWindows = 24
    /// Trip-size rules (leg distance, meters). A leg whose straight-line extent
    /// (chord) is below `mediumTripMeters` is a street-level stop; above it the
    /// camera pulls back so the whole leg fits on screen.
    static let shortTripMeters = 2_000.0
    static let mediumTripMeters = 30_000.0
    /// Zoom anchors (look-ahead depth, meters): street level → transition → the
    /// aerial pitch kicks in fully at `zoomMediumMeters`.
    static let zoomInMeters = 300.0
    static let zoomShortMeters = 1_500.0
    static let zoomMediumMeters = 12_000.0
    /// Cap on the "fit" look-ahead for very long legs (whole route on screen).
    static let maxFitLookAheadMeters = 400_000.0
    /// How much margin the fit view adds beyond the leg's chord, so the whole
    /// route is comfortably visible (look-ahead ≥ chord with backRatio → 1).
    static let fitMarginFactor = 1.15
    /// Winding roads pull the zoom back in so the camera hugs the current
    /// corner instead of staring across several hairpins.
    static let curvatureZoomFactor = 0.45
    /// Lateral spread of the chase rect, as a ratio of look-ahead.
    static let lateralRatio = 420.0 / 1200.0
    /// Route arc length one street-level snapshot window covers; adjacent
    /// windows overlap by `windowOverlapMeters` so the next snapshot always
    /// contains the car's look-ahead (no pop on the crossfade). Sized so
    /// `maxWindows` windows cover ≥ 90 km of arc — winding mountain legs have
    /// a much larger arc than chord and must never outrun the chain.
    static let windowArcMeters = 6000.0
    static let windowOverlapMeters = 2000.0
    /// Look-ahead above which the leg is treated as aerial: a single full-leg
    /// snapshot replaces the street-level window chain.
    static let aerialLookAheadMeters = 4000.0
    /// Trapezoid shape (canvas fractions) at the street-level and aerial ends
    /// of the pitch blend; the ground edge is constant.
    static let streetHorizonFractionY = 0.24
    static let streetHorizonWidthFraction = 0.34
    static let aerialHorizonFractionY = 0.05
    static let aerialHorizonWidthFraction = 0.95
    static let groundFractionY = 0.98
    /// Back ratio (how far behind the car the view extends): street view keeps
    /// the car in the lower third; the aerial view recenters it on the map.
    static let streetBackRatio = 600.0 / 1200.0
    static let aerialBackRatio = 1.0

    /// Camera rail smoothing width (meters): kept generous so the camera stays
    /// fluid and never snaps at route vertices. (Tight hairpins adapt it
    /// downward — see `RoadTripSmoothPath`.) The camera's floor is higher than
    /// the car's so the chase view glides through switchbacks without whiplash.
    static let cameraSigma = 300.0
    /// Camera rail sigma floor inside hairpins (the car keeps the 40 m default).
    /// High enough that the camera never whips through an épingle; the car
    /// stays glued to the road on its own tighter rail.
    static let cameraSigmaMin = 110.0
    /// Car rail smoothing width (meters): tighter than the camera, so the sprite
    /// responds sooner while still gliding through route vertices.
    static let carSigma = 150.0

    // MARK: Heading signal (camera facing + car yaw)
    //
    // The camera faces a precomputed heading rail: raw tangents → continuous
    // look-ahead blend → circular Gaussian (`headingSigmaMeters`) → double-pass
    // rate limiter. The limiter's cap adapts to each leg's film speed so the
    // on-screen rotation never exceeds `cameraMaxAngularSpeed` (≈3.8°/frame at
    // 30 fps) — the root cure for whip on winding roads.

    /// Gaussian width (meters of arc) applied to the heading signal.
    static let headingSigmaMeters = 80.0
    /// Upper bound on |dθ/ds| before the speed adaptation (rad per meter).
    static let cameraTurnRateBase = 0.006
    /// Hard ceiling on the camera's on-screen angular speed (rad/s). The
    /// per-leg turn-rate cap is `cameraMaxAngularSpeed / legFilmSpeed`.
    static let cameraMaxAngularSpeed = 2.0
    /// Look-ahead ahead distance / blend weight / engagement band (radians).
    /// The blend ramps smoothly from `headingBlendThreshold` over
    /// `headingBlendRamp` — no discontinuity at the threshold.
    static let headingLookAheadMeters = 200.0
    static let headingLookAheadBlend = 0.5
    static let headingBlendThreshold = 30.0 * .pi / 180
    static let headingBlendRamp = 15.0 * .pi / 180
    /// How far ahead (meters) the car sprite samples the heading rail relative
    /// to the camera — it noses into corners before the camera turns.
    static let carYawLeadMeters = 70.0

    /// Ground distance the camera looks ahead of the car (meters) — the chase
    /// depth. Below `mediumTripMeters` of straight-line extent the leg is a
    /// street-level chase (piecewise by arc distance, curvature pulls it in).
    /// Above it the camera pulls back so the whole leg fits on screen:
    /// `lookAhead = chord × fitMarginFactor`, capped at `maxFitLookAheadMeters`.
    static func lookAheadMeters(travel: RoadTripTimeline.Travel) -> Double {
        let chord = chordMeters(travel.route)

        if chord <= mediumTripMeters {
            // Street regime: piecewise-linear by arc distance, curvature-tight.
            let d = travel.distanceMeters
            let base: Double
            if d <= shortTripMeters {
                base = zoomInMeters + (zoomShortMeters - zoomInMeters) * (d / shortTripMeters)
            } else {
                base = zoomShortMeters + (zoomMediumMeters - zoomShortMeters) * ((d - shortTripMeters) / (mediumTripMeters - shortTripMeters))
            }
            let twist = RoadTripTravelTiming.twistiness(travel.route)
            let curveScale = 1.0 - curvatureZoomFactor * twist
            return max(zoomInMeters, min(base, zoomMediumMeters) * curveScale)
        }

        // Fit regime: the whole leg is visible (no curvature pull-in — the
        // chord already reflects how winding the route is).
        return min(max(chord * fitMarginFactor, zoomMediumMeters), maxFitLookAheadMeters)
    }

    /// Straight-line extent (meters) between the route's first and last point.
    static func chordMeters(_ route: [RoutePoint]) -> Double {
        guard let first = route.first, let last = route.last, route.count >= 2 else { return 0 }
        return RoadTripClusterer.haversine(first.coordinate, last.coordinate)
    }

    /// 0 (street) → 1 (aerial) pitch blend driven by the look-ahead depth. The
    /// camera is fully top-down by `zoomMediumMeters`, independent of how far
    /// the fit view zooms out.
    static func aerialBlend(lookAheadMeters: Double) -> Double {
        min(max((lookAheadMeters - zoomShortMeters) / (zoomMediumMeters - zoomShortMeters), 0), 1)
    }

    /// Horizon position (canvas fraction from the top) at a look-ahead depth:
    /// higher (smaller fraction) as the view goes aerial — almost no sky.
    static func horizonFractionY(lookAheadMeters: Double) -> Double {
        let t = aerialBlend(lookAheadMeters: lookAheadMeters)
        return streetHorizonFractionY + (aerialHorizonFractionY - streetHorizonFractionY) * t
    }

    /// Horizon edge width (canvas fraction) at a look-ahead depth: wider as the
    /// view goes aerial — the perspective flattens toward top-down.
    static func horizonWidthFraction(lookAheadMeters: Double) -> Double {
        let t = aerialBlend(lookAheadMeters: lookAheadMeters)
        return streetHorizonWidthFraction + (aerialHorizonWidthFraction - streetHorizonWidthFraction) * t
    }

    /// How far behind the car the view extends, as a ratio of look-ahead.
    static func backRatio(lookAheadMeters: Double) -> Double {
        let t = aerialBlend(lookAheadMeters: lookAheadMeters)
        return streetBackRatio + (aerialBackRatio - streetBackRatio) * t
    }

    /// Compass bearing (radians, north = 0, clockwise) of the leg's overall
    /// direction — from the route's first point to its last. The camera keeps
    /// this constant heading for the whole leg: it follows the car's
    /// trajectory (position) but never the car's orientation.
    static func legBearing(route: [RoutePoint]) -> Double {
        guard let first = route.first, let last = route.last, route.count >= 2 else { return 0 }
        let a = MKMapPoint(first.coordinate), b = MKMapPoint(last.coordinate)
        let dx = b.x - a.x, dy = b.y - a.y
        guard dx * dx + dy * dy > 1e-12 else { return 0 }
        // Map point y grows SOUTHWARD: compass bearing = atan2(east, −mapY).
        return atan2(dx, -dy)
    }

    /// The car sprite shrinks as the camera zooms out, so it never dwarfs a
    /// long leg's map. Shared by the live preview and the export.
    static func carSpriteScale(lookAheadMeters: Double) -> Double {
        min(max(8000 / max(lookAheadMeters, 1), 0.12), 1)
    }

    /// Car + camera state at `localTime`: the car rides the exact route while
    /// the camera follows a smoothed rail at the same arc progress and faces
    /// the leg's heading rail (smoothed + rate-limited — see the heading
    /// constants). Fully aerial legs lock to the chord bearing: a top-down map
    /// must not rotate at all.
    static func cameraState(travel: RoadTripTimeline.Travel, localTime: TimeInterval) -> RoadTripCameraState {
        let timing = RoadTripTravelTiming.frame(travel: travel, localTime: localTime)
        let progress = min(max(timing.progress, 0), 1)
        let lookAhead = lookAheadMeters(travel: travel)
        let components = headingComponents(travel: travel)
        let bearing = aerialBlend(lookAheadMeters: lookAhead) >= 1
            ? legBearing(route: travel.route)
            : components.heading.heading(at: progress)
        return RoadTripCameraState(
            progress: timing.progress,
            carCoordinate: timing.carCoordinate,
            cameraCoordinate: components.rail.point(at: progress),
            bearing: bearing,
            lookAheadMeters: lookAhead
        )
    }

    /// The smoothed position rail + its derived heading rail for a leg (both
    /// NSCache-backed; deterministic across the live player and the export).
    private static func headingComponents(travel: RoadTripTimeline.Travel) -> (rail: RoadTripSmoothPath, heading: RoadTripHeadingRail) {
        let rail = RoadTripSmoothPath.make(route: travel.route, sigma: cameraSigma, minSigma: cameraSigmaMin)
        // Adapt the turn-rate cap to this leg's film speed so the on-screen
        // angular speed stays under `cameraMaxAngularSpeed` whatever the pace.
        let speed = max(rail.total / max(travel.duration, 0.5), 50)
        let cap = min(cameraTurnRateBase, cameraMaxAngularSpeed / speed)
        let heading = RoadTripHeadingRail.make(
            rail: rail,
            sigma: headingSigmaMeters,
            maxTurnRate: cap,
            lookAheadFraction: min(headingLookAheadMeters / max(rail.total, 1), 0.25),
            lookAheadBlend: headingLookAheadBlend,
            blendThreshold: headingBlendThreshold,
            blendRamp: headingBlendRamp
        )
        return (rail, heading)
    }

    /// On-screen yaw (radians) of the car sprite relative to the camera
    /// facing: the heading rail sampled `carYawLeadMeters` ahead of the car
    /// minus the camera bearing. One authority for both — the sprite noses
    /// into corners early without fighting a second, differently-smoothed
    /// rail (the old dual-rail yaw swung tens of degrees through hairpins).
    static func carYaw(travel: RoadTripTimeline.Travel, localTime: TimeInterval, bearing: Double) -> Double {
        guard aerialBlend(lookAheadMeters: lookAheadMeters(travel: travel)) < 1 else { return 0 }
        let timing = RoadTripTravelTiming.frame(travel: travel, localTime: localTime)
        let progress = min(max(timing.progress, 0), 1)
        let components = headingComponents(travel: travel)
        let lead = min(carYawLeadMeters / max(components.rail.total, 1), 0.2)
        var d = components.heading.heading(at: min(progress + lead, 1)) - bearing
        d = atan2(sin(d), cos(d))
        return d
    }

    /// Smoothed road heading the camera faces — the leg's heading rail at the
    /// camera's arc progress.
    static func cameraHeading(travel: RoadTripTimeline.Travel, localTime: TimeInterval) -> Double {
        cameraState(travel: travel, localTime: localTime).bearing
    }

    /// The car's smoothed heading — the tangent of a lightly-smoothed rail, so
    /// the sprite hugs the road without stepping at route vertices. Shared by
    /// the live preview and the export so the car turns identically in both.
    static func carHeading(travel: RoadTripTimeline.Travel, localTime: TimeInterval) -> Double {
        let timing = RoadTripTravelTiming.frame(travel: travel, localTime: localTime)
        let rail = RoadTripSmoothPath.make(route: travel.route, sigma: carSigma)
        return rail.heading(at: min(max(timing.progress, 0), 1))
    }

    static func frame(travel: RoadTripTimeline.Travel, localTime: TimeInterval, canvas: CGSize) -> RoadTripDriveFrame {
        let state = cameraState(travel: travel, localTime: localTime)
        let bearing = state.bearing

        // Chase rect centered on the camera (smoothed rail), rotated to the
        // smoothed road heading: `lookAhead` forward (maps to the horizon),
        // `lookAhead * backRatio` back (maps to the ground edge), `lookAhead *
        // lateralRatio` across. The street view keeps the car near the lower
        // third; as the leg zooms out the back ratio grows and the car recenters
        // on the map — same geometry the live MapKit player uses.
        //
        // Map point space: +x east, +y SOUTH. Bearing is compass (north = 0,
        // clockwise), so the forward direction is (sin, −cos) and left of it
        // (−cos, −sin). Distances are METERS — convert to map points with the
        // local scale, otherwise the rect is ~10× too small.
        let lookAhead = state.lookAheadMeters
        let back = lookAhead * backRatio(lookAheadMeters: lookAhead)
        let lateral = lookAhead * lateralRatio
        let cameraMP = MKMapPoint(state.cameraCoordinate.coordinate)
        let camera = CGPoint(x: cameraMP.x, y: cameraMP.y)
        let pointsPerMeter = MKMapPointsPerMeterAtLatitude(state.cameraCoordinate.latitude)
        let f = CGPoint(x: sin(bearing), y: -cos(bearing))
        let l = CGPoint(x: -cos(bearing), y: -sin(bearing))
        func corner(_ forward: Double, _ side: Double) -> CGPoint {
            CGPoint(x: camera.x + (f.x * forward + l.x * side) * pointsPerMeter,
                    y: camera.y + (f.y * forward + l.y * side) * pointsPerMeter)
        }
        let source = [
            corner(lookAhead, lateral),
            corner(lookAhead, -lateral),
            corner(-back, -lateral),
            corner(-back, lateral)
        ]
        let destination = trapezoidCorners(canvas: canvas, lookAheadMeters: lookAhead)
        return RoadTripDriveFrame(
            progress: state.progress,
            carCoordinate: state.carCoordinate,
            cameraCoordinate: state.cameraCoordinate,
            bearing: bearing,
            lookAheadMeters: lookAhead,
            sourceCorners: source,
            destinationCorners: destination,
            matrix: RoadTripMatrix3.homography(from: source, to: destination)
        )
    }

    static func trapezoidCorners(canvas: CGSize, lookAheadMeters: Double) -> [CGPoint] {
        let w = canvas.width, h = canvas.height
        let topY = h * horizonFractionY(lookAheadMeters: lookAheadMeters)
        let bottomY = h * groundFractionY
        let topW = w * horizonWidthFraction(lookAheadMeters: lookAheadMeters)
        return [
            CGPoint(x: (w - topW) / 2, y: topY),
            CGPoint(x: (w + topW) / 2, y: topY),
            CGPoint(x: w, y: bottomY),
            CGPoint(x: 0, y: bottomY)
        ]
    }

    /// Snapshot windows along the leg: a leg whose look-ahead is street-level
    /// gets a chain of overlapping windows (capped at `maxWindows`, the last
    /// one extended to the route end so long winding legs stay covered); an
    /// aerial leg (or a short one) gets a single full-leg snapshot — at that
    /// zoom the whole route is visible in one frame anyway.
    ///
    /// Every window of a leg shares the LARGEST fitted map-rect, so all
    /// snapshots render at identical meters-per-point: crossfades are seamless
    /// and map labels keep a constant size across the leg.
    static func windows(travel: RoadTripTimeline.Travel, canvas: CGSize) -> [RoadTripDriveWindow] {
        let route = travel.route
        guard route.count >= 2 else { return [] }
        let cumulative = RoadTripTravelTiming.cumulativeLengths(route)
        let total = cumulative.last ?? 0
        guard total > 0 else { return [] }
        let lookAhead = lookAheadMeters(travel: travel)
        let lateralMeters = lookAhead * lateralRatio

        if total <= windowArcMeters || lookAhead >= aerialLookAheadMeters {
            return [RoadTripDriveWindow(
                startFraction: 0, endFraction: 1,
                region: region(rect: windowRect(route: route, from: 0, to: 1, total: total, cumulative: cumulative, lateralMeters: lateralMeters, canvas: canvas))
            )]
        }

        var ranges: [(start: Double, end: Double)] = []
        var start = 0.0
        while start < 1.0, ranges.count < maxWindows {
            var end = min(start + windowArcMeters / total, 1.0)
            // Extend the final window so the chain always covers [0, 1] —
            // `activeWindow` must never fall back to "nearest".
            if ranges.count == maxWindows - 1 && end < 1.0 { end = 1.0 }
            ranges.append((start, end))
            if end >= 1.0 { break }
            let overlap = windowOverlapMeters / total
            let nextStart = end - overlap
            start = nextStart > start ? nextStart : end
        }

        var rects: [MKMapRect] = []
        rects.reserveCapacity(ranges.count)
        for range in ranges {
            rects.append(windowRect(route: route, from: range.start, to: range.end, total: total, cumulative: cumulative, lateralMeters: lateralMeters, canvas: canvas))
        }
        guard let spanW = rects.map(\.width).max(), let spanH = rects.map(\.height).max(), spanW > 0, spanH > 0 else {
            return []
        }
        return zip(ranges, rects).map { range, rect in
            RoadTripDriveWindow(
                startFraction: range.start,
                endFraction: range.end,
                region: MKCoordinateRegion(MKMapRect(
                    x: rect.midX - spanW / 2,
                    y: rect.midY - spanH / 2,
                    width: spanW,
                    height: spanH
                ))
            )
        }
    }

    /// Route resampled at a roughly constant arc-length spacing, so warped
    /// polylines stay smooth when zoomed into the driving view. Parallel
    /// `fractions` stay exact (linear along each straight segment).
    static func densified(route: [RoutePoint], fractions: [Double], spacing: Double) -> (points: [RoutePoint], fractions: [Double]) {
        guard route.count >= 2, spacing > 0, fractions.count == route.count else { return (route, fractions) }
        var points: [RoutePoint] = [route[0]]
        var outF: [Double] = [fractions[0]]
        for i in 1..<route.count {
            let a = route[i - 1], b = route[i]
            let fA = fractions[i - 1], fB = fractions[i]
            let segLen = RoadTripClusterer.haversine(a.coordinate, b.coordinate)
            // Tighter spacing through corners so hairpins stay smooth at the
            // driving view's zoom; the base spacing remains on straights.
            let localSpacing = min(spacing, cornerSpacing(route: route, index: i, base: spacing))
            let steps = max(1, Int(segLen / localSpacing))
            for s in 1...steps {
                let t = Double(s) / Double(steps + 1)
                points.append(RoutePoint(
                    latitude: a.latitude + (b.latitude - a.latitude) * t,
                    longitude: a.longitude + (b.longitude - a.longitude) * t
                ))
                outF.append(fA + (fB - fA) * t)
            }
            points.append(b)
            outF.append(fB)
        }
        return (points, outF)
    }

    /// Spacing for the segment ending at `index`, tightened by the local turn
    /// rate: hairpins get ~1/4 the base spacing, straights keep it.
    private static func cornerSpacing(route: [RoutePoint], index: Int, base: Double) -> Double {
        guard index > 0, index < route.count - 1 else { return base }
        let a = route[index - 1].coordinate
        let b = route[index].coordinate
        let c = route[index + 1].coordinate
        let inBearing = bearing(a, b)
        let outBearing = bearing(b, c)
        var turn = abs(outBearing - inBearing)
        if turn > .pi { turn = 2 * .pi - turn }
        let segLen = RoadTripClusterer.haversine(b, c) + RoadTripClusterer.haversine(a, b)
        let turnPerMeter = turn / max(segLen, 1)
        let sharpness = min(turnPerMeter / 0.02, 1)   // ~45° over 40 m ≈ hairpin
        return max(base * (1 - 0.75 * sharpness), 8)
    }

    /// Initial compass bearing (radians, north = 0, clockwise) a→b.
    private static func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return atan2(y, x)
    }

    // MARK: - Regions

    /// Snapshot region for a pre-fitted map rect.
    private static func region(rect: MKMapRect) -> MKCoordinateRegion {
        MKCoordinateRegion(rect)
    }

    /// Base map-rect for one window: bbox of the route inside the fraction
    /// range, expanded by the lateral/forward margins (converted to map points
    /// — the old code added meters as raw points, ~100× too small), then
    /// aspect-fitted to the canvas so every window matches its aspect exactly.
    private static func windowRect(
        route: [RoutePoint],
        from: Double,
        to: Double,
        total: Double,
        cumulative: [Double],
        lateralMeters: Double,
        canvas: CGSize
    ) -> MKMapRect {
        // Cover both the lateral spread of the rotated frame and the forward
        // look-ahead, so the camera never sees past the snapshot edge at a
        // window boundary.
        let forward = lateralMeters / max(lateralRatio, 1e-6)
        let marginMeters = max(lateralMeters * 1.05, forward * 1.15)
        var minX = Double.greatestFiniteMagnitude, maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude, maxY = -Double.greatestFiniteMagnitude
        for (i, p) in route.enumerated() {
            let fraction = total > 0 ? cumulative[i] / total : 0
            guard fraction >= from - 0.02 && fraction <= to else { continue }
            let mp = MKMapPoint(p.coordinate)
            minX = min(minX, mp.x); maxX = max(maxX, mp.x)
            minY = min(minY, mp.y); maxY = max(maxY, mp.y)
        }
        guard minX <= maxX, minY <= maxY else { return .null }
        let midLat = route.reduce(0.0) { $0 + $1.latitude } / Double(route.count)
        let pointsPerMeter = MKMapPointsPerMeterAtLatitude(midLat)
        let margin = marginMeters * pointsPerMeter
        var width = max(maxX - minX, 0) + margin * 2
        var height = max(maxY - minY, 0) + margin * 2
        let canvasAspect = Double(canvas.width / max(canvas.height, 1))
        let rectAspect = width / max(height, 1e-9)
        if rectAspect < canvasAspect {
            width = height * canvasAspect
        } else {
            height = width / canvasAspect
        }
        width *= 1.02; height *= 1.02
        return MKMapRect(x: (minX + maxX) / 2 - width / 2, y: (minY + maxY) / 2 - height / 2, width: width, height: height)
    }
}
