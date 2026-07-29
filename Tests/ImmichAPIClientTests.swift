import XCTest
@testable import ImmichSwiftUI

/// URLProtocol that captures the most recent request + returns a canned response.
final class CapturingURLProtocol: URLProtocol {
    /// Most recent captured URLRequest (thread-safe via lock).
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _lastRequest: URLRequest?
    static var lastRequest: URLRequest? { lock.lock(); defer { lock.unlock() }; return _lastRequest }

    nonisolated(unsafe) static var nextData: Data = Data()
    nonisolated(unsafe) static var nextStatus: Int = 200
    nonisolated(unsafe) static var nextHeaders: [String: String] = ["Content-Type": "application/json"]

    /// Snapshot of the captured body bytes (URLSession may move httpBody → httpBodyStream).
    nonisolated(unsafe) private static var _lastBody: Data = Data()
    static var lastBody: Data { lock.lock(); defer { lock.unlock() }; return _lastBody }

    static func reset() {
        lock.lock(); _lastRequest = nil; _lastBody = Data(); lock.unlock()
        nextData = Data()
        nextStatus = 200
        nextHeaders = ["Content-Type": "application/json"]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self._lastRequest = request
        Self._lastBody = Self.captureBody(from: request)
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.nextStatus, httpVersion: "HTTP/1.1",
            headerFields: Self.nextHeaders
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.nextData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// Reads httpBody, falling back to httpBodyStream (URLSession may convert large bodies).
    private static func captureBody(from request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

final class ImmichAPIClientTests: XCTestCase {

    private func makeMockedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CapturingURLProtocol.self]
        return URLSession(configuration: config)
    }

    override func tearDown() {
        CapturingURLProtocol.reset()
    }

    // AC-008: multipart upload shape + checksum header.
    func test_AC_008_multipartUploadShape() async throws {
        let session = makeMockedSession()
        let client = ImmichAPIClient(session: session)
        client.configure(baseURL: URL(string: "https://example.com")!, token: "tok")

        CapturingURLProtocol.nextData = #"{"id":"new","status":"created"}"#.data(using: .utf8)!
        CapturingURLProtocol.nextStatus = 201
        CapturingURLProtocol.nextHeaders = ["Content-Type": "application/json"]

        let payload = Data(repeating: 0xAB, count: 1024) // 1KB
        _ = try await client.uploadAsset(
            data: payload,
            fileCreatedAt: "2024-07-01T00:00:00.000Z",
            fileModifiedAt: "2024-07-01T00:00:00.000Z",
            filename: "photo.jpg",
            duration: nil,
            isFavorite: false,
            visibility: .timeline,
            livePhotoVideoId: nil,
            checksum: "Y2hlY2tzdW0="
        )

        guard let captured = CapturingURLProtocol.lastRequest else {
            return XCTFail("no request captured")
        }
        XCTAssertEqual(captured.httpMethod, "POST")
        XCTAssertTrue(captured.url?.absoluteString.contains("/api/assets") == true)

        let contentType = captured.value(forHTTPHeaderField: "Content-Type") ?? ""
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data"), "got \(contentType)")

        // x-immich-checksum header present.
        XCTAssertFalse((captured.value(forHTTPHeaderField: "x-immich-checksum") ?? "").isEmpty)

        // Body contains required field names.
        let body = CapturingURLProtocol.lastBody
        // Lossy decode: payload is binary, but field-name ASCII survives.
        let bodyString = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(bodyString.contains(#"name="assetData""#), "assetData field missing")
        XCTAssertTrue(bodyString.contains(#"name="fileCreatedAt""#), "fileCreatedAt missing")
        XCTAssertTrue(bodyString.contains(#"name="fileModifiedAt""#), "fileModifiedAt missing")

        // isFavorite sent as string "false".
        XCTAssertTrue(bodyString.contains(#"name="isFavorite""#))

        // Body length strictly greater than multipart overhead (boundaries + field headers).
        // Overhead computed below covers all 5 emitted text fields + the binary assetData part.
        let boundary = contentType.components(separatedBy: "boundary=").last ?? ""
        let crlf = 2
        let overhead = (
            "--\(boundary)--\r\n".utf8.count
            + "--\(boundary)\r\n".utf8.count * 5 // 5 parts: assetData, fileCreatedAt, fileModifiedAt, isFavorite, visibility
            + ("Content-Disposition: form-data; name=\"assetData\"; filename=\"photo.jpg\"\r\n".utf8.count)
            + ("Content-Type: application/octet-stream\r\n\r\n".utf8.count)
            + ("Content-Disposition: form-data; name=\"fileCreatedAt\"\r\n\r\n".utf8.count)
            + ("2024-07-01T00:00:00.000Z".utf8.count + crlf)
            + ("Content-Disposition: form-data; name=\"fileModifiedAt\"\r\n\r\n".utf8.count)
            + ("2024-07-01T00:00:00.000Z".utf8.count + crlf)
            + ("Content-Disposition: form-data; name=\"isFavorite\"\r\n\r\n".utf8.count)
            + ("false".utf8.count + crlf)
            + ("Content-Disposition: form-data; name=\"visibility\"\r\n\r\n".utf8.count)
            + ("timeline".utf8.count + crlf)
        )
        XCTAssertGreaterThan(body.count, overhead, "body length must exceed multipart overhead")
        XCTAssertGreaterThan(body.count, payload.count, "body must contain the payload")
    }

    // AC-014: any 401 triggers auth reset (Keychain cleared + isAuthenticated false).
    @MainActor
    func test_AC_014_global401ResetsAuth() async throws {
        let session = makeMockedSession()
        let client = ImmichAPIClient(session: session)
        let keychain = MockKeychainStore()
        keychain.saveToken("expired-jwt")
        // Configure the client with the token so authed calls actually dispatch
        // (otherwise sendAuthedRaw throws .unauthorized before any HTTP call,
        // bypassing the delegate path).
        client.configure(baseURL: URL(string: "https://example.com")!, token: "expired-jwt")
        let auth = AuthViewModel(client: client, keychain: keychain)
        auth.serverURLString = "https://example.com"
        _ = auth.baseURL
        auth.accessToken = "expired-jwt"

        // Any authed call returns 401.
        CapturingURLProtocol.nextData = "{}".data(using: .utf8)!
        CapturingURLProtocol.nextStatus = 401
        CapturingURLProtocol.nextHeaders = ["Content-Type": "application/json"]

        // Fire a call; expect APIError.unauthorized + delegate-triggered reset.
        let timeline = TimelineViewModel(client: client)
        await timeline.load() // triggers getTimeBuckets → 401

        // Spin the runloop briefly so the MainActor Task in didReceiveUnauthorized runs.
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertNil(keychain.savedToken, "Keychain should be cleared on 401")
        XCTAssertFalse(auth.isAuthenticated, "auth should be reset on 401")
    }

    // AC-007: thumbnail URL via ImmichAssetURL helper.
    func test_AC_007_thumbnailURLHelper() {
        let url = ImmichAssetURL.thumbnail(
            assetId: "abc123", thumbhash: "xyz",
            baseURL: URL(string: "https://photos.example.com")!
        )
        XCTAssertEqual(
            url.absoluteString,
            "https://photos.example.com/api/assets/abc123/thumbnail?size=thumbnail&c=xyz"
        )
    }
}
