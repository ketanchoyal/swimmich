import CryptoKit
import XCTest
@testable import ImmichSwiftUI

/// The share extension's transport, exercised through the same
/// `CapturingURLProtocol` the app's own upload tests use — the kit is compiled
/// into the app target as well, so `@testable import ImmichSwiftUI` reaches it.
/// Importing `ImmichSharedKit` here would make every kit symbol ambiguous.
final class ShareUploadClientTests: XCTestCase {

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CapturingURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func makeClient() -> SharedUploadClient {
        SharedUploadClient(
            baseURL: "https://example.com",
            token: "tok",
            deviceId: "device-1",
            session: makeSession()
        )
    }

    /// Staged copy of the shared file, in its own directory the test removes.
    private func writeStagedFile(_ payload: Data, name: String = "photo.jpg") throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("share-upload-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(name)
        try payload.write(to: file)
        return file
    }

    private func upload(_ client: SharedUploadClient, file: URL, duration: Int? = nil) async throws -> SharedUploadResult {
        try await client.upload(
            fileURL: file,
            filename: file.lastPathComponent,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            duration: duration,
            deviceAssetId: "share/1"
        )
    }

    override func tearDown() {
        CapturingURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Upload

    func test_upload_postsMultipartBodyWithEveryDeviceField() async throws {
        CapturingURLProtocol.nextStatus = 201
        CapturingURLProtocol.nextData = #"{"id":"a1","status":"created"}"#.data(using: .utf8)!
        let file = try writeStagedFile(Data(repeating: 0x41, count: 2048))
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let result = try await upload(makeClient(), file: file, duration: 12)

        XCTAssertEqual(result.id, "a1")
        XCTAssertEqual(result.status, "created")
        XCTAssertFalse(result.isDuplicate)

        let captured = try XCTUnwrap(CapturingURLProtocol.lastRequest)
        XCTAssertEqual(captured.httpMethod, "POST")
        XCTAssertEqual(captured.url?.absoluteString, "https://example.com/api/assets")
        XCTAssertEqual(captured.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertTrue(
            (captured.value(forHTTPHeaderField: "Content-Type") ?? "").hasPrefix("multipart/form-data; boundary="),
            "the body must be a streamed multipart, not JSON"
        )

        let body = String(decoding: CapturingURLProtocol.lastBody, as: UTF8.self)
        XCTAssertTrue(body.contains(#"name="assetData""#))
        XCTAssertTrue(body.contains(#"filename="photo.jpg""#))
        XCTAssertTrue(body.contains(#"name="fileCreatedAt""#))
        XCTAssertTrue(body.contains(#"name="fileModifiedAt""#))
        XCTAssertTrue(body.contains(#"name="deviceAssetId""#))
        XCTAssertTrue(body.contains("share/1"))
        XCTAssertTrue(body.contains(#"name="deviceId""#))
        XCTAssertTrue(body.contains("device-1"))
        XCTAssertTrue(body.contains(#"name="duration""#))
        XCTAssertTrue(body.contains("12"))
    }

    func test_upload_sendsSha1Base64ChecksumOfTheSharedFile() async throws {
        let payload = Data("immich-share-checksum".utf8)
        CapturingURLProtocol.nextStatus = 201
        CapturingURLProtocol.nextData = #"{"id":"a2","status":"created"}"#.data(using: .utf8)!
        let file = try writeStagedFile(payload)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        _ = try await upload(makeClient(), file: file)

        let expected = Data(Insecure.SHA1.hash(data: payload)).base64EncodedString()
        let captured = try XCTUnwrap(CapturingURLProtocol.lastRequest)
        XCTAssertEqual(captured.value(forHTTPHeaderField: "x-immich-checksum"), expected)
    }

    func test_upload_decodesDuplicateAsASuccess() async throws {
        CapturingURLProtocol.nextStatus = 200
        CapturingURLProtocol.nextData = #"{"id":"existing-1","status":"duplicate"}"#.data(using: .utf8)!
        let file = try writeStagedFile(Data(repeating: 0x42, count: 64))
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let result = try await upload(makeClient(), file: file)

        XCTAssertEqual(result.id, "existing-1")
        XCTAssertTrue(result.isDuplicate)
    }

    func test_upload_surfacesRejectedTokenWithTheServerMessage() async throws {
        CapturingURLProtocol.nextStatus = 401
        CapturingURLProtocol.nextData = #"{"message":"Invalid user token"}"#.data(using: .utf8)!
        let file = try writeStagedFile(Data(repeating: 0x43, count: 64))
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        do {
            _ = try await upload(makeClient(), file: file)
            XCTFail("an upload the server rejected must not report success")
        } catch let error as ShareUploadError {
            XCTAssertEqual(error, .server(401, "Invalid user token"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_upload_reportsAMissingStagedFile() async throws {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gone-\(UUID().uuidString).jpg")

        do {
            _ = try await upload(makeClient(), file: missing)
            XCTFail("a vanished staged file must not reach the network")
        } catch let error as ShareUploadError {
            XCTAssertEqual(error, .unreadableFile)
        }
        XCTAssertNil(CapturingURLProtocol.lastRequest)
    }

    // MARK: - Albums

    func test_albums_readsTheNameTheServerUses() async throws {
        CapturingURLProtocol.nextStatus = 200
        CapturingURLProtocol.nextData = #"[{"id":"alb1","albumName":"Trips","assetCount":3}]"#.data(using: .utf8)!

        let albums = try await makeClient().albums()

        XCTAssertEqual(albums, [ShareAlbum(id: "alb1", albumName: "Trips")])
        XCTAssertEqual(CapturingURLProtocol.lastRequest?.url?.path, "/api/albums")
        XCTAssertEqual(CapturingURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_addAssets_putsTheUploadedIdsUnderTheAlbum() async throws {
        CapturingURLProtocol.nextStatus = 200
        CapturingURLProtocol.nextData = "[]".data(using: .utf8)!

        try await makeClient().addAssets(["a1", "a2"], toAlbum: "alb1")

        let captured = try XCTUnwrap(CapturingURLProtocol.lastRequest)
        XCTAssertEqual(captured.httpMethod, "PUT")
        XCTAssertEqual(captured.url?.path, "/api/albums/alb1/assets")
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: CapturingURLProtocol.lastBody) as? [String: [String]]
        )
        XCTAssertEqual(body["ids"], ["a1", "a2"])
    }
}
