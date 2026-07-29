import SwiftUI

/// Main photo-grid timeline. LazyVGrid 3 columns, day-grouped sections,
/// infinite scroll triggers loadMore() when the last cell appears.
struct TimelineView: View {
    @State private var vm: TimelineViewModel
    @Environment(AuthViewModel.self) private var auth
    private let columns = Array(repeating: GridItem(.flexible(minimum: 80, maximum: 200), spacing: 2), count: 3)

    init(vm: TimelineViewModel) {
        _vm = State(initialValue: vm)
    }

    var body: some View {
        @Bindable var auth = auth
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if vm.items.isEmpty && vm.isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding()
                    }
                    ForEach(vm.groupedByDay, id: \.day) { group in
                        Section {
                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(group.items) { item in
                                    NavigationLink {
                                        AssetDetailView(asset: item)
                                    } label: {
                                        AssetThumbnailCell(asset: item, baseURL: auth.baseURL ?? URL(string: "https://example.com")!, token: auth.accessToken)
                                    }
                                    .buttonStyle(.plain)
                                    .task {
                                        if item.id == vm.items.last?.id {
                                            await vm.loadMore()
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text(group.day)
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                        }
                    }
                    if vm.canLoadMore {
                        ProgressView().frame(maxWidth: .infinity).padding()
                    }
                }
            }
            .navigationTitle("Timeline")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Logout") { Task { await auth.logout() } }
                }
            }
        }
        .task {
            if vm.items.isEmpty {
                await vm.load()
            }
        }
    }
}
