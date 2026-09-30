import XCTest

/// Walks a saved transaction through the app's sections for the App Store
/// screenshots.
///
/// It opens "Minswap Batch", a `.txworkshop` document that already holds its
/// chain data, so Validate runs offline. `scripts/capture-screenshots.sh`
/// copies it into the app's Documents first. On visionOS the test cannot take
/// its own screenshots, so each `snapshot` asks the script to take one; see
/// `SnapshotHelper.swift`.
final class ScreenshotTests: XCTestCase {
    static let document = "Minswap Batch"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureScreenshots() throws {
        let app = XCUIApplication()
        setupSnapshot(app)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_OUTPUT_DIR"] {
            app.launchEnvironment["SCREENSHOT_OUTPUT_DIR"] = dir
        }
        app.launch()

        try openDocument(app)
        XCTAssertTrue(app.staticTexts["In short"].waitForExistence(timeout: 20), "The document never opened.")
        settle()
        snapshot("01_Overview")

        go(to: "Inputs & Outputs", in: app)
        settle()
        snapshot("02_InputsOutputs")

        go(to: "Validate", in: app)
        let run = app.buttons["runValidation"]
        XCTAssertTrue(run.waitForExistence(timeout: 10))
        run.tap()
        let verdict = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Valid'")).firstMatch
        XCTAssertTrue(verdict.waitForExistence(timeout: 60), "Validation never finished.")
        // Bring the verdict and the script budgets into view.
        scrollUp(from: app.staticTexts["Judge it"])
        settle()
        snapshot("03_Validate")

        // The reward script's trace: the last one listed, and the costliest.
        scrollUp(from: verdict.exists ? verdict : app.staticTexts["Judge it"])
        let traces = app.buttons.matching(NSPredicate(format: "label == 'Trace Timeline'"))
        if traces.count > 0 {
            traces.element(boundBy: traces.count - 1).tap()
            let succeeded = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Succeeded'")).firstMatch
            if succeeded.waitForExistence(timeout: 30) {
                settle()
                snapshot("04_Trace")
            }
            let done = app.buttons["Done"]
            if done.exists { done.tap() }
        }

        go(to: "CBOR", in: app)
        let body = app.staticTexts["transaction body"]
        if body.waitForExistence(timeout: 10) {
            body.tap()
            let fee = app.staticTexts["fee"]
            if fee.waitForExistence(timeout: 5) { fee.tap() }
        }
        settle()
        snapshot("05_CBOR")
    }

    // MARK: - Navigation

    /// Opens the sample document from the launch screen's browser, looking in
    /// Recents first and then the app's own folder.
    @MainActor
    private func openDocument(_ app: XCUIApplication) throws {
        let document = app.staticTexts[Self.document]
        if document.waitForExistence(timeout: 10) {
            document.tap()
            return
        }
        for place in ["Browse", "On My Apple Vision Pro", "On My iPhone", "On My iPad", "TxWorkshop"] {
            let item = app.buttons[place].exists ? app.buttons[place] : app.staticTexts[place]
            if item.exists { item.tap(); settle(1) }
            if document.exists { break }
        }
        XCTAssertTrue(document.waitForExistence(timeout: 10), "\(Self.document) is not in the app's Documents.")
        document.tap()
    }

    /// Shows a section: a sidebar row on iPad and visionOS; on iPhone, back
    /// to the section list first.
    @MainActor
    private func go(to section: String, in app: XCUIApplication) {
        func row() -> XCUIElement {
            let button = app.buttons[section].firstMatch
            return button.exists ? button : app.staticTexts[section].firstMatch
        }
        if !row().exists, UIDevice.current.userInterfaceIdiom == .phone {
            app.navigationBars.buttons.firstMatch.tap()
            settle(1)
        }
        XCTAssertTrue(row().waitForExistence(timeout: 5), "No \(section) in the sidebar.")
        row().tap()
    }

    /// Scrolls by dragging up from `element`. visionOS rejects app-wide swipes
    /// ("invalid scene ID"), but a drag from a coordinate works everywhere.
    @MainActor
    private func scrollUp(from element: XCUIElement) {
        guard element.exists else { return }
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -350)))
    }

    /// Lets content and animations settle before a capture.
    private func settle(_ seconds: UInt32 = 2) { sleep(seconds) }
}
