import Foundation

// MARK: - People DTOs (P0 api-surface-expansion)

/// `PersonResponseDto` — full schema verified against OpenAPI (main branch).
///
/// Replaces the stale minimal definition previously in DTOs.swift.
struct PersonResponseDto: Codable, Equatable, Hashable, Identifiable {
    let id: String
    var name: String
    var birthDate: String?
    var thumbnailPath: String?
    var isHidden: Bool
    var color: String?
    var isFavorite: Bool?
    var updatedAt: String?
}

/// `GET /api/people`
struct PeopleResponseDto: Codable, Equatable {
    let people: [PersonResponseDto]
    let hidden: Int
    let total: Int
    var hasNextPage: Bool?
}

/// `PUT /api/people/{id}` — all fields optional, only provided fields are updated.
struct PersonUpdateDto: Codable, Equatable {
    var name: String?
    var birthDate: String?
    var color: String?
    var featureFaceAssetId: String?
    var isFavorite: Bool?
    var isHidden: Bool?
}

/// `POST /api/people` — create a new person.
struct PersonCreateDto: Codable, Equatable {
    var name: String
    var birthDate: String?
    var isHidden: Bool?
    var isFavorite: Bool?
    var color: String?
}

/// `POST /api/people/{id}/merge` — note: POST, not PUT.
struct MergePersonDto: Codable, Equatable {
    let ids: [String]
}

/// `GET /api/people/{id}/statistics`
struct PersonStatisticsResponseDto: Codable, Equatable {
    let assets: Int
}

/// `GET /api/partners`
struct PartnerResponseDto: Codable, Equatable {
    let id: String
    let name: String
    let email: String
    let profileImagePath: String
    let avatarColor: String
    let profileChangedAt: String
    let inTimeline: Bool
}

/// `PUT /api/partners/{id}`
struct PartnerUpdateDto: Codable, Equatable {
    let inTimeline: Bool
}

// MARK: - Faces (gap #5)

/// A single detected face on an asset (`AssetFaceResponseDto`).
struct AssetFaceResponseDto: Codable, Equatable, Identifiable {
    let id: String
    let person: PersonResponseDto?
    let boundingBoxX1: Int
    let boundingBoxX2: Int
    let boundingBoxY1: Int
    let boundingBoxY2: Int
    let imageHeight: Int
    let imageWidth: Int
    var sourceType: String?
}

/// `FaceDto` — body of `PUT /api/faces/{personId}` (re-assign a face).
struct FaceDto: Codable, Equatable {
    let id: String
}