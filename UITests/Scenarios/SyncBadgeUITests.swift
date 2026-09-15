import XCTest

/// End-to-end scenario for the cloud backup badge on timeline tiles (gap G6) —
/// the badge and the ledger behind it, driven from the real app.
///
/// WHAT THIS PROVES, AND WHY IT NEEDS A REAL RUN
///
/// A badge on a tile is a claim about a **backup**: the tile says "this asset is
/// proven to be on the server". The only thing in the app that can make that
/// claim true is a run that asked the server and was told an id — so this
/// scenario seeds the slot's Photos library, runs a manual backup against the
/// stub (dedup + multipart upload), and then reads the timeline. A scenario that
/// stopped at "the toggle exists and the screen renders" would pass with the
/// ledger empty, i.e. with the feature doing nothing at all.
///
/// The sequence is ordered so the setting is the ONLY variable:
///
/// 1. the timeline, ledger empty, setting off → no badge anywhere (pre-state);
/// 2. a real run with the setting **off** → the wire says the run happened, and
///    the timeline is still bare although the ledger now KNOWS the asset. That
///    is the negative proof, and it is stronger than the pre-state: the fact is
///    in the index, and only the preference is missing;
/// 3. the setting on → the SAME ledger lights exactly one tile: the one whose
///    server uuid the upload answered with. The five others, never seen by the
///    ledger, stay bare — never `cloudLocalOnlyBadge`, which for a server uuid
///    the ledger does not know would assert "not on the server" about an asset
///    that another device may well have uploaded (AC-5057).
///
/// Run it with the launcher, never by hand (it owns the slot, seeds the library
/// and grants Photos):
///
///     .omp/orchestration/uitest.sh <worktree> /tmp/sync-badge.uitest.log \
///         UITests/stubs/immich_stub_sync_badge.py SyncBadgeUITests/test_syncBadge \
///         --media /tmp/sync-badge-media.png --erase
///
/// `--erase` matters here: the ledger is a file in the app container, so a
/// leftover entry from an earlier run would leave the timeline badged before
/// anything was backed up — a green that proves nothing.
final class SyncBadgeUITests: XCTestCase {

    /// The stub's URL, as `uitest.sh` hands it over (it forwards
    /// `TEST_RUNNER_IMMICH_STUB_URL`). The fallback is the port a by-hand run
    /// starts under.
    private let stub = ProcessInfo.processInfo.environment["IMMICH_STUB_URL"] ?? "http://127.0.0.1:8421"
    private var app: XCUIApplication!

    /// The tile the run PROVES: it is the first photo of the shell stub's day,
    /// and the uuid the stub answers the upload with — see the stub's docstring.
    private let provenTile = "aaaaaaaa-1111-4111-8111-000000000001"
    /// The control tile: a server uuid the ledger has never heard of.
    private let unseenTile = "aaaaaaaa-1111-4111-8111-000000000002"

    /// The run's outcome, in the two languages the app can be running in (the
    /// slots are English, the repository's own simulator is German, and the app
    /// follows the system — so a literal in one language decides nothing).
    private let runFinished = [
        "Backup complete", "Sauvegarde terminée", "Finished with errors", "Terminé avec des erreurs",
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Skip-vs-run only, so a full-scheme run without a stub stays green.
        // `uitest.sh` starts the stub first and treats a skip as a failure, so
        // this never masks anything under the launcher.
        try XCTSkipUnless(stubIsReachable(), "Local Immich stub not running on \(stub)")
    }

    private func stubIsReachable() -> Bool {
        guard let url = URL(string: "\(stub)/api/server/ping") else { return false }
        let done = DispatchSemaphore(value: 0)
        var ok = false
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        URLSession.shared.dataTask(with: request) { _, response, _ in
            ok = (response as? HTTPURLResponse)?.statusCode == 200
            done.signal()
        }.resume()
        return done.wait(timeout: .now() + 5) == .success && ok
    }

    // MARK: - Helpers
    //
    // Copied from `ImmichRenderScreenshots` / `RecentlyTakenUITests` on purpose:
    // these are `private` there, and the shared file is frozen (the committed
    // scenarios are green against its current text). Extracting them into a
    // shared support file would be a second convention next to the existing one
    // — the harness rule is one file per feature, helpers included.

    private func shot(_ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: "/tmp/shot-\(name).png"))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("SHOT /tmp/shot-\(name).png")
    }

    /// Puts the stub back to its initial state (its request log and its dedup
    /// memory) so no assertion below can be satisfied by a previous run.
    private func reset() {
        var request = URLRequest(url: URL(string: "\(stub)/__reset")!)
        request.timeoutInterval = 5
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, _, _ in done.signal() }.resume()
        _ = done.wait(timeout: .now() + 6)
    }

    /// `manual` = the provider page waits for a click; `auto` = it redirects
    /// itself. This scenario clicks.
    private func setProvider(_ mode: String) {
        let url = URL(string: "\(stub)/__provider?mode=\(mode)")!
        let done = DispatchSemaphore(value: 0)
        var body = ""
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data { body = String(decoding: data, as: UTF8.self) }
            done.signal()
        }.resume()
        XCTAssertEqual(done.wait(timeout: .now() + 10), .success, "Stub did not answer")
        XCTAssertEqual(body, "{\"provider\": \"\(mode)\"}")
    }

    private func labelPredicate(_ labels: [String]) -> NSPredicate {
        NSPredicate(format: labels.map { _ in "label CONTAINS %@" }.joined(separator: " OR "),
                    argumentArray: labels)
    }

    private func waitForStaticText(_ labels: [String], timeout: TimeInterval) -> Bool {
        app.staticTexts.matching(labelPredicate(labels)).firstMatch.waitForExistence(timeout: timeout)
    }

    private func tapAnyButton(_ labels: [String], timeout: TimeInterval = 20) -> Bool {
        let predicate = labelPredicate(labels)
        let direct = app.buttons.matching(predicate).firstMatch
        let contained = app.buttons.containing(predicate).firstMatch
        for candidate in [direct, contained] where candidate.waitForExistence(timeout: timeout) {
            candidate.tap()
            return true
        }
        return false
    }

    /// Waits for any button whose label contains `text` and taps it. Case
    /// sensitive on purpose: the keyboard's return key is labelled "continuer"
    /// in lowercase and would shadow the "Continuer" CTA.
    @discardableResult
    private func tapButton(containing text: String, timeout: TimeInterval = 20) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let button = app.buttons.containing(predicate).firstMatch
        let direct = app.buttons.matching(predicate).firstMatch
        for candidate in [direct, button] where candidate.waitForExistence(timeout: timeout) {
            candidate.tap()
            return true
        }
        return false
    }

    private func dismissSystemSignInAlertIfPresent() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Continue", "Continuer"] {
            let button = springboard.alerts.buttons[label]
            if button.waitForExistence(timeout: 6) {
                button.tap()
                return
            }
        }
        for label in ["Continue", "Continuer"] {
            let button = app.alerts.buttons[label]
            if button.waitForExistence(timeout: 2) {
                button.tap()
                return
            }
        }
    }

    /// The provider page lives in `SafariViewService`, a separate process, so
    /// its "Authorize" link is not in the app's own accessibility tree.
    @discardableResult
    private func tapAuthorizeInProvider(timeout: TimeInterval = 20) -> Bool {
        let safari = XCUIApplication(bundleIdentifier: "com.apple.SafariViewService")
        let predicate = NSPredicate(format: "label CONTAINS 'Authorize'")
        for candidate in [safari.links.matching(predicate).firstMatch,
                          safari.buttons.matching(predicate).firstMatch] {
            if candidate.waitForExistence(timeout: timeout) {
                candidate.tap()
                return true
            }
        }
        return false
    }

    /// Welcome → server URL → login. Leaves the app on the login screen.
    private func walkOnboardingToLogin() {
        XCTAssertTrue(tapAnyButton(["Get Started", "Commencer"], timeout: 30), "Welcome CTA missing")
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "Server URL field missing")
        // The field can hold the PREVIOUS run's URL — a warm slot seeds it — and
        // `typeText` APPENDS. With a random stub port per run that value is
        // always stale, so it is cleared before typing rather than trusted.
        field.tap()
        let seeded = (field.value as? String) ?? ""
        if !seeded.isEmpty && seeded != stub {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: seeded.count))
        }
        if (field.value as? String) != stub {
            field.typeText(stub)
        }
        XCTAssertTrue(tapAnyButton(["Check connection", "Vérifier la connexion"]), "Check-connection CTA missing")
        XCTAssertTrue(app.buttons.matching(labelPredicate(["Continue", "Continuer"]))
            .firstMatch.waitForExistence(timeout: 30), "Server never became reachable")
        // Typing the URL raised the keyboard, and the CTA sits under it: a tap
        // computed from the button's frame then lands on the keyboard and the
        // flow never leaves this screen (measured — it cost one run in two).
        let loginCopy = ["Sign in to Immich", "Connectez-vous à Immich"]
        var onLogin = false
        for _ in 0..<3 where !onLogin {
            app.swipeUp()
            XCTAssertTrue(tapAnyButton(["Continue", "Continuer"]), "Continue CTA missing")
            onLogin = waitForStaticText(loginCopy, timeout: 10)
        }
        if !onLogin {
            shot("sb02b-not-on-login-screen")
            XCTFail("Login screen did not appear — screen reads: "
                    + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        }
    }

    /// Onboarding → SSO → the authenticated shell. A persisted Keychain session
    /// (a slot that was NOT erased) skips the walk instead of failing.
    private func signInIfNeeded() {
        if waitForStaticText(["Your photo library", "Votre photothèque"], timeout: 30) {
            shot("sb01-welcome")
            walkOnboardingToLogin()
            shot("sb02-login-sso")
            XCTAssertTrue(tapButton(containing: "Immich SSO"), "SSO button missing on login screen")
            dismissSystemSignInAlertIfPresent()
            XCTAssertTrue(tapAuthorizeInProvider(), "Authorize link not reachable in the auth sheet")
        }
        XCTAssertTrue(app.tabBars.buttons["Photos"].waitForExistence(timeout: 30),
                      "OAuth did not reach the authenticated shell")
        // A fresh install presents "What's New" over the shell, and a modal
        // swallows every tap: its Done button carries an identifier because its
        // label is translated.
        let whatsNewDone = app.buttons.matching(identifier: "whatsNewDoneButton").firstMatch
        if whatsNewDone.waitForExistence(timeout: 10) {
            shot("sb01b-whats-new")
            whatsNewDone.tap()
        }
    }

    /// One timeline tile, by the identity the grid gives it.
    private func tile(_ assetId: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "assetTile_\(assetId)").firstMatch
    }

    /// Every element carrying `identifier` — the badges are matched this way on
    /// purpose: a query by identifier returns the badge itself, where a
    /// container query would have swallowed its own label.
    private func matches(_ identifier: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: identifier)
    }

    /// A row of the "Me" hub, by IDENTIFIER (its label is translated: "Backup"
    /// / "Sauvegarde"). A `Form` only publishes what it rendered, so the row is
    /// scrolled into view first, letting each swipe settle.
    private func hubRow(_ identifier: String) -> XCUIElement {
        let row = app.buttons.matching(identifier: identifier).firstMatch
        for _ in 0..<8 where !row.exists {
            app.swipeUp()
            sleep(1)
        }
        return row
    }

    /// Me hub → Backup. The hub is a sheet raised from the avatar button.
    private func openBackupScreen() {
        let avatar = app.buttons.matching(identifier: "profileAvatar").firstMatch
        XCTAssertTrue(avatar.waitForExistence(timeout: 20), "Profile avatar missing")
        avatar.tap()
        sleep(4) // the sheet animates in; the Form is not hittable before it does
        let row = hubRow("backupRow")
        if !row.waitForExistence(timeout: 10) {
            shot("sb03b-me-hub-without-backup-row")
            XCTFail("Backup row missing in the Me hub:\n\(app.debugDescription)")
        }
        shot("sb03-me-hub")
        row.tap()
        sleep(2)
        // The push can miss without erroring (a tap that lands on the row's
        // padding does nothing): prove the screen is really the Backup one, or
        // "no badge" assertions below would read the hub and pass vacuously.
        let probe = matches("autoBackupToggle").firstMatch
        for _ in 0..<6 where !probe.exists {
            app.swipeUp()
            sleep(1)
        }
        XCTAssertTrue(probe.waitForExistence(timeout: 10),
                      "the Backup screen did not open after tapping backupRow:\n\(app.debugDescription)")
    }

    /// Is the Me sheet still up? Probed on a row only the hub publishes.
    private func meHubIsUp() -> Bool {
        app.buttons.matching(identifier: "backupRow").firstMatch.exists
    }

    /// The Me hub is a SHEET over the tab tree, and the covered timeline stays in
    /// the accessibility tree: its tiles still exist, and a badge count taken
    /// through the sheet would read them and "prove" the wrong thing. The tab
    /// bar is the element that tells the truth — it sits behind the sheet, so it
    /// is not hittable while the sheet is up.
    private func meSheetIsDown() -> Bool {
        !meHubIsUp() && app.tabBars.buttons["Photos"].isHittable
    }

    /// Backup screen → back to the timeline: pop the pushed screen, then drag
    /// the sheet down. The drag is retried because a Form that is not scrolled
    /// to its top eats the first one.
    private func backToTimeline() {
        dismissNotificationsAlertIfPresent(wait: 2)
        let back = app.navigationBars.firstMatch.buttons.firstMatch
        if back.exists { back.tap(); sleep(2) }
        for _ in 0..<5 where !meSheetIsDown() {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06))
                .press(forDuration: 0.15,
                       thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)),
                       withVelocity: .fast,
                       thenHoldForDuration: 0.2)
            sleep(2)
        }
        XCTAssertTrue(meSheetIsDown(),
                      "the Me sheet never came down — every badge assertion would then read the COVERED "
                      + "timeline, which stays in the accessibility tree and would pass for the wrong reason")
        XCTAssertTrue(tile(provenTile).waitForExistence(timeout: 20),
                      "the timeline is not back after leaving the Me sheet")
        sleep(2)
    }

    /// The sync-badge toggle, scrolled into view (it sits below the four other
    /// toggles of the "Auto backup" section).
    private func syncBadgeToggle() -> XCUIElement {
        let toggle = matches("syncBadgeToggle").firstMatch
        for _ in 0..<8 where !toggle.exists {
            app.swipeUp()
            sleep(1)
        }
        return toggle
    }

    private func isOn(_ element: XCUIElement) -> Bool {
        let value = (element.value as? String)?.lowercased() ?? ""
        return value == "1" || value == "true"
    }

    /// Flips "Show backup status on thumbnails" and verifies the flip: a tap
    /// that missed would leave every later badge assertion meaningless.
    private func setSyncBadge(on: Bool) {
        let toggle = syncBadgeToggle()
        XCTAssertTrue(toggle.waitForExistence(timeout: 10),
                      "the sync-badge toggle is not on the Backup screen:\n\(app.debugDescription)")
        if isOn(toggle) != on { toggle.tap(); sleep(1) }
        XCTAssertEqual(isOn(toggle), on,
                       "the toggle did not turn \(on ? "on" : "off") — a stale preference makes every badge assertion meaningless")
    }

    /// Taps "Run now" and waits for the run's outcome. The completion summary is
    /// drawn after the engine's last ledger commit, so it is the point where the
    /// badge index has already been refreshed.
    private func runBackupAndWait() {
        let run = app.buttons.matching(identifier: "runBackupButton").firstMatch
        for _ in 0..<10 where !run.exists {
            app.swipeUp()
            sleep(1)
        }
        XCTAssertTrue(run.waitForExistence(timeout: 10),
                      "Run now missing on the Backup screen:\n\(app.debugDescription)")
        run.tap()
        // A manual run asks for the notification permission (the run's outcome
        // is posted as a local alert): the system alert belongs to SpringBoard
        // and would swallow every later tap.
        dismissNotificationsAlertIfPresent(wait: 10)
        if !waitForStaticText(runFinished, timeout: 180) {
            shot("sb04b-run-never-finished")
            XCTFail("the backup never reported an outcome — screen reads: "
                    + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        }
        sleep(3) // the summary row is on screen, and the ledger commit is right behind it
    }

    private func dismissNotificationsAlertIfPresent(wait: TimeInterval) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: wait) else { return }
        for label in ["Allow", "Autoriser", "Erlauben", "Consentir"] {
            let button = alert.buttons[label]
            if button.exists {
                button.tap()
                return
            }
        }
    }

    // MARK: - Wire helpers

    /// One entry of the stub's request log. The `checked…`, `deviceAssetId…`
    /// fields are the ones the stub itself noted: it parses the multipart body
    /// and the checksum header, so what is asserted here is what the app SENT,
    /// not what a DTO would have looked like.
    private struct StubRequest: Decodable {
        let method: String
        let path: String
        let checked: Int?
        let firstID: String?
        let firstChecksum: String?
        let deviceAssetId: String?
        let visibility: String?
        let filename: String?
        let checksum: String?
    }

    private func wire() -> [StubRequest] {
        var request = URLRequest(url: URL(string: "\(stub)/__requests")!)
        request.timeoutInterval = 5
        let done = DispatchSemaphore(value: 0)
        var body = ""
        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data { body = String(decoding: data, as: UTF8.self) }
            done.signal()
        }.resume()
        XCTAssertEqual(done.wait(timeout: .now() + 6), .success, "stub did not answer /__requests")
        return (try? JSONDecoder().decode([StubRequest].self, from: Data(body.utf8))) ?? []
    }

    /// `POST /api/assets` — the multipart upload, the only route that puts a
    /// photo on the server.
    private func uploads() -> [StubRequest] {
        wire().filter { $0.method == "POST" && $0.path == "/api/assets" }
    }

    /// `POST /api/assets/bulk-upload-check` — the dedup question.
    private func checks() -> [StubRequest] {
        wire().filter { $0.method == "POST" && $0.path == "/api/assets/bulk-upload-check" }
    }

    // MARK: - Scenario

    func test_syncBadge() throws {
        reset()
        setProvider("manual")
        app.launch()
        signInIfNeeded()

        // MARK: The timeline, before anything: six server uuids, no badge

        let proven = tile(provenTile)
        let unseen = tile(unseenTile)
        if !proven.waitForExistence(timeout: 30) {
            let tiles = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'assetTile_'"))
                .allElementsBoundByIndex.map(\.identifier)
            XCTFail("the timeline never rendered its tiles (\(tiles)) against \(stub); "
                    + "screen reads: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        }
        XCTAssertTrue(unseen.waitForExistence(timeout: 20), "the control tile is missing — nothing to compare against")
        shot("sb05-timeline-clean")
        XCTAssertEqual(matches("cloudBackedUpBadge").count, 0,
                       "a badge is drawn before any backup ran — the ledger is not empty, or the index ignores its setting")
        XCTAssertEqual(matches("cloudLocalOnlyBadge").count, 0,
                       "a 'local only' badge is drawn before any backup ran")
        XCTAssertTrue(uploads().isEmpty, "a photo was uploaded before the run: \(uploads())")

        // MARK: A REAL run, with the setting OFF

        openBackupScreen()
        shot("sb06-backup-settings")
        XCTAssertFalse(isOn(syncBadgeToggle()),
                       "the setting must start off on an erased device")
        runBackupAndWait()
        shot("sb07-backup-complete")

        // MARK: On the wire — the run really happened

        let checks = self.checks()
        let uploads = self.uploads()
        guard let check = checks.first, let upload = uploads.first else {
            XCTFail("the run left no trace on the wire: \(checks.count) bulk-upload-check, \(uploads.count) upload(s) — "
                    + "a badge with no request behind it would be a lie")
            return
        }
        XCTAssertEqual(uploads.count, 1,
                       "one seeded photo must be uploaded exactly once — got ids \(uploads.map { $0.deviceAssetId ?? "-" })")
        XCTAssertEqual(check.checked, 1, "the dedup check must cover the one staged photo")
        XCTAssertEqual(upload.deviceAssetId, check.firstID,
                       "the uploaded photo is not the one that was checked: check=\(check.firstID ?? "nil") upload=\(upload.deviceAssetId ?? "nil")")
        XCTAssertEqual(upload.checksum, check.firstChecksum,
                       "the checksum on the upload differs from the one the dedup check presented — the server would store a different file than it deduplicated")
        XCTAssertEqual(upload.checksum?.count, 28,
                       "the upload's SHA1 must be a base64 digest — got \(upload.checksum ?? "nil")")
        XCTAssertEqual(upload.visibility, "timeline",
                       "a backed-up photo belongs in the timeline — got \(upload.visibility ?? "nil")")
        XCTAssertFalse((upload.filename ?? "").isEmpty,
                       "the upload carried no file name — the multipart file part was empty")
        print("WIRE upload: deviceAssetId=\(upload.deviceAssetId ?? "-") checksum=\(upload.checksum ?? "-") file=\(upload.filename ?? "-")")

        // Back on the timeline, WITH the fact now in the ledger and the setting
        // still off: the feature must stay mute. This is the negative control.

        backToTimeline()
        shot("sb08-timeline-after-run-badge-off")
        XCTAssertEqual(matches("cloudBackedUpBadge").count, 0,
                       "a tile is badged while 'Show backup status on thumbnails' is OFF — the preference is not the badge's gate")
        XCTAssertEqual(matches("cloudLocalOnlyBadge").count, 0,
                       "a 'local only' badge appeared while the setting is OFF")

        // MARK: The SAME ledger, the setting ON — one tile, and only one

        openBackupScreen()
        setSyncBadge(on: true)
        shot("sb09-backup-toggle-on")
        backToTimeline()

        let badge = matches("cloudBackedUpBadge").firstMatch
        if !badge.waitForExistence(timeout: 30) {
            shot("sb10b-no-badge-after-toggle")
            XCTFail("no cloud badge on the timeline after a proven upload — the index is not reaching the cells. "
                    + "Screen reads: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        }
        shot("sb10-timeline-badge")
        XCTAssertEqual(matches("cloudBackedUpBadge").count, 1,
                       "exactly one asset was proven backed up: one badge belongs on screen")
        XCTAssertEqual(matches("cloudLocalOnlyBadge").count, 0,
                       "'only on this device' must never be drawn for a timeline uuid: the timeline serves server ids, and the ledger cannot prove absence")

        // The badge belongs to the tile the server answered with — geometry, not
        // proximity: the pill is drawn in the top-leading corner of ITS cell.
        let badgeFrame = badge.frame
        let provenFrame = tile(provenTile).frame
        let unseenFrame = tile(unseenTile).frame
        XCTAssertTrue(badgeFrame.width > 0 && badgeFrame.height > 0, "the badge has no frame")
        XCTAssertTrue(provenFrame.insetBy(dx: -2, dy: -2).contains(badgeFrame),
                      "the badge is not on the tile the server proved backed up: tile=\(provenFrame) badge=\(badgeFrame)")
        XCTAssertFalse(unseenFrame.contains(badgeFrame),
                       "the badge is drawn on a tile the ledger has never heard of: tile=\(unseenFrame) badge=\(badgeFrame)")
        XCTAssertTrue(["Saved on server", "Enregistré sur le serveur"].contains(badge.label),
                      "the badge must speak the domain's label, not the SF symbol's name — got \(badge.label)")

        // Scroll the first row clear of the floating date header before
        // capturing: the header covers it, so a badge inside it is asserted
        // (accessibility tree) but not visible in the picture.
        app.swipeUp()
        sleep(3)
        shot("sb11-timeline-badge-scrolled")
        XCTAssertTrue(matches("cloudBackedUpBadge").firstMatch.exists,
                      "the badge disappeared when the grid scrolled — it is bound to a row, not to the asset")
        XCTAssertEqual(matches("cloudLocalOnlyBadge").count, 0,
                       "'only on this device' appeared after scrolling")
    }
}
