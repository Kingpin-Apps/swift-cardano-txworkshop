import XCTest

/// A script picked from a blueprint turns its datum and redeemer into forms,
/// and a wrong field says what is wrong with it. Needs the fixture blueprint
/// (`Tests/TxWorkshopEngineTests/Fixtures/blueprint/market.plutus.json`) in
/// the app's library on the simulator: Library/Application Support/Blueprints.
final class BlueprintFormUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBlueprintForms() throws {
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

        let add = app.buttons["Add Script Input"].firstMatch
        scroll(app, toReveal: add)
        add.tap()
        let giveScript = app.switches["Give the script here"].firstMatch
        scroll(app, toReveal: giveScript)
        giveScript.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()

        let fromBlueprint = app.buttons["From Blueprint"].firstMatch
        scroll(app, toReveal: fromBlueprint)
        XCTAssertTrue(fromBlueprint.exists, "No From Blueprint menu: is the fixture in the app's library?")
        let spend = app.buttons["market.market.spend"].firstMatch
        for _ in 0..<3 where !spend.exists {
            fromBlueprint.tap()
            _ = spend.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(spend.exists, "The spend validator is not offered.")
        spend.tap()

        // The script's hash finds its validator: both fields become forms.
        let datumType = app.staticTexts["Order · market.market.spend"].firstMatch
        scroll(app, toReveal: datumType)
        XCTAssertTrue(datumType.exists, "The datum did not become the Order form.")
        save("blueprint-datum")
        let redeemerType = app.staticTexts["Action · market.market.spend"].firstMatch
        scroll(app, toReveal: redeemerType)
        if !redeemerType.exists {
            save("blueprint-redeemer-missing")
            let captions = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'market.'")).allElementsBoundByIndex.map(\.label)
            print("BLUEPRINT CAPTIONS:", captions)
        }
        XCTAssertTrue(redeemerType.exists, "The redeemer did not become the Action form.")

        // Choose Update and give it a price that is not a number.
        let action = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Buy' OR value CONTAINS 'Buy'")).firstMatch
        scroll(app, toReveal: action)
        action.tap()
        let update = app.buttons["Update"].firstMatch
        XCTAssertTrue(update.waitForExistence(timeout: 5), "Update is not offered.")
        update.tap()
        let price = app.textFields["redeemer.price"].firstMatch
        scroll(app, toReveal: price)
        XCTAssertTrue(price.exists, "Update has no price field.")
        price.tap()
        price.typeText("soon")
        XCTAssertTrue(app.staticTexts["\"soon\" is not a whole number."].firstMatch.waitForExistence(timeout: 5), "The bad price was not flagged.")
        save("blueprint-redeemer")
    }

    /// A validator that takes parameters becomes a script once they are
    /// filled in, with the hash Aiken's `blueprint apply` gives, and its
    /// redeemer still finds its type.
    @MainActor
    func testParameterisedMint() throws {
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

        let add = app.buttons["Add Mint or Burn"].firstMatch
        scroll(app, toReveal: add)
        add.tap()
        let fromBlueprint = app.buttons["From Blueprint"].firstMatch
        scroll(app, toReveal: fromBlueprint)
        XCTAssertTrue(fromBlueprint.exists, "No From Blueprint menu: is the fixture in the app's library?")
        let token = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'market.token.mint'")).firstMatch
        // A tap while the form still coasts only stops it.
        for _ in 0..<3 where !token.exists {
            fromBlueprint.tap()
            _ = token.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(token.exists, "The minting validator is not offered.")
        token.tap()

        let owner = app.textFields["parameters.owner"].firstMatch
        scroll(app, toReveal: owner)
        XCTAssertTrue(owner.exists, "No owner parameter.")
        owner.tap()
        owner.typeText("00112233445566778899aabbccddeeff00112233445566778899aabb\n")
        let nonce = app.textFields["parameters.nonce"].firstMatch
        scroll(app, toReveal: nonce)
        nonce.tap()
        nonce.typeText("7\n")

        let hash = app.staticTexts["ae8fd9afa7d726fb95e2415342a67aa4a6194c4736643fbb6cfcdca5"].firstMatch
        scroll(app, toReveal: hash)
        XCTAssertTrue(hash.exists, "The applied script hash is not Aiken's.")
        save("blueprint-parameters")
        let redeemer = app.staticTexts["List<Int> · market.token.mint"].firstMatch
        scroll(app, toReveal: redeemer)
        XCTAssertTrue(redeemer.exists, "The applied script's redeemer did not find its type.")
    }

    /// An inspected inline datum reads as its blueprint type. Needs the
    /// "Blueprint Order" document (an output to the market script holding an
    /// Order) in the app's Documents, besides the fixture blueprint.
    @MainActor
    func testInspectedDatumLabels() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-providerOnboardingShown", "YES"]
        app.launch()
        let document = app.staticTexts["Blueprint Order"].firstMatch
        for place in ["Browse", "On My iPhone", "TxWorkshop"] where !document.exists {
            let item = app.buttons[place].exists ? app.buttons[place] : app.staticTexts[place]
            if item.exists { item.tap(); sleep(1) }
        }
        XCTAssertTrue(document.waitForExistence(timeout: 10), "Blueprint Order is not in the app's Documents.")
        // The name renames; the icon above it opens.
        document.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: -60)).tap()
        let opened = app.staticTexts["In short"].waitForExistence(timeout: 20)
        if !opened { save("blueprint-open-failed") }
        XCTAssertTrue(opened, "The document never opened.")
        go(to: "Inputs & Outputs", in: app)

        let order = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Order · 10 fields'")).firstMatch
        scroll(app, toReveal: order)
        XCTAssertTrue(order.exists, "The inline datum was not read as an Order.")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'market.market.spend'")).firstMatch.exists, "The validator is not named.")
        let price = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'price' AND label CONTAINS '5000000'")).firstMatch
        scroll(app, toReveal: price)
        XCTAssertTrue(price.exists, "The price field is not named.")
        save("blueprint-inspected")
    }

    @MainActor
    private func save(_ name: String) {
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/private/tmp/claude-501/-Users-hadderley-Documents-AgenticOS/8ed2b6c3-a439-4621-baf7-08e15b8ce0dd/scratchpad/\(name).png"))
    }

    // MARK: - Navigation

    /// Creates a document from the launch screen, until `opened` shows.
    @MainActor
    private func newDocument(_ app: XCUIApplication, opened: XCUIElement) {
        for _ in 0..<3 where !opened.exists {
            let browse = app.buttons["Browse"].firstMatch
            if browse.exists { browse.tap() }
            let create = app.staticTexts["Create Document"].firstMatch
            if create.waitForExistence(timeout: 5) { create.tap() }
            _ = opened.waitForExistence(timeout: 10)
        }
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
