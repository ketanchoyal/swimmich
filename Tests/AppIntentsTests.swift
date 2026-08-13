import AppIntents
import XCTest
@testable import ImmichSwiftUI

final class AppIntentsTests: XCTestCase {

    func test_backupIntent_exposesTitle() {
        let intent = BackupNowAppIntent()
        XCTAssertEqual(String(describing: intent), "BackupNowAppIntent()")
    }

    func test_shortcutsProvider_registersOneShortcut() {
        let shortcuts = ImmichAppShortcuts.appShortcuts
        XCTAssertEqual(shortcuts.count, 1)
    }

    func test_backupIntent_openAppWhenRun() {
        XCTAssertTrue(BackupNowAppIntent.openAppWhenRun)
    }
}
