import XCTest

/// End-to-end scenario for **read-only mode** (gap G17) — the one write gate of
/// the app, judged on the WIRE.
///
/// The feature is a single boolean (`ReadOnlyModeStore`, persisted under
/// `readOnlyModeEnabled`) that `ReadOnlyGuardClient` reads from a non-isolated
/// `assertWritable()` in front of every write method of `ImmichClient`. So the
/// scenario does not admire the switch: it makes the app *try* to destroy
/// something, twice, with only the mode in between, and reads the stub's
/// request log to see which attempt left the device.
///
/// Run it with the launcher, never by hand (it owns the slot's simulator,
/// DerivedData and stub port, and refuses a scenario that skipped itself). The
/// mode is a **persisted device setting**, so the device is wiped first —
/// otherwise a previous run's `readOnlyModeEnabled` decides this one:
///
///     .omp/orchestration/uitest.sh <worktree> /tmp/read-only-mode.uitest.log \
///         UITests/stubs/immich_stub_read_only_mode.py \
///         ReadOnlyModeUITests/test_readOnlyMode \
///         --erase --media /tmp/media-a.png --media /tmp/media-b.png
///
/// The stub inherits `immich_stub_base` (OAuth handshake, server config, user,
/// ordinary timeline, real PNG thumbnails) and adds only the backup run's two
/// routes; `DELETE /api/assets` deliberately stays unrouted, so the server
/// answers it happily and its *presence or absence* in `/__requests` is the
/// whole verdict.
final class ReadOnlyModeUITests: XCTestCase {

    /// The stub's URL, as `uitest.sh` hands it over (it forwards
    /// `TEST_RUNNER_IMMICH_STUB_URL`). The fallback is the port a by-hand run
    /// starts under.
    private let stub = ProcessInfo.processInfo.environment["IMMICH_STUB_URL"] ?? "http://127.0.0.1:8421"
    private var app: XCUIApplication!

    // MARK: - Fixtures
    //
    // The shell's own day: six photos, ids recognisable on purpose. The two the
    // scenario touches come from the SECOND row of the grid: the first row sits
    // under the pinned day header, and a tap there would land on the header.
    // `deletedAsset` is the one the allowed delete must name; `refusedAssets`
    // are TWO, so "one refusal" is distinguishable from "one failed call per
    // asset" in the request log.

    private let deletedAsset = "aaaaaaaa-1111-4111-8111-000000000006"
    private let refusedAssets = ["aaaaaaaa-1111-4111-8111-000000000004",
                                 "aaaaaaaa-1111-4111-8111-000000000005"]

    /// The read-only refusal, as `APIError.readOnlyMode` spells it — in every
    /// language the repository ships. The scenario must not care which one the
    /// simulator is set to (the repo's own is German, the launcher's slots are
    /// English).
    private let refusalSnippets = [
        "Read-only mode is on",
        "Le mode lecture seule est activé",
        "Der Nur-Lese-Modus ist aktiv",
        "El modo solo lectura está activado",
        "La modalità sola lettura è attiva",
    ]

    /// The destructive half of the confirmation alerts. A system alert's
    /// buttons are not ours to give identifiers to, so this is the one place
    /// the scenario matches a LABEL — and it matches all five languages.
    private let deleteLabels = ["Delete", "Supprimer", "Löschen", "Eliminar", "Elimina", "Cancella"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // The launcher grants Photos to the bundle before the run (it installs
        // the app first, then grants). If iOS asks anyway, the answer a backup
        // needs is FULL access: XCUITest's default handler taps the alert's
        // default button, which is "Add only" — the run then has no library to
        // read and never uploads (measured: the whole backup CTA control was
        // silently dead). The labels are matched loosely, in the languages a
        // slot can be in; a monitor that never fires changes nothing.
        addUIInterruptionMonitor(withDescription: "Photo library access") { alert in
            let fullAccess = alert.buttons.matching(NSPredicate(format:
                "label CONTAINS[c] 'full access' OR label CONTAINS[c] 'accès complet' "
                + "OR label CONTAINS[c] 'acceso completo' OR label CONTAINS[c] 'accesso completo' "
                + "OR label CONTAINS[c] 'Vollständiger Zugriff'")).firstMatch
            if fullAccess.exists {
                fullAccess.tap()
                return true
            }
            return false
        }
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
    // Copied from `RecentlyTakenUITests` / `ImmichRenderScreenshots` on purpose:
    // they are `private` there, and the shared file is frozen (its committed
    // scenarios are green against its current text). Extracting them into a
    // support file would be a second convention next to the existing one — the
    // harness rule is one file per feature, helpers included.

    private func shot(_ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: "/tmp/shot-\(name).png"))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("SHOT /tmp/shot-\(name).png")
    }

    /// Puts the stub back to its initial state and empties its request log, so
    /// no assertion below can be satisfied by a previous run.
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

    /// Waits for any button whose label contains `text` and taps it.
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
        // Scrolling dismisses the keyboard (`.scrollDismissesKeyboard(.immediately)`),
        // so the CTA is really hittable when it is tapped, and a bounded retry
        // covers the frame the keyboard was still animating over.
        let loginCopy = ["Sign in to Immich", "Connectez-vous à Immich"]
        var onLogin = false
        for _ in 0..<3 where !onLogin {
            app.swipeUp()
            XCTAssertTrue(tapAnyButton(["Continue", "Continuer"]), "Continue CTA missing")
            onLogin = waitForStaticText(loginCopy, timeout: 10)
        }
        if !onLogin {
            shot("00b-not-on-login-screen")
            XCTFail("Login screen did not appear — screen reads: "
                    + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        }
    }

    /// Onboarding → OAuth → the authenticated shell, then waits for the grid.
    /// A persisted Keychain session skips the walk instead of failing.
    private func signInAndReachTimeline() {
        if waitForStaticText(["Your photo library", "Votre photothèque"], timeout: 30) {
            walkOnboardingToLogin()
            shot("00b-login-sso")
            XCTAssertTrue(tapButton(containing: "Immich SSO"), "SSO button missing on login screen")
            dismissSystemSignInAlertIfPresent()
            XCTAssertTrue(tapAuthorizeInProvider(), "Authorize link not reachable in the auth sheet")
        }
        XCTAssertTrue(app.tabBars.buttons["Photos"].waitForExistence(timeout: 30),
                      "OAuth did not reach the authenticated shell")
        // A fresh instal presents "What's New" (gap G23) over the shell, and a
        // modal swallows every tap: the hub would never open under it.
        let whatsNewDone = app.buttons.matching(identifier: "whatsNewDoneButton").firstMatch
        if whatsNewDone.waitForExistence(timeout: 10) {
            shot("00c-whats-new")
            whatsNewDone.tap()
        }
        XCTAssertTrue(tile(refusedAssets[0]).waitForExistence(timeout: 30),
                      "the timeline never rendered the stub's photos — screen reads: "
                      + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    /// One timeline tile, by the identity the grid gives it.
    private func tile(_ assetId: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "assetTile_\(assetId)").firstMatch
    }

    private func avatarButton() -> XCUIElement {
        app.buttons.matching(identifier: "profileAvatar").firstMatch
    }

    /// Taps the avatar and lets the Me sheet finish animating in: a `Form` is
    /// not hittable, and its rows are not published, before it does.
    private func openHub() {
        let avatar = avatarButton()
        XCTAssertTrue(avatar.waitForExistence(timeout: 15), "Profile avatar missing")
        avatar.tap()
        Thread.sleep(forTimeInterval: 4)
    }

    /// A row or control of a `Form`, by IDENTIFIER (its label is translated):
    /// a `Form` only publishes what it rendered, so the element is scrolled into
    /// view — downward only. A row brought back UP ends up under the navigation
    /// bar, and the tap that follows goes to the bar instead of the row
    /// (measured: the Backup screen never opened).
    private func scrolled(_ element: XCUIElement, swipes: Int = 8) -> XCUIElement {
        for _ in 0..<swipes where !element.exists {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
        }
        return element
    }

    /// Scrolls a hub row into view (downward), then taps it and lets the push
    /// animate. Returns once the push had its chance.
    private func openRow(_ identifier: String, swipes: Int = 8) {
        let row = scrolled(app.buttons.matching(identifier: identifier).firstMatch, swipes: swipes)
        guard row.waitForExistence(timeout: 10) else {
            shot("99-no-\(identifier)")
            XCTFail("no '\(identifier)' row reachable in the hub after \(swipes) swipes — screen reads: "
                    + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
            return
        }
        // A row revealed at the very bottom edge is only partly on screen: one
        // nudge brings it clear of the tab bar before the tap.
        if !row.isHittable {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
        }
        row.tap()
        Thread.sleep(forTimeInterval: 3)
    }

    /// A read-only stub device keeps the mode ON, so the switch is turned
    /// through the same value the guard reads — never through a guess about
    /// which half of the row the tap landed on.
    private func setToggle(_ toggle: XCUIElement, on: Bool) {
        let wanted = on ? "1" : "0"
        func value() -> String { (toggle.value as? String) ?? "" }
        if value() == wanted { return }
        toggle.tap()
        if !waitUntil({ value() == wanted }, timeout: 5) {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
        XCTAssertTrue(waitUntil({ value() == wanted }, timeout: 10),
                      "the Read-only Mode switch did not turn \(on ? "on" : "off") (value=\(value()))")
    }

    /// A budgeted wait: the deadline, not a sleep, is the contract. Used for
    /// state this app writes locally (a toggle, an accessibility value), where
    /// no server round-trip tells us when to stop.
    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return condition()
    }

    /// Dismisses the notification-permission prompt a backup run raises (the
    /// run itself is fire-and-forget, so it proceeds under the alert).
    private func dismissSystemAlertIfPresent() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "Autoriser", "Erlauben", "Consenti", "Permitir"] {
            let button = springboard.alerts.buttons[label]
            if button.waitForExistence(timeout: 4) {
                button.tap()
                return
            }
        }
    }

    // MARK: - Deleting

    /// Enters selection mode and taps `ids`, then asks for the batch delete:
    /// the destructive confirmation is up when this returns.
    private func selectForDeletion(_ ids: [String]) {
        // The Photos-style "Select" pill above the grid. It sits inside a
        // `GlassEffectContainer`, and its identifier reaches the button itself
        // (the container is not an accessibility element).
        let select = app.buttons.matching(identifier: "selectButton").firstMatch
        XCTAssertTrue(select.waitForExistence(timeout: 20),
                      "no 'Select' entry point above the grid — screen reads: "
                      + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        select.tap()

        let delete = app.buttons.matching(identifier: "deleteSelectedButton").firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 10),
                      "the selection toolbar never appeared — the tap on Select did not enter selection mode")

        for id in ids {
            let cell = tile(id)
            XCTAssertTrue(cell.waitForExistence(timeout: 20), "tile \(id) missing in the grid")
            cell.tap()
        }
        XCTAssertTrue(delete.isEnabled, "the delete button is disabled with \(ids.count) asset(s) selected")
        delete.tap()
    }

    /// Taps the destructive button of the confirmation alert in front of us.
    private func confirmBatchDelete() {
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "the delete confirmation never came up")
        let confirm = alert.buttons.matching(labelPredicate(deleteLabels)).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5),
                      "no destructive button in the alert — it carries "
                      + "\(alert.buttons.allElementsBoundByIndex.map(\.label))")
        confirm.tap()
    }

    /// The readable half of the refusal: an alert whose message is the
    /// read-only sentence, not a silent no-op. `shotNamed` is captured with the
    /// alert still up — the refusal is the proof, and dismissing it first would
    /// leave no picture of it.
    private func assertRefusalAlert(what: String, shotNamed name: String) {
        let alert = app.alerts.firstMatch
        if !alert.waitForExistence(timeout: 15) {
            let deletes = wire("DELETE", "/api/assets")
            shot("99b-no-refusal-alert")
            XCTFail("\(what) was NOT refused: no alert appeared, and the wire carries "
                    + "\(deletes.count) delete(s) — a refused write leaves the device unchanged:\n"
                    + describe(deletes))
            return
        }
        XCTAssertTrue(alert.staticTexts.matching(labelPredicate(refusalSnippets)).firstMatch.exists,
                      "the alert does not say why \(what) was refused — it reads: "
                      + "\(alert.staticTexts.allElementsBoundByIndex.map(\.label))")
        shot(name)
        alert.buttons.firstMatch.tap()
    }

    // MARK: - Wire helpers

    /// One entry of the stub's request log. `params` is the decoded query
    /// string; `body` carries the fields the assertions need (`ids`, `force`).
    private struct StubRequest: Decodable {
        struct Body: Decodable {
            let ids: [String]?
            let force: Bool?
        }
        let method: String
        let path: String
        let params: [String: String]
        let body: Body?
    }

    private func stubRequests() -> [StubRequest] {
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

    private func wire(_ method: String, _ path: String) -> [StubRequest] {
        stubRequests().filter { $0.method == method && $0.path == path }
    }

    /// Polls the log until `count` requests of that shape are there, or the
    /// deadline passes. A server answer has no event of its own here, so the
    /// wait is budgeted instead of guessed.
    private func waitForWire(_ method: String, _ path: String, atLeast count: Int,
                            timeout: TimeInterval) -> [StubRequest] {
        let deadline = Date().addingTimeInterval(timeout)
        var found = wire(method, path)
        while found.count < count && Date() < deadline {
            Thread.sleep(forTimeInterval: 1)
            found = wire(method, path)
        }
        return found
    }

    private func describe(_ requests: [StubRequest]) -> String {
        requests.map { "\($0.method) \($0.path) params=\($0.params) body=\(String(describing: $0.body))" }
            .joined(separator: "\n")
    }

    // MARK: - Scenario

    func test_readOnlyMode() throws {
        reset()
        setProvider("manual")
        app.launch()

        signInAndReachTimeline()
        shot("01-timeline-mode-off")

        // MARK: 1. Mode off — the delete leaves the device

        selectForDeletion([deletedAsset])
        confirmBatchDelete()
        let allowed = waitForWire("DELETE", "/api/assets", atLeast: 1, timeout: 20)
        XCTAssertEqual(allowed.count, 1,
                       "the allowed delete must reach the server exactly once — got:\n"
                       + describe(stubRequests()))
        XCTAssertEqual(allowed.first?.body?.ids ?? [], [deletedAsset],
                       "the delete must name the selected asset — got:\n\(describe(allowed))")
        XCTAssertEqual(allowed.first?.body?.force, false,
                       "a batch delete is not a force-delete — got:\n\(describe(allowed))")
        XCTAssertTrue(waitUntil({ !self.tile(self.deletedAsset).exists }, timeout: 10),
                      "the server accepted the delete but the grid still shows the asset")
        shot("02-delete-reached-the-server")

        // MARK: 2. The avatar's long press is the SECOND surface of the same boolean.
        //
        // Proved by the guard, not by the avatar's `accessibilityValue`: a delete
        // attempted right after the long press must be refused. The lock badge is
        // the visual (below); the refusal is the fact.

        let avatar = avatarButton()
        XCTAssertTrue(avatar.waitForExistence(timeout: 15), "Profile avatar missing")
        avatar.press(forDuration: 0.8)
        XCTAssertFalse(app.switches.matching(identifier: "readOnlyModeToggle").firstMatch.exists,
                       "the long press must toggle the mode — the Me hub opened instead")
        shot("03-long-press-read-only-on")

        let allowedDeletes = wire("DELETE", "/api/assets").count
        selectForDeletion(refusedAssets)
        confirmBatchDelete()
        assertRefusalAlert(what: "the batch delete of \(refusedAssets.count) assets after the long press",
                           shotNamed: "04-refusal-alert")
        XCTAssertEqual(wire("DELETE", "/api/assets").count, allowedDeletes,
                       "the avatar's long press did not arm the guard: \(refusedAssets.count) assets were "
                       + "selected and the wire carries \(wire("DELETE", "/api/assets").count) delete(s) — "
                       + "got:\n\(describe(stubRequests()))")
        XCTAssertTrue(tile(refusedAssets[1]).exists,
                      "a refused delete must change nothing — the asset left the grid")

        // MARK: 3. The second long press turns it back off
        //
        // The selection survives a refusal (the user can retry), so the grid is
        // left through the toolbar's xmark — behind it the avatar is hidden.

        let cancel = app.navigationBars.firstMatch.buttons.firstMatch
        if cancel.waitForExistence(timeout: 10) { cancel.tap() }
        Thread.sleep(forTimeInterval: 2)
        avatar.press(forDuration: 0.8)
        shot("05-long-press-read-only-off")

        // MARK: 4. One boolean, two readings: the backup CTA, then the hub switch
        //
        // Every `Form` lookup below walks DOWN the form: a row brought back up
        // sits under the navigation bar and the tap misses it.

        openHub()
        openRow("backupRow")
        shot("06-backup-screen-mode-off")

        let runNow = scrolled(app.buttons.matching(identifier: "runBackupButton").firstMatch)
        XCTAssertTrue(runNow.waitForExistence(timeout: 20),
                      "no backup CTA on the backup screen — screen reads: "
                      + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        XCTAssertTrue(runNow.isEnabled,
                      "the second long press left the mode on: the backup CTA still refuses to answer")
        runNow.tap()
        let uploads = waitForWire("POST", "/api/assets", atLeast: 1, timeout: 90)
        dismissSystemAlertIfPresent()
        XCTAssertFalse(uploads.isEmpty,
                       "the allowed run uploaded nothing: without this control, 'the refusal "
                       + "uploaded nothing' would prove nothing — log:\n\(describe(stubRequests()))"
                       + "\nscreen reads: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        XCTAssertFalse(wire("POST", "/api/assets/bulk-upload-check").isEmpty,
                       "the run never confronted the server before uploading — log:\n"
                       + describe(stubRequests()))
        shot("07-backup-uploaded-writes-allowed")

        // Back to the hub (the backup screen is pushed inside it), then down to
        // the Security section: the switch must read what the long presses wrote.
        let back = app.navigationBars.firstMatch.buttons.firstMatch
        if back.waitForExistence(timeout: 10) { back.tap() }
        Thread.sleep(forTimeInterval: 2)

        let toggle = scrolled(app.switches.matching(identifier: "readOnlyModeToggle").firstMatch)
        XCTAssertTrue(toggle.waitForExistence(timeout: 15),
                      "no Read-only Mode switch in the Me hub — screen reads: "
                      + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        XCTAssertEqual(toggle.value as? String, "0",
                       "the two long presses and the hub switch must project ONE boolean; the hub reads "
                       + "\(String(describing: toggle.value))")
        shot("08-hub-switch-off-after-two-long-presses")

        setToggle(toggle, on: true)
        shot("09-hub-switch-on")

        // MARK: 5. The setting survives a relaunch

        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Photos"].waitForExistence(timeout: 40),
                      "the app did not come back to the shell after a relaunch")
        let whatsNewDone = app.buttons.matching(identifier: "whatsNewDoneButton").firstMatch
        if whatsNewDone.waitForExistence(timeout: 5) { whatsNewDone.tap() }

        // MARK: 6. The refused backup CTA — ONE refusal, and no traffic behind it
        //
        // Read on the relaunched app, whose only source for the mode is the
        // persisted default: this is the survival proof AND the refusal.

        openHub()
        openRow("backupRow")

        let blocked = scrolled(app.buttons.matching(identifier: "runBackupButton").firstMatch)
        XCTAssertTrue(blocked.waitForExistence(timeout: 20),
                      "no backup CTA on the backup screen after the relaunch — screen reads: "
                      + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        XCTAssertFalse(blocked.isEnabled,
                       "read-only mode did not survive the relaunch: the backup CTA answers again")
        // MEASURED ANOMALY (2026-09-15, two runs): the Progress footer's
        // conditional sentence ("Read-only mode is on…") is neither drawn nor
        // published to the accessibility tree, while `.disabled(readOnly.isEnabled)`
        // — the same read, in the same section — is in effect on the CTA below.
        // The same holds for the hub's Security footer, whose three texts yield
        // ONE published line: a multi-text `Section(footer:)` only ever shows its
        // first child in this app. So the refusal is asserted where it IS
        // observable: the one control that launches a run is off, and a real touch
        // on it produces no traffic. Reported to the orchestrator.
        shot("10a-backup-cta-disabled-after-relaunch")

        // A real touch on the disabled CTA — a coordinate, so the tap is not
        // filtered by hittability. The run never starts, so neither does the
        // traffic: no upload, and no per-asset confrontation either.
        let uploadsBefore = wire("POST", "/api/assets").count
        let checksBefore = wire("POST", "/api/assets/bulk-upload-check").count
        blocked.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        Thread.sleep(forTimeInterval: 5)
        XCTAssertFalse(app.buttons.matching(identifier: "cancelBackupButton").firstMatch.exists,
                       "the refused backup started anyway — the progress section switched to Cancel")
        XCTAssertEqual(wire("POST", "/api/assets").count, uploadsBefore,
                       "the refused run uploaded: the wire must stay at \(uploadsBefore) upload(s) — got:\n"
                       + describe(stubRequests()))
        XCTAssertEqual(wire("POST", "/api/assets/bulk-upload-check").count, checksBefore,
                       "the refused run still confronted the server per asset — one refusal must not "
                       + "become N attempts — got:\n\(describe(stubRequests()))")
        shot("10-backup-cta-refused-after-relaunch")

        // The second reading of the same boolean, from the hub: the switch the
        // relaunch restored.
        let backAgain = app.navigationBars.firstMatch.buttons.firstMatch
        if backAgain.waitForExistence(timeout: 10) { backAgain.tap() }
        Thread.sleep(forTimeInterval: 2)
        let relaunchedToggle = scrolled(app.switches.matching(identifier: "readOnlyModeToggle").firstMatch)
        XCTAssertTrue(relaunchedToggle.waitForExistence(timeout: 15),
                      "no Read-only Mode switch in the Me hub after the relaunch")
        XCTAssertEqual(relaunchedToggle.value as? String, "1",
                       "read-only mode did not survive the relaunch: the switch reads "
                       + "\(String(describing: relaunchedToggle.value))")
        shot("11-hub-switch-on-after-relaunch")
    }
}
