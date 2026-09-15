import SwiftUI

/// The "What's New" cards (gap G23), in the order of the embedded catalog.
///
/// One view, two entry points: the automatic sheet (with `onDone`) and the row
/// of About (without it, the pushed screen keeps the native back button). No
/// `NavigationStack` here — `ProfileView` carries one when this screen is
/// pushed, and the presenter wraps it when it is a sheet, so a stack declared
/// here would draw a second navigation bar.
struct WhatsNewView: View {
    @Bindable var vm: WhatsNewViewModel

    /// Non-nil only when presented as a sheet: a pushed screen closes with the
    /// back button, a self-presenting one has to offer its exit.
    var onDone: (() -> Void)?

    var body: some View {
        Group {
            if vm.highlights.isEmpty {
                ContentUnavailableView("What's New", systemImage: "sparkles")
            } else {
                ScrollView {
                    LazyVStack(spacing: PVSpacing.s24) {
                        ForEach(vm.highlights) { highlight in
                            card(for: highlight)
                        }
                    }
                    .padding(.horizontal, PVSpacing.s16)
                    .padding(.vertical, PVSpacing.s16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgPrimary)
        .navigationTitle("What's New")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onDone {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                        .accessibilityIdentifier("whatsNewDoneButton")
                }
            }
        }
    }

    private func card(for highlight: FeatureHighlight) -> some View {
        VStack(alignment: .leading, spacing: PVSpacing.s12) {
            tile(for: highlight)

            Text(highlight.title)
                .font(.pvHeadline)
                .foregroundStyle(Color.textPrimaryPV)

            Text(highlight.body)
                .font(.pvSubhead)
                .foregroundStyle(Color.textSecondaryPV)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One element per card: the icon is an illustration, not content, so
        // VoiceOver reads title then body as a single announcement.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("whatsNewCard_\(highlight.id)")
    }

    private func tile(for highlight: FeatureHighlight) -> some View {
        ZStack {
            if let imageName = highlight.imageName {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.bgSecondary
                Image(systemName: highlight.systemImage)
                    .font(.system(size: 44))
                    .foregroundStyle(Color.textSecondaryPV)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 256)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.separatorPV, lineWidth: 0.5)
        }
    }
}
