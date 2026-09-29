import Foundation

/// Injectable time source – the app uses `SystemClock`, tests and debug "fast nights" use `FakeClock`.
public protocol Clock: Sendable {
    var now: Date { get }
}

public struct SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
}

/// Manually driven clock for tests and the debug menu.
public final class FakeClock: Clock, @unchecked Sendable {
    public var now: Date
    public init(_ now: Date) { self.now = now }
    public func advance(_ seconds: TimeInterval) { now += seconds }
}

/// Deterministic RNG (SplitMix64) – used by tests and the debug "simulate nights" tool.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
