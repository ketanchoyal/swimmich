import BackgroundTasks
import SwiftUI

@main
struct ImmichSwiftUIApp: App {
    @State private var container = DependencyContainer.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .background:
                        container.appLock.lock()
                        // No PhotoLibrary observer outside the foreground: it
                        // cannot fire usefully there, and it would race the
                        // BGTask window's own run.
                        container.libraryMonitor.stop()
                    case .active:
                        if container.appLock.isEnabled && container.appLock.isLocked {
                            Task { _ = await container.appLock.authenticate() }
                        }
                        // "Upload at launch / on return": kick the gated
                        // engine directly when auto-backup is configured,
                        // then keep the pending background request alive so
                        // the next OS window picks up anything new.
                        container.kickOffAutoBackup()
                        container.syncLibraryMonitor()
                        if container.isAutoBackupEnabled() {
                            container.backupScheduler.submit()
                        }
                    default:
                        break
                    }
                }
                .onAppear {
                    registerBackgroundBackup()
                }
        }
    }

    /// Registers the one-shot background processing task. Launched by the OS
    /// at its discretion (low priority, network required). The pending
    /// request is re-submitted FIRST (shared scheduler instance) so the
    /// self-perpetuating chain survives even if the run is killed, expires
    /// or the process is terminated mid-flight — a run that never finishes
    /// is still retried on the next OS window.
    private func registerBackgroundBackup() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BGTaskBackupScheduler.taskIdentifier,
            using: nil
        ) { task in
            guard let task = task as? BGProcessingTask else { return }
            if container.isAutoBackupEnabled() {
                container.backupScheduler.submit()
            }
            let upload = container.upload
            task.expirationHandler = {
                upload.engine.cancel()
            }
            Task {
                await upload.runBackup()
                task.setTaskCompleted(
                    success: upload.engine.phase == .done && upload.engine.failedCount == 0
                )
            }
        }
    }
}
