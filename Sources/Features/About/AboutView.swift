import SwiftUI

/// What this app is: its version, the highlights it shipped, and the licences
/// of what it embeds (gap G23).
///
/// Pushed from the Me hub, so it declares no `NavigationStack` — `ProfileView`
/// already carries one.
struct AboutView: View {
    @Bindable var whatsNew: WhatsNewViewModel

    var body: some View {
        List {
            LabeledContent("Version", value: version)
                .accessibilityIdentifier("aboutVersionValue")

            NavigationLink {
                WhatsNewView(vm: whatsNew)
            } label: {
                Label("What's New", systemImage: "sparkles")
            }
            .accessibilityIdentifier("aboutWhatsNewRow")

            NavigationLink {
                LicensesView()
            } label: {
                Label("Licenses", systemImage: "doc.text")
            }
            .accessibilityIdentifier("aboutLicensesRow")
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The bundle's own numbers, not `MARKETING_VERSION` read back from the
    /// project: what the user reports is what the running binary carries.
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}
