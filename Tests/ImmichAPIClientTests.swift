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
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("upload-test-\(UUID().uuidString).bin")
        try payload.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        _ = try await client.uploadAsset(
            fileURL: tmp,
            fileCreatedAt: "2024-07-01T00:00:00.000Z",
            fileModifiedAt: "2024-07-01T00:00:00.000Z",
            filename: "photo.jpg",
            duration: nil,
            isFavorite: false,
            visibility: .timeline,
            livePhotoVideoId: nil,
            checksum: "Y2hlY2tzdW0=",
            deviceAssetId: "local://asset-1",
            deviceId: "device-uuid"
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
        XCTAssertTrue(bodyString.contains(#"name="deviceAssetId""#), "deviceAssetId missing")
        XCTAssertTrue(bodyString.contains(#"name="deviceId""#), "deviceId missing")

        // isFavorite sent as string "false".
        XCTAssertTrue(bodyString.contains(#"name="isFavorite""#))

        // Body length strictly greater than multipart overhead (boundaries + field headers).
        // Overhead computed below covers all 5 emitted text fields + the binary assetData part.
        let boundary = contentType.components(separatedBy: "boundary=").last ?? ""
        let crlf = 2
        let overhead = (
            "--\(boundary)--\r\n".utf8.count
            + "--\(boundary)\r\n".utf8.count * 7 // 7 parts: assetData, fileCreatedAt, fileModifiedAt, deviceAssetId, deviceId, isFavorite, visibility
            + ("Content-Disposition: form-data; name=\"assetData\"; filename=\"photo.jpg\"\r\n".utf8.count)
            + ("Content-Type: application/octet-stream\r\n\r\n".utf8.count)
            + ("Content-Disposition: form-data; name=\"fileCreatedAt\"\r\n\r\n".utf8.count)
            + ("2024-07-01T00:00:00.000Z".utf8.count + crlf)
            + ("Content-Disposition: form-data; name=\"fileModifiedAt\"\r\n\r\n".utf8.count)
            + ("2024-07-01T00:00:00.000Z".utf8.count + crlf)
            + ("Content-Disposition: form-data; name=\"deviceAssetId\"\r\n\r\n".utf8.count)
            + ("local://asset-1".utf8.count + crlf)
            + ("Content-Disposition: form-data; name=\"deviceId\"\r\n\r\n".utf8.count)
            + ("device-uuid".utf8.count + crlf)
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
        let suite = "ImmichAPIClientTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let auth = AuthViewModel(client: client, keychain: keychain, defaults: defaults)
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

    // AC-710: map markers request path + optional query params + decoding.
    func test_AC_710_mapMarkersRequest() async throws {
        let session = makeMockedSession()
        let client = ImmichAPIClient(session: session)
        client.configure(baseURL: URL(string: "https://example.com")!, token: "tok")

        CapturingURLProtocol.nextData = #"""
        [{"id":"a1","lat":48.8566,"lon":2.3522,"city":"Paris","state":null,"country":"France"}]
        """#.data(using: .utf8)!
        CapturingURLProtocol.nextStatus = 200

        let markers = try await client.getMapMarkers(isFavorite: true, isArchived: nil)

        guard let captured = CapturingURLProtocol.lastRequest else {
            return XCTFail("no request captured")
        }
        XCTAssertEqual(captured.httpMethod, "GET")
        XCTAssertTrue(captured.url?.absoluteString.contains("/api/map/markers") == true)
        XCTAssertTrue(captured.url?.absoluteString.contains("isFavorite=true") == true, "favorite filter must be encoded")
        XCTAssertFalse(captured.url?.absoluteString.contains("isArchived") == true, "nil filter must be omitted")

        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(markers.first?.id, "a1")
        XCTAssertEqual(markers.first?.lat, 48.8566)
        XCTAssertEqual(markers.first?.city, "Paris")
        XCTAssertNil(markers.first?.state)
    }

    // AC-710: map markers without filters → no query params.
    func test_AC_710_mapMarkersNoFilters() async throws {
        let session = makeMockedSession()
        let client = ImmichAPIClient(session: session)
        client.configure(baseURL: URL(string: "https://example.com")!, token: "tok")

        CapturingURLProtocol.nextData = "[]".data(using: .utf8)!

        _ = try await client.getMapMarkers(isFavorite: nil, isArchived: nil)

        guard let captured = CapturingURLProtocol.lastRequest else {
            return XCTFail("no request captured")
        }
        XCTAssertEqual(captured.url?.query, nil, "no query params expected")
    }

    // Photo share: GET /api/users returns the instance users.
    func test_photoShare_getUsers_hitsUsersEndpoint() async throws {
        let session = makeMockedSession()
        let client = ImmichAPIClient(session: session)
        client.configure(baseURL: URL(string: "https://example.com")!, token: "tok")

        let usersJSON = """
        [{"id":"u1","name":"Alice","email":"alice@example.com","profileImagePath":"","avatarColor":"#4250AF","profileChangedAt":"2024-01-01T00:00:00.000Z"}]
        """
        CapturingURLProtocol.nextData = usersJSON.data(using: .utf8)!

        let users = try await client.getUsers()

        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(users.first?.id, "u1")
        XCTAssertEqual(users.first?.name, "Alice")

        guard let captured = CapturingURLProtocol.lastRequest else {
            return XCTFail("no request captured")
        }
        XCTAssertEqual(captured.httpMethod, "GET")
        XCTAssertEqual(captured.url?.path, "/api/users")
        XCTAssertEqual(captured.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    // MARK: - Album update (cover) + album users

    private static let albumJSON = """
    {
      "id": "alb-1",
      "albumName": "Trip",
      "description": "",
      "createdAt": "2024-01-01T00:00:00.000Z",
      "updatedAt": "2024-01-01T00:00:00.000Z",
      "albumThumbnailAssetId": "a1",
      "shared": true,
      "hasSharedLink": false,
      "assetCount": 2,
      "isActivityEnabled": false,
      "albumUsers": [
        {"user": {"id": "me", "name": "Me", "email": "me@example.com", "profileImagePath": "", "avatarColor": "#FF0000", "profileChangedAt": "2024-01-01T00:00:00.000Z"}, "role": "owner"}
      ]
    }
    """

    func test_album_setCover_patchesThumbnailAssetId() async throws {
        let session = makeMockedSession()
        let client = ImmichAPIClient(session: session)
        client.configure(baseURL: URL(string: "https://example.com")!, token: "tok")
        CapturingURLProtocol.nextData = Self.albumJSON.data(using: .utf8)!

        let album = try await client.updateAlbum(
            id: "alb-1",
            dto: UpdateAlbumDto(albumName: nil, description: nil, albumThumbnailAssetId: "a9", isActivityEnabled: nil, order: nil)
        )

        XCTAssertEqual(album.id, "alb-1")

        guard let captured = CapturingURLProtocol.lastRequest else {
            return XCTFail("no request captured")
        }
        XCTAssertEqual(captured.httpMethod, "PATCH")
        XCTAssertEqual(captured.url?.path, "/api/albums/alb-1")
        let body = String(decoding: CapturingURLProtocol.lastBody, as: UTF8.self)
        XCTAssertTrue(body.contains(#""albumThumbnailAssetId":"a9""#), "cover id must be sent")
        XCTAssertFalse(body.contains("albumName"), "nil fields must be omitted")
    }

    func test_album_addUsers_hitsPutUsersEndpoint() async throws {
        let session = makeMockedSession()
        let client = ImmichAPIClient(session: session)
        client.configure(baseURL: URL(string: "https://example.com")!, token: "tok")
        CapturingURLProtocol.nextData = Self.albumJSON.data(using: .utf8)!

        _ = try await client.addUsersToAlbum(
            albumId: "alb-1",
            dto: AddUsersDto(albumUsers: [AlbumUserDto(userId: "u1", role: .viewer)])
        )

        guard let captured = CapturingURLProtocol.lastRequest else {
            return XCTFail("no request captured")
        }
        XCTAssertEqual(captured.httpMethod, "PUT")
        XCTAssertEqual(captured.url?.path, "/api/albums/alb-1/users")
        let body = String(decoding: CapturingURLProtocol.lastBody, as: UTF8.self)
        XCTAssertTrue(body.contains(#""userId":"u1""#), "user id must be sent")
        XCTAssertTrue(body.contains(#""role":"viewer""#), "role must be sent")
    }

    func test_album_updateUserRole_hitsPutUserEndpoint() async throws {
        let session = makeMockedSession()
        let client = ImmichAPIClient(session: session)
        client.configure(baseURL: URL(string: "https://example.com")!, token: "tok")
        CapturingURLProtocol.nextStatus = 204

        try await client.updateAlbumUserRole(
            albumId: "alb-1",
            userId: "u1",
            dto: UpdateAlbumUserDto(role: .editor)
        )

        guard let captured = CapturingURLProtocol.lastRequest else {
            return XCTFail("no request captured")
        }
        XCTAssertEqual(captured.httpMethod, "PUT")
        XCTAssertEqual(captured.url?.path, "/api/albums/alb-1/user/u1")
        let body = String(decoding: CapturingURLProtocol.lastBody, as: UTF8.self)
        XCTAssertTrue(body.contains(#""role":"editor""#))
    }

    func test_album_removeUser_hitsDeleteUserEndpoint() async throws {
        let session = makeMockedSession()
        let client = ImmichAPIClient(session: session)
        client.configure(baseURL: URL(string: "https://example.com")!, token: "tok")
        CapturingURLProtocol.nextStatus = 204

        try await client.removeUserFromAlbum(albumId: "alb-1", userId: "u1")

        guard let captured = CapturingURLProtocol.lastRequest else {
            return XCTFail("no request captured")
        }
        XCTAssertEqual(captured.httpMethod, "DELETE")
        XCTAssertEqual(captured.url?.path, "/api/albums/alb-1/user/u1")
    }

    // MARK: - P0 api-surface-expansion endpoints

    private static let personJSON = """
    {"id": "p1", "name": "Alice", "birthDate": "1990-01-01", "thumbnailPath": "/thumbs/p1.jpg", "isHidden": false, "color": "#FF0000", "isFavorite": true, "updatedAt": "2024-01-01T00:00:00.000Z"}
    """

    func test_P0_getPeople_hitsPeopleEndpointWithQuery() async throws {
        let session = makeMockedSession()
        let client = ImmichAPIClient(session: session)
        client.configure(baseURL: URL(string: "https://example.com")!, token: "tok")
        CapturingURLProtocol.nextData = ("{\"people\": [\(Self.personJSON)], \"hidden\": 0, \"total\": 1, \"hasNextPage\": false}").data(using: .utf8)!

        let page = try await client.getPeople(page: 2, withHidden: true)

        XCTAssertEqual(page.total, 1)
        XCTAssertEqual(page.people.first?.name, "Alice")
        guard let captured = CapturingURLProtocol.lastRequest else {
            return XCTFail("no request captured")
        }
        XCTAssertEqual(captured.httpMethod, "GET")
        XCTAssertEqual(captured.url?.path, "/api/people")
        let query = captured.url?.query ?? ""
        XCTAssertTrue(query.contains("page=2"))
        XCTAssertTrue(query.contains("withHidden=true"))
    }

    func test_P0_mergePeople_usesPostMergeEndpoint() async throws {
        let session = makeMockedSession()
        let client = ImmichAPIClient(session: session)
        client.configure(baseURL: URL(string: "https://example.com")!, token: "tok")
        CapturingURLProtocol.nextData = "[{\"id\":\"p2\",\"success\":true}]".data(using: .utf8)!

        let results = try await client.mergePeople(ids: ["p2", "p3"], into: "p1")

        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results.first?.success == true)
        guard let captured = CapturingURLProtocol.lastRequest else {
            return XCTFail("no request captured")
        }
        XCTAssertEqual(captured.httpMethod, "POST", "merge is POST, not PUT")
        XCTAssertEqual(captured.url?.path, "/api/people/p1/merge")
        let body = String(decoding: CapturingURLProtocol.lastBody, as: UTF8.self)
        XCTAssertTrue(body.contains(#""ids":["p2","p3"]"#), "source ids must be sent")
    }

    func test_P0_getMemories_hitsMemoriesEndpoint() async throws {
        let session = makeMockedSession()
        let client = ImmichAPIClient(session: session)
        client.configure(baseURL: URL(string: "https://example.com")!, token: "tok")
        CapturingURLProtocol.nextData = """
        [{"id": "m1", "createdAt": "2024-01-01T00:00:00.000Z", "updatedAt": "2024-01-01T00:00:00.000Z", "memoryAt": "2023-06-15T00:00:00.000Z", "ownerId": "me", "type": "on_this_day", "data": {"year": 2023}, "assets": [], "isSaved": false}]
        """.data(using: .utf8)!

        let memories = try await client.getMemories()

        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(memories.first?.data.year, 2023)
        guard let captured = CapturingURLProtocol.lastRequest else {
            return XCTFail("no request captured")
        }
        XCTAssertEqual(captured.httpMethod, "GET")
        XCTAssertEqual(captured.url?.path, "/api/memories")
    }

    func test_P0_getDuplicates_hitsDuplicatesEndpoint() async throws {
        let session = makeMockedSession()
        let client = ImmichAPIClient(session: session)
        client.configure(baseURL: URL(string: "https://example.com")!, token: "tok")
        CapturingURLProtocol.nextData = """
        [{"duplicateId": "d1", "assets": [], "suggestedKeepAssetIds": ["keep-1"]}]
        """.data(using: .utf8)!

        let duplicates = try await client.getDuplicates()

        XCTAssertEqual(duplicates.count, 1)
        XCTAssertEqual(duplicates.first?.suggestedKeepAssetIds, ["keep-1"])
        guard let captured = CapturingURLProtocol.lastRequest else {
            return XCTFail("no request captured")
        }
        XCTAssertEqual(captured.url?.path, "/api/duplicates")
    }

    func test_P0_getPartners_hitsPartnersEndpoint() async throws {
        let session = makeMockedSession()
        let client = ImmichAPIClient(session: session)
        client.configure(baseURL: URL(string: "https://example.com")!, token: "tok")
        CapturingURLProtocol.nextData = """
        [{"id": "u9", "name": "Pat", "email": "pat@test", "profileImagePath": "", "avatarColor": "#00FF00", "profileChangedAt": "2024-01-01T00:00:00.000Z", "inTimeline": true}]
        """.data(using: .utf8)!

        let partners = try await client.getPartners()

        XCTAssertEqual(partners.count, 1)
        XCTAssertTrue(partners.first?.inTimeline == true)
        guard let captured = CapturingURLProtocol.lastRequest else {
            return XCTFail("no request captured")
        }
        XCTAssertEqual(captured.httpMethod, "GET")
        XCTAssertEqual(captured.url?.path, "/api/partners")
    }

    func test_P0_getActivities_hitsActivitiesEndpointWithQuery() async throws {
        let session = makeMockedSession()
        let client = ImmichAPIClient(session: session)
        client.configure(baseURL: URL(string: "https://example.com")!, token: "tok")
        CapturingURLProtocol.nextData = """
        [{"id": "a1", "createdAt": "2024-01-01T00:00:00.000Z", "type": "comment", "user": {"id": "u1", "name": "U", "email": "u@t", "profileImagePath": "", "avatarColor": "#000000", "profileChangedAt": "2024-01-01T00:00:00.000Z"}, "assetId": "as1", "comment": "Nice!"}]
        """.data(using: .utf8)!

        let activities = try await client.getActivities(albumId: "alb-1", assetId: "as1")

        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(activities.first?.type, .comment)
        guard let captured = CapturingURLProtocol.lastRequest else {
            return XCTFail("no request captured")
        }
        XCTAssertEqual(captured.httpMethod, "GET")
        XCTAssertEqual(captured.url?.path, "/api/activities")
        let query = captured.url?.query ?? ""
        XCTAssertTrue(query.contains("albumId=alb-1"), "albumId is required")
        XCTAssertTrue(query.contains("assetId=as1"))
    }

    func test_P0_getServerStatistics_hitsStatisticsEndpoint() async throws {
        let session = makeMockedSession()
        let client = ImmichAPIClient(session: session)
        client.configure(baseURL: URL(string: "https://example.com")!, token: "tok")
        CapturingURLProtocol.nextData = """
        {"photos": 100, "videos": 10, "usage": 1073741824, "usagePhotos": 1000000000, "usageVideos": 73741824, "usageByUser": []}
        """.data(using: .utf8)!

        let stats = try await client.getServerStatistics()

        XCTAssertEqual(stats.photos, 100)
        guard let captured = CapturingURLProtocol.lastRequest else {
            return XCTFail("no request captured")
        }
        XCTAssertEqual(captured.httpMethod, "GET")
        XCTAssertEqual(captured.url?.path, "/api/server/statistics")
    }

    func test_P0_updateSharedLink_hitsPutEndpoint() async throws {
        let session = makeMockedSession()
        let client = ImmichAPIClient(session: session)
        client.configure(baseURL: URL(string: "https://example.com")!, token: "tok")
        CapturingURLProtocol.nextData = """
        {"id": "l1", "description": "Updated", "password": null, "userId": "me", "key": "a2V5", "type": "ALBUM", "createdAt": "2024-01-01T00:00:00.000Z", "expiresAt": "2025-01-01T00:00:00.000Z", "assets": [], "album": null, "allowUpload": true, "allowDownload": true, "showMetadata": true, "slug": null}
        """.data(using: .utf8)!

        let link = try await client.updateSharedLink(
            id: "l1",
            dto: SharedLinkEditDto(password: nil, expiresAt: "2025-01-01T00:00:00.000Z", allowUpload: true, allowDownload: nil, showMetadata: nil, description: "Updated")
        )

        XCTAssertEqual(link.description, "Updated")
        XCTAssertTrue(link.allowUpload)
        guard let captured = CapturingURLProtocol.lastRequest else {
            return XCTFail("no request captured")
        }
        XCTAssertEqual(captured.httpMethod, "PUT")
        XCTAssertEqual(captured.url?.path, "/api/shared-links/l1")
        let body = String(decoding: CapturingURLProtocol.lastBody, as: UTF8.self)
        XCTAssertTrue(body.contains(#""expiresAt":"2025-01-01T00:00:00.000Z""#))
        XCTAssertFalse(body.contains("allowDownload"), "nil fields must be omitted")
    }

    func test_P0_bulkUpdateAssets_hitsPutAssets204() async throws {
        let session = makeMockedSession()
        let client = ImmichAPIClient(session: session)
        client.configure(baseURL: URL(string: "https://example.com")!, token: "tok")
        CapturingURLProtocol.nextStatus = 204

        try await client.bulkUpdateAssets(dto: AssetBulkUpdateDto(
            ids: ["a1", "a2"], dateTimeOriginal: nil, dateTimeRelative: nil, description: nil,
            isFavorite: nil, latitude: nil, longitude: nil, rating: nil, timeZone: nil,
            visibility: .archive, duplicateId: nil
        ))

        guard let captured = CapturingURLProtocol.lastRequest else {
            return XCTFail("no request captured")
        }
        XCTAssertEqual(captured.httpMethod, "PUT")
        XCTAssertEqual(captured.url?.path, "/api/assets")
        let body = String(decoding: CapturingURLProtocol.lastBody, as: UTF8.self)
        XCTAssertTrue(body.contains(#""ids":["a1","a2"]"#))
        XCTAssertTrue(body.contains(#""visibility":"archive""#))
    }

    func test_P0_timelineFilterExpansion_encodesNewParams() async throws {
        let session = makeMockedSession()
        let client = ImmichAPIClient(session: session)
        client.configure(baseURL: URL(string: "https://example.com")!, token: "tok")
        CapturingURLProtocol.nextData = "[]".data(using: .utf8)!
        CapturingURLProtocol.nextStatus = 200

        _ = try await client.getTimeBuckets(
            isFavorite: nil, isTrashed: nil,
            personId: "p1", withPartners: true, visibility: "archive", withStacked: false
        )

        guard let captured = CapturingURLProtocol.lastRequest else {
            return XCTFail("no request captured")
        }
        XCTAssertEqual(captured.url?.path, "/api/timeline/buckets")
        let query = captured.url?.query ?? ""
        XCTAssertTrue(query.contains("personId=p1"))
        XCTAssertTrue(query.contains("withPartners=true"))
        XCTAssertTrue(query.contains("visibility=archive"))
        XCTAssertTrue(query.contains("withStacked=false"))
        XCTAssertFalse(query.contains("isFavorite"), "nil filters must be omitted")
    }
}
