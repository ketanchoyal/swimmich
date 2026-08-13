import SwiftUI

/// Stack management sheet (gap #1): shows the members of the asset's stack
/// (primary first), lets the user change the primary, remove a member, or
/// unstack everything. Resolves the stack id from the asset detail on appear.
struct StackSheet: View {
    let asset: AssetReactItem
    let client: any ImmichClient
    let baseURL: URL
    let token: String?
    var onChanged: () -> Void = {}

    @State private var stack: StackResponseDto?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("Couldn't load stack", systemImage: "square.stack.3d.up.slash")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Retry") { Task { await load() } }
                            .buttonStyle(PVPrimaryButtonStyle())
                    }
                } else if let stack {
                    stackList(stack)
                } else {
                    ContentUnavailableView(
                        "Not stacked",
                        systemImage: "square.stack.3d.up",
                        description: Text("This photo is not part of a stack.")
                    )
                }
            }
            .navigationTitle("Stack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    private func stackList(_ stack: StackResponseDto) -> some View {
        List {
            ForEach(stack.assets, id: \.id) { member in
                HStack(spacing: PVSpacing.s12) {
                    AuthenticatedAsyncImage(
                        url: ImmichAssetURL.thumbnail(assetId: member.id, thumbhash: member.thumbhash ?? "", baseURL: baseURL, size: .thumbnail),
                        token: token
                    )
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: PVRadius.sm, style: .continuous))

                    Text(member.originalFileName)
                        .font(.pvBody)
                        .foregroundStyle(Color.textPrimaryPV)
                        .lineLimit(1)

                    Spacer()

                    if member.id == stack.primaryAssetId {
                        Image(systemName: "star.fill")
                            .foregroundStyle(Color.immichPrimary)
                            .accessibilityLabel("Primary")
                    }
                }
                .contextMenu {
                    if member.id != stack.primaryAssetId {
                        Button {
                            Task { await setPrimary(stack, member.id) }
                        } label: {
                            Label("Set as primary", systemImage: "star")
                        }
                    }
                    if stack.assets.count > 1 {
                        Button(role: .destructive) {
                            Task { await remove(stack, member.id) }
                        } label: {
                            Label("Remove from stack", systemImage: "square.stack.3d.up.slash")
                        }
                    }
                }
            }

            if stack.assets.count > 1 {
                Section {
                    Button(role: .destructive) {
                        Task { await unstack(stack) }
                    } label: {
                        Label("Unstack all", systemImage: "square.stack.3d.up.slash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func setPrimary(_ stack: StackResponseDto, _ assetId: String) async {
        do {
            _ = try await client.updateStack(id: stack.id, primaryAssetId: assetId)
            errorMessage = nil
            await reload(stackId: stack.id)
            onChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove(_ stack: StackResponseDto, _ assetId: String) async {
        do {
            try await client.removeAssetFromStack(stackId: stack.id, assetId: assetId)
            errorMessage = nil
            await reload(stackId: stack.id)
            onChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func unstack(_ stack: StackResponseDto) async {
        do {
            try await client.deleteStack(id: stack.id)
            self.stack = nil
            onChanged()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let detail = try await client.getAsset(id: asset.id)
            guard let stackId = detail.stack?.id else {
                stack = nil
                errorMessage = nil
                return
            }
            await reload(stackId: stackId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reload(stackId: String) async {
        do {
            stack = try await client.getStack(id: stackId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @Environment(\.dismiss) private var dismiss
}
