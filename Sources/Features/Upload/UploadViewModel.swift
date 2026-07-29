import Foundation
import SwiftUI

/// Upload / backup scaffold state.
///
/// AC-008 (multipart shape) is covered by ImmichAPIClientTests — the upload
/// path through this view model just composes that API. Real background backup
/// (BGTaskScheduler, asset diffing, progress UI) is a roadmap item.
@Observable
final class UploadViewModel {
    let client: any ImmichClient
    let photos: any PhotoLibraryService

    var isBackupEnabled = false
    var uploadedIds: Set<String> = []
    var lastError: String?

    init(client: any ImmichClient, photos: any PhotoLibraryService) {
        self.client = client
        self.photos = photos
    }

    /// Uploads raw asset bytes given pre-resolved metadata. Phase-2 foundation
    /// exposes this so the multipart client path is wired end-to-end.
    @MainActor
    func upload(
        data: Data,
        fileCreatedAt: String,
        fileModifiedAt: String,
        filename: String,
        duration: Int?,
        isFavorite: Bool,
        checksum: String
    ) async {
        do {
            let resp = try await client.uploadAsset(
                data: data,
                fileCreatedAt: fileCreatedAt,
                fileModifiedAt: fileModifiedAt,
                filename: filename,
                duration: duration,
                isFavorite: isFavorite,
                visibility: .timeline,
                livePhotoVideoId: nil,
                checksum: checksum
            )
            uploadedIds.insert(resp.id)
        } catch let e {
            lastError = e.localizedDescription
        }
    }
}

/// Simple backup settings screen.
struct BackupSettingsView: View {
    @Environment(AuthViewModel.self) private var auth

    var body: some View {
        @Bindable var auth = auth
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Server", value: auth.serverURLString)
                    LabeledContent("User", value: auth.userEmail ?? "—")
                }
                Section("Backup") {
                    Text("Background backup is a roadmap item. The upload API surface is wired and unit-tested.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Backup")
        }
    }
}
