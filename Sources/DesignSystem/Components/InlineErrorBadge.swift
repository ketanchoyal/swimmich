import SwiftUI

// MARK: - InlineErrorBadge
//
// Inline error banner for auth/onboarding forms (PRD §5.10: errors render in
// context under the concerned field, never as blocking popups). The optional
// `retry` action renders a "Réessayer" button inside the banner (PRD:252) —
// network errors (timeout, DNS) propose retry directly in the message.

/// Card-style error banner with optional retry action.
struct InlineErrorBadge: View {
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: PVSpacing.s12) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color.immichError)

            Text(message)
                .font(.pvSubhead)
                .foregroundStyle(Color.immichError)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let retry {
                Button("Réessayer", action: retry)
                    .font(.pvSubhead.weight(.semibold))
                    .foregroundStyle(Color.immichError)
            }
        }
        .padding(PVSpacing.s12)
        .background(Color.immichError.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: PVRadius.md, style: .continuous))
        .contentTransition(.opacity)
    }
}
