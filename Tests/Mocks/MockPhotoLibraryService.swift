import Foundation
import Photos
@testable import ImmichSwiftUI

final class MockPhotoLibraryService: PhotoLibraryService, @unchecked Sendable {
    func authorizationStatus() -> PHAuthorizationStatus { .authorized }
    func requestAuthorization(_ handler: @escaping (PHAuthorizationStatus) -> Void) { handler(.authorized) }
    func fetchAssets() -> [PHAsset] { [] }
    func loadData(for asset: PHAsset) async throws -> Data { Data() }
    func checksum(for asset: PHAsset) async throws -> String { "" }
    func isoTimestamps(for asset: PHAsset) -> (createdAt: String, modifiedAt: String) {
        ("2024-07-01T00:00:00.000Z", "2024-07-01T00:00:00.000Z")
    }
}
