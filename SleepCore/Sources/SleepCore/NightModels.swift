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
    case confirmedByShake  // diagnostics: how "Vstal som" was done (logged right before `.confirmed`)
    case confirmedByCode
    case audioResumed
    /// The owner is using the phone on the LOCK SCREEN (camera, replies, widgets): the screen stayed lit with the owner
    /// recognised by Face ID. Counts exactly like `.leftApp`; ends with `.locked` / `.returned`.
    case usedLockScreen
    /// Diagnostics (no effect on the outcome): the screen lit up while the app was not in front.
    case screenOn
    /// Diagnostics: the screen went off again (logged before the `.locked` that the same moment may produce).
    case screenOff
    /// Diagnostics: protected data became available – Face ID / the passcode recognised the owner.
    case ownerRecognised
    /// Diagnostics: protected data is being locked again.
    case dataLocked
    /// "🌙 Pause" tapped (owner 2026-10-02, D17): for `PausePolicy.duration` the owner may leave the app.
    case pauseStarted
    /// iOS told the RUNNING app that it is being terminated (`willTerminate`: the owner swiped it away in the app
    /// switcher, or the phone restarts / shuts down). Owner 2026-10-04, R4: closing the app counts as leaving it, from
    /// this moment until the next `.appLaunched`. A kill without this notice (iOS, a crash) stays "unknown → favour".
    case closedByOwner
    /// Logged at the relaunch right before `.appLaunched` when the phone has booted since the `.closedByOwner`: it was
    /// a restart / shutdown, not the owner – the closure is excused.
    case restartExcused
    /// Everything the owner did out of the app BEFORE this moment of the night is forgiven: a fault of the app made the
    /// night unfair (owner 2026-10-07, B24). Only the developer launch argument `-forgiveNight` adds it.
    case forgiven
    /// Developer aid (`-revokeForgiveness`): once a log has this event every `.forgiven` of the log is ignored by the
    /// rules, so the night is judged as if nothing had been forgiven (owner 2026-10-08).
    case forgivenessRevoked
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
    /// When each pause of the night started, oldest first.
    public var pauseStarts: [Date] { sortedEvents.filter { $0.kind == .pauseStarted }.map(\.at) }
    /// The pause windows (each lasts `PausePolicy.duration` – leaving the app is free inside them).
    public var pauseIntervals: [(Date, Date)] { pauseStarts.map { ($0, $0 + PausePolicy.duration) } }

    /// When the app was closed by its owner and has not been opened again since (nil = no such closure): the last
    /// `.closedByOwner` that no later `.appLaunched` / `.restartExcused` has answered. Diagnostic events logged
    /// around the closure do not matter.
    public var openClosure: Date? {
        var open: Date?
        for e in sortedEvents {
            switch e.kind {
            case .closedByOwner: open = e.at
            case .appLaunched, .restartExcused: open = nil
            default: break
            }
        }
        return open
    }
}

public enum Outcome: String, Codable, Sendable, CaseIterable {
    case complete      // Hotová
    case unfinished    // Rozostavaná
    case ruins         // Ruina
    case missed        // stavba nezačala
    /// Protected by a joker 🛡️ (owner 2026-10-02): the streak neither grows nor breaks, no building, no coins.
    /// Never produced by the evaluator – `Jokers.protect` turns missed / ruined nights into it.
    case excused

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
    /// Pauses used that night. nil = a night from before the pause existed (2026-10-03): it gets no
    /// "undisturbed night" bonus and keeps the old per-trip tolerance.
    public let pauses: Int?
    /// The night's bedtime – the regularity is measured as start − bedtime, so a changed schedule does not
    /// look like irregular sleep.
    public let bedtime: Date?

    public init(key: NightKey, outcome: Outcome, buildingId: String?, awaySeconds: TimeInterval = 0,
                startedAt: Date? = nil, confirmedAt: Date? = nil, pauses: Int? = nil, bedtime: Date? = nil) {
        self.key = key
        self.outcome = outcome
        self.buildingId = buildingId
        self.awaySeconds = awaySeconds
        self.startedAt = startedAt
        self.confirmedAt = confirmedAt
        self.pauses = pauses
        self.bedtime = bedtime
    }
}
