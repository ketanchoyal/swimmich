import Foundation

/// Builds multipart/form-data request bodies for asset uploads.
///
/// Lives in `ImmichSharedKit` because the share extension uploads from its own
/// process and cannot see `Sources/Services`: an extension only links the kit.
/// The app target compiles `Sources/` as one flat entry, so the type is also
/// compiled straight into the app and `ImmichAPIClient` keeps using it without
/// importing the framework. Public so both consumers can reach it.
public struct MultipartBody {
    public let boundary: String
    private let crlf = "\r\n"
    private var parts: [Data] = []

    public init(boundary: String = "----ImmichBoundary-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    /// Adds a text form field.
    public mutating func append(name: String, value: String) {
        var part = Data()
        part.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        part.append("Content-Disposition: form-data; name=\"\(name)\"\(crlf)\(crlf)".data(using: .utf8)!)
        part.append("\(value)\(crlf)".data(using: .utf8)!)
        parts.append(part)
    }

    /// Adds a binary file field.
    public mutating func append(name: String, filename: String, contentType: String, data: Data) {
        var part = Data()
        part.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        part.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\(crlf)\(crlf)".data(using: .utf8)!)
        part.append("Content-Type: \(contentType)\(crlf)\(crlf)".data(using: .utf8)!)
        part.append(data)
        part.append(crlf.data(using: .utf8)!)
        parts.append(part)
    }

    /// Finalizes the body by appending the closing boundary.
    public func encoded() -> Data {
        var body = Data()
        for part in parts { body.append(part) }
        body.append("--\(boundary)--\(crlf)".data(using: .utf8)!)
        return body
    }

    /// Total byte length of the finalized body (computed without mutating).
    public var totalLength: Int {
        var len = 0
        for p in parts { len += p.count }
        let closing = "--\(boundary)--\(crlf)".data(using: .utf8)!.count
        return len + closing
    }

    /// Streams a complete multipart body to `destination`: one binary file
    /// field whose bytes are copied from `fileField.fileURL` in bounded
    /// chunks, then the text `fields`, then the closing boundary. Never holds
    /// the file in memory — the caller uploads via `URLSession.upload(fromFile:)`.
    ///
    /// Declared `mutating` alongside `append`: a body is built and written in
    /// place, so callers hold it in a `var`. It does not read the in-memory
    /// `parts`.
    public mutating func writeStreamed(
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

        // File bytes, streamed from disk one chunk at a time. Each iteration is
        // wrapped in an autorelease pool: FileHandle.read hands back an
        // autoreleased NSData whose backing bytes would otherwise accumulate for
        // the entire file — gigabytes for a video — until this function returns,
        // OOM-killing the process. Draining per chunk pins peak memory at one
        // chunk, which is what makes a video tenable inside an extension's
        // small budget.
        let input = try FileHandle(forReadingFrom: fileField.fileURL)
        defer { try? input.close() }
        while try autoreleasepool(invoking: {
            guard let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty else { return false }
            try out.write(contentsOf: chunk)
            return true
        }) {}
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
    public var contentType: String { "multipart/form-data; boundary=\(boundary)" }
}
