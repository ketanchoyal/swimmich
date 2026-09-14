import Foundation
import ImageIO
import UIKit
import os

/// Shrinks the JPEG/PNG bytes the widget carries in its timeline entry.
///
/// WidgetKit archives every entry to disk and reads it back to render. An entry
/// carrying the server's full-size thumbnails (a `preview` hero is ~300 KB, and
/// a wall holds several) can fail to archive — and a widget whose entry was
/// never archived shows its **placeholder forever**: no photos, no error, no log
/// line on the extension side. That is exactly the symptom this project chased
/// for two days, and the reason it never reproduced on a simulator: the test
/// stub serves 8×8 PNGs, so the entry stayed tiny.
///
/// So the bytes are re-encoded here, once per fetch, at the size the widget can
/// actually draw: the hero gets room for a large-family tile, satellites are
/// small, and the whole wall stays inside `budget`.
enum WidgetImageEncoder {

    /// Total image bytes an entry may carry. Comfortably below what WidgetKit
    /// refuses to archive, and small enough to keep the whole widget cheap.
    static let budget = 256 * 1024

    /// Longest edge, in pixels, for a re-encoded image.
    enum Size: CGFloat {
        /// A hero drawn across a large widget. 900 px is under the 1032 px a
        /// 344 pt tile wants at 3×, and keeps the encoded weight around 100 KB
        /// for a real photo — the difference is invisible behind the widget's
        /// corner radius and scrim.
        case hero = 900
        /// A mosaic cell (a third of a medium widget).
        case cell = 320
    }

    /// Re-encodes `data` at `size`. Returns nil when the bytes cannot be decoded
    /// (the caller then renders its branded plate) or when re-encoding would not
    /// help.
    static func encode(_ data: Data, at size: Size, quality: CGFloat = 0.6) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: size.rawValue,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let renderer = UIImage(cgImage: thumbnail)
        return renderer.jpegData(compressionQuality: quality)
    }

    /// Re-encodes a wall's photos, hero first, and stops attaching bytes once
    /// `budget` is spent — a partial mosaic beats an entry that never renders.
    static func budgeted(_ photos: [WidgetPhoto], budget: Int = budget) -> [WidgetPhoto] {
        var spent = 0
        return photos.enumerated().map { index, photo in
            guard let data = photo.imageData else { return photo }
            let size: Size = index == 0 ? .hero : .cell
            guard let encoded = encode(data, at: size), spent + encoded.count <= budget else {
                // Drop the bytes, keep the cell: `hydrating(with: nil)` is a
                // no-op by design, so this needs a fresh photo.
                return WidgetPhoto(
                    id: photo.id,
                    imageData: nil,
                    isVideo: photo.isVideo,
                    isFavorite: photo.isFavorite,
                    day: photo.day
                )
            }
            spent += encoded.count
            return WidgetPhoto(
                id: photo.id,
                imageData: encoded,
                isVideo: photo.isVideo,
                isFavorite: photo.isFavorite,
                day: photo.day
            )
        }
    }
}
