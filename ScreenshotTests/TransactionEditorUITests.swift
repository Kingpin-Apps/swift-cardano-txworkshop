import XCTest

/// A transaction opened from a file is edited in Build and built again; Build
/// starts over; a confirmed submission links to the explorer; and a signing
/// key is read from its file. Needs "Edit Me.txworkshop" and "Needs Chain
/// Data.txworkshop" (scripts/screenshot-sample), and a `payment.skey`, in the
/// app's Documents.
final class TransactionEditorUITests: XCTestCase {
    /// The sample's transaction, built from "Choose UTxOs".
    static let transactionID = "885c0cc0707fa360bc428ca8b99b1983638a9a2dee84fbcff5f99124abf8950a"
    /// The UTxO it spends.
    static let spent = "80e03970283fb74823f5c825f3b16c213e93058ef9d1f1603b782ea246c400cb#2"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testEditInBuildBuildsTheTransactionAgain() throws {
        let app = launch()
        open("Edit Me", in: app)

        tapToolbar("editInBuild", label: "Edit in Build…", in: app)
        let replace = app.buttons["Replace"].firstMatch
        if replace.waitForExistence(timeout: 3) { replace.tap() }
        // Build opens on the form read from the transaction, with what was
        // worked out again.
        let notes = app.staticTexts["Read from the transaction"].firstMatch
        XCTAssertTrue(notes.waitForExistence(timeout: 10), "Edit in Build did not open Build with the import notes.")
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'taken as the change'")).firstMatch.exists,
            "The note on the change output is missing."
        )
        let spent = app.buttons["utxoChoice-\(Self.spent)"].firstMatch
        scroll(app, toReveal: spent)
        XCTAssertTrue(spent.exists, "The input the transaction spends is not in the form.")
        XCTAssertTrue(spent.label.contains("Always Use"), "The input it spends is not kept: \(spent.label)")
        save("edit-in-build-form")

        // The new form parts are there.
        let references = app.staticTexts["Reference inputs"].firstMatch
        scroll(app, toReveal: references)
        XCTAssertTrue(references.exists, "No Reference inputs section.")

        // It builds again from the form.
        let build = app.buttons["buildRecipe"].firstMatch
        scroll(app, toReveal: build)
        build.tap()
        let built = app.staticTexts["Built"].firstMatch
        scroll(app, toReveal: built)
        XCTAssertTrue(built.waitForExistence(timeout: 20), "The imported form did not build.")
        XCTAssertFalse(app.staticTexts["Fix before building"].exists, "The imported form has problems.")
        save("edit-in-build-built")
    }

    @MainActor
    func testEditWithoutChainDataPointsToChainData() throws {
        let app = launch()
        open("Needs Chain Data", in: app)
        tapToolbar("editInBuild", label: "Edit in Build…", in: app)
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "No alert for the missing UTxOs.")
        XCTAssertTrue(
            alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", String(Self.spent.prefix(16)))).firstMatch.exists,
            "The alert does not name the missing UTxO."
        )
        save("edit-needs-chain-data")
        alert.buttons["Open Chain Data"].tap()
        XCTAssertTrue(app.navigationBars["Chain Data"].firstMatch.waitForExistence(timeout: 10), "Open Chain Data did not open Chain Data.")
    }

    @MainActor
    func testStartOverClearsTheForm() throws {
        let app = launch()
        open("Edit Me", in: app)
        tapToolbar("editInBuild", label: "Edit in Build…", in: app)
        // A form saved by an earlier edit is replaced, after asking.
        let replace = app.buttons["Replace"].firstMatch
        if replace.waitForExistence(timeout: 3) { replace.tap() }
        let notes = app.staticTexts["Read from the transaction"].firstMatch
        XCTAssertTrue(notes.waitForExistence(timeout: 10), "Edit in Build did not open Build with the import notes.")

        let reset = app.buttons["resetRecipe"].firstMatch
        scroll(app, toReveal: reset)
        XCTAssertTrue(reset.isEnabled, "Start Over is off with a form to clear.")
        reset.tap()
        let confirm = app.buttons["Start Over"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Start Over did not ask first.")
        confirm.tap()

        sleep(1)
        XCTAssertFalse(reset.isEnabled, "Start Over is still on with nothing to clear.")
        save("start-over")
        // At the top of the form: no notes, and no input left.
        for _ in 0..<20 { app.swipeDown(); usleep(300_000) }
        sleep(1)
        XCTAssertTrue(app.staticTexts["Source addresses"].firstMatch.waitForExistence(timeout: 5), "Not at the top of the form.")
        XCTAssertFalse(notes.exists, "The import notes outlived Start Over.")
        XCTAssertFalse(app.buttons["utxoChoice-\(Self.spent)"].exists, "The form still lists the input.")
    }

    @MainActor
    func testConfirmedSubmissionLinksToTheExplorer() throws {
        let app = launch()
        open("Edit Me", in: app)
        go(to: "Sign & Submit", in: app)
        let link = app.links.containing(NSPredicate(format: "label CONTAINS %@", Self.transactionID)).firstMatch
        scroll(app, toReveal: link)
        XCTAssertTrue(link.exists, "No explorer link under the confirmed transaction.")
        XCTAssertTrue(link.label.hasPrefix("https://"), "The link does not show the URL: \(link.label)")
        save("explorer-link")
    }

    @MainActor
    func testSigningKeyFile() throws {
        let app = launch()
        open("Edit Me", in: app)
        go(to: "Sign & Submit", in: app)
        let add = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Add a Signing Key'")).firstMatch
        scroll(app, toReveal: add)
        add.tap()

        let fromFile = app.buttons["signingKeyFromFile"].firstMatch
        XCTAssertFalse(fromFile.waitForExistence(timeout: 2), "Choose File… is offered for a recovery phrase.")
        // A form's picker reads as one button: its label and its value.
        let kind = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Recovery phrase' OR label BEGINSWITH 'Kind'")).firstMatch
        XCTAssertTrue(kind.waitForExistence(timeout: 5), "No Kind picker.")
        kind.tap()
        let keyFile = app.buttons["Key file (.skey)"].firstMatch
        XCTAssertTrue(keyFile.waitForExistence(timeout: 5))
        keyFile.tap()
        XCTAssertTrue(fromFile.waitForExistence(timeout: 5), "No Choose File… for a key file.")
        // The system picker it opens runs in its own process, which a UI test
        // cannot reliably drive; reading the chosen file is
        // SigningKeyFileTests'. Here the file's contents are pasted instead.

        // A key file pasted in, a fresh one each run.
        let name = app.textFields["Name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10), "The sheet did not come back.")
        focus(name)
        name.typeText("payment")
        let contents = app.textViews["Key file contents"].firstMatch
        XCTAssertTrue(contents.waitForExistence(timeout: 5), "No field for the key file.")
        focus(contents)
        let seed = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        contents.typeText(#"{"type": "PaymentSigningKeyShelley_ed25519", "description": "Payment Signing Key", "cborHex": "5820\#(seed)"}"#)
        let addButton = app.buttons["Add"].firstMatch
        XCTAssertTrue(addButton.isEnabled, "Add is off with a key file given.")
        save("signing-key-from-file")
        addButton.tap()

        // It is kept, as a key file.
        let kept = app.staticTexts["payment"].firstMatch
        scroll(app, toReveal: kept)
        XCTAssertTrue(kept.waitForExistence(timeout: 5), "The key was not added.")
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'missing from the Keychain'")).firstMatch.exists)

        // Removed again, so the next run starts without it: the row's button,
        // then the dialog's, which comes after it.
        let removeButtons = app.buttons.matching(NSPredicate(format: "label == 'Remove payment'"))
        removeButtons.firstMatch.tap()
        let confirm = removeButtons.element(boundBy: 1)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Removing did not ask first.")
        confirm.tap()
        let gone = expectation(for: NSPredicate(format: "count == 0"), evaluatedWith: removeButtons)
        wait(for: [gone], timeout: 10)
    }

    // MARK: - Helpers

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-providerOnboardingShown", "YES"]
        app.launch()
        return app
    }

    /// Opens the document `name` from the app's Documents.
    @MainActor
    private func open(_ name: String, in app: XCUIApplication) {
        let document = app.staticTexts[name].firstMatch
        // The document browser takes a while to come up after launch.
        XCTAssertTrue(app.buttons["Browse"].firstMatch.waitForExistence(timeout: 30), "The document browser never showed.")
        browse(to: document, through: ["Browse", "On My iPhone", "On My iPad", "TxWorkshop"], in: app)
        XCTAssertTrue(document.waitForExistence(timeout: 10), "\(name) is not in the app's Documents.")
        // The name renames; the icon above it opens.
        document.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: -60)).tap()
        sleep(3)
    }

    /// Taps `field` until it has the keyboard, as it may not while a sheet
    /// above it is still closing.
    @MainActor
    private func focus(_ field: XCUIElement) {
        for _ in 0..<5 where !((field.value(forKey: "hasKeyboardFocus") as? Bool) ?? false) {
            field.tap()
            sleep(1)
        }
    }

    /// Taps through the browser's places, in order, until `target` shows.
    @MainActor
    private func browse(to target: XCUIElement, through places: [String], in app: XCUIApplication) {
        for place in places where !target.waitForExistence(timeout: 2) {
            let item = app.buttons[place].exists ? app.buttons[place].firstMatch : app.staticTexts[place].firstMatch
            if item.waitForExistence(timeout: 3) { item.tap(); sleep(2) }
        }
    }

    /// Taps a toolbar button, from the overflow menu when it is there; a
    /// menu item keeps its label, not its identifier.
    @MainActor
    private func tapToolbar(_ identifier: String, label: String, in app: XCUIApplication) {
        let button = app.buttons[identifier].firstMatch
        if button.waitForExistence(timeout: 3) && button.isHittable {
            button.tap()
            return
        }
        let more = app.navigationBars.buttons["More"].exists ? app.navigationBars.buttons["More"].firstMatch : app.buttons["More"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5), "No \(identifier), nor a More menu.")
        more.tap()
        let item = app.buttons[label].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "No \(label) in the toolbar's menu.")
        item.tap()
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
        sleep(1)
    }

    @MainActor
    private func scroll(_ app: XCUIApplication, toReveal element: XCUIElement, upwards: Bool = false) {
        func clear() -> Bool {
            guard element.waitForExistence(timeout: 1), element.isHittable else { return false }
            // Below the toolbar and on screen; the foot of a form may not
            // scroll any higher.
            let screen = app.frame.height
            return element.frame.minY > screen * 0.12 && element.frame.maxY < screen * 0.97
        }
        // A second after each swipe, so the list has stopped moving.
        for _ in 0..<15 where !clear() {
            let above = element.exists && element.frame.maxY < app.frame.height * 0.12
            above || upwards ? app.swipeDown() : app.swipeUp()
            sleep(1)
        }
        for _ in 0..<30 where !clear() {
            upwards ? app.swipeUp() : app.swipeDown()
            sleep(1)
        }
    }

    @MainActor
    private func save(_ name: String) {
        let folder = ProcessInfo.processInfo.environment["UITEST_SCREENSHOTS"] ?? NSTemporaryDirectory()
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
    }
}
