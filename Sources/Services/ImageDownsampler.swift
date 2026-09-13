import AVFoundation
import ImageIO
import UIKit

/// Downsamples image files with ImageIO instead of decoding them whole.
///
/// A cached asset is an **original**: a 12-megapixel photo decoded at full size
/// per grid cell is tens of megabytes of bitmap sitting in the scroll path.
/// `CGImageSourceCreateThumbnailAtIndex` reads only what it needs and applies
/// the EXIF orientation, so a cached tile costs a thumbnail-sized bitmap.
///
/// Returns nil for anything ImageIO can't read as an image — a cached video has
/// no still frame here (see `videoPoster(at:maxPixelSize:)` for that case).
enum ImageDownsampler {

    static func image(at url: URL, maxPixelSize: Int = 2048) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(64, maxPixelSize)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    /// First frame of a local video file, for cached-video tiles.
    ///
    /// Without this a cached video shows the failure placeholder in the offline
    /// grid: its thumbnail normally comes from the server, which is exactly what
    /// isn't reachable. `maximumSize` is capped the same way, so the tile stays a
    /// thumbnail rather than a frame buffer.
    ///
    /// Synchronous and bounded: one seek to time zero on a local file. Returns
    /// nil on any failure — a tile falls back to the placeholder rather than
    /// blocking the grid.
    static func videoPoster(at url: URL, maxPixelSize: Int = 1024) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
