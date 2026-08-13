import Foundation

/// Decodes a server-config QR payload (Flutter convention):
/// 1. JSON `{"serverUrl": "https://…"}` (also tolerates `{"url": …}`),
/// 2. a bare URL string (`photos.example.com` → `https://photos.example.com`),
/// 3. anything else → `nil`.
enum QRServerConfigParser {

    /// Parses + normalizes a scanned payload into a server base URL.
    static func parse(_ payload: String) -> URL? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) {
            if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for key in ["serverUrl", "url"] {
                    if let raw = dict[key] as? String, let url = normalize(raw) {
                        return url
                    }
                }
            }
            return nil
        }
        return normalize(trimmed)
    }

    private static func normalize(_ raw: String) -> URL? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return nil }
        if !value.contains("://") { value = "https://" + value }
        while value.hasSuffix("/") { value.removeLast() }
        guard let url = URL(string: value), url.host != nil else { return nil }
        return url
    }
}
