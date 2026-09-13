import SwiftUI

/// Edits an existing shared link (AC-1092): description, password, slug, expiry
/// and permissions (upload/download/metadata). Reusable across surfaces — the
/// caller supplies the save closure, so the sheet has no client dependency.
///
/// Server semantics: `password: ""` clears the password, `nil` leaves it
/// unchanged; a nil `expiresAt` clears the expiry. Permission booleans are
/// always sent (full edit).
///
/// The **slug** is different: `SharedLinkService.update` writes
/// `slug: dto.slug || null`, so an omitted slug is CLEARED. The DTO therefore
/// always carries the current value — an empty field means "remove the slug",
/// which is the only reading the server supports.
struct EditSharedLinkSheet: View {
    let link: SharedLinkResponseDto
    let onSave: (SharedLinkEditDto) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var description: String
    @State private var usePassword: Bool
    @State private var password: String
    @State private var slug: String
    @State private var expiresAt: Date?
    @State private var allowUpload: Bool
    @State private var allowDownload: Bool
    @State private var showMetadata: Bool
    @State private var isSaving = false
    @State private var saveTick = 0

    init(link: SharedLinkResponseDto, onSave: @escaping (SharedLinkEditDto) async -> Bool) {
        self.link = link
        self.onSave = onSave
        _description = State(initialValue: link.description ?? "")
        _usePassword = State(initialValue: link.password != nil)
        _password = State(initialValue: link.password ?? "")
        _slug = State(initialValue: link.slug ?? "")
        _expiresAt = State(initialValue: LongDateFormatter.parse(isoTimestamp: link.expiresAt ?? ""))
        _allowUpload = State(initialValue: link.allowUpload)
        _allowDownload = State(initialValue: link.allowDownload)
        _showMetadata = State(initialValue: link.showMetadata)
    }

    private var dto: SharedLinkEditDto {
        let trimmedSlug = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        return SharedLinkEditDto(
            password: usePassword ? password : nil,
            expiresAt: expiresAt.map { Self.isoFormatter.string(from: $0) },
            allowUpload: allowUpload,
            allowDownload: allowDownload,
            showMetadata: showMetadata,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : description.trimmingCharacters(in: .whitespacesAndNewlines),
            slug: trimmedSlug.isEmpty ? "" : trimmedSlug
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Description (optional)", text: $description)
                    Toggle("Password protect", isOn: $usePassword)
                    if usePassword {
                        SecureField("Password", text: $password)
                    }
                    HStack(spacing: 0) {
                        if !slug.isEmpty {
                            Text("/s/")
                                .foregroundStyle(Color.textSecondaryPV)
                                .accessibilityHidden(true)
                        }
                        TextField("Custom URL", text: $slug)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("sharedLinkSlugField")
                    }
                }
                Section("Expiration") {
                    SharedLinkExpiryPicker(date: $expiresAt)
                }
                Section("Permissions") {
                    Toggle("Allow upload", isOn: $allowUpload)
                    Toggle("Allow download", isOn: $allowDownload)
                    Toggle("Show metadata", isOn: $showMetadata)
                }
            }
            .navigationTitle("Edit Shared Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task {
                                isSaving = true
                                let ok = await onSave(dto)
                                isSaving = false
                                if ok {
                                    saveTick &+= 1
                                    dismiss()
                                }
                            }
                        }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("confirmEditSharedLink")
                    }
                }
            }
        }
        .sensoryFeedback(.success, trigger: saveTick)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
