import SwiftUI

/// App Logs (gap G24) — the transport's own record, newest first.
///
/// Pushed from `ProfileView`'s Advanced section, which already owns the hub's
/// navigation container: this screen declares none of its own (the
/// OfflineAssetsView rule), or the navigation bar would be doubled.
///
/// This is an instrument, not a setting: nothing here changes the app's
/// behaviour, and the only writable thing on it is the buffer's Clear action.
struct AppLogView: View {
    @Bindable var vm: AppLogViewModel

    var body: some View {
        List {
            Section {
                Picker("Level", selection: $vm.levelFilter) {
                    Text("All").tag(AppLogLevel?.none)
                    ForEach(AppLogLevel.allCases) { level in
                        Text(Self.title(for: level)).tag(AppLogLevel?.some(level))
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("appLogLevelPicker")
            }

            Section {
                ForEach(vm.filteredEntries) { entry in
                    NavigationLink {
                        AppLogDetailView(entry: entry)
                    } label: {
                        AppLogRow(entry: entry, subtitle: vm.subtitle(for: entry))
                    }
                }
            }
        }
        .accessibilityIdentifier("appLogList")
        .navigationTitle("App Logs")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $vm.searchText)
        .overlay {
            if vm.filteredEntries.isEmpty {
                ContentUnavailableView(
                    "No logs yet",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Requests will appear here as you use the app.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: vm.exportText()) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("appLogShareButton")
                .disabled(vm.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                // No confirmation: the buffer lives in memory, so clearing it
                // loses nothing that survives a relaunch anyway.
                Button("Clear", systemImage: "trash") { vm.clear() }
                    .accessibilityIdentifier("appLogClearButton")
                    .disabled(vm.isEmpty)
            }
        }
        .task { vm.refresh() }
        .refreshable { vm.refresh() }
    }

    private static func title(for level: AppLogLevel) -> LocalizedStringKey {
        switch level {
        case .info: "Info"
        case .warning: "Warning"
        case .severe: "Severe"
        }
    }
}

/// One line. The fact has to fit on one row: the density of this screen comes
/// from reading many rows at once, not from any single row's detail — which is
/// why the message is truncated and the monospace is reserved for the detail
/// screen.
private struct AppLogRow: View {
    let entry: AppLogEntry
    /// Already stamped by the view model.
    let subtitle: String

    private var tint: Color {
        switch entry.level {
        case .info: .immichPrimary
        case .warning: .immichWarning
        case .severe: .immichError
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: PVSpacing.s12) {
            // Colour alone carries nothing: VoiceOver gets the level in the
            // label below, and the dot is decoration.
            Circle()
                .fill(tint)
                .frame(width: 10, height: 10)
                .padding(.top, PVSpacing.s4)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: PVSpacing.s4) {
                Text(entry.message)
                    .font(.pvBody)
                    .foregroundStyle(Color.textPrimaryPV)
                    .lineLimit(4)
                Text(subtitle)
                    .font(.pvCaption)
                    .foregroundStyle(Color.textSecondaryPV)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, PVSpacing.s4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.level.rawValue) \(entry.message)")
    }
}
