import Foundation

/// Bounded, synchronous, in-memory log of the transport's egress (gap G24).
///
/// `os.Logger` was the obvious alternative and is rejected for three measurable
/// reasons: it carries no application-level severity of its own, it records
/// neither the request's path nor its status nor its duration, and it offers no
/// "Clear" action — a screen built on it could show nothing an operator wants and
/// could not empty what it did show.
///
/// Synchronous and lock-guarded like `BackupLedger`, the house pattern for a
/// store several threads touch: `dispatch` records on its way out of a
/// `URLSession` call, so `record` cannot `await`. `@unchecked Sendable` because
/// the lock — not the compiler — is what makes it safe.
///
/// **Local only.** Nothing is written to disk, nothing is synchronised, and
/// nothing leaves the device on its own: the buffer dies with the process, and
/// the export is a user action (`ShareLink` in `AppLogView`), never a background
/// one.
final class AppLogStore: AppLogSink, @unchecked Sendable {
    private let lock = NSLock()
    /// Oldest first; `snapshot()` reverses for the screen.
    private var entries: [AppLogEntry] = []
    private let capacity: Int

    /// 500 lines — the bound the Flutter client's logger keeps, chosen there to
    /// hold a session's traffic without holding a session's memory.
    init(capacity: Int = 500) {
        self.capacity = capacity
    }

    func record(_ entry: AppLogEntry) {
        lock.lock(); defer { lock.unlock() }
        entries.append(entry)
        // Surplus goes out the bottom: the newest lines are the ones that
        // describe what just failed, and they are what the operator is reading.
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    /// A copy, most recent first — the order the screen lists and the export
    /// writes.
    func snapshot() -> [AppLogEntry] {
        lock.lock(); defer { lock.unlock() }
        return Array(entries.reversed())
    }

    func count() -> Int {
        lock.lock(); defer { lock.unlock() }
        return entries.count
    }

    /// Empties the buffer — the screen's "Clear" action, and the only eraser.
    func clear() {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll()
    }
}
