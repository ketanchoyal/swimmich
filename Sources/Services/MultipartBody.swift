import Foundation

/// Builds multipart/form-data request bodies for asset uploads.
struct MultipartBody {
    let boundary: String
    private let crlf = "\r\n"
    private var parts: [Data] = []

    init(boundary: String = "----ImmichBoundary-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    /// Adds a text form field.
    mutating func append(name: String, value: String) {
        var part = Data()
        part.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        part.append("Content-Disposition: form-data; name=\"\(name)\"\(crlf)\(crlf)".data(using: .utf8)!)
        part.append("\(value)\(crlf)".data(using: .utf8)!)
        parts.append(part)
    }

    /// Adds a binary file field.
    mutating func append(name: String, filename: String, contentType: String, data: Data) {
        var part = Data()
        part.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        part.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\(crlf)".data(using: .utf8)!)
        part.append("Content-Type: \(contentType)\(crlf)\(crlf)".data(using: .utf8)!)
        part.append(data)
        part.append(crlf.data(using: .utf8)!)
        parts.append(part)
    }

    /// Finalizes the body by appending the closing boundary.
    func encoded() -> Data {
        var body = Data()
        for part in parts { body.append(part) }
        body.append("--\(boundary)--\(crlf)".data(using: .utf8)!)
        return body
    }

    /// Total byte length of the finalized body (computed without mutating).
    var totalLength: Int {
        var len = 0
        for p in parts { len += p.count }
        let closing = "--\(boundary)--\(crlf)".data(using: .utf8)!.count
        return len + closing
    }

    /// Content-Type header value.
    var contentType: String { "multipart/form-data; boundary=\(boundary)" }
}
