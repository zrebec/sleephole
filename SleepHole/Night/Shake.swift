import SwiftUI
import UIKit

extension Notification.Name {
    static let deviceDidShake = Notification.Name("SleepHole.deviceDidShake")
}

extension UIWindow {
    /// Shake → notification (used to confirm waking up, D15).
    override open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { NotificationCenter.default.post(name: .deviceDidShake, object: nil) }
        super.motionEnded(motion, with: event)
    }
}

extension View {
    func onShake(perform action: @escaping () -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in action() }
    }
}
