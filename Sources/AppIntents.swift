import AppIntents

/// "Back up now" — Siri / Shortcuts entry point (P5 widgets-appintents).
/// Runs in the app process via the shared container, so it reuses the exact
/// backup engine the settings screen drives.
struct BackupNowAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Back up now"
    static var description = IntentDescription("Uploads new photos from the photo library to Immich.")

    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        let upload = await MainActor.run { DependencyContainer.shared.makeUploadViewModel() }
        await upload.runBackup(manual: true)
        return .result()
    }}

/// Registers the shortcut so Siri/Shortcuts can surface it.
struct ImmichAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: BackupNowAppIntent(),
            phrases: [
                "Run \(.applicationName) backup",
                "Back up my \(.applicationName) photos",
                "\(.applicationName) backup now",
            ],
            shortTitle: "Back up now",
            systemImageName: "icloud.and.arrow.up"
        )
    }
}
