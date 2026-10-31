import XCTest

extension XCUIApplication {
    /// Taps a toolbar button, from the overflow menu when it is there; a
    /// menu item keeps its label, not its identifier.
    @MainActor
    func tapToolbar(_ identifier: String, label: String) {
        let button = buttons[identifier].firstMatch
        if button.waitForExistence(timeout: 3) && button.isHittable {
            button.tap()
            return
        }
        let more = navigationBars.buttons["More"].exists ? navigationBars.buttons["More"].firstMatch : buttons["More"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5), "No \(identifier), nor a More menu.")
        more.tap()
        let item = buttons[label].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "No \(label) in the toolbar's menu.")
        item.tap()
    }
}
