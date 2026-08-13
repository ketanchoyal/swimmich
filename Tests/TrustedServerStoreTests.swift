import XCTest
@testable import ImmichSwiftUI

final class TrustedServerStoreTests: XCTestCase {

    private func makeIsolatedStore() -> (TrustedServerStoreImpl, UserDefaults, String) {
        let suite = "trustStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (TrustedServerStoreImpl(defaults: defaults), defaults, suite)
    }

    func test_contains_emptyIsFalse() {
        let (store, defaults, suite) = makeIsolatedStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(store.contains("photos.example.com"))
    }

    func test_add_thenContains() {
        let (store, defaults, suite) = makeIsolatedStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.add("photos.example.com")
        XCTAssertTrue(store.contains("photos.example.com"))
        XCTAssertFalse(store.contains("other.example.com"))
    }

    func test_add_persistsAcrossInstances() {
        let (store, defaults, suite) = makeIsolatedStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.add("192.168.1.10:2283")

        let reloaded = TrustedServerStoreImpl(defaults: defaults)
        XCTAssertTrue(reloaded.contains("192.168.1.10:2283"))
    }

    func test_add_isIdempotent() {
        let (store, defaults, suite) = makeIsolatedStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.add("a.example.com")
        store.add("a.example.com")
        XCTAssertEqual(defaults.stringArray(forKey: TrustedServerStoreImpl.defaultsKey)?.count, 1)
    }
}
