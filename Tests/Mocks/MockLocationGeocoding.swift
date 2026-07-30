import Foundation
@testable import ImmichSwiftUI

/// Test double for `LocationGeocoding`. Records callCount + injectable result/error.
@MainActor
final class MockLocationGeocoding: LocationGeocoding, @unchecked Sendable {
    var placeNameResult: String?
    var placeNameError: Error?
    private(set) var callCount = 0

    func placeName(latitude: Double, longitude: Double) async throws -> String {
        callCount += 1
        if let placeNameError { throw placeNameError }
        return placeNameResult ?? "Mock Place"
    }
}
