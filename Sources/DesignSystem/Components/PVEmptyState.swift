import SwiftUI

// MARK: - PVEmptyState
//
// Hero empty / zero-data state. The illustration SF Symbol is rendered at
// `.font(.system(size: 48))` — this is a hero illustration, NOT body text,
// so it is intentionally exempt from the font-token rule (spec §8.6).
// `textTertiaryPV` is referenced here (AC-013 spot-check).

struct PVEmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: PVSpacing.s16) {
            Image(systemName: symbol)
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiaryPV)

            Text(title)
                .font(.pvTitle)
                .foregroundStyle(Color.textPrimaryPV)

            Text(message)
                .font(.pvBody)
                .foregroundStyle(Color.textTertiaryPV)
                .multilineTextAlignment(.center)
        }
    }
}
