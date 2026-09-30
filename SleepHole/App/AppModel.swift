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
    ///   -lang en|sk                   switch the UI language (stored like the Settings picker)
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
        if let a = value("-ambience") { settings.ambience = AudioKeeper.Ambience(rawValue: a) ?? .brownNoise }
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

    static func launchLanguage(args: [String] = ProcessInfo.processInfo.arguments) -> AppLanguage? {
        args.firstIndex(of: "-lang").flatMap { args.indices.contains($0 + 1) ? AppLanguage(rawValue: args[$0 + 1]) : nil }
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
        if initialSettings == nil, let lang = Self.launchLanguage() { language = lang }
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
        records().filter { !$0.isDebug && !$0.isNap && $0.isFinalized }
    }

    /// Naps for the stats: how many complete ones and the coins they paid.
    var napSummary: (count: Int, coins: Int) {
        let outcomes = napResults().compactMap(\.outcome)
        return (outcomes.filter { $0 == .complete }.count, outcomes.reduce(0) { $0 + NapPlan.reward($1) })
    }

    /// Finalized real naps (coins only).
    func napResults() -> [NightRecord] {
        records().filter { !$0.isDebug && $0.isNap && $0.isFinalized }
    }

    var builtNights: Int { realResults().filter { $0.outcome?.isBuildNight == true }.count }

    // MARK: - one night in detail (Štatistiky → tap a calendar day)

    func nightRecord(for key: NightKey) -> NightRecord? {
        records().last { !$0.isDebug && !$0.isNap && $0.isFinalized && $0.keyString == key.description }
    }

    /// The nap taken on the day before the morning `key` (i.e. the afternoon before that night).
    func napRecord(before key: NightKey) -> NightRecord? {
        let day = key.adding(days: -1, calendar: calendar).description
        return records().last { !$0.isDebug && $0.isNap && $0.isFinalized && $0.keyString == day }
    }

    func townBuilding(for key: NightKey) -> TownBuilding? {
        townSnapshot?.buildings.first { $0.nightKey == key }
    }

    func coinsEarned(for key: NightKey) -> Int? {
        Economy.ledger(realResults().compactMap(\.result), calendar: calendar).last { $0.key == key }?.coins
    }

    /// Everything for the Štatistiky tab.
    var stats: StatsSummary {
        Stats.summary(realResults().compactMap(\.result), today: NightKey(date: clock.now, calendar: calendar),
                      calendar: calendar)
    }

    /// Coin balance 🪙 (replayed from the real nights; spending comes with the building shop).
    var coins: Int {
        Economy.earned(realResults().compactMap(\.result), calendar: calendar)
            + napResults().compactMap(\.outcome).reduce(0) { $0 + NapPlan.reward($1) }
    }
    /// What the night in `shownResult` paid (reward + streak bonus).
    private(set) var lastReward = 0
    private(set) var lastStreakBonus = 0

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

    // MARK: - afternoon rest ("Odpočinok", owner 2026-09-30)

    /// Why the nap button is disabled right now (nil = it can be started).
    func napBlockReason(at t: Date? = nil) -> String? {
        let now = t ?? clock.now
        if active != nil { return L("A night is in progress.") }
        let plan = settings.nap
        let key = NightKey(date: now, calendar: calendar)
        if records().contains(where: { $0.isNap && !$0.isDebug && $0.keyString == key.description }) {
            return L("You've already had today's nap 😴")
        }
        guard plan.canStart(at: now, calendar: calendar) else {
            return L("You can't nap now (\(Fmt.time(plan.windowStart))–\(Fmt.time(plan.windowEnd))).")
        }
        return nil
    }

    func startNap() {
        guard napBlockReason() == nil else { return }
        let now = clock.now
        let window = settings.nap.session(startingAt: now, calendar: calendar)
        let rec = NightRecord(window: window, buildingId: "", isDebug: false,
                              setupGrace: NapPlan.rules.setupGrace, isNap: true)
        rec.append(.started, at: now)
        context.insert(rec)
        save()
        active = rec
        startServices(for: rec)
        if servicesEnabled {
            Notifications.scheduleNight(setupEnds: window.setupEnds(start: now, rules: NapPlan.rules), wake: window.wake,
                                        alarmFile: settings.alarmSound.fileName)
        }
        buzz(.start)
        refresh(now: now)
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
        language = p.languageRaw.flatMap(AppLanguage.init(rawValue:)) ?? .fallback
    }

    // MARK: - language (stored in the database, `UserProgress.languageRaw`)

    /// The UI language. Setting it stores the choice, switches `L(...)` at once and re-schedules the reminders.
    var language: AppLanguage = .fallback {
        didSet {
            Lang.current = language
            guard language != oldValue else { return }
            let p = progress()
            if p.languageRaw != language.rawValue {
                p.languageRaw = language.rawValue
                save()
            }
            if servicesEnabled { Notifications.scheduleReminders(settings.schedule) }
        }
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

    // MARK: - backup (F4)

    func makeBackup() -> BackupFile {
        let p = progress()
        return BackupFile(exportedAt: clock.now, settings: settings, onboardingCompletedAt: p.onboardingCompletedAt,
                          firstNightBriefingAt: p.firstNightBriefingAt, nights: records().map(\.backup),
                          language: p.languageRaw)
    }

    /// Replaces ALL nights, settings and guide flags with the backup (not while a night is running).
    func restore(_ b: BackupFile) throws {
        guard active == nil else { throw BackupError.nightRunning }
        guard b.version <= BackupFile.currentVersion else { throw BackupError.tooNew }
        try context.delete(model: NightRecord.self)
        for n in b.nights { context.insert(NightRecord(backup: n)) }
        let p = progress()
        p.onboardingCompletedAt = b.onboardingCompletedAt
        p.firstNightBriefingAt = b.firstNightBriefingAt
        if let lang = b.language, AppLanguage(rawValue: lang) != nil { p.languageRaw = lang }
        save()
        settings = b.settings
        loadProgress()
        shownResult = nil
        rebuildTown()
        refresh()
    }

    enum BackupError: LocalizedError {
        case nightRunning, tooNew
        var errorDescription: String? {
            switch self {
            case .nightRunning: L("A backup can't be restored during a night.")
            case .tooNew: L("The backup is from a newer version of SleepHole.")
            }
        }
    }

    /// Automatic backup after every finished night → Documents (Files app) and a safe copy for migrations.
    func writeAutoBackup() {
        guard let data = try? makeBackup().encoded() else { return }
        try? data.write(to: BackupFile.autoBackupURL, options: .atomic)
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
                warnBeforeSetupEnds(rec, now: now)
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
            Notifications.scheduleNight(setupEnds: rec.window.setupEnds(start: now, rules: rec.rules), wake: rec.wake,
                                        alarmFile: settings.alarmSound.fileName)
            SoundFX.play("night_start", volume: 0.5)
        }
        buzz(.start)
        refresh(now: now)
    }

    /// Shake or correct wake code. Returns false when the code is wrong / confirming is not possible yet.
    @discardableResult
    func confirm(code: String? = nil) -> Bool {
        guard let rec = active, rec.window.canConfirm(at: clock.now) else { return false }
        if let code, code != settings.wakeCode { return false }
        append(code == nil ? .confirmedByShake : .confirmedByCode)
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

    // MARK: - sleep sound during the night (owner 2026-09-30: allowed while building – you stay in the app)

    /// The sleep sound started from the night screen: which one and until when (nil end = all night).
    private(set) var sleepSound: (ambience: AudioKeeper.Ambience, endsAt: Date?)?

    func playSleepSound(_ ambience: AudioKeeper.Ambience, minutes: Int?) {
        guard active != nil else { return }
        settings.ambience = ambience
        settings.ambienceMinutes = minutes
        let seconds = minutes.map { Double($0) * 60 }
        sleepSound = ambience == .silence ? nil : (ambience, seconds.map { clock.now + $0 })
        guard servicesEnabled else { return }
        audio.setVolume(settings.volume, ambience: ambience)
        audio.sleepTimer(seconds: seconds, volume: settings.volume)
    }

    func stopSleepSound() {
        sleepSound = nil
        if servicesEnabled { audio.silenceNow() }
    }

    // MARK: - live info for the UI

    var collapsedAt: Date? {
        active.flatMap { NightEvaluator.collapsedAt($0.log, rules: $0.isNap ? NapPlan.rules : $0.rules) }
    }

    /// End of the setup time: bedtime + grace (or start + grace after bedtime), see `NightWindow.setupEnds`.
    var graceEnds: Date? {
        active.flatMap { rec in
            rec.startedAt.map { rec.window.setupEnds(start: $0, rules: rec.isNap ? NapPlan.rules : rec.rules) }
        }
    }

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
        if let total = settings.ambienceSeconds {                     // sleep timer from the start of the night
            let elapsed = clock.now.timeIntervalSince(rec.startedAt ?? clock.now)
            audio.sleepTimer(seconds: max(0, total - elapsed), volume: settings.volume)
        }
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
        sleepSound = nil
        isAway = false
        waitingForReturn = false
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
            isAway = true
            if let graceEnds, date >= graceEnds, !alreadyCollapsed {
                nudgesSent += 1
                waitingForReturn = true
                buzz(.warning)
                if servicesEnabled { Notifications.nudge(tolerance: rec.rules.accidentalTolerance) }
            }
        case .returned, .locked:
            isAway = false
            if servicesEnabled { Notifications.cancelNudge() }
            if waitingForReturn, collapsedAt == nil {
                buzz(kind == .locked ? .locked : .relief)
            } else if kind == .locked, date < rec.wake, collapsedAt == nil {
                buzz(.locked)
            }
            waitingForReturn = false
        default:
            break
        }
    }

    // MARK: - vibrations (owner 2026-09-30, idea XS)

    /// Every vibration requested this app session, in order (diagnostics + tests).
    private(set) var haptics: [Haptic] = []
    /// The app is in the background right now (left without locking).
    private var isAway = false
    /// A "Come back!" warning was sent and the owner has not returned yet.
    private var waitingForReturn = false
    /// The night whose "setup ends in 15 s" vibration was already played.
    private var setupWarningFor: String?

    private func buzz(_ h: Haptic) {
        haptics.append(h)
        if servicesEnabled { Haptics.play(h) }
    }

    /// Together with the "⏳ 15 s of setup left" notification – but only when the owner is away from SleepHole.
    private func warnBeforeSetupEnds(_ rec: NightRecord, now: Date) {
        guard let ends = graceEnds, now >= ends - 15, now < ends, isAway, setupWarningFor != rec.id else { return }
        setupWarningFor = rec.id
        buzz(.warning)
    }

    private func finalize(_ rec: NightRecord) {
        let before = builtNights
        let coinsBefore = coins
        let log = rec.log
        let result = NightEvaluator.result(for: log, key: log.key, rules: rec.isNap ? NapPlan.rules : rec.rules)
        rec.outcomeRaw = result.outcome.rawValue
        rec.awaySeconds = result.awaySeconds
        rec.finalizedAt = clock.now
        save()
        stopServices()
        active = nil
        shownResult = rec
        levelUp = rec.isDebug || rec.isNap ? nil : Progression.levelUp(builtBefore: before, builtAfter: builtNights)
        if !rec.isDebug && !rec.isNap { rebuildTown() }
        lastReward = rec.isDebug ? 0 : coins - coinsBefore
        if !rec.isDebug { writeAutoBackup() }
        lastStreakBonus = rec.isDebug || rec.isNap ? 0
            : Economy.ledger(realResults().compactMap(\.result), calendar: calendar).last?.streakBonus ?? 0
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
