import Foundation
import Network
import UIKit

/// Runtime conditions the backup engine gates on (testable seam).
protocol BackupEnvironment: Sendable {
    var isCharging: Bool { get }
    var hasWiFiConnection: Bool { get }
    /// Any usable network path (Wi-Fi or cellular). `hasWiFiConnection ==
    /// false` alone cannot tell "on cellular" from "airplane mode", so a run
    /// without the Wi-Fi gate used to export + hash the whole library offline
    /// and then fail every upload.
    var isOnline: Bool { get }
}

/// Production environment: UIDevice battery state + NWPathMonitor cache.
/// The monitor polls in the background; the engine only reads flags.
struct SystemBackupEnvironment: BackupEnvironment, @unchecked Sendable {
    private static let stateLock = NSLock()
    private static var cachedWiFi = false
    private static var cachedOnline = false
    private static var monitorStarted = false

    init() {
        Self.ensureMonitor()
        // Battery state is `.unknown` (→ isCharging false) unless monitoring
        // is explicitly enabled; do it once so the charging gate is accurate.
        DispatchQueue.main.async {
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
    }

    /// Starts the NWPathMonitor once (process-wide) and caches the WiFi flag.
    private static func ensureMonitor() {
        stateLock.lock()
        let shouldStart = !monitorStarted
        monitorStarted = true
        stateLock.unlock()
        guard shouldStart else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            let isWiFi = path.usesInterfaceType(.wifi) && path.status == .satisfied
            let online = path.status == .satisfied
            stateLock.lock()
            cachedWiFi = isWiFi
            cachedOnline = online
            stateLock.unlock()
        }
        monitor.start(queue: .global(qos: .utility))
    }

    var isCharging: Bool {
        switch UIDevice.current.batteryState {
        case .charging, .full: return true
        default: return false
        }
    }

    var hasWiFiConnection: Bool {
        Self.stateLock.lock()
        defer { Self.stateLock.unlock() }
        return Self.cachedWiFi
    }

    var isOnline: Bool {
        Self.stateLock.lock()
        defer { Self.stateLock.unlock() }
        return Self.cachedOnline
    }
}