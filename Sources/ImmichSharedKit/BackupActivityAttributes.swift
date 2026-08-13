import ActivityKit
import Foundation

/// Live Activity attributes for backup progress, shared by the app target
/// (driver) and the widget extension target (rendering). Lives in its own
/// framework so both binaries link the SAME type identity — `Activity`
/// matching is by (module, type).
public struct BackupActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var progress: Double
        public var uploaded: Int
        public var total: Int

        public init(progress: Double, uploaded: Int, total: Int) {
            self.progress = progress
            self.uploaded = uploaded
            self.total = total
        }
    }

    public var totalCount: Int

    public init(totalCount: Int) {
        self.totalCount = totalCount
    }
}