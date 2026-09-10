import ActivityKit
import Foundation

/// Live Activity attributes for backup progress, shared by the app target
/// (driver) and the widget extension target (rendering). Lives in its own
/// framework so both binaries link the SAME type identity — `Activity`
/// matching is by (module, type).
public struct BackupActivityAttributes: ActivityAttributes {

    /// Lifecycle stage of the backup, mirrored from the engine.
    public enum Phase: String, Codable, Hashable, Sendable {
        case checking
        case uploading
        case done
        case cancelled
    }

    public struct ContentState: Codable, Hashable {
        /// 0...1 completion — same value as the in-app bar. An asset counts
        /// half a step once its original is exported + hashed and the rest
        /// when its outcome lands, so the bar moves during the slow pass.
        public var progress: Double
        /// Assets the run has worked through: finished plus staged. Same
        /// number as the in-app "N of M" counter.
        public var processed: Int
        public var total: Int
        /// Outcome breakdown for the status chips (uploaded / already on
        /// server / waiting for iCloud / failed).
        public var uploaded: Int
        public var onServer: Int
        public var waiting: Int
        public var failed: Int
        public var phase: Phase
        /// Asset in flight (nil between items) — shows *what* is uploading.
        public var fileName: String?
        /// ETA of the upload phase, rendered as a live countdown. Nil while
        /// checking (no throughput yet) or when done.
        public var estimatedDone: Date?

        public init(
            progress: Double,
            processed: Int,
            total: Int,
            uploaded: Int,
            onServer: Int,
            waiting: Int,
            failed: Int,
            phase: Phase,
            fileName: String?,
            estimatedDone: Date?
        ) {
            self.progress = progress
            self.processed = processed
            self.total = total
            self.uploaded = uploaded
            self.onServer = onServer
            self.waiting = waiting
            self.failed = failed
            self.phase = phase
            self.fileName = fileName
            self.estimatedDone = estimatedDone
        }
    }

    public var totalCount: Int

    public init(totalCount: Int) {
        self.totalCount = totalCount
    }
}
