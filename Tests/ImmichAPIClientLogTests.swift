import XCTest
@testable import ImmichSwiftUI

/// The transport's logging contract (gap G24): what a dispatch leaves in the
/// buffer, and — the security half — what it must never leave there.
///
/// A real `AppLogStore` is injected, so the buffer under test is the production
/// one, and the client is built the way the composition root builds it
/// (`ImmichAPIClient(trustStore:log:)`) with the shared session interposed on by
/// the same `URLProtocol` stub the client suite uses.
@MainActor
final class ImmichAPIClientLogTests: XCTestCase {

    private var store: AppLogStore!

    override func setUp() {
        super.setUp()
        CapturingURLProtocol.reset()
        URLProtocol.registerClass(CapturingURLProtocol.self)
        store = AppLogStore()
    }

    override func tearDown() {
        URLProtocol.unregisterClass(CapturingURLProtocol.self)
        CapturingURLProtocol.reset()
        store = nil
        super.tearDown()
    }

    private func makeClient() -> ImmichAPIClient {
        ImmichAPIClient(trustStore: nil, log: store)
    }

    /// A successful call is recorded — with the path and nothing that followed
    /// it. The folder endpoint is the worst case on purpose: its `path` query
    /// item carries a real filesystem location, exactly the shape of secret the
    /// buffer must not keep (the shared-link visitor's credential travels the
    /// same way).
    func test_successfulRequest_isLoggedWithoutQueryNorHeaders() async throws {
        let client = makeClient()
        let credential = "visitor-credential-b7f1"
        client.configure(baseURL: URL(string: "https://example.test")!, token: credential)
        CapturingURLProtocol.nextStatus = 200
        CapturingURLProtocol.nextData = "[]".data(using: .utf8)!

        _ = try await client.getFolderAssets(path: "/mnt/media/private-folder")

        let entry = try XCTUnwrap(store.snapshot().first)
        XCTAssertEqual(entry.path, "/api/view/folder")
        XCTAssertEqual(entry.category, "HTTP")
        XCTAssertEqual(entry.status, 200)
        XCTAssertEqual(entry.level, .info)
        XCTAssertNotNil(entry.durationMS)

        for recorded in [entry.path, entry.message, entry.details ?? "", entry.stack ?? ""] {
            XCTAssertFalse(recorded.contains("?"), "the URL's parameters must not be recorded: \(recorded)")
            XCTAssertFalse(recorded.contains("private-folder"), "the URL's parameters must not be recorded: \(recorded)")
            XCTAssertFalse(recorded.contains(credential), "the session's proof must not be recorded: \(recorded)")
            XCTAssertFalse(recorded.lowercased().contains("bearer"), "request metadata must not be recorded: \(recorded)")
        }
    }

    /// A server-side failure is a `severe` line, with the status that caused it.
    func test_serverError_isLoggedAsSevere() async throws {
        let client = makeClient()
        client.configure(baseURL: URL(string: "https://example.test")!, token: "tok")
        CapturingURLProtocol.nextStatus = 503
        CapturingURLProtocol.nextData = #"{"message":"Service Unavailable"}"#.data(using: .utf8)!

        do {
            _ = try await client.serverVersion()
            XCTFail("a 5xx must throw")
        } catch {
            // Expected: what the call does with the failure is the client
            // suite's business — here only the log line is under test.
        }

        let entry = try XCTUnwrap(store.snapshot().first)
        XCTAssertEqual(entry.level, .severe)
        XCTAssertEqual(entry.status, 503)
        XCTAssertEqual(entry.path, "/api/server/version")
        XCTAssertEqual(entry.category, "HTTP")
    }
}
