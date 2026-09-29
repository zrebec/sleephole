import Foundation
import Observation
import SleepCore
import SwiftData
import UIKit

/// The app's single state machine (plan §6.1): which phase of the night we are in, and the night services
/// (lifecycle monitor, background audio, alarm, notifications) while a night is running.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case idle          // daytime / before the start window
        case canStart      // "Začať stavbu" is possible
        case building      // night running
        case alarm         // wake time reached, waiting for shake / code
        case result        // outcome screen until "Pokračovať"
    }

    private(set) var phase: Phase = .idle
    private(set) var window: NightWindow
    /// Started and not yet finalized.
    private(set) var active: NightRecord?
    /// Finalized, shown until the owner taps "Pokračovať".
    private(set) var shownResult: NightRecord?
    /// Level unlocked by the night in `shownResult`, if any.
    private(set) var levelUp: Int?
    /// A debug "fast night" window that overrides the schedule until it is started.
    private(set) var debugWindow: NightWindow?

    var settings: AppSettings {
        didSet {
            settings.save()
            guard servicesEnabled else { return }
            if settings.schedule != oldValue.schedule { Notifications.scheduleReminders(settings.schedule) }
            if active != nil { audio.setVolume(settings.volume, ambience: settings.ambience) }
        }
    }

    let catalog: Catalog?
    let audio = AudioKeeper()
    private let context: ModelContext
    /// ModelContext does not retain its container – keep it alive as long as the model lives.
    private let container: ModelContainer
    private let calendar = Calendar.current
    private let monitor = LifecycleMonitor()
    private var alarmTask: Task<Void, Never>?
    private var ticker: Timer?

    static let debugGrace: TimeInterval = 20

    /// Dev aid – launch arguments (e.g. via `xcrun devicectl device process launch … sk.zrebec.sleephole -clearNights`):
    ///   -clearNights                  delete all night records
    ///   -bedtime HH:MM -wake HH:MM    set the schedule
    ///   -ambience silence|brown       set the night sound
    ///   -startTestNight               immediately start a 4-min debug night (screenshots in the simulator)
    ///   -seedNights N                 SIMULATOR ONLY: replace all nights with N fake finished nights
    ///   -openTab town                 start on the Mesto tab
    static func applyLaunchArguments(to settings: inout AppSettings, context: ModelContext,
                                     args: [String] = ProcessInfo.processInfo.arguments) {
        func value(_ flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        }
        func time(_ s: String?) -> TimeOfDay? {
            guard let p = s?.split(separator: ":").compactMap({ Int($0) }), p.count == 2 else { return nil }
            return TimeOfDay(p[0], p[1])
        }
        if args.contains("-clearNights") {
            try? context.delete(model: NightRecord.self)
            try? context.save()
        }
        if let t = time(value("-bedtime")) { settings.schedule.bedtime = t }
        if let t = time(value("-wake")) { settings.schedule.wake = t }
        if let a = value("-ambience") { settings.ambience = a == "silence" ? .silence : .brownNoise }
        #if targetEnvironment(simulator)
        if let n = value("-seedNights").flatMap(Int.init), let catalog = SpriteLibrary.loadFromBundle().catalog {
            try? context.delete(model: NightRecord.self)
            var rng = SeededGenerator(seed: 3)
            var history: [String] = []
            var town = TownLayout()
            let cal = Calendar.current
            for i in 0..<n {
                let day = cal.date(byAdding: .day, value: i - n, to: Date())!
                let w = settings.schedule.window(containing: cal.startOfDay(for: day) + 12 * 3600, calendar: cal)
                let built = i                                  // ~every night builds in the demo
                let e = BuildingPicker.pick(maxLevel: Progression.unlockedMaxLevel(builtBefore: built), catalog: catalog,
                                            history: history, canUpgradeStreets: town.canUpgradeStreets, rng: &rng)
                if e.kind == .roadLit { town.upgradeStreets() } else { town.place(e) }
                history.append(e.id)
                let rec = NightRecord(window: w, buildingId: e.id, isDebug: false, setupGrace: 300)
                rec.append(.started, at: w.bedtime)
                let roll = Int.random(in: 0..<10, using: &rng)
                rec.append(.confirmed, at: w.wake + (roll == 0 ? 30 * 60 : 60))
                rec.outcomeRaw = roll == 9 ? Outcome.ruins.rawValue : roll == 0 ? Outcome.unfinished.rawValue
                    : Outcome.complete.rawValue
                rec.finalizedAt = w.wake + 120
                context.insert(rec)
            }
            try? context.save()
        }
        #endif
        settings.save()
    }

    /// Injected time (tests use `FakeClock`).
    let clock: any Clock
    /// false in unit tests: no audio, lifecycle monitor, notifications, timers or sounds.
    let servicesEnabled: Bool

    init(context: ModelContext, catalog: Catalog?, clock: any Clock = SystemClock(),
         settings initialSettings: AppSettings? = nil, servicesEnabled: Bool = true) {
        self.context = context
        self.container = context.container
        self.catalog = catalog
        self.clock = clock
        self.servicesEnabled = servicesEnabled
        var settings = initialSettings ?? AppSettings.load()
        if initialSettings == nil { Self.applyLaunchArguments(to: &settings, context: context) }
        self.settings = settings
        self.window = settings.schedule.window(containing: clock.now, calendar: .current)
        loadProgress()
        resumeActiveNight()
        rebuildTown()
        refresh()
        guard servicesEnabled else { return }
        if ProcessInfo.processInfo.arguments.contains("-startTestNight"), active == nil {
            startTestNight()
            startNight()
        }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    // MARK: - queries

    func records() -> [NightRecord] {
        (try? context.fetch(FetchDescriptor<NightRecord>(sortBy: [SortDescriptor(\.bedtime)]))) ?? []
    }

    /// Finalized real nights, oldest first (debug nights never count).
    func realResults() -> [NightRecord] {
        records().filter { !$0.isDebug && $0.isFinalized }
    }

    var builtNights: Int { realResults().filter { $0.outcome?.isBuildNight == true }.count }

    /// Current 🔥 streak: complete nights in a row up to the most recent night that could be finished.
    var streak: Int {
        let results = realResults().compactMap(\.result)
        let lastPossible = window.key.adding(days: -1, calendar: calendar)
        let last = max(results.map(\.key).max() ?? lastPossible, lastPossible)
        return Progression.currentStreak(results, lastNight: last, calendar: calendar)
    }

    /// The town is not stored – it is replayed from the finalized nights (placement is deterministic).
    func town() -> TownLayout { buildSnapshot().layout }

    private func buildSnapshot() -> TownSnapshot {
        guard let catalog else { return TownSnapshot() }
        return TownBuilder.build(results: realResults().compactMap(\.result), catalog: catalog)
    }

    // MARK: - town (observed by the Mesto tab)

    private(set) var townSnapshot: TownSnapshot?
    private(set) var townRender: TownRenderModel?
    /// Bumped whenever the town changes → the scene rebuilds.
    private(set) var townVersion = 0
    /// Where the camera should look after a rebuild (the newest building).
    private(set) var townFocus: ScenePoint?

    func rebuildTown() {
        guard let catalog else { return }
        let snap = buildSnapshot()
        townSnapshot = snap
        townRender = TownRender.build(snap, catalog: catalog, today: NightKey(date: clock.now, calendar: calendar),
                                      calendar: calendar)
        townFocus = snap.buildings.last.map { IsoProjection.scenePoint(x: $0.placement.centre.x, z: $0.placement.centre.z) }
        townVersion += 1
    }

    /// One-shot (owner request): the next debug test night counts as a real night for the town.
    var nextTestNightCounts = false

    // MARK: - guide & first night (stored in the database, `UserProgress`)

    private(set) var onboardingDone = false
    private(set) var firstNightBriefed = false

    private func progress() -> UserProgress {
        if let p = try? context.fetch(FetchDescriptor<UserProgress>()).first { return p }
        let p = UserProgress()
        context.insert(p)
        save()
        return p
    }

    private func loadProgress() {
        let p = progress()
        onboardingDone = p.onboardingCompletedAt != nil
        firstNightBriefed = p.firstNightBriefingAt != nil
    }

    func completeOnboarding() {
        progress().onboardingCompletedAt = clock.now
        save()
        onboardingDone = true
    }

    /// The "Tvoja prvá noc" checklist is shown once, before the first REAL night is started.
    var needsFirstNightBriefing: Bool {
        !firstNightBriefed && debugWindow == nil && !records().contains { !$0.isDebug && $0.startedAt != nil }
    }

    func acknowledgeFirstNightBriefing() {
        progress().firstNightBriefingAt = clock.now
        save()
        firstNightBriefed = true
    }

    /// Debug: show the guide and the first-night checklist again.
    func resetGuide() {
        let p = progress()
        p.onboardingCompletedAt = nil
        p.firstNightBriefingAt = nil
        save()
        loadProgress()
    }

    // MARK: - phase machine

    func refresh() { refresh(now: clock.now) }

    func refresh(now: Date) {
        if let rec = active {
            let log = rec.log
            if log.confirmedAt != nil || now > log.window.confirmLateUntil {
                finalize(rec)
            } else if now >= log.window.wake {
                if !log.has(.alarmFired) { ringAlarm() }
                phase = .alarm
            } else {
                phase = .building
            }
            return
        }
        if shownResult != nil {
            phase = .result
            return
        }
        window = debugWindow ?? settings.schedule.window(containing: now, calendar: calendar)
        let alreadyPlayed = debugWindow == nil && records().contains { $0.id == window.key.description }
        phase = !alreadyPlayed && window.canStart(at: now) ? .canStart : .idle
    }

    // MARK: - actions

    func startNight() {
        guard phase == .canStart, let catalog else { return }
        let now = clock.now
        let isBonus = debugWindow != nil && nextTestNightCounts
        let isDebug = debugWindow != nil && !isBonus
        if isBonus { nextTestNightCounts = false }
        let real = realResults()
        var rng = SystemRandomNumberGenerator()
        let entry = BuildingPicker.pick(
            maxLevel: Progression.unlockedMaxLevel(builtBefore: builtNights), catalog: catalog,
            history: real.map(\.buildingId), canUpgradeStreets: town().canUpgradeStreets,
            rng: &rng)
        let rec = NightRecord(window: window, buildingId: entry.id, isDebug: isDebug,
                              setupGrace: debugWindow != nil ? debugGrace : SleepRules().setupGrace,
                              idPrefix: isBonus ? "bonus" : nil)
        rec.append(.started, at: now)
        context.insert(rec)
        save()
        active = rec
        debugWindow = nil
        startServices(for: rec)
        if servicesEnabled {
            Notifications.scheduleNight(start: now, setupGrace: rec.setupGrace, wake: rec.wake,
                                        alarmFile: settings.alarmSound.fileName)
            SoundFX.play("night_start", volume: 0.5)
        }
        refresh(now: now)
    }

    /// Shake or correct wake code. Returns false when the code is wrong / confirming is not possible yet.
    @discardableResult
    func confirm(code: String? = nil) -> Bool {
        guard let rec = active, rec.window.canConfirm(at: clock.now) else { return false }
        if let code, code != settings.wakeCode { return false }
        append(.confirmed)
        refresh()
        return true
    }

    func abandonNight() {
        guard active != nil else { return }
        append(.abandoned)
        if let rec = active { finalize(rec) }
    }

    func acknowledgeResult() {
        shownResult = nil
        levelUp = nil
        refresh()
    }

    /// Setup grace of the pending debug night.
    private(set) var debugGrace: TimeInterval = AppModel.debugGrace

    /// Debug night: bedtime in 1 min, wake in `minutes`, setup grace `grace` s. Never counts for the town.
    func startTestNight(minutes: Double = 4, grace: TimeInterval = AppModel.debugGrace) {
        guard active == nil else { return }
        let now = clock.now
        debugWindow = NightWindow(key: NightKey(date: now, calendar: calendar), bedtime: now + 60,
                                  wake: now + minutes * 60)
        debugGrace = grace
        shownResult = nil
        refresh(now: now)
    }

    func cancelFastNight() {
        debugWindow = nil
        refresh()
    }

    func clearNights() {
        guard active == nil else { return }
        try? context.delete(model: NightRecord.self)
        save()
        shownResult = nil
        rebuildTown()
        refresh()
    }

    // MARK: - live info for the UI

    var collapsedAt: Date? { active.flatMap { NightEvaluator.collapsedAt($0.log, rules: $0.rules) } }

    var graceEnds: Date? { active.flatMap { rec in rec.startedAt.map { $0 + rec.setupGrace } } }

    // MARK: - night services

    private func resumeActiveNight() {
        guard let rec = records().first(where: { $0.startedAt != nil && !$0.isFinalized }) else { return }
        active = rec
        rec.append(.appLaunched, at: clock.now)
        save()
        startServices(for: rec)
    }

    private func startServices(for rec: NightRecord) {
        guard servicesEnabled else { return }
        UIApplication.shared.isIdleTimerDisabled = false
        try? audio.start(ambience: settings.ambience, volume: settings.volume)
        audio.onInterruption = { [weak self] text in
            self?.append(text.hasSuffix("began") ? .audioInterrupted : .audioResumed)
        }
        monitor.onEvent = { [weak self] kind, date in self?.append(kind, at: date) }
        monitor.start()
        alarmTask?.cancel()
        let wake = rec.wake
        alarmTask = Task { [weak self] in
            let delay = wake.timeIntervalSinceNow
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    private func stopServices() {
        guard servicesEnabled else { return }
        alarmTask?.cancel()
        alarmTask = nil
        monitor.stop()
        monitor.onEvent = nil
        audio.stop()
        Notifications.cancelNight()
    }

    private func ringAlarm() {
        guard let rec = active else { return }
        append(.alarmFired)
        guard servicesEnabled else { return }
        Notifications.cancelBackupAlarm()               // the app is alive → the backup is not needed
        Notifications.alarmScreen()                     // light up the lock screen
        // after a kill the alarm may be late: ring only for what is left of the 2 minutes
        let left = rec.rules.alarmDuration - clock.now.timeIntervalSince(rec.wake)
        guard left > 0 else { return }
        audio.ringAlarm(file: settings.alarmSound.fileName, ramp: settings.alarmSound.rampSeconds,
                        maxDuration: left) { [weak self] in
            self?.append(.alarmStopped)
        }
    }

    /// Appends a night event (from the lifecycle monitor; internal for tests).
    func append(_ kind: NightEventKind) { append(kind, at: clock.now) }

    /// How many "Vráť sa" warnings were sent this app session (diagnostics + tests).
    private(set) var nudgesSent = 0

    func append(_ kind: NightEventKind, at date: Date) {
        guard let rec = active else { return }
        // Must be evaluated BEFORE the event is stored: an open `.leftApp` interval counts until the
        // wake time, so afterwards the building always looks collapsed and no warning was ever sent
        // (bug found by the owner 2026-09-29).
        let alreadyCollapsed = collapsedAt != nil
        rec.append(kind, at: date)
        save()
        switch kind {
        case .leftApp:
            if let graceEnds, date >= graceEnds, !alreadyCollapsed {
                nudgesSent += 1
                if servicesEnabled { Notifications.nudge(tolerance: rec.rules.accidentalTolerance) }
            }
        case .returned, .locked:
            if servicesEnabled { Notifications.cancelNudge() }
        default:
            break
        }
    }

    private func finalize(_ rec: NightRecord) {
        let before = builtNights
        let log = rec.log
        let result = NightEvaluator.result(for: log, key: log.key, rules: rec.rules)
        rec.outcomeRaw = result.outcome.rawValue
        rec.awaySeconds = result.awaySeconds
        rec.finalizedAt = clock.now
        save()
        stopServices()
        active = nil
        shownResult = rec
        levelUp = rec.isDebug ? nil : Progression.levelUp(builtBefore: before, builtAfter: builtNights)
        if !rec.isDebug { rebuildTown() }
        phase = .result
        if servicesEnabled {
            switch result.outcome {
            case .complete: SoundFX.play("building_done")
            case .unfinished: SoundFX.play("building_unfinished")
            default: SoundFX.play("building_ruin")
            }
            if levelUp != nil { SoundFX.play("level_up") }
        }
    }

    private func save() { try? context.save() }
}
