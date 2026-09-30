//
//  SnapshotHelper.swift
//  Example
//
//  Created by Felix Krause on 10/8/15.
//

// -----------------------------------------------------
// IMPORTANT: When modifying this file, make sure to
//            increment the version number at the very
//            bottom of the file to notify users about
//            the new SnapshotHelper.swift
// -----------------------------------------------------

import Foundation
import XCTest
#if os(OSX)
import AppKit
#endif

@MainActor
func setupSnapshot(_ app: XCUIApplication, waitForAnimations: Bool = true) {
    Snapshot.setupSnapshot(app, waitForAnimations: waitForAnimations)
}

@MainActor
func snapshot(_ name: String, waitForLoadingIndicator: Bool) {
    if waitForLoadingIndicator {
        Snapshot.snapshot(name)
    } else {
        Snapshot.snapshot(name, timeWaitingForIdle: 0)
    }
}

/// - Parameters:
///   - name: The name of the snapshot
///   - timeout: Amount of seconds to wait until the network loading indicator disappears. Pass `0` if you don't want to wait.
@MainActor
func snapshot(_ name: String, timeWaitingForIdle timeout: TimeInterval = 20) {
    Snapshot.snapshot(name, timeWaitingForIdle: timeout)
}

enum SnapshotError: Error, CustomDebugStringConvertible {
    case cannotFindSimulatorHomeDirectory
    case cannotRunOnPhysicalDevice

    var debugDescription: String {
        switch self {
        case .cannotFindSimulatorHomeDirectory:
            return "Couldn't find simulator home location. Please, check SIMULATOR_HOST_HOME env variable."
        case .cannotRunOnPhysicalDevice:
            return "Can't use Snapshot on a physical device."
        }
    }
}

@objcMembers
@MainActor
open class Snapshot: NSObject {
    static var app: XCUIApplication?
    static var waitForAnimations = true
    static var cacheDirectory: URL?
    static var screenshotsDirectory: URL? {
        return cacheDirectory?.appendingPathComponent("screenshots", isDirectory: true)
    }
    static var deviceLanguage = ""
    static var currentLocale = ""

    open class func setupSnapshot(_ app: XCUIApplication, waitForAnimations: Bool = true) {

        Snapshot.app = app
        Snapshot.waitForAnimations = waitForAnimations

        do {
            let cacheDir = try getCacheDirectory()
            Snapshot.cacheDirectory = cacheDir
            setLanguage(app)
            setLocale(app)
            setLaunchArguments(app)
        } catch let error {
            NSLog(error.localizedDescription)
        }
    }

    class func setLanguage(_ app: XCUIApplication) {
        guard let cacheDirectory = self.cacheDirectory else {
            NSLog("CacheDirectory is not set - probably running on a physical device?")
            return
        }

        let path = cacheDirectory.appendingPathComponent("language.txt")

        do {
            let trimCharacterSet = CharacterSet.whitespacesAndNewlines
            deviceLanguage = try String(contentsOf: path, encoding: .utf8).trimmingCharacters(in: trimCharacterSet)
            app.launchArguments += ["-AppleLanguages", "(\(deviceLanguage))"]
        } catch {
            NSLog("Couldn't detect/set language...")
        }
    }

    class func setLocale(_ app: XCUIApplication) {
        guard let cacheDirectory = self.cacheDirectory else {
            NSLog("CacheDirectory is not set - probably running on a physical device?")
            return
        }

        let path = cacheDirectory.appendingPathComponent("locale.txt")

        do {
            let trimCharacterSet = CharacterSet.whitespacesAndNewlines
            currentLocale = try String(contentsOf: path, encoding: .utf8).trimmingCharacters(in: trimCharacterSet)
        } catch {
            NSLog("Couldn't detect/set locale...")
        }

        if currentLocale.isEmpty && !deviceLanguage.isEmpty {
            currentLocale = Locale(identifier: deviceLanguage).identifier
        }

        if !currentLocale.isEmpty {
            app.launchArguments += ["-AppleLocale", "\"\(currentLocale)\""]
        }
    }

    class func setLaunchArguments(_ app: XCUIApplication) {
        guard let cacheDirectory = self.cacheDirectory else {
            NSLog("CacheDirectory is not set - probably running on a physical device?")
            return
        }

        let path = cacheDirectory.appendingPathComponent("snapshot-launch_arguments.txt")
        app.launchArguments += ["-FASTLANE_SNAPSHOT", "YES", "-ui_testing"]

        do {
            let launchArguments = try String(contentsOf: path, encoding: String.Encoding.utf8)
            let regex = try NSRegularExpression(pattern: "(\\\".+?\\\"|\\S+)", options: [])
            let matches = regex.matches(in: launchArguments, options: [], range: NSRange(location: 0, length: launchArguments.count))
            let results = matches.map { result -> String in
                (launchArguments as NSString).substring(with: result.range)
            }
            app.launchArguments += results
        } catch {
            NSLog("Couldn't detect/set launch_arguments...")
        }
    }

    open class func snapshot(_ name: String, timeWaitingForIdle timeout: TimeInterval = 20) {
        if timeout > 0 {
            waitForLoadingIndicatorToDisappear(within: timeout)
        }

        NSLog("snapshot: \(name)") // more information about this, check out https://docs.fastlane.tools/actions/snapshot/#how-does-it-work

        if Snapshot.waitForAnimations {
            sleep(1) // Waiting for the animation to be finished (kind of)
        }

        #if os(OSX)
            // macOS runs on the host and the UI-test runner is sandboxed — it can't write PNGs to an
            // arbitrary path (e.g. the repo). So attach the shot to the test result instead; the
            // fastlane lane pulls it out of the .xcresult with `xcresulttool export attachments`.
            guard let app = self.app else {
                NSLog("XCUIApplication is not set. Please call setupSnapshot(app) before snapshot().")
                return
            }
            let window = app.windows.firstMatch
            let shot = window.exists ? window.screenshot() : app.screenshot()
            let device = ProcessInfo().environment["SCREENSHOT_DEVICE_NAME"] ?? "Mac"
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = "\(device)-\(name)"       // the lane keys off this "Mac-<name>" name
            attachment.lifetime = .keepAlways           // keep even though the test passes
            XCTContext.runActivity(named: "snapshot \(name)") { $0.add(attachment) }
        #else

            guard let app = self.app else {
                NSLog("XCUIApplication is not set. Please call setupSnapshot(app) before snapshot().")
                return
            }

            // Cardano TxWorkshop: when scripts/capture-screenshots.sh sets
            // SCREENSHOT_OUTPUT_DIR, every simulator hands the capture to it, so iPhone,
            // iPad and Vision Pro screenshots all come from `simctl io` at full resolution.
            if ProcessInfo().environment["SCREENSHOT_OUTPUT_DIR"] != nil {
                requestHostCapture(named: name)
                return
            }

            #if os(visionOS)
            // visionOS: every XCUITest screenshot API returns a 1x1 image (the app floats in a
            // volume — there's no flat screen to grab). The fastlane lane captures the simulator
            // display with `xcrun simctl io … screenshot` on the host instead. Hand off through the
            // shared output dir: drop a request marker, wait for the host's ".done" ack, then let
            // navigation continue so it doesn't race the capture. Falls through after a timeout so a
            // run without the host poller (e.g. straight from Xcode) doesn't hang forever.
            _ = app
            if let dirPath = ProcessInfo().environment["SCREENSHOT_OUTPUT_DIR"] {
                let dir = URL(fileURLWithPath: dirPath, isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let done = dir.appendingPathComponent(".done-\(name)")
                try? FileManager.default.removeItem(at: done)
                FileManager.default.createFile(
                    atPath: dir.appendingPathComponent(".request-\(name)").path,
                    contents: Data(name.utf8)
                )
                let deadline = Date().addingTimeInterval(20)
                while Date() < deadline && !FileManager.default.fileExists(atPath: done.path) {
                    Thread.sleep(forTimeInterval: 0.2)
                }
            }
            #else
            let screenshot = XCUIScreen.main.screenshot()
            #if os(iOS) && !targetEnvironment(macCatalyst)
            let image = XCUIDevice.shared.orientation.isLandscape ?  fixLandscapeOrientation(image: screenshot.image) : screenshot.image
            #else
            let image = screenshot.image
            #endif

            // Prefer an explicit output dir (set by the mac fastlane lane via
            // TEST_RUNNER_SCREENSHOT_OUTPUT_DIR) so collection is deterministic; otherwise fall back
            // to the stock fastlane cache dir the classic `capture_screenshots` (iOS) lane pulls from.
            let overrideDir = ProcessInfo().environment["SCREENSHOT_OUTPUT_DIR"]
                .map { URL(fileURLWithPath: $0, isDirectory: true) }
            guard var simulator = ProcessInfo().environment["SIMULATOR_DEVICE_NAME"],
                  let screenshotsDir = overrideDir ?? screenshotsDirectory else { return }

            do {
                try FileManager.default.createDirectory(at: screenshotsDir, withIntermediateDirectories: true)
                // The simulator name contains "Clone X of " inside the screenshot file when running parallelized UI Tests on concurrent devices
                let regex = try NSRegularExpression(pattern: "Clone [0-9]+ of ")
                let range = NSRange(location: 0, length: simulator.count)
                simulator = regex.stringByReplacingMatches(in: simulator, range: range, withTemplate: "")

                let path = screenshotsDir.appendingPathComponent("\(simulator)-\(name).png")
                #if swift(<5.0)
                    try UIImagePNGRepresentation(image)?.write(to: path, options: .atomic)
                #else
                    try image.pngData()?.write(to: path, options: .atomic)
                #endif
            } catch let error {
                NSLog("Problem writing screenshot: \(name) to \(screenshotsDir)/\(simulator)-\(name).png")
                NSLog(error.localizedDescription)
            }
            #endif
        #endif
    }

    // Only iOS (non-Catalyst) uses this — and only iOS has UIImage. Guarding the definition to
    // match the call site (see above) keeps SnapshotHelper compiling for the macOS UI-test bundle.
    #if os(iOS) && !targetEnvironment(macCatalyst)
    class func fixLandscapeOrientation(image: UIImage) -> UIImage {
        #if os(watchOS)
            return image
        #else
            if #available(iOS 10.0, *) {
                let format = UIGraphicsImageRendererFormat()
                format.scale = image.scale
                let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
                return renderer.image { context in
                    image.draw(in: CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height))
                }
            } else {
                return image
            }
        #endif
    }
    #endif

    class func waitForLoadingIndicatorToDisappear(within timeout: TimeInterval) {
        #if os(tvOS)
            return
        #endif

        guard let app = self.app else {
            NSLog("XCUIApplication is not set. Please call setupSnapshot(app) before snapshot().")
            return
        }

        let networkLoadingIndicator = app.otherElements.deviceStatusBars.networkLoadingIndicators.element
        let networkLoadingIndicatorDisappeared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: networkLoadingIndicator)
        _ = XCTWaiter.wait(for: [networkLoadingIndicatorDisappeared], timeout: timeout)
    }

    class func getCacheDirectory() throws -> URL {
        let cachePath = "Library/Caches/tools.fastlane"
        // on OSX config is stored in /Users/<username>/Library
        // and on iOS/tvOS/WatchOS it's in simulator's home dir
        #if os(OSX)
            let homeDir = URL(fileURLWithPath: NSHomeDirectory())
            return homeDir.appendingPathComponent(cachePath)
        #elseif arch(i386) || arch(x86_64) || arch(arm64)
            guard let simulatorHostHome = ProcessInfo().environment["SIMULATOR_HOST_HOME"] else {
                throw SnapshotError.cannotFindSimulatorHomeDirectory
            }
            let homeDir = URL(fileURLWithPath: simulatorHostHome)
            return homeDir.appendingPathComponent(cachePath)
        #else
            throw SnapshotError.cannotRunOnPhysicalDevice
        #endif
    }
}

private extension XCUIElementAttributes {
    var isNetworkLoadingIndicator: Bool {
        if hasAllowListedIdentifier { return false }

        let hasOldLoadingIndicatorSize = frame.size == CGSize(width: 10, height: 20)
        let hasNewLoadingIndicatorSize = frame.size.width.isBetween(46, and: 47) && frame.size.height.isBetween(2, and: 3)

        return hasOldLoadingIndicatorSize || hasNewLoadingIndicatorSize
    }

    var hasAllowListedIdentifier: Bool {
        let allowListedIdentifiers = ["GeofenceLocationTrackingOn", "StandardLocationTrackingOn"]

        return allowListedIdentifiers.contains(identifier)
    }

    func isStatusBar(_ deviceWidth: CGFloat) -> Bool {
        if elementType == .statusBar { return true }
        guard frame.origin == .zero else { return false }

        let oldStatusBarSize = CGSize(width: deviceWidth, height: 20)
        let newStatusBarSize = CGSize(width: deviceWidth, height: 44)

        return [oldStatusBarSize, newStatusBarSize].contains(frame.size)
    }
}

private extension XCUIElementQuery {
    var networkLoadingIndicators: XCUIElementQuery {
        let isNetworkLoadingIndicator = NSPredicate { (evaluatedObject, _) in
            guard let element = evaluatedObject as? XCUIElementAttributes else { return false }

            return element.isNetworkLoadingIndicator
        }

        return self.containing(isNetworkLoadingIndicator)
    }

    @MainActor
    var deviceStatusBars: XCUIElementQuery {
        guard let app = Snapshot.app else {
            fatalError("XCUIApplication is not set. Please call setupSnapshot(app) before snapshot().")
        }

        let deviceWidth = app.windows.firstMatch.frame.width

        let isStatusBar = NSPredicate { (evaluatedObject, _) in
            guard let element = evaluatedObject as? XCUIElementAttributes else { return false }

            return element.isStatusBar(deviceWidth)
        }

        return self.containing(isStatusBar)
    }
}

private extension CGFloat {
    func isBetween(_ numberA: CGFloat, and numberB: CGFloat) -> Bool {
        return numberA...numberB ~= self
    }
}

// Please don't remove the lines below
// They are used to detect outdated configuration files
// SnapshotHelperVersion [1.30]

extension Snapshot {
    /// Asks the host script for a screenshot: writes ".request-<name>" to
    /// SCREENSHOT_OUTPUT_DIR and waits up to 20 seconds for ".done-<name>".
    class func requestHostCapture(named name: String) {
        guard let dirPath = ProcessInfo().environment["SCREENSHOT_OUTPUT_DIR"] else { return }
        let dir = URL(fileURLWithPath: dirPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let done = dir.appendingPathComponent(".done-\(name)")
        try? FileManager.default.removeItem(at: done)
        FileManager.default.createFile(atPath: dir.appendingPathComponent(".request-\(name)").path, contents: Data(name.utf8))
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline && !FileManager.default.fileExists(atPath: done.path) {
            Thread.sleep(forTimeInterval: 0.2)
        }
    }
}
