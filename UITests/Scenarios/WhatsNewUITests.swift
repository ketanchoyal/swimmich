import XCTest

/// End-to-end scenario for the "What's New" sheet and its "once per batch" rule
/// (gap G23) — one `XCTestCase` per feature, in its own file, against its own
/// committed stub, like `RecentlyTakenUITests` and the 23 scenarios beside it.
///
/// Run it with the launcher, never by hand (it owns the slot's simulator,
/// DerivedData and stub port, and refuses a scenario that skipped itself):
///
///     .omp/orchestration/uitest.sh <worktree> /tmp/whats-new.uitest.log \
///         UITests/stubs/immich_stub_whats_new.py WhatsNewUITests/test_whatsNew \
///         --erase
///
/// `--erase` MATTERS HERE. A slot device is shared and does not reset itself, and
/// this scenario asserts a FIRST presentation: it must start from a device whose
/// app container (defaults + keychain) is empty.
///
/// WHAT IT PROVES, AND WHY IT NEEDS A SEEDED SEEN-RELEASE
///     The batch is announced to an install that UPDATES, not to a brand-new one:
///     `AuthViewModel.applySession` marks the current batch seen as it applies a
///     session (AC-5236), and the only way a freshly erased simulator becomes
///     authenticated is by logging in. So the state the sheet exists for — "an
///     account with a session, a batch it has never seen" — is written by the
///     scenario through `UserDefaults`' argument domain (`-whatsNewSeenRelease
///     0.0.0`, the store's own "has seen nothing" value). Nothing else is faked:
///     the app reads that key through the very `WhatsNewStore` it uses in
///     production, decides from it, marks it seen when the sheet closes, and the
///     relaunch below is launched WITHOUT the override — so what it reads there
///     is what the app PERSISTED.
///
///     The wire is asserted as much as the screen. The batch is embedded, so the
///     run must contain no request for it at all: `assertNoBatchRequest` reads the
///     stub's own log, and the stub answers `/api/feature…` with a 404 rather than
///     the shell's silent `[]` — a screen that looked right while the app fetched
///     its notes from a server would be the bug, not the feature.
final class WhatsNewUITests: XCTestCase {

    /// The stub's URL, as `uitest.sh` hands it over (it forwards
    /// `TEST_RUNNER_IMMICH_STUB_URL`). The fallback is the port a by-hand run
    /// starts under.
    private let stub = ProcessInfo.processInfo.environment["IMMICH_STUB_URL"] ?? "http://127.0.0.1:8421"
    private var app: XCUIApplication!

    /// The five cards of the embedded batch, in catalog order. Matched by
    /// IDENTIFIER: their titles and bodies are localized in five languages, so a
    /// literal would follow the slot's language.
    private let cardIDs = ["shareQuality", "slideshow", "recentlyAdded", "ocr", "uploadToAlbum"]

    /// "Choose your share quality" as the five shipped catalogs render it. The
    /// first card's accessibility label is its title + body (`children: .combine`),
    /// so matching any of these proves the card carries the batch's OWN copy —
    /// which no server in this run could have supplied.
    private let shareQualityTitles = [
        "Choose your share quality",
        "Wähle die Freigabequalität",
        "Elige la calidad al compartir",
        "Choisissez la qualité du partage",
        "Scegli la qualità della condivisione",
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Skip-vs-run only, so a full-scheme run without a stub stays green.
        // `uitest.sh` starts the stub first and treats a skip as a failure.
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
    // Copied from `ImmichRenderScreenshots` on purpose: these are `private`
    // there, and the shared file is frozen (11 committed scenarios are green
    // against its current text). The harness rule is one file per feature,
    // helpers included.

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

    /// The onboarding copy is localized (issue #21), and the repo's own
    /// simulator is in German while the runs use English slots: a walk accepts
    /// both, never one hard-coded language.
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
        // computed from the button's frame lands on the keyboard and the flow
        // never leaves this screen. Scrolling dismisses the keyboard, so the CTA
        // is really hittable when it is tapped.
        let loginCopy = ["Sign in to Immich", "Connectez-vous à Immich"]
        var onLogin = false
        for _ in 0..<3 where !onLogin {
            app.swipeUp()
            XCTAssertTrue(tapAnyButton(["Continue", "Continuer"]), "Continue CTA missing")
            onLogin = waitForStaticText(loginCopy, timeout: 10)
        }
        if !onLogin {
            shot("w00b-not-on-login-screen")
            XCTFail("Login screen did not appear — screen reads: "
                    + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        }
    }

    /// A row of the "Me" hub, by IDENTIFIER (its label is localized: "About" /
    /// "À propos" / "Über"). A `Form` only publishes what it has rendered, so
    /// the row is scrolled into view first, letting each swipe settle.
    private func hubRow(_ identifier: String) -> XCUIElement {
        let row = app.buttons.matching(identifier: identifier).firstMatch
        for _ in 0..<10 where !row.exists {
            app.swipeUp()
            sleep(1)
        }
        return row
    }

    // MARK: - Driving the app

    /// Launches the app with a KNOWN seen-release, through `UserDefaults`'
    /// argument domain (`-key value`) — the standard way a test places a
    /// preference, and the very key the feature reads
    /// (`WhatsNewStore.seenReleaseKey`).
    ///
    /// `"0.0.0"` is the store's own value for "has seen nothing", i.e. exactly
    /// the state the sheet exists for; `nil` launches with no override, so the
    /// app reads what it PERSISTED. The difference between two launches is
    /// therefore only that key — which is what makes the last step of the
    /// scenario a proof rather than a coincidence.
    private func launch(seenRelease: String?) {
        app.terminate()
        app.launchArguments = seenRelease.map { ["-whatsNewSeenRelease", $0] } ?? []
        app.launch()
    }

    /// Onboarding → SSO when the device is fresh, nothing when a session is
    /// already there. `--erase` means the first launch of the run always walks.
    private func signIn() {
        if waitForStaticText(["Your photo library", "Votre photothèque"], timeout: 30) {
            shot("w00-welcome")
            walkOnboardingToLogin()
            shot("w01-login-sso")
            XCTAssertTrue(tapButton(containing: "Immich SSO"), "SSO button missing on the login screen")
            dismissSystemSignInAlertIfPresent()
            XCTAssertTrue(tapAuthorizeInProvider(), "Authorize link not reachable in the auth sheet")
        }
    }

    /// The authenticated shell, by the one thing only it can show: a tile of
    /// THIS stub's timeline — which also proves the app is talking to the stub
    /// of this run and not to a server left over from another slot.
    @discardableResult
    private func shellIsUp(timeout: TimeInterval = 40) -> Bool {
        let tab = app.tabBars.buttons.matching(labelPredicate(["Photos", "Fotos"])).firstMatch
        let tile = app.descendants(matching: .any)
            .matching(identifier: "assetTile_aaaaaaaa-1111-4111-8111-000000000001").firstMatch
        return tab.waitForExistence(timeout: timeout) && tile.waitForExistence(timeout: timeout)
    }

    /// A card of the sheet, by IDENTIFIER.
    private func card(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "whatsNewCard_\(id)").firstMatch
    }

    private func back() {
        let back = app.navigationBars.firstMatch.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10), "no way back from the pushed screen")
        back.tap()
        sleep(1)
    }

    // MARK: - Wire helpers

    /// One entry of the stub's request log.
    private struct StubRequest: Decodable {
        let method: String
        let path: String
        let params: [String: String]
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

    private func describe(_ requests: [StubRequest]) -> String {
        requests.map { "\($0.method) \($0.path) params=\($0.params)" }.joined(separator: "\n")
    }

    /// No request of the whole run may have asked a server for the batch: it is
    /// embedded (AC-5230). Read from the stub's own log, so it also covers a
    /// request the app sent and then ignored.
    private func assertNoBatchRequest(on moment: String) {
        let suspicious = stubRequests().filter {
            let path = $0.path.lowercased()
            return path.contains("feature") || path.contains("whatsnew") || path.contains("what's-new")
        }
        XCTAssertTrue(suspicious.isEmpty,
                      "the batch is embedded and must never be fetched — \(moment), these went out:\n"
                      + describe(suspicious))
    }

    // MARK: - Scenario

    func test_whatsNew() throws {
        reset()
        setProvider("manual")

        // MARK: 1. A batch this account has never seen: the sheet opens BY ITSELF

        launch(seenRelease: "0.0.0")
        signIn()
        guard shellIsUp() else {
            shot("w02b-no-shell")
            return XCTFail("the app never reached the authenticated shell; screen reads: "
                           + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        }
        shot("w02-first-authenticated-launch")

        let firstCard = card("shareQuality")
        guard firstCard.waitForExistence(timeout: 40) else {
            shot("w03b-no-whats-new-sheet")
            return XCTFail("the sheet did not present itself at the first authenticated launch "
                           + "(stored release 0.0.0, catalog release 3.0.0); screen reads: "
                           + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        }

        // The batch's OWN copy is on the first card — in whichever of the five
        // languages the slot renders it.
        let firstLabel = firstCard.label
        XCTAssertTrue(shareQualityTitles.contains { firstLabel.contains($0) },
                      "the first card does not carry the batch's copy (label: \(firstLabel))")

        // All five cards, scrolling the sheet the way a reader would: a
        // `LazyVStack` only publishes what it has rendered.
        var seen = Set<String>()
        for _ in 0..<8 {
            for id in cardIDs where card(id).exists { seen.insert(id) }
            if seen.count == cardIDs.count { break }
            app.swipeUp()
            sleep(1)
        }
        XCTAssertEqual(seen.sorted(), cardIDs.sorted(),
                       "the sheet does not list the whole embedded batch; screen reads: "
                       + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        shot("w04-whats-new-sheet")

        // MARK: On the wire — nothing was fetched for it

        let log = stubRequests()
        XCTAssertTrue(log.contains { $0.method == "POST" && $0.path == "/api/oauth/callback" },
                      "the app never completed the OAuth handshake against \(stub):\n\(describe(log))")
        assertNoBatchRequest(on: "while the sheet was up")

        // MARK: 2. Closing it marks the batch seen

        let done = app.buttons.matching(identifier: "whatsNewDoneButton").firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10), "the presented sheet offers no Done button")
        XCTAssertTrue(done.isHittable, "the Done button is not hittable")
        done.tap()
        XCTAssertTrue(firstCard.waitForNonExistence(timeout: 15), "Done did not dismiss the sheet")
        shot("w05-sheet-dismissed")

        // MARK: 3. Relaunched with NO override: the release persisted, the sheet stays away

        launch(seenRelease: nil)
        guard shellIsUp() else {
            shot("w06b-no-shell-after-relaunch")
            return XCTFail("the relaunch never reached the authenticated shell; screen reads: "
                           + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        }
        XCTAssertFalse(firstCard.waitForExistence(timeout: 15),
                       "the sheet came back after it was dismissed: the release was not persisted as seen")
        shot("w06-relaunch-no-sheet")

        // MARK: 4. The Me hub's About row — version, and the batch ON DEMAND

        let avatar = app.buttons.matching(identifier: "profileAvatar").firstMatch
        guard avatar.waitForExistence(timeout: 20) else {
            shot("w07b-no-profile-avatar")
            return XCTFail("the Me hub is unreachable:\n\(app.debugDescription)")
        }
        avatar.tap()
        sleep(4) // the sheet animates in; its Form is not hittable before it does

        let aboutRow = hubRow("aboutRow")
        guard aboutRow.waitForExistence(timeout: 10) else {
            shot("w07c-no-about-row")
            return XCTFail("About row missing in the Me hub:\n\(app.debugDescription)")
        }
        aboutRow.tap()
        shot("w07-about")

        // The version is the BINARY's, read from the bundle: a placeholder or an
        // empty value here means the Info.plist keys were not resolved. A
        // `LabeledContent` publishes ONE element ("Version, 0.1.0 (1)"), and its
        // caption is translated, so only the tail is matched.
        let version = app.staticTexts
            .matching(NSPredicate(format: "label MATCHES %@", #".*\d+(\.\d+)+ \(\d+\)$"#)).firstMatch
        XCTAssertTrue(version.waitForExistence(timeout: 15),
                      "About shows no bundle version (expected a \"…, 0.1.0 (1)\" row); screen reads: "
                      + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")

        let whatsNewRow = app.buttons.matching(identifier: "aboutWhatsNewRow").firstMatch
        XCTAssertTrue(whatsNewRow.waitForExistence(timeout: 15), "About has no What's New row")
        whatsNewRow.tap()
        XCTAssertTrue(card("slideshow").waitForExistence(timeout: 20),
                      "the About row did not open the batch; screen reads: "
                      + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        // Pushed, not presented: it closes with the back button, and the Done
        // button belongs to the sheet only (`WhatsNewView.onDone`).
        XCTAssertFalse(app.buttons.matching(identifier: "whatsNewDoneButton").firstMatch.exists,
                       "the pushed screen must not offer the sheet's Done button")
        shot("w08-whats-new-from-about")
        back()

        // MARK: 5. Licences — the files the app really ships

        let licensesRow = app.buttons.matching(identifier: "aboutLicensesRow").firstMatch
        XCTAssertTrue(licensesRow.waitForExistence(timeout: 15), "About has no Licenses row")
        licensesRow.tap()

        // Each row names a dependency this app links, and its body is the bundled
        // attribution FILE — asserted by a phrase only that file contains (the
        // MIT grant, the Apache URL), never by text copied into the app. Each
        // licence is COLLAPSED again after it is read: a 230-line body pushes the
        // next section out of the `List`'s rendered window (measured — the second
        // row was unreachable with the first one left open), so the list is put
        // back the way it was found before moving on.
        for (id, phrase) in [("socket.io-client-swift", "Permission is hereby granted"),
                             ("starscream", "http://www.apache.org/licenses/")] {
            let row = app.descendants(matching: .any)
                .matching(identifier: "licenseRow_\(id)").firstMatch
            for _ in 0..<10 where !row.isHittable {
                app.swipeUp()
                sleep(1)
            }
            guard row.isHittable else {
                shot("w09b-no-license-row")
                return XCTFail("no \(id) row on the Licenses screen:\n\(app.debugDescription)")
            }
            row.tap() // expand the disclosure group
            let body = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", phrase)).firstMatch
            XCTAssertTrue(body.waitForExistence(timeout: 15),
                          "\(id)'s bundled attribution file is not on screen (looked for \(phrase)); screen reads: "
                          + "\(app.staticTexts.allElementsBoundByIndex.map { String($0.label.prefix(60)) })")
            // The marker a packaging failure would show INSTEAD of the body: it
            // only ever renders inside an expanded section, so it is checked here.
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "licenseMissingRow").firstMatch.exists,
                           "\(id)'s attribution file could not be resolved in the bundle")
            guard row.isHittable else {
                shot("w09c-license-row-unreachable")
                return XCTFail("\(id)'s row can no longer be reached to collapse it:\n\(app.debugDescription)")
            }
            row.tap() // collapse, so the next section is on screen again
            sleep(1)
        }
        shot("w09-licenses")

        // MARK: 6. The stored release is what decides — mark it seen, then zero it

        // Two relaunches that differ by ONE thing: the release the app reads as
        // already seen. Same binary, same account, same session, same server, no
        // rebuild in between. Did the sheet follow something else — a timer, the
        // account, a build flag, "the first launch of the process" — these two
        // would agree, and one of them would fail.
        launch(seenRelease: "3.0.0")
        guard shellIsUp() else {
            shot("w10b-no-shell-after-relaunch")
            return XCTFail("the relaunch with the batch marked seen never reached the authenticated shell")
        }
        XCTAssertFalse(card("shareQuality").waitForExistence(timeout: 15),
                       "the sheet was presented although the stored release IS the catalog release (3.0.0)")
        shot("w10-stored-release-is-current-no-sheet")

        launch(seenRelease: "0.0.0")
        guard shellIsUp() else {
            shot("w11b-no-shell-after-relaunch")
            return XCTFail("the last relaunch never reached the authenticated shell")
        }
        XCTAssertTrue(card("shareQuality").waitForExistence(timeout: 40),
                      "the same app, with only its stored release put back to 0.0.0, did not present the sheet "
                      + "again — so the stored release is not what decides; screen reads: "
                      + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        shot("w11-stored-release-zeroed-sheet-returns")
        assertNoBatchRequest(on: "after the last relaunch")
    }
}
