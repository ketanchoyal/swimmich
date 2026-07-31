import SwiftUI

// MARK: - PVHeaderBadge
//
// "Badge bg-accent" header mark (PRD §5.10 Écran 1): a large icon in a soft
// indigo wash, used as the hero of onboarding/auth screen headers — the
// visual anchor the plain 36pt icons of the input screens were missing. The
// badge exposes itself as a VoiceOver header via `.accessibilityAddTraits`.

/// Icon-in-wash hero badge for onboarding/auth screen headers.
struct PVHeaderBadge: View {
    let icon: String

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 32, weight: .medium))
            .foregroundStyle(Color.immichPrimary)
            .frame(width: 72, height: 72)
            .background(Color.immichPrimary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: PVRadius.lg, style: .continuous))
            .accessibilityAddTraits(.isHeader)
    }
}
