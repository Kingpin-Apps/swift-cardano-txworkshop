import XCTest

/// The script debugger on a real script: the Minswap batch sample's first
/// redeemer. Needs "Minswap Batch.txworkshop" (scripts/screenshot-sample) in
/// the app's Documents.
final class ScriptDebuggerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testStepping() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-providerOnboardingShown", "YES"]
        app.launch()
        let document = app.staticTexts["Minswap Batch"].firstMatch
        for place in ["Browse", "On My iPhone", "On My iPad", "TxWorkshop"] where !document.exists {
            let item = app.buttons[place].exists ? app.buttons[place] : app.staticTexts[place]
            if item.exists { item.tap(); sleep(1) }
        }
        XCTAssertTrue(document.waitForExistence(timeout: 10), "Minswap Batch is not in the app's Documents.")
        // The name renames; the icon above it opens.
        document.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: -60)).tap()
        XCTAssertTrue(app.staticTexts["In short"].waitForExistence(timeout: 20), "The document never opened.")
        go(to: "Scripts & Datums", in: app)

        let debug = app.buttons["Debug Script"].firstMatch
        XCTAssertTrue(debug.waitForExistence(timeout: 10), "No Debug Script button.")
        debug.tap()
        let step = app.staticTexts["debugStep"].firstMatch
        XCTAssertTrue(step.waitForExistence(timeout: 30), "The debugger never opened.")
        XCTAssertTrue(step.label.hasPrefix("Step 0 of"), step.label)
        save("debugger-start")

        for _ in 0..<12 { app.buttons["debugStep1"].firstMatch.tap() }
        XCTAssertTrue(waitFor(step) { $0.label.hasPrefix("Step 12 of") }, step.label)
        app.buttons["debugBack"].firstMatch.tap()
        XCTAssertTrue(waitFor(step) { $0.label.hasPrefix("Step 11 of") }, step.label)
        app.buttons["debugOver"].firstMatch.tap()
        save("debugger-stepped")

        // The variables pane, then one variable in full.
        // A narrow screen switches panes; a wide one shows them all.
        if app.buttons["Variables"].firstMatch.exists { app.buttons["Variables"].firstMatch.tap() }
        let variable = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '#1'")).firstMatch
        XCTAssertTrue(variable.waitForExistence(timeout: 10), "No variables listed.")
        save("debugger-variables")
        variable.tap()
        XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout: 10))
        save("debugger-detail")
        app.buttons["Done"].firstMatch.tap()

        // Continue runs to the end: the batch succeeds.
        if app.buttons["Term"].firstMatch.exists { app.buttons["Term"].firstMatch.tap() }
        app.buttons["debugContinue"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Finished"].firstMatch.waitForExistence(timeout: 30), "Continue did not run to the end.")
        save("debugger-finished")
    }

    /// Editing the redeemer runs the script with it, as a what-if, and Reset
    /// goes back to the transaction's.
    @MainActor
    func testEditRedeemer() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-providerOnboardingShown", "YES"]
        app.launch()
        let document = app.staticTexts["Minswap Batch"].firstMatch
        for place in ["Browse", "On My iPhone", "On My iPad", "TxWorkshop"] where !document.exists {
            let item = app.buttons[place].exists ? app.buttons[place] : app.staticTexts[place]
            if item.exists { item.tap(); sleep(1) }
        }
        XCTAssertTrue(document.waitForExistence(timeout: 10), "Minswap Batch is not in the app's Documents.")
        document.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: -60)).tap()
        XCTAssertTrue(app.staticTexts["In short"].waitForExistence(timeout: 20), "The document never opened.")
        go(to: "Scripts & Datums", in: app)
        let debug = app.buttons["Debug Script"].firstMatch
        XCTAssertTrue(debug.waitForExistence(timeout: 10))
        debug.tap()
        XCTAssertTrue(app.staticTexts["debugStep"].firstMatch.waitForExistence(timeout: 30), "The debugger never opened.")

        app.buttons["debugEditRedeemer"].firstMatch.tap()
        let field = app.textFields.firstMatch.exists ? app.textFields.firstMatch : app.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "No redeemer field.")
        // At the end of the text, so the deletes clear it.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 400) + "d88080")
        save("debugger-edit-sheet")
        app.buttons["debugRunEdited"].firstMatch.tap()

        let banner = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'edited redeemer'")).firstMatch
        if !banner.waitForExistence(timeout: 30) {
            save("debugger-edit-failed")
            print("DEBUG PROBLEM:", app.staticTexts["debugProblem"].firstMatch.exists ? app.staticTexts["debugProblem"].firstMatch.label : "none")
        }
        XCTAssertTrue(banner.exists, "No what-if banner.")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'The run fails'")).firstMatch.waitForExistence(timeout: 10), "The edited run did not fail.")
        save("debugger-edited")
        app.buttons["debugResetRedeemer"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["The run succeeds."].firstMatch.waitForExistence(timeout: 30), "Reset did not return to the transaction's redeemer.")
        XCTAssertFalse(banner.exists)
    }

    /// Validate shows whether hardware wallets can sign the transaction (CIP-21).
    @MainActor
    func testCIP21Section() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-providerOnboardingShown", "YES"]
        app.launch()
        let document = app.staticTexts["Minswap Batch"].firstMatch
        for place in ["Browse", "On My iPhone", "On My iPad", "TxWorkshop"] where !document.exists {
            let item = app.buttons[place].exists ? app.buttons[place] : app.staticTexts[place]
            if item.exists { item.tap(); sleep(1) }
        }
        XCTAssertTrue(document.waitForExistence(timeout: 10), "Minswap Batch is not in the app's Documents.")
        document.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: -60)).tap()
        XCTAssertTrue(app.staticTexts["In short"].waitForExistence(timeout: 20), "The document never opened.")
        go(to: "Validate", in: app)
        let mode = app.staticTexts["Signing mode"].firstMatch
        XCTAssertTrue(mode.waitForExistence(timeout: 10), "No CIP-21 section.")
        XCTAssertTrue(app.staticTexts["Plutus"].firstMatch.exists, "The batch should sign in Plutus mode.")
        let verdict = app.staticTexts["cip21Compatible"].firstMatch.exists || app.buttons["cip21Rebuild"].firstMatch.exists
            || app.images["xmark.octagon"].firstMatch.exists
        XCTAssertTrue(verdict || app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'hardware'")).count > 0, "No CIP-21 verdict.")
        save("cip21-section")
    }

    /// Chain Data shows the saved snapshot: the tip, the protocol version and
    /// parameters, and the inputs.
    @MainActor
    func testChainDataScreen() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-providerOnboardingShown", "YES"]
        app.launch()
        let document = app.staticTexts["Minswap Batch"].firstMatch
        for place in ["Browse", "On My iPhone", "On My iPad", "TxWorkshop"] where !document.exists {
            let item = app.buttons[place].exists ? app.buttons[place] : app.staticTexts[place]
            if item.exists { item.tap(); sleep(1) }
        }
        XCTAssertTrue(document.waitForExistence(timeout: 10), "Minswap Batch is not in the app's Documents.")
        document.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: -60)).tap()
        XCTAssertTrue(app.staticTexts["In short"].waitForExistence(timeout: 20), "The document never opened.")
        go(to: "Chain Data", in: app)
        XCTAssertTrue(app.staticTexts["Tip slot"].firstMatch.waitForExistence(timeout: 10), "No tip slot.")
        XCTAssertTrue(app.staticTexts["Protocol version"].firstMatch.exists, "No protocol version.")
        save("chain-data")
        let fee = app.staticTexts["Fee per byte"].firstMatch
        for _ in 0..<6 where !fee.isHittable { app.swipeUp(); sleep(1) }
        XCTAssertTrue(fee.exists, "No protocol parameters.")
        save("chain-data-parameters")
    }

    @MainActor
    private func waitFor(_ element: XCUIElement, _ condition: (XCUIElement) -> Bool) -> Bool {
        for _ in 0..<20 {
            if condition(element) { return true }
            usleep(250_000)
        }
        return condition(element)
    }

    @MainActor
    private func save(_ name: String) {
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/private/tmp/claude-501/-Users-hadderley-Documents-AgenticOS/8ed2b6c3-a439-4621-baf7-08e15b8ce0dd/scratchpad/\(name).png"))
    }

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
}
