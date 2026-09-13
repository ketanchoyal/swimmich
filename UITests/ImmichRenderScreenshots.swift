import XCTest

/// End-to-end UI verification for the OAuth/SSO flow — drives the real app
/// through onboarding and `ASWebAuthenticationSession` against a local Immich
/// API stub and writes screenshots to `/tmp`.
///
/// This is the only test that exercises the real browser session: it is the
/// regression guard for the 404 the flow used to hit on `/api/auth/oauth/*`
/// (the app never reached the authenticated shell). It needs the stub running:
///
///     python3 /tmp/immich_stub_modes.py 8421
///
/// Without it the tests skip, so the default scheme stays green.
final class ImmichRenderScreenshots: XCTestCase {

    private let stub = "http://127.0.0.1:8421"
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        try XCTSkipUnless(stubIsReachable(), "Local Immich stub not running on \(stub)")
    }

    /// Probe used only to decide skip-vs-run; the assertions below make their
    /// own requests.
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

    private func shot(_ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: "/tmp/shot-\(name).png"))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("SHOT /tmp/shot-\(name).png")
    }

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

    /// Puts the stacks stub back to its initial state (one 3-photo stack).
    /// Best-effort: the plain OAuth stub has no such route, and those tests
    /// never look at stacks.
    private func resetStacks() {
        var request = URLRequest(url: URL(string: "\(stub)/__reset")!)
        request.timeoutInterval = 5
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, _, _ in done.signal() }.resume()
        _ = done.wait(timeout: .now() + 6)
    }

    /// Waits for any button whose label contains `text` and taps it.
    ///
    /// Case-sensitive on purpose: the software keyboard's return key is
    /// labelled "continuer" (lowercase) and would otherwise shadow the
    /// "Continuer" CTA.
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
        // Some iOS builds surface the consent alert inside the app's own tree.
        for label in ["Continue", "Continuer"] {
            let button = app.alerts.buttons[label]
            if button.waitForExistence(timeout: 2) {
                button.tap()
                return
            }
        }
    }

    /// Taps the provider's "Authorize" link. The OAuth page is presented by
    /// `ASWebAuthenticationSession` in the system's `SafariViewService`
    /// process, so it is invisible to the app's own accessibility tree.
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

    /// The app persists the OAuth session (Keychain token), so only a
    /// simulator without it can present the onboarding flow. Re-runs on a warm
    /// simulator skip the full browser walk instead of failing.
    ///
    ///     xcrun simctl erase <device>   # to re-arm the full walk
    private func requireCleanSession() throws {
        try XCTSkipUnless(
            app.staticTexts["Votre photothèque"].waitForExistence(timeout: 25),
            "A persisted OAuth session skips onboarding — erase the simulator to re-run the full walk"
        )
    }

    /// Welcome → server URL → login. Leaves the app on the login screen.
    private func walkOnboardingToLogin() {
        XCTAssertTrue(tapButton(containing: "Commencer", timeout: 30), "Welcome CTA missing")
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "Server URL field missing")
        // The stub URL may already be seeded in the app's defaults; retyping
        // would append and produce an invalid URL.
        if (field.value as? String) != stub {
            field.tap()
            field.typeText(stub)
        }
        XCTAssertTrue(tapButton(containing: "Vérifier la connexion"), "Check-connection CTA missing")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Continuer'"))
            .firstMatch.waitForExistence(timeout: 30), "Server never became reachable")
        shot("02-server-reachable")
        XCTAssertTrue(tapButton(containing: "Continuer"), "Continue CTA missing")
        XCTAssertTrue(app.staticTexts["Identifiez-vous"].waitForExistence(timeout: 20),
                      "Login screen did not appear")
        app.swipeUp() // dismisses the keyboard (.scrollDismissesKeyboard)
    }

    // MARK: - Scenarios

    func test_01_onboardingAndOAuthSignIn() throws {
        setProvider("manual")
        app.launch()
        try requireCleanSession()
        shot("01-welcome")
        walkOnboardingToLogin()
        shot("03-login-sso-visible")

        XCTAssertTrue(tapButton(containing: "Immich SSO"), "SSO button missing on login screen")
        dismissSystemSignInAlertIfPresent()
        // The provider page lives in the system auth sheet (a separate
        // process), so the "Authorize" link is queried there, not in `app`.
        XCTAssertTrue(tapAuthorizeInProvider(), "Authorize link not reachable in the auth sheet")

        // Callback → POST /api/oauth/callback → session applied → main shell.
        XCTAssertTrue(app.tabBars.buttons["Photos"].waitForExistence(timeout: 30),
                      "OAuth did not reach the authenticated shell")
        sleep(4) // let the timeline load its first buckets
        shot("06-timeline-after-oauth")

        // "Me" is a sheet raised from the avatar button in every tab's bar.
        let profile = app.buttons["Profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 15), "Profile avatar missing")
        profile.tap()
        sleep(3)
        shot("07-profile-me")
    }

    func test_02_renderAuthorizedShellAfterRelaunch() {
        setProvider("auto")
        app.launch()
        if app.staticTexts["Votre photothèque"].waitForExistence(timeout: 30) {
            walkOnboardingToLogin()
            XCTAssertTrue(tapButton(containing: "Immich SSO"), "SSO button missing on login screen")
            dismissSystemSignInAlertIfPresent()
            _ = tapAuthorizeInProvider()
        }
        XCTAssertTrue(app.tabBars.buttons["Photos"].waitForExistence(timeout: 30),
                      "Authorized shell missing")
        sleep(4)
        shot("08-timeline-relaunch")

        app.tabBars.buttons["Albums"].tap()
        sleep(3)
        shot("09-albums")
    }

    /// Stacks (gap #1) against a stub that returns one 3-photo stack: the
    /// timeline tile must show the stack badge, tapping it must open the stack
    /// detail (the bucket carries only the cover), and the «Me» hub must list
    /// the same stack.
    ///
    /// Needs the stacks stub, which also serves the timeline bucket:
    ///
    ///     python3 /tmp/immich_stub_stacks.py 8421
    func test_03_stacksBadgeDetailAndHub() throws {
        setProvider("auto")
        resetStacks()
        app.launch()
        if app.staticTexts["Votre photothèque"].waitForExistence(timeout: 30) {
            walkOnboardingToLogin()
            XCTAssertTrue(tapButton(containing: "Immich SSO"), "SSO button missing on login screen")
            dismissSystemSignInAlertIfPresent()
            _ = tapAuthorizeInProvider()
        }
        XCTAssertTrue(app.tabBars.buttons["Photos"].waitForExistence(timeout: 30),
                      "Authorized shell missing")
        sleep(5)
        shot("10-timeline")

        // 3 members → the cover advertises the 2 photos behind it.
        let badge = app.descendants(matching: .any).matching(identifier: "stackBadge").firstMatch
        for _ in 0..<4 where !badge.exists {
            app.swipeUp()
            sleep(1)
        }
        XCTAssertTrue(badge.waitForExistence(timeout: 20),
                      "stack badge missing on the cover tile (withStacked column not rendered)")
        shot("11-timeline-stack-badge")

        badge.tap()
        XCTAssertTrue(app.staticTexts["Cover"].waitForExistence(timeout: 15),
                      "tapping a stacked tile did not open the stack detail")
        sleep(2)
        shot("12-stack-detail")

        // Back out of the pushed detail (the timeline hides its bar in browse
        // mode, so this also proves the destination puts a back affordance up).
        let back = app.navigationBars.firstMatch.buttons.firstMatch
        if back.waitForExistence(timeout: 5) {
            shot("13-stack-detail-back-button")
            back.tap()
        } else {
            app.swipeRight()
        }
        sleep(2)

        let profile = app.buttons["Profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 15), "Profile avatar missing")
        profile.tap()
        sleep(4)

        // The Management section sits below Storage, past the first screenful —
        // a Form only publishes what it has rendered.
        let stacksRow = app.buttons["Stacks"]
        for _ in 0..<4 where !stacksRow.exists {
            app.swipeUp()
            sleep(1)
        }
        shot("14-profile-me")
        XCTAssertTrue(stacksRow.waitForExistence(timeout: 10), "Stacks row missing in the Me hub")
        stacksRow.tap()
        sleep(3)
        shot("15-stacks-hub")
        XCTAssertTrue(app.staticTexts["3 photos"].waitForExistence(timeout: 15),
                      "the hub did not list the stack")
    }

    /// Adding photos to an existing stack. There is no add-asset route on the
    /// server: the app re-posts `POST /api/stacks` with the stack's current
    /// cover first, which makes the server merge it — **and return a new stack
    /// id**. The stub models that faithfully (the old id 404s), so this test
    /// fails if the detail screen keeps holding the id it was pushed with.
    ///
    /// Needs the stacks stub: `python3 /tmp/immich_stub_stacks.py 8421`
    func test_04_addPhotosToExistingStack() throws {
        setProvider("auto")
        resetStacks()
        app.launch()
        if app.staticTexts["Votre photothèque"].waitForExistence(timeout: 30) {
            walkOnboardingToLogin()
            XCTAssertTrue(tapButton(containing: "Immich SSO"), "SSO button missing on login screen")
            dismissSystemSignInAlertIfPresent()
            _ = tapAuthorizeInProvider()
        }
        XCTAssertTrue(app.tabBars.buttons["Photos"].waitForExistence(timeout: 30),
                      "Authorized shell missing")
        sleep(5)

        let badge = app.descendants(matching: .any).matching(identifier: "stackBadge").firstMatch
        shot("16-timeline")
        for _ in 0..<4 where !badge.exists {
            app.swipeUp()
            sleep(1)
        }
        XCTAssertTrue(badge.waitForExistence(timeout: 20), "stack badge missing")
        badge.tap()

        // The stack the stub started with: aaaa-01.jpg on the cover.
        XCTAssertTrue(app.staticTexts["aaaa-01.jpg"].waitForExistence(timeout: 15),
                      "stack detail did not open")
        shot("17-stack-before-add")

        let addPhotos = app.buttons["addPhotosToStack"]
        XCTAssertTrue(addPhotos.waitForExistence(timeout: 10), "no 'Add photos' entry point")
        addPhotos.tap()

        // bbbb-09.jpg belongs to no stack, so it is the photo to add. It sits
        // behind the stack's own members, which the picker leaves out.
        let candidate = app.descendants(matching: .any)
            .matching(identifier: "pickerAsset_bbbbbbbb-2222-4222-8222-000000000009")
            .firstMatch
        for _ in 0..<5 where !candidate.exists {
            app.swipeUp()
            sleep(1)
        }
        XCTAssertTrue(candidate.waitForExistence(timeout: 15), "pickable photo missing from the grid")
        XCTAssertFalse(app.descendants(matching: .any)
            .matching(identifier: "pickerAsset_aaaaaaaa-1111-4111-8111-000000000002")
            .firstMatch.exists,
            "a photo already in the stack must not be offered again")
        candidate.tap()
        shot("18-add-to-stack-picker")

        // Identifiers, not labels: the CTA's label is localized ("Créer"/"Add"
        // depending on the catalog), the identifier is not.
        let add = app.buttons["confirmAddToStack"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Add CTA missing")
        XCTAssertTrue(add.isEnabled, "tapping a photo did not select it")
        add.tap()
        sleep(4)

        // The server re-created the stack under a new id: the screen must have
        // followed it, kept the cover, and gained the member.
        XCTAssertTrue(app.staticTexts["bbbb-09.jpg"].waitForExistence(timeout: 20),
                      "the added photo is not in the stack (detail screen stranded on the dead id?)")
        XCTAssertTrue(app.staticTexts["aaaa-01.jpg"].exists, "the cover changed")
        shot("19-stack-after-add")

        let back = app.navigationBars.firstMatch.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "no back button on the stack detail")
        back.tap()
        sleep(2)

        let profile = app.buttons["Profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 15), "Profile avatar missing")
        profile.tap()
        sleep(4)
        let stacksRow = app.buttons["Stacks"]
        for _ in 0..<4 where !stacksRow.exists {
            app.swipeUp()
            sleep(1)
        }
        XCTAssertTrue(stacksRow.waitForExistence(timeout: 10), "Stacks row missing in the Me hub")
        stacksRow.tap()
        sleep(3)
        shot("20-stacks-hub-after-add")

        XCTAssertTrue(app.staticTexts["4 photos"].waitForExistence(timeout: 15),
                      "the hub still shows the stack it had before the add")
    }

    /// Creating a stack from the hub. Kept as its own flow because the picker is
    /// where a silent regression hides: `AssetThumbnailCell` carries its own
    /// `onTapGesture`, so wrapping it in a `Button` swallows every tap — the
    /// grid then renders perfectly and selects nothing.
    ///
    /// Needs the stacks stub: `python3 /tmp/immich_stub_stacks.py 8421`
    func test_05_createStackFromHub() throws {
        setProvider("auto")
        resetStacks()
        app.launch()
        if app.staticTexts["Votre photothèque"].waitForExistence(timeout: 30) {
            walkOnboardingToLogin()
            XCTAssertTrue(tapButton(containing: "Immich SSO"), "SSO button missing on login screen")
            dismissSystemSignInAlertIfPresent()
            _ = tapAuthorizeInProvider()
        }
        XCTAssertTrue(app.tabBars.buttons["Photos"].waitForExistence(timeout: 30),
                      "Authorized shell missing")
        sleep(4)

        let profile = app.buttons["Profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 15), "Profile avatar missing")
        profile.tap()
        sleep(4)
        let stacksRow = app.buttons["Stacks"]
        for _ in 0..<4 where !stacksRow.exists {
            app.swipeUp()
            sleep(1)
        }
        XCTAssertTrue(stacksRow.waitForExistence(timeout: 10), "Stacks row missing in the Me hub")
        stacksRow.tap()
        sleep(3)

        let plus = app.buttons["newStackButton"]
        XCTAssertTrue(plus.waitForExistence(timeout: 10), "no create button in the hub")
        plus.tap()
        sleep(3)

        let first = app.descendants(matching: .any)
            .matching(identifier: "pickerAsset_cccccccc-3333-4333-8333-000000000001").firstMatch
        let second = app.descendants(matching: .any)
            .matching(identifier: "pickerAsset_cccccccc-3333-4333-8333-000000000002").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15), "picker did not load")

        // The CTA stays disabled until 2 photos are picked (the server's
        // minimum), so a tap that fails to register shows up there — which is
        // exactly how the swallowed-tap defect surfaced.
        first.tap()
        second.tap()
        shot("21-create-stack-picker")

        let create = app.buttons["confirmCreateStack"]
        XCTAssertTrue(create.waitForExistence(timeout: 10), "Create CTA missing")
        XCTAssertTrue(create.isEnabled, "tapping photos did not select them (2 needed)")
        create.tap()
        sleep(4)
        shot("22-stacks-hub-after-create")

        XCTAssertTrue(app.staticTexts["2 photos"].waitForExistence(timeout: 15),
                      "the new stack is not in the hub")
    }
}
