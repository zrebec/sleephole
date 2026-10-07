import Foundation

/// When the phone last booted (`kern.boottime`). A termination notice that arrives right before a restart or a
/// shutdown looks exactly like the owner swiping SleepHole away – at the next launch the boot time tells them apart:
/// a boot AFTER the closure means the phone restarted (R4, the owner's favour).
enum DeviceBoot {
    static func date() -> Date? {
        var boot = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0, boot.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(boot.tv_sec) + TimeInterval(boot.tv_usec) / 1_000_000)
    }
}
