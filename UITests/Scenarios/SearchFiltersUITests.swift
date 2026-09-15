import XCTest

/// End-to-end scenario for the Search tab's Filters sheet (gap G14) from
/// `.omp/search-filters/search-filters.AC.md` — and the one scenario of the
/// wave whose stub owns the SERVER GENERATION, because the shape of the request
/// is a function of it.
///
/// The sheet sets constraints (`city`, `rating`); `POST /api/search/metadata`
/// can be written in two languages, and which one is legal depends on the
/// server: the v3.2.0 generation takes `filter`/`orderBy`/`cursor`, everything
/// older takes the deprecated flat fields (`city`, `rating`, `page`). They are
/// **mutually exclusive** — one body carries one of the two groups, never a mix
/// (the server's `withShapeExclusivity` answers 400 on the mix, and the stub
/// here enforces the same rule).
///
/// So the scenario runs the SAME filter twice against two generations of the
/// same stub (`/__version`):
///
///   1. server 3.2.0 → the body carries `filter` (`city.eq`, `rating.eq`), the
///      second page carries `cursor` — and no flat field, `page` included;
///   2. server 1.120.0 → the same filter leaves as flat `city` + `rating` with
///      `page`, and no `filter`/`orderBy`/`cursor`.
///
/// Both passes also prove the SCREEN said the same thing as the wire: the chips
/// bar and the grid on one side, and — the generation made visible — the
/// detected-text section, which is offered on 3.2.0 and dead on 1.120.0.
///
/// Run it with the launcher, never by hand (it owns the slot's simulator,
/// DerivedData and stub port, and refuses a scenario that skipped itself):
///
///     .omp/orchestration/uitest.sh <worktree> /tmp/search-filters.uitest.log \
///         UITests/stubs/immich_stub_search_filters.py SearchFiltersUITests/test_searchFilters --erase
///
/// `--erase` is not decoration: the second pass relaunches the app to get a
/// fresh `SearchViewModel` (the version probe is cached per session — that is
/// the point of the probe), and a device a neighbouring scenario left an app
/// lock or a persisted filter on would poison both passes.
final class SearchFiltersUITests: XCTestCase {

    /// The stub's URL, as `uitest.sh` hands it over (it forwards
    /// `TEST_RUNNER_IMMICH_STUB_URL`). The fallback is the port a by-hand run
    /// starts under.
    private let stub = ProcessInfo.processInfo.environment["IMMICH_STUB_URL"] ?? "http://127.0.0.1:8421"
    private var app: XCUIApplication!

    /// What the sheet is asked for, and what both bodies must therefore say.
    /// ASCII on purpose: the value is typed on a simulator keyboard.
    private let city = "Zurich"
    private let rating = 3

    /// The opaque token the stub hands out on page 1 of a structured search;
    /// page 2 must send it back verbatim.
    private let cursor = "stub-cursor-0001"

    /// The flat fields of `MetadataSearchDto` this scenario refuses to see next
    /// to `filter`/`orderBy`/`cursor` — the deprecated group the server rejects
    /// in that company. `query`, `size` and `withExif` are absent from the list:
    /// both shapes send those legitimately.
    private let deprecatedFlatFields = [
        "page", "rating", "ocr", "city", "state", "country", "make", "model",
        "lensModel", "type", "isFavorite", "takenAfter", "takenBefore", "order",
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
    // they are `private` there, and those files are frozen (their scenarios are
    // green against their current text). Extracting them into a shared support
    // file would be a second convention next to the existing one — the harness
    // rule is one file per feature, helpers included.

    private func shot(_ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: "/tmp/shot-\(name).png"))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("SHOT /tmp/shot-\(name).png")
    }

    /// One GET against the stub, with a bounded wait: nil means it never
    /// answered (and the caller fails with the reason it asked).
    private func stubGET(_ path: String, timeout: TimeInterval = 10) -> String? {
        guard let url = URL(string: "\(stub)\(path)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        let done = DispatchSemaphore(value: 0)
        var body: String?
        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data { body = String(decoding: data, as: UTF8.self) }
            done.signal()
        }.resume()
        guard done.wait(timeout: .now() + timeout + 1) == .success else { return nil }
        return body
    }

    /// Puts the stub back to its initial state — server generation included, and
    /// the request log emptied — so no assertion below can be satisfied by a
    /// previous run.
    private func reset() {
        let body = stubGET("/__reset")
        XCTAssertEqual(body?.contains("\"reset\"") ?? false, true,
                       "the stub did not answer /__reset (got \(body ?? "nothing"))")
    }

    /// The generation the stub answers on `/api/server/version` — the knob the
    /// whole scenario turns. It is sent back by the app's own probe, so the
    /// answer is read here too, never assumed.
    private func setServerVersion(major: Int, minor: Int) {
        let expected = "{\"version\": \"\(major).\(minor).0\"}"
        XCTAssertEqual(stubGET("/__version?major=\(major)&minor=\(minor)"), expected,
                       "the stub did not take the server generation \(major).\(minor)")
    }

    /// `manual` = the provider page waits for a click; `auto` = it redirects
    /// itself. This scenario clicks, like `test_01` of the shared class.
    private func setProvider(_ mode: String) {
        let body = stubGET("/__provider?mode=\(mode)")
        XCTAssertEqual(body, "{\"provider\": \"\(mode)\"}", "Stub did not answer /__provider")
    }

    /// Waits for any button whose label contains `text` and taps it. Case
    /// sensitive on purpose: the keyboard's return key is labelled "continuer"
    /// in lowercase and would shadow the "Continuer" CTA.
    @discardableResult
    private func tapButton(containing text: String, timeout: TimeInterval = 20) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let direct = app.buttons.matching(predicate).firstMatch
        let contained = app.buttons.containing(predicate).firstMatch
        for candidate in [direct, contained] where candidate.waitForExistence(timeout: timeout) {
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

    /// The two screens a launch can open on. Named rather than boolean so the
    /// caller reads which one it got, and so a third state ("neither", i.e. a
    /// launch that never got anywhere) cannot be mistaken for a pass.
    private enum Launch: Equatable { case welcome, shell, neither }

    private func welcomeOrShell() -> Launch {
        let shell = app.tabBars.buttons.matching(labelPredicate(["Photos", "Fotos"])).firstMatch
        if shell.exists { return .shell }
        if app.staticTexts.matching(labelPredicate(["Your photo library", "Votre photothèque"])).firstMatch.exists {
            return .welcome
        }
        return .neither
    }

    /// Polls until `probe` stops saying `neither`, or the budget runs out.
    private func waitForEither(timeout: TimeInterval, _ probe: () -> Launch) -> Launch {
        let deadline = Date().addingTimeInterval(timeout)
        var state = probe()
        while state == .neither && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.5)
            state = probe()
        }
        return state
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
            shot("s90b-not-on-login-screen")
            XCTFail("Login screen did not appear — screen reads: "
                    + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        }
    }

    /// Launch → the authenticated shell, whatever state the device is in.
    ///
    /// The FIRST pass walks the OAuth handshake (a fresh device after
    /// `--erase`). The SECOND pass relaunches over a session the Keychain kept,
    /// and the app opens on the shell directly — the two paths are the same
    /// screen afterwards, which is all this scenario needs.
    private func reachAuthenticatedShell() {
        app.launch()
        // Whichever comes first: a device without a session shows the welcome,
        // a relaunch over the Keychain's session opens on the shell directly.
        // Waiting for the welcome alone would burn its whole budget on pass 2.
        if waitForEither(timeout: 30, welcomeOrShell) == .welcome {
            shot("s01-welcome")
            walkOnboardingToLogin()
            shot("s02-login-sso")
            XCTAssertTrue(tapButton(containing: "Immich SSO"), "SSO button missing on login screen")
            dismissSystemSignInAlertIfPresent()
            XCTAssertTrue(tapAuthorizeInProvider(), "Authorize link not reachable in the auth sheet")
        }
        XCTAssertTrue(app.tabBars.buttons.matching(labelPredicate(["Photos", "Fotos"]))
            .firstMatch.waitForExistence(timeout: 30),
                      "the authenticated shell never appeared — screen reads: "
                      + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")

        // The app must be talking to THIS stub. A session persisted against
        // another slot's port restores the shell just as happily, and every
        // screen then looks right while nothing reaches the server that owns
        // the version under test — the socle paid for that trap once already
        // ("a scenario served by the WRONG stub is a false green").
        XCTAssertFalse(stubRequests().isEmpty,
                       "the app has sent \(stub) nothing — a session restored from another slot's port?")

        // A fresh install presents "What's New" (gap G23) over the shell, and a
        // modal swallows every tap: the Search tab would never be reachable
        // under it. Its Done button carries an identifier because its label is
        // translated.
        let whatsNewDone = app.buttons.matching(identifier: "whatsNewDoneButton").firstMatch
        if whatsNewDone.waitForExistence(timeout: 10) {
            shot("s03-whats-new")
            whatsNewDone.tap()
        }
    }

    /// Switches to the Search tab — `Tab("Search", role: .search)` of the root
    /// `TabView`. Matched by label, in the languages a slot can actually be in
    /// ("Rechercher" after `--erase`, which adopts the host language; "Search"
    /// on a slot that kept English), and by prefix so the exact French wording
    /// ("Recherche"/"Rechercher") cannot break the walk.
    private func openSearchTab() {
        let tab = app.tabBars.buttons.matching(labelPredicate(["Search", "Recherch", "Suche"])).firstMatch
        if !tab.waitForExistence(timeout: 30) {
            XCTFail("no Search tab — tab bar reads: "
                    + "\(app.tabBars.buttons.allElementsBoundByIndex.map(\.label))")
        }
        tab.tap()
    }

    /// Opens the Filters sheet and returns its city field, which is the first
    /// control this scenario needs. The sheet is raised by the toolbar button
    /// the feature added (`searchFilterButton`), never by a menu item.
    @discardableResult
    private func openFiltersSheet(_ label: String) -> XCUIElement {
        let button = app.buttons.matching(identifier: "searchFilterButton").firstMatch
        if !button.waitForExistence(timeout: 20) {
            shot("\(label)b-no-filters-button")
            XCTFail("the Filters button is not in the Search toolbar — bar reads: "
                    + "\(app.navigationBars.firstMatch.buttons.allElementsBoundByIndex.map { $0.identifier + "/" + $0.label })")
        }
        button.tap()

        // The sheet's own name rides the app bar of its `NavigationStack`
        // (`searchFilterSheet`), and the `Form` publishes its controls once it
        // has drawn them.
        let sheet = app.descendants(matching: .any).matching(identifier: "searchFilterSheet").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 20),
                      "the Filters sheet never opened — screen reads: "
                      + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        return sheetElement("searchFilterCity", label: label)
    }

    /// A control of the Filters sheet, scrolled into view if the `Form` has not
    /// rendered it yet (a `Form` only publishes what it drew).
    private func sheetElement(_ identifier: String, label: String,
                             kind: XCUIElement.ElementType = .textField, timeout: TimeInterval = 10) -> XCUIElement {
        let element = app.descendants(matching: kind).matching(identifier: identifier).firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while !element.exists && Date() < deadline {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.5)
        }
        if !element.exists {
            shot("\(label)b-no-\(identifier)")
            XCTFail("`\(identifier)` is not in the Filters sheet — sheet reads: "
                    + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        }
        return element
    }

    /// The user's gesture: type the city, rate three stars, confirm. `Done` is
    /// what dispatches the search (`SearchFilterSheet` → `vm.applyFilters()`),
    /// so nothing else has to be tapped after it.
    private func setCityAndRatingInSheet(_ label: String) {
        let cityField = openFiltersSheet(label)
        cityField.tap()
        cityField.typeText(city)

        let star = app.buttons.matching(identifier: "searchFilterStar\(rating)").firstMatch
        XCTAssertTrue(star.waitForExistence(timeout: 10), "the \(rating)-star control of the sheet is missing")
        star.tap()
    }

    /// The detected-text section of the sheet: offered when the server has a
    /// field for the criterion, dead when it has not. This is the generation
    /// made visible on the screen, and it is read as a capability
    /// (`isEnabled`), never as a localized footer.
    private func ocrField(_ label: String) -> XCUIElement {
        sheetElement("searchFilterOCR", label: label, kind: .textField)
    }

    private func tapDoneInSheet() {
        let done = app.buttons.matching(identifier: "searchFilterDone").firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10), "the sheet's Done button is missing")
        done.tap()
    }

    // MARK: - Wire helpers

    /// One entry of the stub's request log. `body` is kept as raw JSON on
    /// purpose: the whole scenario is about WHICH KEYS a body carries, and a
    /// typed DTO would silently drop the very key an assertion is about.
    private struct StubRequest {
        let method: String
        let path: String
        let params: [String: String]
        let body: [String: Any]

        var hasCursor: Bool { body["cursor"] != nil }
        var bodyJSON: String {
            let data = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
            return String(decoding: data, as: UTF8.self)
        }
        func object(_ key: String) -> [String: Any]? { body[key] as? [String: Any] }
        func string(_ key: String) -> String? { body[key] as? String }
        func number(_ key: String) -> Double? { (body[key] as? NSNumber)?.doubleValue }
        /// The value of `filter.<field>.eq`, as a string.
        func eqString(_ field: String) -> String? { (object("filter")?[field] as? [String: Any])?["eq"] as? String }
        /// The value of `filter.<field>.eq`, as a number.
        func eqNumber(_ field: String) -> Double? {
            ((object("filter")?[field] as? [String: Any])?["eq"] as? NSNumber)?.doubleValue
        }
    }

    private func stubRequests() -> [StubRequest] {
        guard let raw = stubGET("/__requests") else {
            XCTFail("stub did not answer /__requests")
            return []
        }
        guard let entries = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]] else {
            XCTFail("the stub's request log is not JSON — got: \(raw.prefix(400))")
            return []
        }
        return entries.map { entry in
            StubRequest(method: entry["method"] as? String ?? "",
                        path: entry["path"] as? String ?? "",
                        params: (entry["params"] as? [String: String]) ?? [:],
                        body: (entry["body"] as? [String: Any]) ?? [:])
        }
    }

    /// Every `POST /api/search/metadata` the app sent, in order — the one route
    /// the whole feature hangs on.
    private func metadataRequests() -> [StubRequest] {
        stubRequests().filter { $0.method == "POST" && $0.path == "/api/search/metadata" }
    }

    private func describe(_ requests: [StubRequest]) -> String {
        requests.isEmpty ? "(none)" : requests.map { "\($0.method) \($0.path) body=\($0.bodyJSON)" }
            .joined(separator: "\n")
    }

    /// Polls the stub's log until `condition` holds, never sleeping past the
    /// budget: what is awaited here is a server round-trip, not a fixed delay.
    private func waitForMetadata(timeout: TimeInterval = 40,
                                 _ condition: ([StubRequest]) -> Bool) -> [StubRequest] {
        let deadline = Date().addingTimeInterval(timeout)
        var requests = metadataRequests()
        while !condition(requests) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.5)
            requests = metadataRequests()
        }
        return requests
    }

    /// Waits for the page-2 request of the structured pass. The grid fires it
    /// from the LAST cell's `onAppear` (`SearchView.resultsGrid`), so the wait
    /// also nudges the grid once: on a narrower viewport that cell is below the
    /// fold, and a scroll is what a user does to reach the next page.
    private func waitForCursorRequest(timeout: TimeInterval = 30) -> [StubRequest] {
        let start = Date()
        var requests = metadataRequests()
        var nudged = false
        while !requests.contains(where: \.hasCursor) && Date() < start.addingTimeInterval(timeout) {
            Thread.sleep(forTimeInterval: 0.5)
            if !nudged && Date() > start.addingTimeInterval(8) {
                app.swipeUp()
                nudged = true
            }
            requests = metadataRequests()
        }
        return requests
    }

    /// The exclusivity rule, asserted on one body: the two languages never mix.
    private func assertNoDeprecatedFlatField(_ request: StubRequest, _ pass: String) {
        for field in deprecatedFlatFields {
            XCTAssertFalse(request.body.keys.contains(field),
                           "\(pass): a structured body must not carry the deprecated flat field `\(field)` — "
                           + "the server answers 400 to that mix. Body: \(request.bodyJSON)")
        }
    }

    // MARK: - Scenario

    func test_searchFilters() throws {
        reset()
        setProvider("manual")

        // MARK: Pass 1 — a v3.2.0 server speaks the structured body

        setServerVersion(major: 3, minor: 2)
        reachAuthenticatedShell()
        openSearchTab()
        shot("s04-search-tab")

        setCityAndRatingInSheet("s04")
        // The generation is visible on the screen before it is on the wire: a
        // 3.2.0 server has a field for a detected-text criterion, so the sheet
        // offers it.
        XCTAssertTrue(ocrField("s04").isEnabled,
                      "a v3.2.0 server has a field for the OCR criterion — the sheet must offer it")
        shot("s05-sheet-320")
        tapDoneInSheet()

        var requests = waitForMetadata { !$0.isEmpty }
        guard let structured = requests.first else {
            return XCTFail("the sheet's Done never dispatched a metadata search — log:\n\(describe(stubRequests()))")
        }
        XCTAssertEqual(structured.string("query"), "",
                       "the query field travels unchanged — body: \(structured.bodyJSON)")
        XCTAssertNotNil(structured.object("filter"),
                        "on a v3.2.0 server the constraints must travel as `filter` — body: \(structured.bodyJSON)")
        XCTAssertEqual(structured.eqString("city"), city,
                       "the city constraint must reach `filter.city.eq` — body: \(structured.bodyJSON)")
        XCTAssertEqual(structured.eqNumber("rating"), Double(rating),
                       "the rating constraint must reach `filter.rating.eq` — body: \(structured.bodyJSON)")
        XCTAssertFalse(structured.body.keys.contains("cursor"),
                       "page 1 cannot carry a cursor: no response has handed one out yet — body: \(structured.bodyJSON)")
        assertNoDeprecatedFlatField(structured, "structured pass")

        // MARK: On the wire — page 2 paginates with the cursor, never a page

        requests = waitForCursorRequest()
        guard let second = requests.first(where: \.hasCursor) else {
            return XCTFail("the structured search never paginated with a cursor — log:\n\(describe(requests))")
        }
        XCTAssertEqual(second.string("cursor"), cursor,
                       "the cursor of the previous response must travel back verbatim — body: \(second.bodyJSON)")
        XCTAssertNotNil(second.object("filter"),
                        "the cursor request carries the same filter — body: \(second.bodyJSON)")
        assertNoDeprecatedFlatField(second, "structured pass, page 2")

        // MARK: On the screen — the constraints and their results

        XCTAssertTrue(app.staticTexts.matching(identifier: "searchActiveFiltersBar").firstMatch
            .waitForExistence(timeout: 20),
                      "the active-filters bar must be on the screen the constraints produced — screen reads: "
                      + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        XCTAssertTrue(app.buttons.matching(identifier: "searchFilterChip_city").firstMatch.exists,
                      "the city constraint must have its own chip")
        XCTAssertTrue(app.buttons.matching(identifier: "searchFilterChip_rating").firstMatch.exists,
                      "the rating constraint must have its own chip")
        XCTAssertTrue(tile(TIMELINE_FIRST_ASSET).waitForExistence(timeout: 20),
                      "the filtered grid never rendered the stub's assets — screen reads: "
                      + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        shot("s06-results-320")

        // MARK: Pass 2 — a pre-3.2.0 server speaks the flat body

        // The version is probed once per session and cached (that is what makes
        // it a probe); a second generation therefore needs a second session, and
        // a relaunch is one — the Keychain keeps the login, so the walk is not
        // repeated.
        setServerVersion(major: 1, minor: 120)
        app.terminate()
        reachAuthenticatedShell()
        openSearchTab()

        setCityAndRatingInSheet("s07")
        // The same screen, one generation older: no server field for the OCR
        // criterion, so the sheet says so instead of offering a control that
        // could only be sent in a body the server rejects.
        XCTAssertFalse(ocrField("s07").isEnabled,
                       "a pre-v3.2.0 server has no field for the OCR criterion — the sheet must not offer it")
        shot("s08-sheet-1120")
        // The baseline is read BEFORE the dispatch: reading it after `Done`
        // would race the very request it is meant to exclude, and the pass
        // would fail on an empty diff while the wire was perfectly right.
        let before = metadataRequests().count
        tapDoneInSheet()

        requests = waitForMetadata { $0.count > before }
        let flatOnes = Array(requests.dropFirst(before))
        guard let flat = flatOnes.first else {
            return XCTFail("the second pass dispatched no metadata search — log:\n\(describe(requests))")
        }
        XCTAssertEqual(flat.string("city"), city,
                       "on a pre-v3.2.0 server the city travels as the flat field — body: \(flat.bodyJSON)")
        XCTAssertEqual(flat.number("rating"), Double(rating),
                       "on a pre-v3.2.0 server the rating travels as the flat field — body: \(flat.bodyJSON)")
        XCTAssertEqual(flat.number("page"), 1,
                       "the flat route paginates with `page` — body: \(flat.bodyJSON)")
        for field in ["filter", "orderBy", "cursor"] {
            XCTAssertFalse(flat.body.keys.contains(field),
                           "the flat body must not carry `\(field)`: one body speaks one language, and the "
                           + "server answers 400 to the mix — body: \(flat.bodyJSON)")
        }
        // And the whole pass stayed flat: a single structured request among them
        // would mean the app changed language behind the same filter.
        for request in flatOnes {
            for field in ["filter", "orderBy", "cursor"] {
                XCTAssertFalse(request.body.keys.contains(field),
                               "every request of the pre-v3.2.0 pass must be flat — got: \(describe(flatOnes))")
            }
        }

        XCTAssertTrue(app.staticTexts.matching(identifier: "searchActiveFiltersBar").firstMatch
            .waitForExistence(timeout: 20),
                      "the active-filters bar must be on the flat pass' screen too — screen reads: "
                      + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        XCTAssertTrue(tile(TIMELINE_FIRST_ASSET).waitForExistence(timeout: 20),
                      "the flat pass' grid never rendered — screen reads: "
                      + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
        shot("s09-results-1120")
    }

    /// One timeline tile, by the identity the grid gives it. The stub's own day
    /// is what both filtered searches return — the fixtures are the same six
    /// photos, so a grid that renders is a stub the app really reached.
    private let TIMELINE_FIRST_ASSET = "aaaaaaaa-1111-4111-8111-000000000001"

    private func tile(_ assetId: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "assetTile_\(assetId)").firstMatch
    }
}
