import XCTest

/// Build names each mistake in the recipe, and the list follows the form as
/// it changes.
final class RecipeCheckUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testProblemsAreNamedAndFollowTheForm() throws {
        let app = XCUIApplication()
        // The provider set-up is SyncToggleTests' to test; here it is
        // already done.
        app.launchArguments += ["-providerOnboardingShown", "YES"]
        app.launch()

        // Build is off until the document has a network.
        let networkMenu = app.buttons["No Network"].firstMatch
        newDocument(app, opened: networkMenu)
        XCTAssertTrue(networkMenu.exists, "The new document never opened.")
        networkMenu.tap()
        let preprod = app.buttons["Preprod"].firstMatch
        XCTAssertTrue(preprod.waitForExistence(timeout: 5))
        preprod.tap()

        go(to: "Build", in: app)
        let build = app.buttons["buildRecipe"].firstMatch
        let heading = app.staticTexts["Fix before building"].firstMatch
        let output1 = problem("Output 1 · Address", in: app)
        let output2 = problem("Output 2 · Address", in: app)
        let change = problem("Sources · Change address", in: app)

        XCTAssertFalse(heading.exists, "Problems shown before Build was pressed.")
        scroll(app, toReveal: build)
        build.tap()

        // The empty recipe: an output with no address, and nowhere for change.
        // The list is under the button, and the form loads rows as they
        // scroll into view.
        scroll(app, toReveal: change)
        XCTAssertTrue(heading.exists, "Build did not list the recipe's problems.")
        XCTAssertTrue(change.exists, "The missing change address is not named.")
        scroll(app, toReveal: output1)
        XCTAssertTrue(output1.exists, "The empty output's address is not named.")
        XCTAssertFalse(output2.exists)

        // A second, empty output joins the list without pressing Build again.
        let addOutput = app.buttons["Add Output"].firstMatch
        scroll(app, toReveal: addOutput, upwards: true)
        addOutput.tap()
        scroll(app, toReveal: output2)
        XCTAssertTrue(output2.waitForExistence(timeout: 5), "The list did not follow the new output.")
    }

    /// A row in the problem list: its place, field and message read as one.
    @MainActor
    private func problem(_ placeAndField: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", placeAndField)).firstMatch
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
