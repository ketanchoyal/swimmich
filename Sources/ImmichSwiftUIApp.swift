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
                    case .active:
                        if container.appLock.isEnabled && container.appLock.isLocked {
                            Task { _ = await container.appLock.authenticate() }
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
    /// at its discretion (low priority, network required). Each run resubmits
    /// so the chain survives as long as backups are enabled.
    private func registerBackgroundBackup() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BGTaskBackupScheduler.taskIdentifier,
            using: nil
        ) { task in
            guard let task = task as? BGProcessingTask else { return }
            let upload = container.makeUploadViewModel()
            task.expirationHandler = {
                upload.engine.cancel()
            }
            Task {
                await upload.runBackup()
                task.setTaskCompleted(success: upload.engine.failedCount == 0)
                BGTaskBackupScheduler().submit()
            }
        }
    }
}
