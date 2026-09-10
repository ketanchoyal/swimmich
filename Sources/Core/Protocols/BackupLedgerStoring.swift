import Foundation

/// Persistent record of assets already backed up to the server, keyed by the
/// Photos `localIdentifier`. It lets a run skip assets it has already handled
/// — uploaded, or confirmed by the server as duplicates — *before* exporting
/// them, so an iCloud-optimized library is never re-downloaded run after run
/// just to be re-hashed and re-rejected.
///
/// The stored value is the asset's `modificationDate` signature: a later edit
/// changes it, so the asset drops out of the ledger match and is reconsidered
/// (and re-uploaded) on the next run.
protocol BackupLedgerStoring: Sendable {
    /// True when this exact asset+signature was already backed up.
    func isBackedUp(id: String, signature: String) -> Bool

    /// Records an asset as backed up, with the checksum it was uploaded (or
    /// rejected) under. The checksum is what makes the ledger reconcilable:
    /// it is replayed against `bulk-upload-check` to detect assets the server
    /// no longer has, at no media-byte cost. In-memory and cheap; durability is
    /// flushed by `save()`.
    func markBackedUp(id: String, signature: String, checksum: String)

    /// Every tracked entry that has a checksum — the reconciliation payload.
    /// Entries migrated from the v1 file have none and are skipped: replaying
    /// them is impossible without re-hashing the asset, which is precisely the
    /// download the ledger exists to avoid.
    func entriesForReconciliation() -> [(id: String, checksum: String)]

    /// Drops entries the server no longer has, so the next scan re-uploads them.
    func forget(ids: [String])

    /// When the ledger was last confronted with the server (nil = never).
    var lastReconciliation: Date? { get }

    /// Stamps a successful reconciliation pass.
    func recordReconciliation(at date: Date)

    /// Flushes pending changes to disk (best-effort, may run asynchronously).
    func save()

    /// Number of tracked assets — surfaced in the backup settings UI.
    func trackedCount() -> Int

    /// Forgets every tracked asset, forcing a full re-backup on the next run.
    /// Used when the server library was wiped and the local ledger is stale.
    func removeAll()
}
