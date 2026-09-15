import Foundation

// MARK: - Connected devices (gap G19)

/// `GET /api/sessions` — one row per device signed in to the account, the one
/// in your hand included (`current`).
///
/// Optionality is the OpenAPI `required` list verbatim: everything is required
/// except `expiresAt`, and `appVersion` is `nullable` (a session whose client
/// never reported one). The three dates decode through `JSONDecoder.immich`
/// (`.immichISO8601`, `JSONCoding.swift`), so they are `Date`, not `String`.
///
/// Nothing here carries the **elevated access** the session may hold: the
/// server keeps it in `pinExpiresAt` on `GET /api/auth/status`, and no field of
/// this DTO mirrors it. A screen that shows the elevation therefore has to hold
/// it locally — see `DeviceSessionsViewModel.isElevated`.
struct SessionResponseDto: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let createdAt: Date
    let updatedAt: Date
    let expiresAt: Date?
    let current: Bool
    let deviceType: String
    let deviceOS: String
    let appVersion: String?
    let isPendingSyncReset: Bool
}
