import XCTest
@testable import ImmichSwiftUI

final class DTOEncodingTests: XCTestCase {

    // AC-011: Codable round-trip for key DTOs.
    func test_AC_011_loginResponseRoundTrip() throws {
        let json = """
        {
          "accessToken": "test-jwt",
          "userId": "11111111-1111-1111-1111-111111111111",
          "userEmail": "test@example.com",
          "name": "Test User",
          "profileImagePath": "/path/img",
          "isAdmin": false,
          "shouldChangePassword": false,
          "isOnboarded": true
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder.immich.decode(LoginResponseDto.self, from: json)
        XCTAssertEqual(decoded.accessToken, "test-jwt")
        XCTAssertEqual(decoded.userId, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(decoded.userEmail, "test@example.com")
        XCTAssertEqual(decoded.name, "Test User")
        XCTAssertTrue(decoded.isOnboarded)

        let reencoded = try JSONEncoder.immich.encode(decoded)
        let redecoded = try JSONDecoder.immich.decode(LoginResponseDto.self, from: reencoded)
        XCTAssertEqual(decoded, redecoded)
    }

    func test_AC_011_logoutResponseRoundTrip() throws {
        let json = #"{"successful":true,"redirectUri":""}"#.data(using: .utf8)!
        let decoded = try JSONDecoder.immich.decode(LogoutResponseDto.self, from: json)
        XCTAssertTrue(decoded.successful)
        XCTAssertEqual(decoded.redirectUri, "")
        let reencoded = try JSONEncoder.immich.encode(decoded)
        let redecoded = try JSONDecoder.immich.decode(LogoutResponseDto.self, from: reencoded)
        XCTAssertEqual(decoded, redecoded)
    }

    func test_AC_011_serverPingResponseRoundTrip() throws {
        let json = #"{"res":"pong"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder.immich.decode(ServerPingResponse.self, from: json)
        XCTAssertEqual(decoded.res, "pong")
        let reencoded = try JSONEncoder.immich.encode(decoded)
        let redecoded = try JSONDecoder.immich.decode(ServerPingResponse.self, from: reencoded)
        XCTAssertEqual(decoded, redecoded)
    }

    func test_AC_011_assetResponseRoundTrip() throws {
        let json = """
        {
          "id": "asset-1",
          "type": "IMAGE",
          "thumbhash": null,
          "localDateTime": "2024-07-01T00:00:00.000Z",
          "duration": null,
          "hasMetadata": true,
          "width": 1024,
          "height": 768,
          "createdAt": "2024-07-02T00:00:00.000Z",
          "ownerId": "owner-1",
          "originalPath": "/upload/2024/x.jpg",
          "originalFileName": "x.jpg",
          "fileCreatedAt": "2024-07-01T00:00:00.000Z",
          "fileModifiedAt": "2024-07-01T00:00:00.000Z",
          "updatedAt": "2024-07-03T00:00:00.000Z",
          "isFavorite": false,
          "isArchived": false,
          "isTrashed": false,
          "isOffline": false,
          "visibility": "timeline",
          "checksum": "Y2hlY2tzdW0=",
          "isEdited": false
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder.immich.decode(AssetResponseDto.self, from: json)
        XCTAssertEqual(decoded.id, "asset-1")
        XCTAssertEqual(decoded.type, "IMAGE")
        XCTAssertEqual(decoded.visibility, "timeline")
        XCTAssertEqual(decoded.width, 1024)
        XCTAssertFalse(decoded.isFavorite)

        let reencoded = try JSONEncoder.immich.encode(decoded)
        let redecoded = try JSONDecoder.immich.decode(AssetResponseDto.self, from: reencoded)
        XCTAssertEqual(decoded.id, redecoded.id)
        XCTAssertEqual(decoded.type, redecoded.type)
        XCTAssertEqual(decoded.visibility, redecoded.visibility)
    }

    // AC-011b: columnar TimeBucketAssetResponseDto round-trips.
    func test_AC_011b_columnarRoundTrip() throws {
        let original = TimeBucketAssetResponseDto(
            id: ["a", "b"], ownerId: ["o1", "o2"], ratio: [1.5, 0.5],
            isFavorite: [true, false], visibility: ["timeline", "archive"],
            isTrashed: [false, true], isImage: [true, false],
            thumbhash: ["h1", nil], createdAt: ["c1", "c2"], fileCreatedAt: ["f1", "f2"],
            localOffsetHours: [0, 5.5], duration: [nil, 1200], livePhotoVideoId: [nil, "vid"],
            projectionType: [nil, nil],
            stack: nil, city: ["Paris", nil], country: ["FR", nil],
            latitude: [48.85, nil], longitude: [2.35, nil]
        )
        let encoded = try JSONEncoder.immich.encode(original)
        let decoded = try JSONDecoder.immich.decode(TimeBucketAssetResponseDto.self, from: encoded)
        XCTAssertEqual(decoded, original)
    }
}
