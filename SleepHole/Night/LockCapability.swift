import Foundation
import LocalAuthentication

/// Whether this iPhone can tell locking the phone from leaving the app. That needs a passcode (without one protected
/// data never changes) and Face ID / Touch ID (without it a passcode grace period may delay the lock signal). Both
/// checks never show a prompt.
enum LockCapability {
    static func canTellLockFromLeaving() -> Bool {
        #if targetEnvironment(simulator)
        return true            // the simulator has no passcode; it behaves like a capable phone (screenshots, tests)
        #else
        passcodeSet() && biometricsEnrolled()
        #endif
    }

    static func passcodeSet() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    static func biometricsEnrolled() -> Bool {
        var error: NSError?
        if LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) { return true }
        // locked out after failed attempts = still enrolled
        return (error?.code).map { $0 == LAError.biometryLockout.rawValue } ?? false
    }
}
