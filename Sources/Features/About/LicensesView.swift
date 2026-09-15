import SwiftUI

/// Attribution for the dependencies the app embeds (gap G23), one collapsible
/// section per dependency.
///
/// The body is the bundled file, read at expand time: a licence is long, and
/// nothing here should hand a retyped copy that drifts from the shipped one.
/// A file that cannot be resolved keeps its row and says so — a packaging
/// failure has to be visible, not an empty screen.
struct LicensesView: View {
    @State private var expanded: Set<String> = []

    private let licenses = ThirdPartyLicense.all

    var body: some View {
        List {
            ForEach(licenses) { license in
                Section {
                    DisclosureGroup(isExpanded: binding(for: license.id)) {
                        text(for: license)
                    } label: {
                        Text(license.name)
                    }
                    .accessibilityIdentifier("licenseRow_\(license.id)")
                }
            }
        }
        .navigationTitle("Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func text(for license: ThirdPartyLicense) -> some View {
        if let body = try? ThirdPartyLicense.licenseText(for: license) {
            Text(body)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
        } else {
            Text("License text unavailable")
                .foregroundStyle(Color.textSecondaryPV)
                .accessibilityIdentifier("licenseMissingRow")
        }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expanded.insert(id)
                } else {
                    expanded.remove(id)
                }
            }
        )
    }
}
