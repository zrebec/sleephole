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
}
