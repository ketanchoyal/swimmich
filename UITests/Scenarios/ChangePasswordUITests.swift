import XCTest

/// End-to-end scenario for the change-password screen (gap G18) and the server's
/// `shouldChangePassword` reminder — one `XCTestCase` per feature, in its own
/// file, against its own committed stub.
///
/// It drives the real app: onboarding → SSO → the "Me" hub, where the Security
/// section shows the reminder the SERVER asked for → "Change Password" → a wrong
/// current password (refused, the form kept) → the stub's secret (accepted) →
/// back to the hub, where the reminder is gone. And it asserts on the WIRE what
/// each attempt carried, which is where the feature really lives:
/// `POST /api/auth/change-password` is the only place the three DTO fields
/// exist, and the "Sign out on other devices" switch — turned off before the
/// accepted send — has to reach it as `invalidateSessions: false` rather than as
/// the default the screen happened to open with.
///
/// A wrongly typed current password is a **400** on the real server, not a 401:
/// the app answers a 401 by dropping the whole session, so the scenario also
/// proves the refusal did not log the user out (the form, the hub and the
/// session are all still there afterwards).
///
/// Run it with the launcher, never by hand (it owns the slot's simulator,
/// DerivedData and stub port, and refuses a scenario that skipped itself):
///
///     .omp/orchestration/uitest.sh <worktree> /tmp/change-password.uitest.log \
///         UITests/stubs/immich_stub_change_password.py ChangePasswordUITests/test_changePassword
///
/// The stub inherits `immich_stub_base` (OAuth handshake, server config, user,
/// ordinary timeline, real PNG thumbnails) and adds the two routes that make the
/// flag load-bearing: `/api/users/me` answers `shouldChangePassword: true` until
/// `POST /api/auth/change-password` accepts the stub's secret. See its docstring.
final class ChangePasswordUITests: XCTestCase {

    /// The stub's URL, as `uitest.sh` hands it over (it forwards
    /// `TEST_RUNNER_IMMICH_STUB_URL`). The fallback is the port a by-hand run
    /// starts under.
    private let stub = ProcessInfo.processInfo.environment["IMMICH_STUB_URL"] ?? "http://127.0.0.1:8421"
    private var app: XCUIApplication!

    /// The stub's secret, the typo submitted first, and the new password.
    /// `wrongPassword.count` is how many characters the `SecureField` has to
    /// give back before it is retyped, and the new one is over the server's
    /// `minLength: 8` so the local rules let the valid form through.
    private let currentPassword = "stub-current-secret"
    private let wrongPassword = "stub-wrong-secret"
    private let newPassword = "stub-brand-new-secret"

    /// The two outcomes the screen shows, in every language the catalogue
    /// carries: the repo's own simulator is German, the slots are English, and a
    /// literal would follow whichever one ran.
    private let refusedMessage = ["That password is not right.", "Ce mot de passe est incorrect.",
                                  "Das Passwort ist nicht korrekt.", "Esa contraseña no es correcta.",
                                  "La password non è corretta."]
    private let changedMessage = ["Your password has been changed.", "Votre mot de passe a été modifié.",
                                  "Dein Passwort wurde geändert.", "Tu contraseña se ha cambiado.",
                                  "La tua password è stata cambiata."]

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
    // these are `private` there, and the shared file is frozen (its committed
    // scenarios are green against its current text). Extracting them into a
    // shared support file would be a second convention next to the existing one —
    // the harness rule is one file per feature, helpers included.

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
    /// no assertion below can be satisfied by a previous run: the server asks
    /// for a new password again, and no change has been applied.
    private func reset() {
        var request = URLRequest(url: URL(string: "\(stub)/__reset")!)
        request.timeoutInterval = 5
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, _, _ in done.signal() }.resume()
        _ = done.wait(timeout: .now() + 6)
    }

    /// `manual` = the provider page waits for a click; `auto` = it redirects
    /// itself. This scenario clicks, like the committed ones.
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

    /// The copy of the walk is localized (issue #21), and the repo's own
    /// simulator is in German while the runs use English slots: a walk accepts
    /// both, never one hard-coded language.
    private func labelPredicate(_ labels: [String]) -> NSPredicate {
        NSPredicate(format: labels.map { _ in "label CONTAINS %@" }.joined(separator: " OR "),
                    argumentArray: labels)
    }

    private func waitForStaticText(_ labels: [String], timeout: TimeInterval) -> Bool {
        app.staticTexts.matching(labelPredicate(labels)).firstMatch.waitForExistence(timeout: timeout)
    }

    /// Waits for a text to leave the screen — the reminder's disappearance is
    /// proof, and it happens one server round trip after the change.
    private func waitForAbsence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                            object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
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
            shot("cp01b-not-on-login-screen")
            XCTFail("Login screen did not appear — screen reads: "
                    + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        }
    }

    /// One timeline tile, by the identity the grid gives it.
    private func tile(_ assetId: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "assetTile_\(assetId)").firstMatch
    }

    /// A row of the "Me" hub, by IDENTIFIER (its label is localized: "Change
    /// Password" / "Passwort ändern"). The Security section sits below the fold
    /// and a `Form` only publishes what it has rendered, so the row is scrolled
    /// into a HITTABLE position — existence alone could be an off-screen row, and
    /// an off-screen row would also make the reminder's later absence a false
    /// proof.
    private func hubRow(_ identifier: String) -> XCUIElement {
        let row = app.buttons.matching(identifier: identifier).firstMatch
        _ = bringIntoView(row, tries: 12)
        return row
    }

    // MARK: - The screen's own elements

    /// An element by identifier, whatever its type: the reminder is a `Label`
    /// (a static text or a group depending on the platform).
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// One of the three password fields. They flip between `secureTextFields`
    /// and `textFields` with their reveal button, so both are accepted — the
    /// identifier is the anchor, never the element type.
    private func passwordField(_ identifier: String) -> XCUIElement {
        let secure = app.secureTextFields.matching(identifier: identifier).firstMatch
        return secure.exists ? secure : app.textFields.matching(identifier: identifier).firstMatch
    }

    /// Scrolls until `element` can really be tapped, then reports whether it got
    /// there. Two things cover it: the form is longer than the screen (the hub's
    /// Security row, the submit section at the bottom of this form), and the
    /// keyboard takes the lower half once a field has focus. The preferred
    /// direction is the caller's, and the opposite one is tried afterwards —
    /// a form too short to move under the first swipe must not fail a tap that
    /// one swipe the other way would have made.
    private func bringIntoView(_ element: XCUIElement, preferringUp: Bool = true,
                               tries: Int = 5) -> Bool {
        for _ in 0..<tries where !element.isHittable {
            if preferringUp { app.swipeUp() } else { app.swipeDown() }
            sleep(1)
        }
        for _ in 0..<tries where !element.isHittable {
            if preferringUp { app.swipeDown() } else { app.swipeUp() }
            sleep(1)
        }
        return element.isHittable
    }

    /// Types into one of the three password fields, scrolling it into a hittable
    /// position first: a tap computed on a field the keyboard covers lands on the
    /// keyboard, so hittability is a precondition, not a hope.
    private func type(_ identifier: String, _ text: String) {
        let field = passwordField(identifier)
        XCTAssertTrue(field.waitForExistence(timeout: 15),
                      "\(identifier) missing on the change-password screen")
        XCTAssertTrue(bringIntoView(field), "\(identifier) never became hittable")
        field.tap()
        field.typeText(text)
    }

    /// Replaces a field's content. Select-all + delete is flaky on a
    /// `SecureField`, so the existing characters are removed one by one — which
    /// is why the scenario keeps its literal and knows its length.
    private func retype(_ identifier: String, replacing count: Int, with text: String) {
        let field = passwordField(identifier)
        XCTAssertTrue(bringIntoView(field), "\(identifier) never became hittable")
        field.tap()
        if count > 0 {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count))
        }
        field.typeText(text)
    }

    /// Taps the form's submit button, scrolling it out from under the keyboard
    /// first. A filled form is submittable by construction: the button is
    /// disabled while the local rules refuse the entry, so a disabled button here
    /// means the rules are wrong, not that the tap was early.
    private func tapSubmit() {
        let submit = app.buttons.matching(identifier: "changePasswordSubmit").firstMatch
        XCTAssertTrue(submit.waitForExistence(timeout: 20), "the submit button is missing")
        XCTAssertTrue(bringIntoView(submit), "the submit button never came out from under the keyboard")
        XCTAssertTrue(submit.isEnabled, "a valid form must be submittable")
        submit.tap()
    }

    /// Drives "Sign out on other devices" to `on`, and proves the switch really
    /// moved: the wire assertion below reads this control, so a tap that quietly
    /// missed would turn that assertion into a guess about the screen's default.
    ///
    /// Two details are measured, not assumed. A tap on the ROW's centre does not
    /// move a `Form` toggle here (the switch stayed on for a full ten seconds),
    /// so the first attempt aims at the switch itself — 94 % across the row; and
    /// the drag that pulls the row out from under the keyboard is still settling
    /// when the tap lands, so taps repeat until the value changes, alternating
    /// the switch and the row as targets. The loop cannot sneak a pass through:
    /// only the value the element reports ends it.
    private func setSessionsToggle(_ on: Bool) {
        let toggle = app.switches.matching(identifier: "invalidateSessionsToggle").firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 15),
                      "the 'Sign out on other devices' toggle is missing")
        XCTAssertTrue(bringIntoView(toggle), "the session toggle never became hittable")
        let expected = on ? "1" : "0"
        var taps = 0
        let deadline = Date().addingTimeInterval(20)
        while (toggle.value as? String) != expected && Date() < deadline {
            let across = taps % 2 == 0 ? 0.94 : 0.5
            toggle.coordinate(withNormalizedOffset: CGVector(dx: across, dy: 0.5)).tap()
            taps += 1
            usleep(800_000)
        }
        XCTAssertEqual(toggle.value as? String, expected,
                       "the 'Sign out on other devices' switch never reached \(expected) "
                       + "after \(taps) taps; it reads \(String(describing: toggle.value))")
    }

    // MARK: - Wire helpers

    /// One entry of the stub's request log, decoded with the three fields the
    /// feature posts — the wire is what the screen cannot be trusted for.
    private struct StubRequest: Decodable {
        struct Body: Decodable {
            let password: String?
            let newPassword: String?
            let invalidateSessions: Bool?
        }

        let method: String
        let path: String
        let params: [String: String]
        let body: Body

        var summary: String {
            "\(method) \(path) params=\(params) password=\(body.password ?? "-") "
                + "newPassword=\(body.newPassword ?? "-") "
                + "invalidateSessions=\(body.invalidateSessions.map(String.init) ?? "-")"
        }
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

    /// Every `POST /api/auth/change-password` the app sent, in order — the one
    /// route the whole feature hangs on.
    private func changePasswordPosts() -> [StubRequest] {
        stubRequests().filter { $0.method == "POST" && $0.path == "/api/auth/change-password" }
    }

    /// Waits for the log to hold `count` change-password posts. A request that
    /// the app refused LOCALLY never reaches the wire, so "no post" and "not yet"
    /// have to be told apart by waiting, not by sleeping.
    private func waitForChangePasswordPosts(_ count: Int, timeout: TimeInterval) -> [StubRequest] {
        let deadline = Date().addingTimeInterval(timeout)
        var posts = changePasswordPosts()
        while posts.count < count && Date() < deadline {
            usleep(300_000)
            posts = changePasswordPosts()
        }
        return posts
    }

    private func describe(_ requests: [StubRequest]) -> String {
        requests.map(\.summary).joined(separator: "\n")
    }

    // MARK: - Scenario

    func test_changePassword() throws {
        reset()
        setProvider("manual")
        app.launch()

        // Onboarding → OAuth. A persisted Keychain session skips the walk
        // instead of failing, so re-running on a warm slot stays useful; the
        // launcher's refusal of `skipped` only concerns the stub being absent.
        if waitForStaticText(["Your photo library", "Votre photothèque"], timeout: 30) {
            shot("cp01-welcome")
            walkOnboardingToLogin()
            shot("cp02-login-sso")
            XCTAssertTrue(tapButton(containing: "Immich SSO"), "SSO button missing on login screen")
            dismissSystemSignInAlertIfPresent()
            XCTAssertTrue(tapAuthorizeInProvider(), "Authorize link not reachable in the auth sheet")
        }
        XCTAssertTrue(app.tabBars.buttons["Photos"].waitForExistence(timeout: 30),
                      "OAuth did not reach the authenticated shell")

        // A fresh install presents "What's New" (gap G23) over the shell, and a
        // modal swallows every tap: the hub would never open under it.
        let whatsNewDone = app.buttons.matching(identifier: "whatsNewDoneButton").firstMatch
        if whatsNewDone.waitForExistence(timeout: 10) {
            shot("cp03-whats-new")
            whatsNewDone.tap()
        }

        // The ordinary timeline: the shell's own day, six photos. Its first tile
        // also proves the app is talking to THIS stub — a session persisted
        // against another slot's port would leave the grid empty.
        XCTAssertTrue(tile("aaaaaaaa-1111-4111-8111-000000000001").waitForExistence(timeout: 30),
                      "the timeline never rendered against \(stub); screen reads: "
                      + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")

        // MARK: The "Me" hub — the reminder the server asked for

        let avatar = app.buttons.matching(identifier: "profileAvatar").firstMatch
        XCTAssertTrue(avatar.waitForExistence(timeout: 15), "Profile avatar missing")
        avatar.tap()
        sleep(4) // the sheet animates in; the Form is not hittable before it does

        let row = hubRow("changePasswordRow")
        if !row.waitForExistence(timeout: 10) {
            shot("cp04b-me-hub-without-security-row")
            XCTFail("Change Password row missing in the Me hub:\n\(app.debugDescription)")
        }
        // The stub answered `shouldChangePassword: true` on `/api/users/me`, which
        // is the ONLY reason this reminder is on screen: the hub asks the server
        // when it opens.
        let reminder = element("shouldChangePasswordNotice")
        XCTAssertTrue(reminder.waitForExistence(timeout: 20),
                      "the server asks for a new password but the Security section does not say so")
        shot("cp05-me-hub-security")

        row.tap()
        sleep(2)

        // MARK: The form — nothing is sent while it is empty

        let submit = app.buttons.matching(identifier: "changePasswordSubmit").firstMatch
        XCTAssertTrue(submit.waitForExistence(timeout: 20),
                      "the change-password screen did not present — screen reads: "
                      + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        XCTAssertTrue(passwordField("currentPasswordField").exists, "the current-password field is missing")
        XCTAssertTrue(passwordField("newPasswordField").exists, "the new-password field is missing")
        XCTAssertTrue(passwordField("confirmPasswordField").exists, "the confirmation field is missing")
        XCTAssertTrue(app.switches.matching(identifier: "invalidateSessionsToggle").firstMatch.exists,
                      "the 'Sign out on other devices' toggle is missing")
        XCTAssertFalse(submit.isEnabled, "an empty form must not be submittable")
        shot("cp06-form-empty")
        XCTAssertTrue(changePasswordPosts().isEmpty,
                      "an untouched form posted to the server:\n\(describe(changePasswordPosts()))")

        // MARK: A wrong current password — refused, and the entry kept

        type("currentPasswordField", wrongPassword)
        type("newPasswordField", newPassword)
        type("confirmPasswordField", newPassword)
        shot("cp07-form-filled")

        tapSubmit()
        XCTAssertTrue(waitForStaticText(refusedMessage, timeout: 25),
                      "a wrong current password must say so — screen reads: "
                      + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        let refused = waitForChangePasswordPosts(1, timeout: 10)
        guard let first = refused.first else {
            return XCTFail("no POST /api/auth/change-password for the refused attempt — got:\n"
                           + "\(describe(stubRequests()))")
        }
        XCTAssertEqual(first.body.password, wrongPassword)
        XCTAssertEqual(first.body.newPassword, newPassword)
        XCTAssertEqual(first.body.invalidateSessions, true,
                       "the toggle opens on: other devices are signed out unless the user says otherwise")
        shot("cp08-wrong-current-password")

        // The form is kept — proven on the wire, not by reading a masked field:
        // submitting again with no retyping is only possible if all three fields
        // still hold what they held, because `canSubmit` is what enables the
        // button. A screen that cleared the entry would send nothing here.
        tapSubmit()
        XCTAssertTrue(waitForChangePasswordPosts(2, timeout: 15).count >= 2,
                      "the refused attempt emptied the form: a second tap sent nothing — got:\n"
                      + "\(describe(stubRequests()))")
        XCTAssertEqual(changePasswordPosts()[1].body.password, wrongPassword,
                       "the retried attempt must carry the same entry")

        // MARK: The accepted change

        // The current password is corrected (one character at a time: a typo is
        // a typo) and "Sign out on other devices" is turned OFF, so the wire
        // below reads the switch and not the screen's default.
        retype("currentPasswordField", replacing: wrongPassword.count, with: currentPassword)
        setSessionsToggle(false)
        shot("cp09-form-corrected")
        tapSubmit()

        XCTAssertTrue(waitForStaticText(changedMessage, timeout: 25),
                      "the accepted change is not confirmed on screen — screen reads: "
                      + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        shot("cp10-changed")
        let accepted = waitForChangePasswordPosts(3, timeout: 15)
        guard accepted.count >= 3 else {
            return XCTFail("the accepted attempt never reached the server — got:\n"
                           + "\(describe(stubRequests()))")
        }
        XCTAssertEqual(accepted[2].body.password, currentPassword,
                       "the accepted body must carry the corrected current password")
        XCTAssertEqual(accepted[2].body.newPassword, newPassword)
        XCTAssertEqual(accepted[2].body.invalidateSessions, false,
                       "the wire must carry the toggle the user set, not the default it opened on")

        // MARK: Back in the hub — the reminder is gone

        let back = app.navigationBars.firstMatch.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10), "no way back from the change-password screen")
        back.tap()
        sleep(2)

        let rowAgain = hubRow("changePasswordRow")
        XCTAssertTrue(rowAgain.waitForExistence(timeout: 15),
                      "the Security section did not come back — screen reads: "
                      + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        // Looking at the very section that carried the reminder: its absence is
        // the flag falling, not a form scrolled out of the tree.
        XCTAssertTrue(waitForAbsence(reminder, timeout: 15),
                      "the reminder survived a successful change — the server no longer asks for one")
        shot("cp11-reminder-gone")

        // And the hub asked the server again on its way back, which is what makes
        // the reminder's fall the server's answer rather than an in-memory guess.
        let log = stubRequests()
        guard let acceptedIndex = log.lastIndex(where: {
            $0.method == "POST" && $0.path == "/api/auth/change-password"
        }), let lastRead = log.lastIndex(where: {
            $0.method == "GET" && $0.path == "/api/users/me"
        }) else {
            return XCTFail("no GET /api/users/me on the wire at all — got:\n\(describe(log))")
        }
        XCTAssertLessThan(acceptedIndex, lastRead,
                          "the hub kept its stale flag instead of re-reading the server's answer — got:\n"
                          + "\(describe(log))")

        print("WIRE\n" + describe(log))
    }
}
