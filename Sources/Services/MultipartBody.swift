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

    /// Streams a complete multipart body to `destination`: one binary file
    /// field whose bytes are copied from `fileField.fileURL` in bounded
    /// chunks, then the text `fields`, then the closing boundary. Never holds
    /// the file in memory — the caller uploads via `URLSession.upload(fromFile:)`.
    func writeStreamed(
        fileField: (name: String, filename: String, contentType: String, fileURL: URL),
        fields: [(name: String, value: String)],
        to destination: URL
    ) throws {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let out = try FileHandle(forWritingTo: destination)
        defer { try? out.close() }

        func write(_ string: String) throws {
            try out.write(contentsOf: Data(string.utf8))
        }

        // File part header.
        try write("--\(boundary)\(crlf)")
        try write("Content-Disposition: form-data; name=\"\(fileField.name)\"; filename=\"\(fileField.filename)\"\(crlf)")
        try write("Content-Type: \(fileField.contentType)\(crlf)\(crlf)")

        // File bytes, streamed from disk one chunk at a time.
        let input = try FileHandle(forReadingFrom: fileField.fileURL)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
            try out.write(contentsOf: chunk)
        }
        try write(crlf)

        // Text fields.
        for field in fields {
            try write("--\(boundary)\(crlf)")
            try write("Content-Disposition: form-data; name=\"\(field.name)\"\(crlf)\(crlf)")
            try write("\(field.value)\(crlf)")
        }

        // Closing boundary.
        try write("--\(boundary)--\(crlf)")
    }

    /// Content-Type header value.
    var contentType: String { "multipart/form-data; boundary=\(boundary)" }
}
