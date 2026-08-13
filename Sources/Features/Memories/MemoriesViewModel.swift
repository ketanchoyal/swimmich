import Foundation

/// Memories ("On this day") tab state — parity with the Flutter client's
/// Memories screen. Lists `MemoryResponseDto`s from `GET /api/memories` (P0
/// api-surface-expansion). Display + browsing only; save/unsave is a backlog
/// item (server endpoints not exposed in the client yet).
@MainActor
@Observable
final class MemoriesViewModel {
    private let client: any ImmichClient

    var memories: [MemoryResponseDto] = []
    var isLoading = false
    var errorMessage: String?

    init(client: any ImmichClient) {
        self.client = client
    }

    /// Loads the memory list, sorted by memory date descending (freshest year
    /// first). try-then-mutate: `memories` is replaced only on success.
    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let fetched = try await client.getMemories()
            memories = fetched.sorted {
                ($0.data.year, $0.memoryAt) > ($1.data.year, $1.memoryAt)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
