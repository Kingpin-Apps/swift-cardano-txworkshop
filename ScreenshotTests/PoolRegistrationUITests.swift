import XCTest

/// Build offers every certificate, and the stake pool registration form
/// opens with its import, fetch, owners and relays.
final class PoolRegistrationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPoolRegistrationForm() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-providerOnboardingShown", "YES"]
        app.launch()

        let networkMenu = app.buttons["No Network"].firstMatch
        newDocument(app, opened: networkMenu)
        XCTAssertTrue(networkMenu.exists, "The new document never opened.")
        networkMenu.tap()
        let preprod = app.buttons["Preprod"].firstMatch
        XCTAssertTrue(preprod.waitForExistence(timeout: 5))
        preprod.tap()
        go(to: "Build", in: app)

        let add = app.buttons["Add Staking or Governance"].firstMatch
        scroll(app, toReveal: add)
        add.tap()
        let certificate = app.buttons["Certificate"].firstMatch
        XCTAssertTrue(certificate.waitForExistence(timeout: 5))
        certificate.tap()

        // The kind picker, in the new certificate's section.
        let picker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Certificate'")).element(boundBy: 0)
        scroll(app, toReveal: picker)
        picker.tap()
        sleep(1)
        save("certificate-kinds")
        // The menu is long; these are near its top and middle.
        for kind in ["Register stake address (pre-Conway)", "Register and delegate stake and votes", "Retire a stake pool"] {
            XCTAssertTrue(app.buttons[kind].firstMatch.waitForExistence(timeout: 5), "\(kind) is not offered.")
        }
        app.buttons["Register or update a stake pool"].firstMatch.tap()

        let importButton = app.buttons["Import pool.json…"].firstMatch
        scroll(app, toReveal: importButton)
        XCTAssertTrue(importButton.exists, "No pool.json import.")
        XCTAssertTrue(app.buttons["Fetch Registration"].firstMatch.exists, "No fetch from chain.")
        save("pool-registration")
        let addRelay = app.buttons["Add Relay"].firstMatch
        scroll(app, toReveal: addRelay)
        addRelay.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Relay'")).firstMatch.waitForExistence(timeout: 5), "Add Relay added no relay.")
        save("pool-relay")
    }

    @MainActor
    private func save(_ name: String) {
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/private/tmp/claude-501/-Users-hadderley-Documents-AgenticOS/8ed2b6c3-a439-4621-baf7-08e15b8ce0dd/scratchpad/\(name).png"))
    }

    // MARK: - Navigation

    /// Creates a document from the launch screen, until `opened` shows.
    @MainActor
    private func newDocument(_ app: XCUIApplication, opened: XCUIElement) {
        // The launch screen can miss the first tap while it settles.
        for _ in 0..<3 where !opened.exists {
            // "Create Document" is in the Browse tab; the browser may open on Recents.
            let browse = app.buttons["Browse"].firstMatch
            if browse.exists { browse.tap() }
            let create = app.staticTexts["Create Document"].firstMatch
            if create.waitForExistence(timeout: 5) { create.tap() }
            _ = opened.waitForExistence(timeout: 10)
        }
    }

    /// Shows a section: a sidebar row on iPad and visionOS; on iPhone, back
    /// to the section list first.
    @MainActor
    private func go(to section: String, in app: XCUIApplication) {
        func row() -> XCUIElement {
            let button = app.buttons[section].firstMatch
            return button.isHittable ? button : app.staticTexts[section].firstMatch
        }
        if !row().exists, UIDevice.current.userInterfaceIdiom == .phone {
            app.navigationBars.buttons.firstMatch.tap()
        }
        XCTAssertTrue(row().waitForExistence(timeout: 5), "No \(section) in the sidebar.")
        row().tap()
    }

    /// Scrolls the form until `element` is well inside the screen, clear of
    /// the bars the form scrolls under, or gives up.
    @MainActor
    private func scroll(_ app: XCUIApplication, toReveal element: XCUIElement, upwards: Bool = false) {
        func clear() -> Bool {
            guard element.waitForExistence(timeout: 1), element.isHittable else { return false }
            let screen = app.frame.height
            return element.frame.minY > screen * 0.2 && element.frame.maxY < screen * 0.85
        }
        for _ in 0..<10 where !clear() {
            upwards ? app.swipeDown() : app.swipeUp()
            // A tap while the form still coasts only stops it.
            sleep(1)
        }
    }
}
