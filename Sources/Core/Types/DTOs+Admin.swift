import Foundation

// MARK: - Admin DTOs (gap #12)

/// `GET /api/admin/users` — user row for admin management.
struct UserAdminResponseDto: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let email: String
    var profileImagePath: String?
    var avatarColor: String?
    var profileChangedAt: String?
    var storageLabel: String?
    var shouldChangePassword: Bool?
    var isAdmin: Bool?
    var createdAt: String?
    var deletedAt: String?
    var updatedAt: String?
    var oauthId: String?
    var quotaSizeInBytes: Int?
    var quotaUsageInBytes: Int?
    var status: String?
}

/// `POST /api/admin/users`
struct UserAdminCreateDto: Codable, Equatable {
    let email: String
    let password: String
    let name: String
    var storageLabel: String?
    var quotaSizeInBytes: Int?
    var shouldChangePassword: Bool?
    var isAdmin: Bool?
}

/// `PUT /api/admin/users/{id}`
struct UserAdminUpdateDto: Codable, Equatable {
    var email: String?
    var password: String?
    var name: String?
    var storageLabel: String?
    var shouldChangePassword: Bool?
    var quotaSizeInBytes: Int?
    var isAdmin: Bool?
}

// MARK: - Jobs (legacy `/api/jobs`)

/// `GET /api/jobs` returns a dictionary keyed by queue name.
struct QueueStatusLegacyDto: Codable, Equatable {
    let isActive: Bool
    let isPaused: Bool
}

struct QueueStatisticsDto: Codable, Equatable {
    let active: Int
    let completed: Int
    let failed: Int
    let delayed: Int
    let waiting: Int
    let paused: Int
}

struct QueueResponseLegacyDto: Codable, Equatable {
    let queueStatus: QueueStatusLegacyDto
    let jobCounts: QueueStatisticsDto
}

/// `PUT /api/jobs/{name}` — command in "start" | "pause" | "resume" | "empty" | "clear-failed".
struct QueueCommandDto: Codable, Equatable {
    let command: String
    var force: Bool?
}

// MARK: - Libraries

/// `GET /api/libraries`
struct LibraryResponseDto: Codable, Equatable, Identifiable {
    let id: String
    let ownerId: String
    let name: String
    var assetCount: Int?
    var importPaths: [String]?
    var exclusionPatterns: [String]?
    var createdAt: String?
    var updatedAt: String?
    var refreshedAt: String?
}

// MARK: - API keys

/// `GET /api/api-keys`
struct ApiKeyResponseDto: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    var createdAt: String?
    var updatedAt: String?
    var permissions: [String]?
}

/// `POST /api/api-keys` — secret shown only once.
struct ApiKeyCreateResponseDto: Codable, Equatable {
    let secret: String
    let apiKey: ApiKeyResponseDto
}
