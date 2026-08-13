import SwiftUI

/// Initials avatar using the user's `avatarColor` (hex) — no image round-trip.
/// Shared by the photo-share sheet, the album "Shared With" sheet and the
/// album detail hero.
struct UserAvatarCircle: View {
    let user: UserResponseDto
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle().fill(Color(hex: user.avatarColor) ?? Color.immichPrimary)
            Text(Self.initials(from: user.name))
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(Color.white)
        }
        .frame(width: size, height: size)
    }

    static func initials(from name: String) -> String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }.map(String.init)
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }
}
