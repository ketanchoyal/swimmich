import SwiftUI

/// Media Stats (gap G24) — the numbers, side by side: what this device holds and
/// what the server holds.
///
/// The two sections are the two halves of the question. `Local` reads only the
/// device (the ledger and the cache) and is therefore always available, even
/// with no connection; `Server` is the one call, and shows the retry when it
/// fails.
///
/// Pushed from `ProfileView`'s Advanced section, which owns the hub's navigation
/// container — no `NavigationStack` here.
struct MediaStatsView: View {
    @Bindable var vm: MediaStatsViewModel

    var body: some View {
        List {
            Section {
                LabeledContent("Tracked assets", value: "\(vm.trackedCount)")
                LabeledContent("Cached offline", value: "\(vm.offlineCount)")
                LabeledContent("Offline size", value: vm.formattedUsage(vm.offlineBytes))
                LabeledContent("Last server check", value: vm.formattedLastReconciliation())
            } header: {
                Text("Local")
            }

            Section {
                if vm.isLoading {
                    ProgressView()
                }
                if let error = vm.errorMessage {
                    InlineErrorBadge(message: error) { Task { await vm.load() } }
                }
                LabeledContent("Photos", value: "\(vm.photos)")
                    .accessibilityIdentifier("mediaStatsServerPhotos")
                LabeledContent("Videos", value: "\(vm.videos)")
                LabeledContent("Usage", value: vm.formattedUsage(vm.usage))
                // No quota defined → no row at all, rather than a zero that
                // would read as "no space".
                if let quota = vm.quotaSizeInBytes {
                    LabeledContent("Quota", value: vm.formattedUsage(quota))
                }
            } header: {
                Text("Server")
            }
        }
        .navigationTitle("Media Stats")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }
}
