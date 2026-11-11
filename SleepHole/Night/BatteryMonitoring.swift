import UIKit

/// `UIDevice.isBatteryMonitoringEnabled` is one switch with several users: the battery reminder of the setup (13l) wants
/// it only while its card exists, the diagnostic track (13ab) while a night or nap runs. Each user holds it under its own
/// name (setting it twice is harmless, releasing it releases only that user's claim); the switch is on while anyone holds it.
@MainActor
enum BatteryMonitoring {
    private static var owners = Set<String>()

    static func set(_ owner: String, on: Bool) {
        if on { owners.insert(owner) } else { owners.remove(owner) }
        let wanted = !owners.isEmpty
        if UIDevice.current.isBatteryMonitoringEnabled != wanted { UIDevice.current.isBatteryMonitoringEnabled = wanted }
    }

    static var isHeld: Bool { !owners.isEmpty }
    static func holds(_ owner: String) -> Bool { owners.contains(owner) }
}
