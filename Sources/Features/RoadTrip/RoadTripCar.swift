import UIKit
import CoreGraphics

/// Renders a shaded side-view car (nose pointing +x) to a single `CGImage`,
/// shared by the live map annotation and the export renderer so the car looks
/// identical in both. Drawn with Core Graphics — no external asset, no SwiftUI.
enum RoadTripCar {

    static func render() -> CGImage {
        let size = CGSize(width: 320, height: 160)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in draw() }.cgImage!
    }

    private static func draw() {
        // Wheels first (their top half hides under the body).
        drawWheel(center: CGPoint(x: 95, y: 112), radius: 20)
        drawWheel(center: CGPoint(x: 245, y: 112), radius: 20)

        // Body silhouette (nose at +x).
        let body = UIBezierPath()
        body.move(to: CGPoint(x: 40, y: 112))
        body.addLine(to: CGPoint(x: 46, y: 84))
        body.addQuadCurve(to: CGPoint(x: 72, y: 66), controlPoint: CGPoint(x: 50, y: 68))
        body.addLine(to: CGPoint(x: 196, y: 66))
        body.addQuadCurve(to: CGPoint(x: 252, y: 82), controlPoint: CGPoint(x: 228, y: 60))
        body.addLine(to: CGPoint(x: 296, y: 90))
        body.addQuadCurve(to: CGPoint(x: 300, y: 104), controlPoint: CGPoint(x: 306, y: 96))
        body.addLine(to: CGPoint(x: 40, y: 112))
        body.close()

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = [
            UIColor(white: 0.30, alpha: 1).cgColor,
            UIColor(white: 0.10, alpha: 1).cgColor
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) {
            let context = UIGraphicsGetCurrentContext()!
            context.saveGState()
            body.addClip()
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 60),
                end: CGPoint(x: 0, y: 118),
                options: []
            )
            context.restoreGState()
        } else {
            UIColor(white: 0.20, alpha: 1).setFill()
            body.fill()
        }

        // Glass cabin.
        let glass = UIBezierPath(roundedRect: CGRect(x: 84, y: 72, width: 112, height: 22), cornerRadius: 8)
        if let glassGradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                UIColor(red: 0.10, green: 0.12, blue: 0.18, alpha: 1).cgColor,
                UIColor(red: 0.05, green: 0.07, blue: 0.11, alpha: 1).cgColor
            ] as CFArray,
            locations: [0, 1]
        ) {
            let context = UIGraphicsGetCurrentContext()!
            context.saveGState()
            glass.addClip()
            context.drawLinearGradient(glassGradient, start: CGPoint(x: 0, y: 70), end: CGPoint(x: 0, y: 96), options: [])
            context.restoreGState()
        } else {
            UIColor(red: 0.08, green: 0.10, blue: 0.15, alpha: 1).setFill()
            glass.fill()
        }

        // Glass highlight streak.
        UIColor.white.withAlphaComponent(0.25).setFill()
        UIBezierPath(roundedRect: CGRect(x: 90, y: 74, width: 70, height: 5), cornerRadius: 2.5).fill()

        // Headlight + taillight.
        UIColor(red: 1.0, green: 0.95, blue: 0.8, alpha: 1).setFill()
        UIBezierPath(roundedRect: CGRect(x: 294, y: 92, width: 7, height: 10), cornerRadius: 2).fill()
        UIColor(red: 0.95, green: 0.25, blue: 0.22, alpha: 1).setFill()
        UIBezierPath(roundedRect: CGRect(x: 42, y: 92, width: 6, height: 9), cornerRadius: 2).fill()

        // Body top highlight (specular edge).
        UIColor.white.withAlphaComponent(0.5).setStroke()
        let highlight = UIBezierPath()
        highlight.move(to: CGPoint(x: 74, y: 67))
        highlight.addLine(to: CGPoint(x: 194, y: 67))
        highlight.addQuadCurve(to: CGPoint(x: 250, y: 82), controlPoint: CGPoint(x: 226, y: 61))
        highlight.lineWidth = 2
        highlight.stroke()
    }

    private static func drawWheel(center: CGPoint, radius: CGFloat) {
        let context = UIGraphicsGetCurrentContext()!
        // Tire.
        context.setFillColor(UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1).cgColor)
        context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        // Rim.
        context.setFillColor(UIColor(red: 0.35, green: 0.38, blue: 0.45, alpha: 1).cgColor)
        context.fillEllipse(in: CGRect(x: center.x - radius * 0.62, y: center.y - radius * 0.62, width: radius * 1.24, height: radius * 1.24))
        // Hub.
        context.setFillColor(UIColor(red: 0.75, green: 0.78, blue: 0.85, alpha: 1).cgColor)
        context.fillEllipse(in: CGRect(x: center.x - radius * 0.28, y: center.y - radius * 0.28, width: radius * 0.56, height: radius * 0.56))
    }
}
