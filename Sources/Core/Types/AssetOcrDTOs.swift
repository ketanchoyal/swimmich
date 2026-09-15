import Foundation

/// One detected text box of an asset — `GET /api/assets/{id}/ocr` answers an
/// **array** of these (gap #8, ocr-text).
///
/// Mirrors `AssetOcrResponseDto` of the published OpenAPI exactly: all thirteen
/// fields are `required`. `CodingKeys` is explicit so a one-letter coordinate
/// key never depends on the decoder's automatic key mapping.
///
/// The eight coordinates are the **four corners** of the box, normalized to
/// 0–1 on the stored image: `x1`/`y1` = top-left, `x2`/`y2` = top-right,
/// `x3`/`y3` = bottom-right, `x4`/`y4` = bottom-left. A box can be tilted, so
/// it is a quadrilateral — never an axis-aligned `CGRect`.
struct AssetOcrResponseDto: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let assetId: String
    /// Recognized text of the box.
    let text: String
    /// Confidence score for the text detection box.
    let boxScore: Double
    /// Confidence score for the text recognition.
    let textScore: Double
    let x1: Double
    let x2: Double
    let x3: Double
    let x4: Double
    let y1: Double
    let y2: Double
    let y3: Double
    let y4: Double

    enum CodingKeys: String, CodingKey {
        case id, assetId, text, boxScore, textScore
        case x1, x2, x3, x4, y1, y2, y3, y4
    }
}

/// A text box as four **normalized** (0–1) corners, in the server's order.
struct OcrQuad: Equatable, Sendable {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomRight: CGPoint
    let bottomLeft: CGPoint

    /// The four corners clockwise from the top-left.
    var corners: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }
}

extension AssetOcrResponseDto {
    /// The box as a quadrilateral (the server's corner → corner convention).
    var quad: OcrQuad {
        OcrQuad(
            topLeft: CGPoint(x: x1, y: y1),
            topRight: CGPoint(x: x2, y: y2),
            bottomRight: CGPoint(x: x3, y: y3),
            bottomLeft: CGPoint(x: x4, y: y4)
        )
    }

    /// Display threshold for the text label — a client-side cut-off, **not** a
    /// server filter: a low-confidence box is still drawn.
    var isConfident: Bool { textScore >= 0.5 }
}
