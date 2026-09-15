import Foundation
import Observation

/// App Logs (gap G24): projects the transport's buffer for the screen.
///
/// The store stays the only writer. This view model snapshots it, filters the
/// copy and formats the export — so what the screen shows is always what the
/// transport actually did, never a parallel story assembled for display.
@MainActor
@Observable
final class AppLogViewModel {
    private let store: AppLogStore

    /// The buffer as of the last `refresh()`, most recent first.
    private(set) var entries: [AppLogEntry] = []
    /// nil = every level.
    var levelFilter: AppLogLevel?
    var searchText = ""

    init(store: AppLogStore) {
        self.store = store
    }

    /// Re-reads the buffer. Cheap — one lock and a copy of at most 500 lines —
    /// so appear and pull-to-refresh can both call it without a thought.
    func refresh() {
        entries = store.snapshot()
    }

    /// The rows the list draws: the level first, then free text over the path
    /// and the message, the two things an operator scans for.
    var filteredEntries: [AppLogEntry] {
        var result = entries
        if let levelFilter {
            result = result.filter { $0.level == levelFilter }
        }
        let needle = searchText.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return result }
        return result.filter {
            $0.path.localizedCaseInsensitiveContains(needle)
                || $0.message.localizedCaseInsensitiveContains(needle)
        }
    }

    var isEmpty: Bool { entries.isEmpty }

    func clear() {
        store.clear()
        refresh()
    }

    /// The second line of a row, already stamped: the view formats neither a
    /// date nor a byte.
    ///
    /// The catalog template is filled through `String(format:)` rather than
    /// interpolated into the lookup: an interpolated `String(localized:)` whose
    /// key is not in the catalog yet renders its own placeholders verbatim
    /// ("at %@ in %@"), and this is the line someone reads while diagnosing
    /// exactly that kind of breakage.
    func subtitle(for entry: AppLogEntry) -> String {
        String(
            format: String(localized: "at %@ in %@"),
            Self.timestamp.string(from: entry.date),
            entry.category
        )
    }

    /// The export: one line per entry, in the shape the Flutter logger writes
    /// its file — `date | level | category | method path | status | duration |
    /// message`. Text only, and only when the user asks for it.
    func exportText() -> String {
        entries.map { entry in
            let status = entry.status.map(String.init) ?? "-"
            let duration = entry.durationMS.map { "\($0) ms" } ?? "-"
            return "\(Self.timestamp.string(from: entry.date)) | \(entry.level.rawValue) | \(entry.category)"
                + " | \(entry.method) \(entry.path) | \(status) | \(duration) | \(entry.message)"
        }
        .joined(separator: "\n")
    }

    /// `HH:mm:ss.SSS`, the stamp the upstream log page prints. POSIX so the
    /// format stays the format whatever the device's locale is.
    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
