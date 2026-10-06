import XCTest

/// Build spends what coin selection picks, until a UTxO is marked Don't Use,
/// when it builds again without it. Needs "Choose UTxOs.txworkshop"
/// (scripts/screenshot-sample) in the app's Documents.
final class UTxOChoiceUITests: XCTestCase {
    static let smaller = "80e03970283fb74823f5c825f3b16c213e93058ef9d1f1603b782ea246c400cb#1"
    static let larger = "80e03970283fb74823f5c825f3b16c213e93058ef9d1f1603b782ea246c400cb#2"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testDontUseBuildsAgainWithoutIt() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-providerOnboardingShown", "YES"]
        app.launch()
        let document = app.staticTexts["Choose UTxOs"].firstMatch
        for place in ["Browse", "On My iPhone", "On My iPad", "TxWorkshop"] where !document.exists {
            let item = app.buttons[place].exists ? app.buttons[place] : app.staticTexts[place]
            if item.exists { item.tap(); sleep(1) }
        }
        XCTAssertTrue(document.waitForExistence(timeout: 10), "Choose UTxOs is not in the app's Documents.")
        // The name renames; the icon above it opens.
        document.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: -60)).tap()
        sleep(3)
        go(to: "Build", in: app)

        // Build sits at the foot of a long form.
        let build = app.buttons["buildRecipe"].firstMatch
        for _ in 0..<40 where !(build.exists && build.isHittable) { app.swipeUp() }
        XCTAssertTrue(build.isHittable, "No Build button.")
        build.tap()
        // Largest first takes the larger UTxO.
        let larger = app.buttons["utxoChoice-\(Self.larger)"].firstMatch
        for _ in 0..<40 where !(larger.exists && larger.isHittable) { app.swipeDown() }
        XCTAssertTrue(spent(Self.larger, in: app).waitForExistence(timeout: 20), "The first build did not spend the larger UTxO.")
        save("utxo-choice-before")

        larger.tap()
        let dontUse = app.buttons["Don't Use"].firstMatch
        XCTAssertTrue(dontUse.waitForExistence(timeout: 5), "No choices for the UTxO.")
        dontUse.tap()

        // It builds again at once, with the smaller one.
        XCTAssertTrue(spent(Self.smaller, in: app).waitForExistence(timeout: 20), "Did not build again with the other UTxO.")
        XCTAssertFalse(spent(Self.larger, in: app).exists, "Still spends the UTxO marked Don't Use.")
        save("utxo-choice-after")
    }

    /// The row for `id`, when it says the last build spent it.
    @MainActor
    private func spent(_ id: String, in app: XCUIApplication) -> XCUIElement {
        // The row reads as one button, its label holding all it says.
        app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS 'Spent by the last build'", "utxoChoice-\(id)")).firstMatch
    }

    @MainActor
    private func save(_ name: String) {
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/private/tmp/claude-501/-Users-hadderley-Documents-AgenticOS/8ed2b6c3-a439-4621-baf7-08e15b8ce0dd/scratchpad/\(name).png"))
    }

    // MARK: - Navigation

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

    @MainActor
    private func scroll(_ app: XCUIApplication, toReveal element: XCUIElement, upwards: Bool = false) {
        func clear() -> Bool {
            guard element.waitForExistence(timeout: 1), element.isHittable else { return false }
            let screen = app.frame.height
            return element.frame.minY > screen * 0.2 && element.frame.maxY < screen * 0.85
        }
        // Toward the element when it is laid out but off screen; else on, then
        // back: a list lays out only the rows near the screen.
        for _ in 0..<15 where !clear() {
            let above = element.exists && element.frame.maxY < app.frame.height * 0.2
            above || upwards ? app.swipeDown() : app.swipeUp()
            sleep(1)
        }
        for _ in 0..<30 where !clear() {
            upwards ? app.swipeUp() : app.swipeDown()
            sleep(1)
        }
    }
}
