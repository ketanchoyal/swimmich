import SwiftUI

/// "Partagé" tab root (PRD §4).
///
/// Phase 0 scaffold. The existing `SharedLinkSheet` manages links scoped to a
/// single album (it is coupled to `AlbumDetailViewModel`). A cross-album
/// "all my shared links" list view requires a server endpoint that is not yet
/// wired into `ImmichClient` — it is deferred to a later PRD phase and tracked
/// via the `$PHASE_SHARED_LINKS_LIST` marker below.
///
/// Until then this screen surfaces a clear empty state and routes the user to
/// the album list, where per-album link management already works via the sheet.
struct SharedLinksView: View {
    @Environment(AuthViewModel.self) private var auth

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Partagé", systemImage: "person.2.fill")
            } description: {
                Text("Vos liens partagés apparaîtront ici.")
            }
            .navigationTitle("Partagé")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
