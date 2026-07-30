import Foundation
import CoreImage
import CoreGraphics
import simd

// MARK: - EditPipeline
//
// Pure, non-isolated, unit-testable functions implementing the non-destructive edit
// pipeline (cahier §5). No UIKit, no CIContext — operates on `CIImage` only.
//
// Pipeline order (FM-1, FM-5):
//   1. Color filters: exposure → color(contrast+saturation combined) → warmth
//   2. Crop (cropRect normalized UIKit-space → CoreImage pixels, Y-axis flip)
//   3. Rotate (totalRotationDeg around crop center if cropRect!=nil, else original extent center)
//
// Neutral state = identity (extent unchanged).

enum EditPipeline {

    // MARK: Filters (AC-607)

    /// Builds the ordered list of CIFilters for the color-adjustment phase.
    /// Neutral values are omitted (empty array for `.neutral`).
    ///
    /// Order: exposure (CIExposureAdjust) → color (CIColorControls UNIQUE, contrast+saturation combined)
    /// → warmth (CITemperatureAndTint). FM-1.
    static func buildEditFilters(for state: EditState) -> [CIFilter] {
        var filters: [CIFilter] = []

        // Exposure — CIExposureAdjust.inputEV
        if state.exposure != 0 {
            let f = CIFilter(name: "CIExposureAdjust")!
            f.setValue(state.exposure, forKey: "inputEV")
            filters.append(f)
        }

        // Contrast + Saturation combined into ONE CIColorControls filter (loop 2 advisory resolution).
        if state.contrast != 0 || state.saturation != 0 {
            let f = CIFilter(name: "CIColorControls")!
            f.setValue(state.contrast, forKey: "inputContrast")
            f.setValue(state.saturation, forKey: "inputSaturation")
            // inputBrightness stays neutral (0).
            filters.append(f)
        }

        // Warmth — CITemperatureAndTint. Scale warmth [-1,+1] → ±1500K temperature delta.
        if state.warmth != 0 {
            let f = CIFilter(name: "CITemperatureAndTint")!
            f.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            f.setValue(CIVector(x: 6500 + state.warmth * 1500, y: 0), forKey: "inputTargetNeutral")
            filters.append(f)
        }

        return filters
    }

    // MARK: Apply (AC-607, AC-619)

    /// Applies the full pipeline to a `CIImage`. Pure function, deterministic.
    /// FM-1 (filter order), FM-4 (Y-flip crop), FM-5 (crop→rotate order).
    static func applyEditState(to image: CIImage, state: EditState) -> CIImage {
        // 1. Color filters
        var output = image
        for filter in buildEditFilters(for: state) {
            filter.setValue(output, forKey: kCIInputImageKey)
            guard let filtered = filter.outputImage else { continue }
            output = filtered
        }

        // 2. Crop (normalized UIKit-space → CoreImage pixels, Y-axis flip)
        if let crop = state.cropRect {
            let extent = output.extent
            if extent.width > 0 && extent.height > 0 {
                let xPx = crop.origin.x * extent.width
                // UIKit top-left vs CoreImage bottom-left → flip Y.
                let yPx = (1.0 - crop.origin.y - crop.height) * extent.height
                let wPx = crop.width * extent.width
                let hPx = crop.height * extent.height
                let pixelRect = CGRect(x: xPx, y: yPx, width: wPx, height: hPx)
                if let cropFilter = CIFilter(name: "CICrop") {
                    cropFilter.setValue(output, forKey: kCIInputImageKey)
                    cropFilter.setValue(CIVector(cgRect: pixelRect), forKey: "inputRectangle")
                    if let cropped = cropFilter.outputImage {
                        output = cropped
                    }
                }
            }
        }

        // 3. Rotate — totalRotationDeg around the center of the (possibly cropped) extent.
        let totalDeg = state.totalRotationDeg
        if totalDeg != 0 {
            let center = CGPoint(x: output.extent.midX, y: output.extent.midY)
            let radians = totalDeg * .pi / 180.0
            // Translate(-C) → Rotate → Translate(+C).
            // t.concatenating(u) applies u first, then t. Compose accordingly.
            let toOrigin = CGAffineTransform(translationX: -center.x, y: -center.y)
            let rotation = CGAffineTransform(rotationAngle: radians)
            let fromOrigin = CGAffineTransform(translationX: center.x, y: center.y)
            let combined = fromOrigin.concatenating(rotation.concatenating(toOrigin))
            output = output.transformed(by: combined)
        }

        return output
    }

    // MARK: Gesture helper (AC-618)

    /// Converts a gesture-space CGRect (view points) to normalized 0..1 coordinates
    /// relative to the display size. Pure helper, unit-testable.
    static func gestureRectToNormalized(_ gestureRect: CGRect, in displaySize: CGSize) -> CGRect {
        guard displaySize.width > 0 && displaySize.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        return CGRect(
            x: gestureRect.origin.x / displaySize.width,
            y: gestureRect.origin.y / displaySize.height,
            width: gestureRect.width / displaySize.width,
            height: gestureRect.height / displaySize.height
        )
    }
}
