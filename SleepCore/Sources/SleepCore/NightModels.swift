import Foundation

/// Everything that can happen during a night. Persisted append-only (plan §5.2).
public enum NightEventKind: String, Codable, Sendable {
    case started        // "Začať stavbu" tapped
    case locked         // phone locked (protected data became unavailable)
    case unlocked       // phone unlocked
    case leftApp        // app went to background while the phone was unlocked
    case returned       // app became active again
    case alarmFired
    case confirmed      // "Vstal som" / shake
    case appLaunched    // cold launch while a night was active (the app had been killed)
    case callStarted    // a phone call began (CXCallObserver) – "system-forced" background is excused
    case callEnded
    case abandoned      // owner explicitly cancelled the night
    case alarmStopped   // the alarm stopped ringing on its own (max 2 min)
    case audioInterrupted  // diagnostics: our keep-alive audio was interrupted (no effect on the outcome)
    case audioResumed
}

public struct NightEvent: Codable, Equatable, Sendable {
    public let kind: NightEventKind
    public let at: Date
    public init(_ kind: NightEventKind, at: Date) { self.kind = kind; self.at = at }
}

public struct NightLog: Codable, Equatable, Sendable {
    public let window: NightWindow
    public var buildingId: String
    public private(set) var events: [NightEvent]

    public init(window: NightWindow, buildingId: String, events: [NightEvent] = []) {
        self.window = window
        self.buildingId = buildingId
        self.events = events
    }

    public var key: NightKey { window.key }

    public mutating func append(_ kind: NightEventKind, at date: Date) {
        events.append(NightEvent(kind, at: date))
    }

    /// Events in time order (a delayed `.leftApp` may be appended after later events).
    public var sortedEvents: [NightEvent] {
        events.enumerated().sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }.map(\.element)
    }

    public func first(_ kind: NightEventKind) -> NightEvent? { sortedEvents.first { $0.kind == kind } }
    public func has(_ kind: NightEventKind) -> Bool { events.contains { $0.kind == kind } }
    public var startedAt: Date? { first(.started)?.at }
    public var confirmedAt: Date? { first(.confirmed)?.at }
}

public enum Outcome: String, Codable, Sendable, CaseIterable {
    case complete      // Hotová
    case unfinished    // Rozostavaná
    case ruins         // Ruina
    case missed        // stavba nezačala

    /// Did this night produce a building (counts toward level unlocks)?
    public var isBuildNight: Bool { self == .complete || self == .unfinished }
}

/// The final, persisted verdict of one night.
public struct NightResult: Codable, Equatable, Sendable {
    public let key: NightKey
    public let outcome: Outcome
    public let buildingId: String?
    public let awaySeconds: TimeInterval
    public let startedAt: Date?
    public let confirmedAt: Date?

    public init(key: NightKey, outcome: Outcome, buildingId: String?, awaySeconds: TimeInterval = 0,
                startedAt: Date? = nil, confirmedAt: Date? = nil) {
        self.key = key
        self.outcome = outcome
        self.buildingId = buildingId
        self.awaySeconds = awaySeconds
        self.startedAt = startedAt
        self.confirmedAt = confirmedAt
    }
}
