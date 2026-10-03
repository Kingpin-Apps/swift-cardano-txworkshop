import XCTest

/// The iCloud sync switch in the provider set-up starts off, and turns on and off.
final class SyncToggleTests: XCTestCase {
    @MainActor
    func testSyncSwitch() throws {
        let app = XCUIApplication()
        app.launch()
        // The launch screen can miss the first tap while it settles.
        let new = app.buttons["New Transaction"].firstMatch
        let sync = app.switches["syncWithICloud"].firstMatch
        for _ in 0..<3 where !sync.exists {
            // "Create Document" is in the Browse tab; the browser may open on Recents.
            let browse = app.buttons["Browse"].firstMatch
            if browse.exists { browse.tap() }
            let create = app.staticTexts["Create Document"].firstMatch
            if create.waitForExistence(timeout: 5) { create.tap() } else if new.exists { new.tap() }
            _ = sync.waitForExistence(timeout: 10)
        }
        XCTAssertTrue(sync.exists, "No sync switch in the set-up.")
        XCTAssertEqual(sync.value as? String, "0", "Sync should be off until turned on.")
        sync.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(sync.value as? String, "1", "The switch did not turn on.")
        sync.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(sync.value as? String, "0", "The switch did not turn back off.")
    }
}
