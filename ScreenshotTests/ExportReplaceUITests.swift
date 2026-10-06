import XCTest

/// Overview's Export & Share menu offers the text envelope and the reports,
/// and Replace Transaction offers paste, a file, or a fetch. Needs "Export
/// Sample.txworkshop" (a copy of scripts/screenshot-sample's Minswap Batch) in
/// the app's Documents.
final class ExportReplaceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testExportMenuAndReplaceSheet() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-providerOnboardingShown", "YES"]
        app.launch()
        let document = app.staticTexts["Export Sample"].firstMatch
        for place in ["Browse", "On My iPhone", "On My iPad", "TxWorkshop"] where !document.exists {
            let item = app.buttons[place].exists ? app.buttons[place] : app.staticTexts[place]
            if item.exists { item.tap(); sleep(1) }
        }
        XCTAssertTrue(document.waitForExistence(timeout: 10), "Export Sample is not in the app's Documents.")
        // The name renames; the icon above it opens.
        document.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: -60)).tap()
        XCTAssertTrue(app.staticTexts["In short"].waitForExistence(timeout: 20), "The document never opened.")

        let menu = app.buttons["exportShare"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "No Export & Share menu.")
        menu.tap()
        for item in ["Share Transaction…", "Text Envelope (.tx)", "JSON Report", "Markdown Report", "PDF Report"] {
            XCTAssertTrue(app.buttons[item].firstMatch.waitForExistence(timeout: 5), "No \(item) in the menu.")
        }
        save("export-share-menu")

        // Text Envelope opens the save panel.
        app.buttons["Text Envelope (.tx)"].firstMatch.tap()
        let saveButton = app.buttons["Save"].firstMatch.exists ? app.buttons["Save"].firstMatch : app.buttons["Move"].firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 10) || app.navigationBars.firstMatch.waitForExistence(timeout: 2), "No save panel.")
        save("export-envelope-panel")
        // iOS 27's save panel closes with a swipe; older ones have Cancel.
        if app.buttons["Cancel"].firstMatch.exists {
            app.buttons["Cancel"].firstMatch.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        }
        sleep(2)

        let replace = app.buttons["replaceTransaction"].firstMatch
        XCTAssertTrue(replace.waitForExistence(timeout: 10), "No Replace Transaction button.")
        replace.tap()
        XCTAssertTrue(app.staticTexts["Replace Transaction"].firstMatch.waitForExistence(timeout: 10), "The sheet never opened.")
        XCTAssertTrue(app.buttons["Open from File…"].firstMatch.exists, "No Open from File in the sheet.")
        XCTAssertTrue(app.staticTexts["PASTE A TRANSACTION"].firstMatch.exists || app.staticTexts["Paste a transaction"].firstMatch.exists, "No paste section.")
        save("replace-transaction-sheet")
    }

    @MainActor
    private func save(_ name: String) {
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/private/tmp/claude-501/-Users-hadderley-Documents-AgenticOS/8ed2b6c3-a439-4621-baf7-08e15b8ce0dd/scratchpad/\(name).png"))
    }
}
