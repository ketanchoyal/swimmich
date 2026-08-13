import SwiftUI

/// Assign-one-face sheet (gap #5): reassign the tapped face to an existing
/// person or create a new person by name and assign it. Backed by
/// `AssetDetailViewModel` so a successful assignment refreshes the panel's
/// face list in place.
struct FaceAssignSheet: View {
    let face: AssetFaceResponseDto
    let asset: AssetReactItem
    let vm: AssetDetailViewModel
    let baseURL: URL
    let token: String?
    var onChanged: () -> Void = {}

    @State private var newName = ""
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: PVSpacing.s12) {
                        FaceThumbnailView(asset: asset, face: face, baseURL: baseURL, token: token)
                            .frame(width: 96, height: 96)
                            .clipShape(Circle())
                        Text(face.person?.name ?? "Unnamed")
                            .font(.pvH6)
                            .foregroundStyle(Color.textPrimaryPV)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, PVSpacing.s8)
                }

                Section("Existing people") {
                    let candidates = vm.allPeople.filter { $0.id != face.person?.id }
                    if candidates.isEmpty {
                        Text("No other people yet.")
                            .font(.pvCaption)
                            .foregroundStyle(Color.textSecondaryPV)
                    } else {
                        ForEach(candidates) { person in
                            Button {
                                Task { await assign(to: person) }
                            } label: {
                                HStack(spacing: PVSpacing.s12) {
                                    AuthenticatedAsyncImage(
                                        url: ImmichAssetURL.personThumbnail(personId: person.id, baseURL: baseURL),
                                        token: token
                                    )
                                    .frame(width: 36, height: 36)
                                    .clipShape(Circle())
                                    Text(person.name)
                                        .font(.pvBody)
                                        .foregroundStyle(Color.textPrimaryPV)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("New person") {
                    TextField("Name", text: $newName)
                        .textInputAutocapitalization(.words)
                    Button {
                        Task { await createAndAssign() }
                    } label: {
                        Label("Create and assign", systemImage: "person.badge.plus")
                    }
                    .disabled(isBusy || newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Assign Face")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func assign(to person: PersonResponseDto) async {
        isBusy = true
        await vm.reassignFace(faceId: face.id, toPersonId: person.id)
        isBusy = false
        if vm.errorMessage == nil {
            onChanged()
            dismiss()
        }
    }

    private func createAndAssign() async {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isBusy = true
        await vm.createPersonAndAssign(faceId: face.id, name: name)
        isBusy = false
        if vm.errorMessage == nil {
            onChanged()
            dismiss()
        }
    }

    @Environment(\.dismiss) private var dismiss
}
