import Foundation
import LocalAuthentication

/// Asks the person to prove they are the device's owner (Face ID, Touch ID,
/// Optic ID or the device password) before a stored key is used.
enum OwnerCheck {
    static func confirm(_ reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode or biometrics set up: nothing to ask.
            return true
        }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}
