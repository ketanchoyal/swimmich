import SwiftUI

/// Edits an existing shared link (AC-1092): description, password, expiry and
/// permissions (upload/download/metadata). Reusable across surfaces — the
/// caller supplies the save closure, so the sheet has no client dependency.
///
/// Server semantics: `password: ""` clears the password, `nil` leaves it
/// unchanged; `expiresAt: nil` clears the expiry. Permission booleans are
/// always sent (full edit).
struct EditSharedLinkSheet: View {
    let link: SharedLinkResponseDto
    let onSave: (SharedLinkEditDto) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var description: String
    @State private var usePassword: Bool
    @State private var password: String
    @State private var hasExpiry: Bool
    @State private var expiryDate: Date
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
        _hasExpiry = State(initialValue: link.expiresAt != nil)
        _expiryDate = State(initialValue: LongDateFormatter.parse(isoTimestamp: link.expiresAt ?? "") ?? Date().addingTimeInterval(30 * 24 * 3600))
        _allowUpload = State(initialValue: link.allowUpload)
        _allowDownload = State(initialValue: link.allowDownload)
        _showMetadata = State(initialValue: link.showMetadata)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private var dto: SharedLinkEditDto {
        SharedLinkEditDto(
            password: usePassword ? password : nil,
            expiresAt: hasExpiry ? Self.isoFormatter.string(from: expiryDate) : nil,
            allowUpload: allowUpload,
            allowDownload: allowDownload,
            showMetadata: showMetadata,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : description.trimmingCharacters(in: .whitespacesAndNewlines)
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
                }
                Section("Expiration") {
                    Toggle("Expires", isOn: $hasExpiry)
                    if hasExpiry {
                        DatePicker("Expiry date", selection: $expiryDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    }
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
                    }
                }
            }
        }
        .sensoryFeedback(.success, trigger: saveTick)
    }
}
