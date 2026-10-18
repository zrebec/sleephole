import Foundation

/// Developer launch arguments (screenshots, simulator aids, repairs on the owner's own phone). A Release build
/// – TestFlight and the App Store – sees none of them.
enum DevArgs {
    static var list: [String] {
        #if DEBUG
        ProcessInfo.processInfo.arguments
        #else
        []
        #endif
    }

    /// The word after a flag (`-openTab stats`, `-scrollTo sounds`) – matched exactly, so a bare `stats` anywhere
    /// else in the arguments (a value of another flag) is never mistaken for the tab or the scroll target (B16b).
    static func value(after flag: String, in args: [String] = list) -> String? {
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }
}
