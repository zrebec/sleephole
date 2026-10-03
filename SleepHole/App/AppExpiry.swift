import Foundation

/// When the installed app stops launching (audit 2026-10-03, B2). With free Personal Team signing the
/// provisioning profile lives 7 days from its CREATION – a reinstall does not extend it, only a build signed
/// with a fresh profile does. nil in the simulator (no profile) and for App Store builds.
enum AppExpiry {
    /// Dev aid: `-expiresIn 20` pretends the profile runs out in 20 hours (screenshots in the simulator).
    static let date: Date? = {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-expiresIn"), args.indices.contains(i + 1), let hours = Double(args[i + 1]) {
            return Date() + hours * 3600
        }
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        return expirationDate(inProvision: data)
    }()

    /// A `.mobileprovision` file is a signed (CMS) blob with an XML property list inside.
    static func expirationDate(inProvision data: Data) -> Date? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return nil }
        let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], format: nil)
        return (plist as? [String: Any])?["ExpirationDate"] as? Date
    }

    /// Show the warning card on Today from this long before the expiry.
    static let warnAhead: TimeInterval = 48 * 3600

    static func isSoon(at now: Date) -> Bool {
        date.map { $0.timeIntervalSince(now) < warnAhead } ?? false
    }
}
