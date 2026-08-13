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

    // AC-310: BulkIdsDto + TrashResponseDto round-trip.
    func test_AC_310_trashDtos() throws {
        let bulk = BulkIdsDto(ids: ["a", "b"])
        let encodedBulk = try JSONEncoder.immich.encode(bulk)
        let decodedBulk = try JSONDecoder.immich.decode(BulkIdsDto.self, from: encodedBulk)
        XCTAssertEqual(decodedBulk, bulk)

        // Server-style JSON for TrashResponseDto.
        let countJSON = #"{"count":3}"#.data(using: .utf8)!
        let resp = try JSONDecoder.immich.decode(TrashResponseDto.self, from: countJSON)
        XCTAssertEqual(resp.count, 3)

        let reencoded = try JSONEncoder.immich.encode(resp)
        let redecoded = try JSONDecoder.immich.decode(TrashResponseDto.self, from: reencoded)
        XCTAssertEqual(resp, redecoded)
    }

    // AC-311: ImmichAPI.trash SubPath resolves to /api/trash/<suffix>.
    func test_AC_311_trashSubpath() {
        XCTAssertEqual(ImmichAPI.trash.path("/restore/assets"), "/api/trash/restore/assets")
        XCTAssertEqual(ImmichAPI.trash.path("/restore"), "/api/trash/restore")
        XCTAssertEqual(ImmichAPI.trash.path("/empty"), "/api/trash/empty")
    }

    // AC-500: ImmichAPI.albums + sharedLinks SubPath resolution.
    func test_AC_500_albumsSharedLinksSubpath() {
        XCTAssertEqual(ImmichAPI.albums.path(""), "/api/albums")
        XCTAssertEqual(ImmichAPI.albums.path("/x"), "/api/albums/x")
        XCTAssertEqual(ImmichAPI.albums.path("/x/assets"), "/api/albums/x/assets")
        XCTAssertEqual(ImmichAPI.sharedLinks.path(""), "/api/shared-links")
        XCTAssertEqual(ImmichAPI.sharedLinks.path("/y"), "/api/shared-links/y")
    }

    // AC-501: AlbumResponseDto decodes server JSON (no assets field) + round-trips.
    func test_AC_501_albumResponseDtoRoundTrip() throws {
        let json = """
        {
          "id": "album-1",
          "albumName": "Vacation",
          "description": "Summer trip",
          "createdAt": "2024-06-01T00:00:00.000Z",
          "updatedAt": "2024-06-02T00:00:00.000Z",
          "albumThumbnailAssetId": "asset-thumb",
          "shared": true,
          "albumUsers": [{"user": {"id": "u1", "name": "Alice", "email": "alice@example.com", "profileImagePath": "", "avatarColor": "#FF0000", "profileChangedAt": "2024-06-01T00:00:00.000Z"}, "role": "editor"}],
          "hasSharedLink": true,
          "assetCount": 42,
          "isActivityEnabled": false,
          "order": "asc",
          "startDate": "2024-06-01T00:00:00.000Z",
          "endDate": "2024-06-10T00:00:00.000Z",
          "contributorCounts": []
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder.immich.decode(AlbumResponseDto.self, from: json)
        XCTAssertEqual(decoded.id, "album-1")
        XCTAssertEqual(decoded.albumName, "Vacation")
        XCTAssertEqual(decoded.description, "Summer trip")
        XCTAssertEqual(decoded.albumThumbnailAssetId, "asset-thumb")
        XCTAssertTrue(decoded.shared)
        XCTAssertTrue(decoded.hasSharedLink)
        XCTAssertEqual(decoded.assetCount, 42)
        XCTAssertEqual(decoded.order, .asc)
        XCTAssertEqual(decoded.albumUsers.first?.user.id, "u1", "collaborators must decode")
        XCTAssertEqual(decoded.albumUsers.first?.role, .editor)

        let reencoded = try JSONEncoder.immich.encode(decoded)
        let redecoded = try JSONDecoder.immich.decode(AlbumResponseDto.self, from: reencoded)
        XCTAssertEqual(decoded, redecoded)
    }

    // AC-502: CreateAlbumDto encodes optional fields (absent when nil).
    func test_AC_502_createAlbumDtoEncoding() throws {
        let withAssets = CreateAlbumDto(albumName: "A", description: "D", assetIds: ["id1", "id2"])
        let enc1 = try JSONEncoder.immich.encode(withAssets)
        let obj1 = try JSONSerialization.jsonObject(with: enc1) as? [String: Any]
        XCTAssertEqual(obj1?["albumName"] as? String, "A")
        XCTAssertEqual(obj1?["description"] as? String, "D")
        XCTAssertEqual(obj1?["assetIds"] as? [String], ["id1", "id2"])

        let minimal = CreateAlbumDto(albumName: "B", description: nil, assetIds: nil)
        let enc2 = try JSONEncoder.immich.encode(minimal)
        let obj2 = try JSONSerialization.jsonObject(with: enc2) as? [String: Any]
        XCTAssertEqual(obj2?["albumName"] as? String, "B")
        XCTAssertNil(obj2?["description"])
        XCTAssertNil(obj2?["assetIds"])
    }

    // AC-503: SharedLinkCreateDto encodes type enum + password; SharedLinkResponseDto decodes.
    func test_AC_503_sharedLinkDtos() throws {
        let withPw = SharedLinkCreateDto(type: .album, albumId: "a1", password: "secret")
        let enc1 = try JSONEncoder.immich.encode(withPw)
        let obj1 = try JSONSerialization.jsonObject(with: enc1) as? [String: Any]
        XCTAssertEqual(obj1?["type"] as? String, "ALBUM")
        XCTAssertEqual(obj1?["albumId"] as? String, "a1")
        XCTAssertEqual(obj1?["password"] as? String, "secret")

        let noPw = SharedLinkCreateDto(type: .album, albumId: "a1")
        let enc2 = try JSONEncoder.immich.encode(noPw)
        let obj2 = try JSONSerialization.jsonObject(with: enc2) as? [String: Any]
        XCTAssertNil(obj2?["password"])

        let respJSON = """
        {
          "id": "link-1", "description": null, "password": null, "userId": "u1",
          "key": "a2V5", "type": "ALBUM", "createdAt": "2024-01-01T00:00:00.000Z",
          "expiresAt": null, "assets": [], "album": null,
          "allowUpload": false, "allowDownload": true, "showMetadata": true, "slug": null
        }
        """.data(using: .utf8)!
        let resp = try JSONDecoder.immich.decode(SharedLinkResponseDto.self, from: respJSON)
        XCTAssertEqual(resp.id, "link-1")
        XCTAssertEqual(resp.type, .album)
        XCTAssertEqual(resp.key, "a2V5")
        XCTAssertNil(resp.password)
    }

    // AC-504: BulkIdResponseDto decodes mixed success/failure.
    func test_AC_504_bulkIdResponseDto() throws {
        let json = """
        [
          {"id": "x", "success": true},
          {"id": "y", "success": false, "error": "DUPLICATE", "errorMessage": "Already in album"}
        ]
        """.data(using: .utf8)!
        let decoded = try JSONDecoder.immich.decode([BulkIdResponseDto].self, from: json)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertTrue(decoded[0].success)
        XCTAssertNil(decoded[0].error)
        XCTAssertFalse(decoded[1].success)
        XCTAssertEqual(decoded[1].error, .duplicate)
        XCTAssertEqual(decoded[1].errorMessage, "Already in album")
    }

    // AC-519: MetadataSearchDto.albumIds encodes correctly (present/absent).
    func test_AC_519_metadataSearchAlbumIds() throws {
        let withAlbums = MetadataSearchDto(query: nil, albumIds: ["a", "b"])
        let enc1 = try JSONEncoder.immich.encode(withAlbums)
        let obj1 = try JSONSerialization.jsonObject(with: enc1) as? [String: Any]
        XCTAssertEqual(obj1?["albumIds"] as? [String], ["a", "b"])

        let withoutAlbums = MetadataSearchDto(query: "x", albumIds: nil)
        let enc2 = try JSONEncoder.immich.encode(withoutAlbums)
        let obj2 = try JSONSerialization.jsonObject(with: enc2) as? [String: Any]
        XCTAssertNil(obj2?["albumIds"])
        XCTAssertEqual(obj2?["query"] as? String, "x")
    }

    // Photo share: AlbumUserRole raw values match the server contract (lowercase).
    func test_photoShare_albumUserRoleRawValues() {
        XCTAssertEqual(AlbumUserRole.editor.rawValue, "editor")
        XCTAssertEqual(AlbumUserRole.viewer.rawValue, "viewer")
        XCTAssertEqual(AlbumUserRole.owner.rawValue, "owner")
    }

    // Photo share: CreateAlbumDto round-trips albumUsers (shared album).
    func test_photoShare_createAlbumWithUsersRoundTrip() throws {
        let dto = CreateAlbumDto(
            albumName: "Weekend",
            description: nil,
            assetIds: ["a1"],
            albumUsers: [AlbumUserDto(userId: "u1", role: .editor), AlbumUserDto(userId: "u2", role: .viewer)]
        )

        let enc = try JSONEncoder.immich.encode(dto)
        let obj = try JSONSerialization.jsonObject(with: enc) as? [String: Any]
        XCTAssertEqual(obj?["albumName"] as? String, "Weekend")
        XCTAssertEqual(obj?["assetIds"] as? [String], ["a1"])
        let users = obj?["albumUsers"] as? [[String: Any]]
        XCTAssertEqual(users?.count, 2)
        XCTAssertEqual(users?.first?["userId"] as? String, "u1")
        XCTAssertEqual(users?.first?["role"] as? String, "editor")

        let decoded = try JSONDecoder.immich.decode(CreateAlbumDto.self, from: enc)
        XCTAssertEqual(decoded.albumUsers, dto.albumUsers)
    }

    // Photo share: albumUsers is omitted from the wire when nil (backward compatible).
    func test_photoShare_createAlbumWithoutUsersOmitsField() throws {
        let dto = CreateAlbumDto(albumName: "Plain", description: nil, assetIds: nil)
        let enc = try JSONEncoder.immich.encode(dto)
        let obj = try JSONSerialization.jsonObject(with: enc) as? [String: Any]
        XCTAssertNil(obj?["albumUsers"])
    }

    // MARK: - P0 api-surface-expansion DTOs

    func test_P0_peopleResponseDto() throws {
        let json = """
        {
          "people": [
            {"id": "p1", "name": "Alice", "birthDate": "1990-01-01", "thumbnailPath": "/thumbs/p1.jpg", "isHidden": false, "color": "#FF0000", "isFavorite": true, "updatedAt": "2024-01-01T00:00:00.000Z"}
          ],
          "hidden": 2,
          "total": 3,
          "hasNextPage": true
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder.immich.decode(PeopleResponseDto.self, from: json)
        XCTAssertEqual(decoded.total, 3)
        XCTAssertEqual(decoded.hidden, 2)
        XCTAssertTrue(decoded.hasNextPage ?? false)
        let person = try XCTUnwrap(decoded.people.first)
        XCTAssertEqual(person.name, "Alice")
        XCTAssertEqual(person.birthDate, "1990-01-01")
        XCTAssertEqual(person.color, "#FF0000")
        XCTAssertEqual(person.isFavorite, true)
        XCTAssertEqual(person.updatedAt, "2024-01-01T00:00:00.000Z")
        let reencoded = try JSONEncoder.immich.encode(decoded)
        XCTAssertEqual(decoded, try JSONDecoder.immich.decode(PeopleResponseDto.self, from: reencoded))
    }

    func test_P0_personUpdateDtoOmitsNilFields() throws {
        let dto = PersonUpdateDto(name: "Bob", birthDate: nil, color: nil, featureFaceAssetId: nil, isFavorite: nil, isHidden: true)
        let enc = try JSONEncoder.immich.encode(dto)
        let obj = try JSONSerialization.jsonObject(with: enc) as? [String: Any]
        XCTAssertEqual(obj?["name"] as? String, "Bob")
        XCTAssertEqual(obj?["isHidden"] as? Bool, true)
        XCTAssertNil(obj?["birthDate"])
        XCTAssertNil(obj?["color"])
        XCTAssertNil(obj?["featureFaceAssetId"])
    }

    func test_P0_partnerResponseDto() throws {
        let json = """
        {"id": "u9", "name": "Pat", "email": "pat@test", "profileImagePath": "", "avatarColor": "#00FF00", "profileChangedAt": "2024-01-01T00:00:00.000Z", "inTimeline": true}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder.immich.decode(PartnerResponseDto.self, from: json)
        XCTAssertEqual(decoded.id, "u9")
        XCTAssertTrue(decoded.inTimeline)
        XCTAssertEqual(decoded.avatarColor, "#00FF00")
    }

    func test_P0_activityResponseDto() throws {
        let json = """
        {"id": "a1", "createdAt": "2024-01-01T00:00:00.000Z", "type": "comment", "user": {"id": "u1", "name": "U", "email": "u@t", "profileImagePath": "", "avatarColor": "#000000", "profileChangedAt": "2024-01-01T00:00:00.000Z"}, "assetId": "as1", "comment": "Nice!"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder.immich.decode(ActivityResponseDto.self, from: json)
        XCTAssertEqual(decoded.type, .comment)
        XCTAssertEqual(decoded.comment, "Nice!")
        XCTAssertEqual(decoded.assetId, "as1")
        XCTAssertEqual(decoded.user.id, "u1")

        let likeJSON = """
        {"id": "a2", "createdAt": "2024-01-01T00:00:00.000Z", "type": "like", "user": {"id": "u1", "name": "U", "email": "u@t", "profileImagePath": "", "avatarColor": "#000000", "profileChangedAt": "2024-01-01T00:00:00.000Z"}, "assetId": "as1"}
        """.data(using: .utf8)!
        let like = try JSONDecoder.immich.decode(ActivityResponseDto.self, from: likeJSON)
        XCTAssertEqual(like.type, .like)
        XCTAssertNil(like.comment)
    }

    func test_P0_memoryResponseDto() throws {
        let json = """
        {"id": "m1", "createdAt": "2024-01-01T00:00:00.000Z", "updatedAt": "2024-01-01T00:00:00.000Z", "memoryAt": "2023-06-15T00:00:00.000Z", "ownerId": "me", "type": "on_this_day", "data": {"year": 2023}, "assets": [], "isSaved": false}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder.immich.decode(MemoryResponseDto.self, from: json)
        XCTAssertEqual(decoded.type, .on_this_day)
        XCTAssertEqual(decoded.data.year, 2023)
        XCTAssertEqual(decoded.memoryAt, "2023-06-15T00:00:00.000Z")
        XCTAssertFalse(decoded.isSaved)
        XCTAssertEqual(decoded.assets.count, 0)
    }

    func test_P0_memoryResponseDto_unknownTypeDecodesLeniently() throws {
        let json = """
        {"id": "m2", "createdAt": "2024-01-01T00:00:00.000Z", "updatedAt": "2024-01-01T00:00:00.000Z", "memoryAt": "2023-06-15T00:00:00.000Z", "ownerId": "me", "type": "year_in_review", "data": {"year": 2023}, "assets": [], "isSaved": false}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder.immich.decode(MemoryResponseDto.self, from: json)
        XCTAssertEqual(decoded.type, .unknown)
        XCTAssertEqual(decoded.data.year, 2023)
    }

    func test_P0_duplicateResponseDto() throws {
        let json = """
        {"duplicateId": "d1", "assets": [], "suggestedKeepAssetIds": ["keep-1"]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder.immich.decode(DuplicateResponseDto.self, from: json)
        XCTAssertEqual(decoded.duplicateId, "d1")
        XCTAssertEqual(decoded.suggestedKeepAssetIds, ["keep-1"])
    }

    func test_P0_serverStatsResponseDto() throws {
        let json = """
        {"photos": 100, "videos": 10, "usage": 1073741824, "usagePhotos": 1000000000, "usageVideos": 73741824, "usageByUser": [{"userId": "u1", "userName": "U", "photos": 100, "videos": 10, "usage": 1073741824, "usagePhotos": 1000000000, "usageVideos": 73741824, "quotaSizeInBytes": 107374182400}]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder.immich.decode(ServerStatsResponseDto.self, from: json)
        XCTAssertEqual(decoded.photos, 100)
        XCTAssertEqual(decoded.videos, 10)
        XCTAssertEqual(decoded.usagePhotos, 1_000_000_000)
        let user = try XCTUnwrap(decoded.usageByUser.first)
        XCTAssertEqual(user.quotaSizeInBytes, 107_374_182_400)
    }

    func test_P0_sharedLinkEditDtoOmitsNilFields() throws {
        let dto = SharedLinkEditDto(password: nil, expiresAt: "2025-01-01T00:00:00.000Z", allowUpload: true, allowDownload: nil, showMetadata: nil, description: nil)
        let enc = try JSONEncoder.immich.encode(dto)
        let obj = try JSONSerialization.jsonObject(with: enc) as? [String: Any]
        XCTAssertEqual(obj?["expiresAt"] as? String, "2025-01-01T00:00:00.000Z")
        XCTAssertEqual(obj?["allowUpload"] as? Bool, true)
        XCTAssertNil(obj?["password"])
        XCTAssertNil(obj?["allowDownload"])
        XCTAssertNil(obj?["showMetadata"])
        XCTAssertNil(obj?["description"])
    }

    func test_P0_assetBulkUpdateDto() throws {
        let dto = AssetBulkUpdateDto(
            ids: ["a1", "a2"], dateTimeOriginal: nil, dateTimeRelative: nil, description: nil,
            isFavorite: nil, latitude: 48.85, longitude: 2.35, rating: nil, timeZone: nil,
            visibility: .archive, duplicateId: nil
        )
        let enc = try JSONEncoder.immich.encode(dto)
        let obj = try JSONSerialization.jsonObject(with: enc) as? [String: Any]
        XCTAssertEqual(obj?["ids"] as? [String], ["a1", "a2"])
        XCTAssertEqual(obj?["visibility"] as? String, "archive")
        XCTAssertEqual(obj?["latitude"] as? Double, 48.85)
        XCTAssertNil(obj?["duplicateId"])
        let decoded = try JSONDecoder.immich.decode(AssetBulkUpdateDto.self, from: enc)
        XCTAssertEqual(decoded, dto)
    }
}
