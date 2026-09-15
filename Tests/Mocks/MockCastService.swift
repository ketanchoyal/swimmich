import Foundation
@testable import ImmichSwiftUI

/// Deterministic `CastService` for the cast ViewModel tests.
///
/// Settable field by field on purpose: it is what lets today's tests describe
/// the behaviour of a future Google Cast implementation (`supportsStillImages`
/// true, the receiver fetching its own media) without that service existing —
/// and what lets the airplay path be exercised without a route, a window or any
/// AVFoundation object.
@MainActor
final class MockCastService: CastService {

    var isAvailable = false
    var isConnected = false
    var connectedRouteName: String?
    var supportsStillImages = false

    private(set) var startObservingCount = 0
    private(set) var stopObservingCount = 0

    func startObserving() { startObservingCount += 1 }

    func stopObserving() { stopObservingCount += 1 }
}
