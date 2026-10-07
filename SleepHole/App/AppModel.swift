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
            // during a night, Settings switch the sound that is playing (a stopped sound stays stopped)
            if active != nil, sleepSoundPlaying,
               settings.ambience != oldValue.ambience || settings.volume != oldValue.volume {
                sleepSound = settings.ambience == .silence ? nil : (settings.ambience, sleepSound?.endsAt)
                if servicesEnabled { audio.setVolume(settings.volume, ambience: settings.ambience) }
            }
            guard servicesEnabled else { return }
            if settings.schedule != oldValue.schedule { Notifications.scheduleReminders(settings.schedule) }
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
    ///   -startNap                     screenshots: open the nap window around now and start a nap
    ///   -testNightMinutes N           with -startTestNight: a debug night of N minutes (> 30 keeps the normal night layout)
    ///   -seedNights N                 SIMULATOR ONLY: replace all nights with N fake finished nights
    ///   -openTab town                 start on the Mesto tab
    ///   -lang en|sk                   switch the UI language (stored like the Settings picker)
    ///   -theme system|light|dark      set the appearance (Settings → Theme)
    ///   -screenshot                   no permission alert, no first-run guide (use with a pulled store, tools/sim_shot.sh)
    ///   -thenTab 1|island|abandon|pause   4 s after launch: select a tab / open the Town tab / cancel the
    ///                                 running night and close its result / start a pause once the setup is over
    ///   -expiresIn HOURS              pretend the provisioning profile runs out then (AppExpiry)
    ///   -mute                         silence every sound (alarm, effects) – for screenshots of a night's end
    ///   -buddy awake|asleep           force the sleep buddy's state (screenshots)
    ///   -buddyReaction purr|arch|wink show that tap reaction's hold frame (hearts / sparkle too) on Today (screenshots)
    ///   -skyCity "Name,lat,lon"       set the city of the real sky for this run (e.g. "Bratislava,48.1486,17.1077")
    ///   -skyTime HH:MM                pin the sky's time of day; -skyArc 0.3 / -skyBody sun|moon|none / -skyMoon 0.5
    ///                                 force the drawn arc / body / moon's lit fraction (see `SkyOverrides`)
    ///   -cityQuery Brat               pre-fill Settings → Sky → city so the real Apple Maps search runs
    ///   -scrollTo sky                 scroll Settings to the Sky section (also: sounds, notifications)
    ///   -systemAlarm allowed|denied|notAsked   SIMULATOR ONLY: pretend that consent for the system alarm (a silent
    ///                                 stand-in – nothing is ever scheduled with AlarmKit in the simulator)
    ///   -weather clear|cloudy|fog|rain|heavyRain|thunder|snow, -weatherTemp N, -weatherSnowCover   simulate the weather
    ///                                 for this run (see `WeatherSimulation`); -openWeatherTest opens Developer → Weather test
    ///   -openSystemAlarmTest          with -openTab settings: open Developer → System alarm test at once
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
        if args.contains("-mute") { AudioKeeper.muted = true }          // screenshots: no alarm on the Mac's speakers
        if let t = time(value("-bedtime")) { settings.schedule.bedtime = t }
        if let t = time(value("-wake")) { settings.schedule.wake = t }
        if let a = value("-ambience") {
            settings.ambience = AudioKeeper.Ambience(rawValue: a) ?? .brownNoise
            settings.playsAtStart = true                    // an explicit choice also switches "play at the start" on
        }
        if let t = value("-theme").flatMap(AppTheme.init(rawValue:)) { settings.theme = t }
        if let c = value("-skyCity").flatMap(Self.parseCity) { settings.city = c }
        if args.contains("-startNap") {                     // the nap window opens an hour ago and closes in an hour
            let cal = Calendar.current
            func tod(_ d: Date) -> TimeOfDay { TimeOfDay(cal.component(.hour, from: d), cal.component(.minute, from: d)) }
            settings.nap.windowStart = tod(Date().addingTimeInterval(-3600))
            settings.nap.windowEnd = tod(Date().addingTimeInterval(3600))
        }
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

    /// "Bratislava,48.1486,17.1077" → the city (the name may itself contain commas: the last two parts are the
    /// coordinates).
    static func parseCity(_ text: String) -> SkyCity? {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 3, let lat = Double(parts[parts.count - 2]), let lon = Double(parts[parts.count - 1]),
              (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        let name = parts.dropLast(2).joined(separator: ", ")
        return name.isEmpty ? nil : SkyCity(name: name, latitude: lat, longitude: lon)
    }

    static func launchLanguage(args: [String] = ProcessInfo.processInfo.arguments) -> AppLanguage? {
        args.firstIndex(of: "-lang").flatMap { args.indices.contains($0 + 1) ? AppLanguage(rawValue: args[$0 + 1]) : nil }
    }

    /// Injected time (tests use `FakeClock`).
    let clock: any Clock
    /// false in unit tests: no audio, lifecycle monitor, notifications, timers or sounds.
    let servicesEnabled: Bool
    /// The system alarm (phase F6b). The default does nothing: only `SleepHoleApp` passes the real one.
    let systemAlarm: any SystemAlarm
    /// The weather over the owner's city (TOWN-W); `SleepHoleApp` passes the launch's store, the default has no source.
    let weather: WeatherStore
    private let defaults: UserDefaults
    /// When the phone last booted – a closure of the app before that was a restart, not the owner (R4). Tests pass a
    /// fake to simulate a restart.
    private let bootDate: () -> Date?

    init(context: ModelContext, catalog: Catalog?, clock: any Clock = SystemClock(),
         settings initialSettings: AppSettings? = nil, servicesEnabled: Bool = true,
         systemAlarm: any SystemAlarm = NoSystemAlarm(), weather: WeatherStore? = nil, defaults: UserDefaults = .standard,
         bootDate: @escaping () -> Date? = { DeviceBoot.date() }) {
        self.context = context
        self.container = context.container
        self.catalog = catalog
        self.clock = clock
        self.servicesEnabled = servicesEnabled
        self.systemAlarm = systemAlarm
        self.weather = weather ?? WeatherStore(source: NoWeather(), defaults: defaults)
        self.defaults = defaults
        self.bootDate = bootDate
        let memory = SystemAlarmMemory(defaults: defaults)
        systemAlarmAt = memory.at
        systemAlarmIsSafety = memory.isSafety
        var settings = initialSettings ?? AppSettings.load()
        if initialSettings == nil { Self.applyLaunchArguments(to: &settings, context: context) }
        self.settings = settings
        self.window = settings.schedule.window(containing: clock.now, calendar: .current)
        loadProgress()
        if initialSettings == nil, let lang = Self.launchLanguage() { language = lang }
        resumeActiveNight()
        tidySystemAlarm(now: clock.now, atLaunch: true)
        rebuildTown()
        refresh()
        guard servicesEnabled else { return }
        if ProcessInfo.processInfo.arguments.contains("-startTestNight"), active == nil {
            let a = ProcessInfo.processInfo.arguments
            let minutes = a.firstIndex(of: "-testNightMinutes").flatMap { a.indices.contains($0 + 1) ? Double(a[$0 + 1]) : nil }
            startTestNight(minutes: minutes ?? 4)
            startNight()
        }
        if ProcessInfo.processInfo.arguments.contains("-startNap"), active == nil { startNap() }
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

    /// The real results as every rule sees them: nights protected by a joker are `.excused` (owner 2026-10-02).
    func coreResults() -> [NightResult] { jokerState.results }

    /// Jokers in effect (switched on + automatic bronze) and the protected results.
    var jokerState: (results: [NightResult], uses: [JokerUse]) {
        Jokers.apply(results: realResults().compactMap(\.result), manual: jokerRecords().compactMap(\.use),
                     lastNight: window.key.adding(days: -1, calendar: calendar), calendar: calendar,
                     breaks: streakBreaks)
    }

    func jokerRecords() -> [JokerRecord] {
        (try? context.fetch(FetchDescriptor<JokerRecord>(sortBy: [SortDescriptor(\.at)]))) ?? []
    }

    /// The night a joker switched on now would start with (last night if it went wrong, else tonight).
    var jokerFirstNight: NightKey {
        let last = window.key.adding(days: -1, calendar: calendar)
        return Jokers.firstNight(tonight: window.key, lastNightResult: coreResults().last { $0.key == last },
                                 calendar: calendar)
    }

    func jokerBlock(_ tier: JokerTier) -> Jokers.Block? {
        Jokers.block(tier, firstNight: jokerFirstNight, uses: jokerState.uses, coins: coins)
    }

    /// The joker protecting tonight or a night around now, if any (shown on Today).
    var activeJoker: JokerUse? {
        let tonight = window.key
        return jokerState.uses.last {
            $0.covers(tonight, calendar: calendar) || $0.covers(tonight.adding(days: -1, calendar: calendar), calendar: calendar)
        }
    }

    func useJoker(_ tier: JokerTier) {
        guard jokerBlock(tier) == nil else { return }
        if tier.price > 0 { spend(tier.price, reason: "joker-\(tier.rawValue)") }
        context.insert(JokerRecord(at: clock.now, tier: tier, firstNight: jokerFirstNight))
        save()
        rebuildTown()
        refresh()
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
        Economy.ledger(coreResults(), calendar: calendar, breaks: streakBreaks, catalog: catalog)
            .last { $0.key == key }?.coins
    }

    /// Everything for the Štatistiky tab.
    var stats: StatsSummary {
        Stats.summary(coreResults(), today: NightKey(date: clock.now, calendar: calendar),
                      calendar: calendar, breaks: streakBreaks, catalog: catalog)
    }

    /// Coin balance 🪙: earned (replayed from the real nights, naps and achievements) − spent (`CoinSpend`).
    var coins: Int { coinsEarned - coinsSpent }

    var coinsEarned: Int {
        Economy.earned(coreResults(), calendar: calendar, breaks: streakBreaks, catalog: catalog)
            + napResults().compactMap(\.outcome).reduce(0) { $0 + NapPlan.reward($1) }
            + Achievements.coins(achievements)
    }

    var coinsSpent: Int { spends().reduce(0) { $0 + $1.amount } }

    func spends() -> [CoinSpend] {
        (try? context.fetch(FetchDescriptor<CoinSpend>(sortBy: [SortDescriptor(\.at)]))) ?? []
    }

    private func spend(_ amount: Int, reason: String) {
        context.insert(CoinSpend(at: clock.now, amount: amount, reason: reason))
        save()
    }

    /// Schedule changes, oldest first; the ones that were not free reset the streak (`streakBreaks`).
    func scheduleChanges() -> [ScheduleChange] {
        (try? context.fetch(FetchDescriptor<ScheduleChange>(sortBy: [SortDescriptor(\.at)]))) ?? []
    }

    var streakBreaks: [NightKey] { scheduleChanges().compactMap { $0.breakKey.flatMap(NightKey.init) } }

    /// Unlocked achievements, oldest first (replayed like the coins – old nights count too).
    var achievements: [Achievements.Unlocked] {
        Achievements.unlocked(results: coreResults(), naps: napResults().compactMap(\.result),
                              repairs: townSnapshot?.repairs ?? [], catalog: catalog, calendar: calendar,
                              breaks: streakBreaks)
    }
    /// Achievements earned by the night in `shownResult` (result screen).
    private(set) var newAchievements: [Achievement] = []

    // MARK: - weekly town journal (owner 2026-09-30, idea M)

    /// Weeks (Monday–Sunday evenings) with nights or naps, newest first.
    var journalWeeks: [WeekSummary] {
        WeeklyJournal.weeks(results: coreResults(), naps: napResults().compactMap(\.result),
                            calendar: calendar, breaks: streakBreaks, catalog: catalog)
    }

    func journalWeek(monday: NightKey) -> WeekSummary {
        WeeklyJournal.week(monday: monday, results: coreResults(),
                           naps: napResults().compactMap(\.result), calendar: calendar, breaks: streakBreaks,
                           catalog: catalog)
    }

    /// Monday of the week we are in now.
    var currentMonday: NightKey { WeeklyJournal.monday(of: NightKey(date: clock.now, calendar: calendar), calendar: calendar) }

    /// The week that just ended, shown once on the result screen (Monday morning after "I'm up").
    private(set) var finishedWeek: WeekSummary?
    /// What the night in `shownResult` paid (reward + streak bonus).
    private(set) var lastReward = 0
    private(set) var lastStreakBonus = 0
    /// +30 when the night in `shownResult` was complete without a pause.
    private(set) var lastUndisturbedBonus = 0

    /// Current 🔥 streak: complete nights in a row up to the most recent night that could be finished.
    var streak: Int {
        let results = coreResults()
        let lastPossible = window.key.adding(days: -1, calendar: calendar)
        let last = max(results.map(\.key).max() ?? lastPossible, lastPossible)
        return Progression.currentStreak(results, lastNight: last, calendar: calendar, breaks: streakBreaks)
    }

    /// The town is not stored – it is replayed from the finalized nights (placement is deterministic).
    func town() -> TownLayout { buildSnapshot().layout }

    private func buildSnapshot() -> TownSnapshot {
        guard let catalog else { return TownSnapshot() }
        return TownBuilder.build(results: coreResults(), catalog: catalog)
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
        armAlarm(for: rec, setupEnds: window.setupEnds(start: now, rules: NapPlan.rules))
        fx("fx_sleep", volume: 0.6)
        say(.napStart, after: Motion.t(1.4))
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
        customTownName = p.townName
        if p.scheduleCalibrationStart == nil {             // the free first week starts with the first launch
            p.scheduleCalibrationStart = clock.now
            save()
        }
        scheduleCalibrationStart = p.scheduleCalibrationStart
        schedulePromptAnswered = p.schedulePromptMonth
    }

    // MARK: - schedule changes (owner 2026-09-30: free on days 1–3 of a month + the first week, else the streak)

    private(set) var scheduleCalibrationStart: Date?
    private(set) var schedulePromptAnswered: String?
    /// Bumped by "Adjust" on the monthly card → the root view opens Settings.
    private(set) var settingsRequest = 0
    /// Bumped to open the Town tab (the Today island did it; `-thenTab island` still does) → RootView switches to it.
    private(set) var townRequest = 0
    func showTown() { townRequest += 1 }

    func scheduleChangeCost(at t: Date? = nil) -> SchedulePolicy.Change {
        SchedulePolicy.change(at: t ?? clock.now, calibrationStart: scheduleCalibrationStart, calendar: calendar)
    }

    var nextFreeScheduleChange: Date {
        SchedulePolicy.nextFreeWindow(after: clock.now, calibrationStart: scheduleCalibrationStart, calendar: calendar)
    }

    var scheduleCalibrationEnds: Date? {
        SchedulePolicy.calibrationEnds(after: clock.now, calibrationStart: scheduleCalibrationStart)
    }

    /// Saves a new schedule. A new bedtime / wake outside the free window resets the 🔥 streak from tonight
    /// (a `ScheduleChange` with a `breakKey`); the reminder can change any time for free.
    func applySchedule(_ new: Schedule) {
        let old = settings.schedule
        guard new != old, active == nil else { return }
        if (new.bedtime != old.bedtime || new.wake != old.wake), onboardingDone {
            let free = scheduleChangeCost() != .resetsStreak
            context.insert(ScheduleChange(at: clock.now, from: "\(old.bedtime)–\(old.wake)",
                                          to: "\(new.bedtime)–\(new.wake)", free: free,
                                          breakKey: free ? nil : SchedulePolicy.streakBreak(changedAt: clock.now,
                                                                                            calendar: calendar).description))
            save()
        }
        settings.schedule = new
        refresh()
    }

    private var monthKey: String {
        let c = calendar.dateComponents([.year, .month], from: clock.now)
        return String(format: "%04d-%02d", c.year!, c.month!)
    }

    /// "New month 🌙 Does your bedtime still fit?" on days 1–3 until answered.
    var showsMonthlySchedulePrompt: Bool {
        onboardingDone && active == nil && SchedulePolicy.freeDays.contains(calendar.component(.day, from: clock.now))
            && schedulePromptAnswered != monthKey
    }

    /// `adjust` = open Settings to change the schedule.
    func answerMonthlyPrompt(adjust: Bool) {
        progress().schedulePromptMonth = monthKey
        save()
        schedulePromptAnswered = monthKey
        if adjust { settingsRequest += 1 }
    }

    // MARK: - town name (owner 2026-09-30, idea S; stored in the database)

    static let townNameMaxLength = 30
    /// nil = never named → "My Town" in the current language.
    private(set) var customTownName: String?
    var townName: String { customTownName ?? L("My Town") }

    /// What renaming would cost now (owner 2026-09-30: once a year free, otherwise 5 000 🪙).
    func renameCost(at t: Date? = nil) -> RenamePolicy.Cost {
        let p = progress()
        return RenamePolicy.cost(at: t ?? clock.now, hasCustomName: customTownName != nil,
                                 lastRenameAt: p.lastRenameAt, lastFreeRenameAt: p.lastFreeRenameAt)
    }

    /// When the yearly free rename is available again (nil = now).
    var nextFreeRename: Date? { RenamePolicy.nextFree(after: clock.now, lastFreeRenameAt: progress().lastFreeRenameAt) }

    enum RenameResult: Equatable { case renamed, unchanged, notEnoughCoins }

    /// Trimmed, at most 30 characters; empty = back to the default name. Pays for it when it is not free.
    @discardableResult
    func renameTown(_ name: String) -> RenameResult {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.townNameMaxLength))
        let new = trimmed.isEmpty ? nil : trimmed
        guard new != customTownName else { return .unchanged }
        let cost = renameCost()
        let p = progress()
        switch cost {
        case .paid(let price):
            guard coins >= price else { return .notEnoughCoins }
            spend(price, reason: "rename-town")
            p.lastRenameAt = clock.now
        case .free(.yearly):
            p.lastRenameAt = clock.now
            p.lastFreeRenameAt = clock.now
        case .free(.firstNaming):
            p.lastRenameAt = clock.now                    // opens the 10-min typo window, keeps the yearly one
        case .free(.typoFix):
            break                                         // the typo window stays anchored to the rename
        }
        customTownName = new
        p.townName = new
        save()
        return .renamed
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
                          language: p.languageRaw, townName: p.townName, lastRenameAt: p.lastRenameAt,
                          lastFreeRenameAt: p.lastFreeRenameAt, scheduleCalibrationStart: p.scheduleCalibrationStart,
                          spends: spends().map { .init(at: $0.at, amount: $0.amount, reason: $0.reason) },
                          scheduleChanges: scheduleChanges().map {
                              .init(at: $0.at, from: $0.from, to: $0.to, free: $0.free, breakKey: $0.breakKey)
                          },
                          jokers: jokerRecords().map { .init(at: $0.at, tier: $0.tierRaw, firstNight: $0.firstNight) })
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
        if let name = b.townName { p.townName = name }
        if let d = b.lastRenameAt { p.lastRenameAt = d }
        if let d = b.lastFreeRenameAt { p.lastFreeRenameAt = d }
        if let d = b.scheduleCalibrationStart { p.scheduleCalibrationStart = d }
        // the backup is the whole truth: an older one (no spends / changes) had none
        try context.delete(model: CoinSpend.self)
        for s in b.spends ?? [] { context.insert(CoinSpend(at: s.at, amount: s.amount, reason: s.reason)) }
        try context.delete(model: ScheduleChange.self)
        for c in b.scheduleChanges ?? [] {
            context.insert(ScheduleChange(at: c.at, from: c.from, to: c.to, free: c.free, breakKey: c.breakKey))
        }
        try context.delete(model: JokerRecord.self)
        for j in b.jokers ?? [] {
            guard let tier = JokerTier(rawValue: j.tier), let key = NightKey(j.firstNight) else { continue }
            let r = JokerRecord(at: j.at, tier: tier, firstNight: key)
            context.insert(r)
        }
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
                if !log.has(.alarmFired) { ringAlarm() } else { startAlarmSound() }
                phase = .alarm
            } else {
                phase = .building
            }
            return
        }
        tidySystemAlarm(now: now)
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
        armAlarm(for: rec, setupEnds: rec.window.setupEnds(start: now, rules: rec.rules))
        fx("fx_sleep", volume: 0.6)
        say(.goodNight, after: Motion.t(1.4))
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
        lastUndisturbedBonus = 0
        levelUp = nil
        newAchievements = []
        finishedWeek = nil
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

    /// The sleep sound of the running night (from Settings at the start or from the night screen):
    /// which one and until when (nil end = all night).
    private(set) var sleepSound: (ambience: AudioKeeper.Ambience, endsAt: Date?)?

    var sleepSoundPlaying: Bool { sleepSound.map { $0.endsAt.map { $0 > clock.now } ?? true } ?? false }

    /// ▶ during a night or nap: plays the sound, remembers the sound + minutes and switches "play when the night
    /// starts" back on (a pressed ■ is forgiven, bug B19).
    func playSleepSound(_ ambience: AudioKeeper.Ambience, minutes: Int?) {
        guard active != nil else { return }
        var s = settings
        s.ambience = ambience
        s.ambienceMinutes = minutes
        if ambience != .silence { s.playsAtStart = true }
        settings = s
        let seconds = minutes.map { Double($0) * 60 }
        sleepSound = ambience == .silence ? nil : (ambience, seconds.map { clock.now + $0 })
        guard servicesEnabled else { return }
        audio.setVolume(settings.volume, ambience: ambience)
        audio.sleepTimer(seconds: seconds, volume: settings.volume)
    }

    /// ■ during a night or nap: silences the sound and remembers it – the next night / nap starts silent while
    /// the chosen sound and minutes stay for ▶ (bug B19). A timer that simply ran out is not a stop.
    func stopSleepSound() {
        sleepSound = nil
        if active != nil { settings.playsAtStart = false }
        if servicesEnabled { audio.silenceNow() }
    }

    // MARK: - live info for the UI

    /// Dev aid: `-buddy awake|asleep` forces the sleep buddy's state (screenshots).
    static let forcedBuddyState: BuddyState? = {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-buddy"), a.indices.contains(i + 1) else { return nil }
        switch a[i + 1] {
        case "awake": return .awake
        case "asleep": return .asleep
        default: return nil
        }
    }()

    /// Dev aid: `-buddyReaction purr|arch|wink` shows that reaction's hold frame on Today (screenshots).
    static let forcedBuddyReaction: BuddyReaction? = {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-buddyReaction"), a.indices.contains(i + 1) else { return nil }
        switch a[i + 1] {
        case "purr": return .purr
        case "arch": return .arch
        case "wink": return .wink
        default: return nil
        }
    }()

    /// The reaction the next tap on the cat gives (plan P2b). Session state only – never stored, never in a backup.
    @ObservationIgnored private var nextBuddyReaction = BuddyReaction.purr

    /// The owner pets the cat on Today: returns this tap's reaction (purr → arched back → wink → purr …) and plays its
    /// sound and vibration. Presentation only – no coins, no rules, nothing is saved.
    @discardableResult
    func petBuddy() -> BuddyReaction {
        let reaction = nextBuddyReaction
        nextBuddyReaction = reaction.next
        switch reaction {
        case .purr:
            fx("fx_purr", volume: 0.9)
            buzz(.purr)
        case .arch:
            fx("fx_meow", volume: 0.45)
            buzz(.pet)
        case .wink:
            fx("fx_sparkle", volume: 0.4)
            buzz(.pet)
        }
        return reaction
    }

    /// What the sleep buddy does now (plan P2): awake on Today; during a night or a nap only in the setup, in a pause
    /// and from the alarm on; asleep otherwise – a collapsed night too (the cat never judges).
    func buddyState(at t: Date? = nil) -> BuddyState {
        if let forced = Self.forcedBuddyState { return forced }
        let now = t ?? clock.now
        return Buddy.state(at: now, running: active != nil, setupEnds: graceEnds, pauseEnds: pauseEnds(at: now),
                           wake: active?.wake)
    }

    var collapsedAt: Date? {
        active.flatMap { NightEvaluator.collapsedAt($0.log, rules: $0.isNap ? NapPlan.rules : $0.rules) }
    }

    /// End of the setup time: bedtime + grace (or start + grace after bedtime), see `NightWindow.setupEnds`.
    var graceEnds: Date? {
        active.flatMap { rec in
            rec.startedAt.map { rec.window.setupEnds(start: $0, rules: rec.isNap ? NapPlan.rules : rec.rules) }
        }
    }

    // MARK: - system alarm (AlarmKit backup, phase F6b)

    /// When the one system alarm is set to ring (nil = none). It is the app's INTENT, written at once; the calls to the
    /// system run one after another in `systemAlarmQueue`. Persisted: a relaunched app must still know about it.
    private(set) var systemAlarmAt: Date? {
        didSet { SystemAlarmMemory(defaults: defaults).at = systemAlarmAt }
    }
    /// That alarm is a safety alarm (an early confirmation), not the backup of a running night.
    private(set) var systemAlarmIsSafety = false {
        didSet { SystemAlarmMemory(defaults: defaults).isSafety = systemAlarmIsSafety }
    }
    /// The five backup notifications are scheduled for the running night – always, also next to the system alarm
    /// (belt and braces). False once our own alarm really rings (they are cancelled then) and when the night is over.
    /// Diagnostics + tests.
    private(set) var backupNotificationsOn = false
    /// The time the test alarm (Developer → System alarm test) was set for; it is `testAlarmAt` only while it waits.
    private var testAlarmTime: Date?
    /// The system alarm was already moved behind our own alarm tonight.
    @ObservationIgnored private var systemAlarmMoved = false
    @ObservationIgnored private var systemAlarmQueue: Task<Void, Never>?
    @ObservationIgnored private var consentTask: Task<Void, Never>?

    /// When the safety alarm rings (nil = none, or its time has passed): the owner confirmed waking up early, and the
    /// system alarm stays on in case he falls asleep again.
    var safetyAlarmAt: Date? {
        guard systemAlarmIsSafety, let at = systemAlarmAt, at > clock.now else { return nil }
        return at
    }

    /// "I'm really up": cancels the safety alarm.
    func switchOffSafetyAlarm() {
        guard systemAlarmIsSafety else { return }
        cancelSystemAlarm()
    }

    // MARK: system alarm test (Settings → Developer → System alarm test)

    /// When the test alarm rings, while it waits (nil = none, or its time has passed).
    var testAlarmAt: Date? {
        guard let t = testAlarmTime, safetyAlarmAt == t else { return nil }
        return t
    }

    /// The test can be started: nothing runs (a night / nap has its own alarm), the system alarm is allowed, and no
    /// real safety alarm waits (the test would replace it).
    var canTestSystemAlarm: Bool {
        active == nil && systemAlarm.consent == .allowed && (safetyAlarmAt == nil || safetyAlarmAt == testAlarmTime)
    }

    /// Rings the system alarm `seconds` from now with the chosen alarm sound, so the owner can check AlarmKit in
    /// seconds, without a night. It is scheduled like a safety alarm: the housekeeping keeps it until its time and then
    /// forgets it (Today shows it as a safety alarm meanwhile). Returns whether the test was set.
    @discardableResult
    func testSystemAlarm(after seconds: TimeInterval = 20) -> Bool {
        guard canTestSystemAlarm else { return false }
        let at = clock.now + seconds
        testAlarmTime = at
        scheduleSystemAlarm(at: at, safety: true)
        return true
    }

    /// Cancels the test alarm while it waits.
    func cancelTestSystemAlarm() {
        guard testAlarmAt != nil else { return }
        cancelSystemAlarm()
    }

    /// Waits until every system alarm call so far has finished (tests).
    func systemAlarmIdle() async {
        await consentTask?.value
        await systemAlarmQueue?.value
    }

    /// The calls to the system go one after another: schedule, move and cancel can never overtake each other.
    private func enqueueSystemAlarm(_ work: @escaping @MainActor () async -> Void) {
        let previous = systemAlarmQueue
        systemAlarmQueue = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    /// Sets THE system alarm to `date` (replacing the earlier one). When the system does not accept it, the intent goes
    /// back to what it was.
    private func scheduleSystemAlarm(at date: Date, safety: Bool = false) {
        let before = (at: systemAlarmAt, safety: systemAlarmIsSafety)
        systemAlarmAt = date
        systemAlarmIsSafety = safety
        let file = settings.alarmSound.fileName
        enqueueSystemAlarm { [weak self] in
            guard let self else { return }
            let accepted = await self.systemAlarm.schedule(at: date, soundFile: file)
            if !accepted, self.systemAlarmAt == date {
                self.systemAlarmAt = before.at
                self.systemAlarmIsSafety = before.safety
            }
        }
    }

    private func cancelSystemAlarm() {
        systemAlarmAt = nil
        systemAlarmIsSafety = false
        testAlarmTime = nil
        enqueueSystemAlarm { [weak self] in self?.systemAlarm.cancel() }
    }

    /// The alarm side of a night / nap that has just started. The five backup notifications are ALWAYS scheduled (belt
    /// and braces: the system alarm cannot be trusted alone until it has proven itself on the phone). Next to them,
    /// with the owner's consent, the system alarm (wake + 30 s). Consent not asked yet: ask once, and schedule the
    /// system alarm when the answer is yes.
    private func armAlarm(for rec: NightRecord, setupEnds: Date) {
        systemAlarmMoved = false
        backupNotificationsOn = true
        if servicesEnabled {
            Notifications.scheduleNight(setupEnds: setupEnds, wake: rec.wake, alarmFile: settings.alarmSound.fileName)
        }
        switch systemAlarm.consent {
        case .allowed:
            scheduleSystemAlarm(at: rec.wake + SystemAlarmPlan.afterWake)
        case .notAsked:
            consentTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let answer = await self.systemAlarm.requestConsent()
                // the owner may take a while to answer: the night can be over by then
                guard answer == .allowed, self.active?.id == rec.id, rec.wake > self.clock.now else { return }
                self.scheduleSystemAlarm(at: rec.wake + SystemAlarmPlan.afterWake)
            }
        case .denied, .unavailable:
            break
        }
    }

    /// Our alarm rings from the wake time for `alarmDuration`: the system alarm moves to the moment ours stops, once.
    /// A system alarm that is already due (the app was killed and came back late, or the owner opened it while the
    /// alarm rang) is ringing or has rung: it is stopped – never two alarms at once – and, while time is left of our
    /// two minutes, set again for the moment ours stops, so it still takes over when the owner sleeps through them.
    private func moveSystemAlarmBehindOurs() {
        guard !systemAlarmMoved, let rec = active, !systemAlarmIsSafety, let at = systemAlarmAt else { return }
        let now = clock.now
        let target = rec.wake + rec.rules.alarmDuration
        if at <= now {
            systemAlarmMoved = true
            cancelSystemAlarm()                                   // stops a ringing one
            if target.timeIntervalSince(now) > 1 { scheduleSystemAlarm(at: target) }
            return
        }
        guard at < target else { return }
        systemAlarmMoved = true
        scheduleSystemAlarm(at: target)
    }

    /// A night / nap is over (confirmed, abandoned or expired). Confirmed at or after the wake time, abandoned or
    /// expired → the system alarm is cancelled. Confirmed EARLY (a night, from wake − 30 min) → it moves to the wake
    /// time and stays as a safety alarm. Without consent there is no safety alarm.
    private func settleSystemAlarm(for rec: NightRecord) {
        systemAlarmMoved = false
        let early = !rec.isNap && rec.log.confirmedAt.map { $0 < rec.wake } == true
        if early, systemAlarm.consent == .allowed, rec.wake > clock.now {
            scheduleSystemAlarm(at: rec.wake, safety: true)
        } else {
            cancelSystemAlarm()
        }
    }

    /// Housekeeping: while no night / nap runs, a system alarm nobody waits for is cancelled. A safety alarm waits for
    /// its time; one whose time has passed is only forgotten (it has rung – a ringing alarm is left alone). At launch
    /// everything left over is cancelled, even what the app does not remember; a night that was running when the app
    /// was killed keeps its alarm – that is the point of it.
    private func tidySystemAlarm(now: Date, atLaunch: Bool = false) {
        guard active == nil else { return }
        if systemAlarmIsSafety, let at = systemAlarmAt, at > now { return }
        if !atLaunch {
            guard let at = systemAlarmAt else { return }
            if at <= now {
                systemAlarmAt = nil
                systemAlarmIsSafety = false
                return
            }
        }
        cancelSystemAlarm()
    }

    // MARK: - night services

    /// A night / nap was running when the process died: pick it up again. A closure iOS announced before the death
    /// (`.closedByOwner`) is the owner swiping the app away – this launch ends that trip. Unless the phone has booted
    /// since: then it was a restart and the closure is excused (`.restartExcused`, logged right before `.appLaunched`).
    private func resumeActiveNight() {
        guard let rec = records().first(where: { $0.startedAt != nil && !$0.isFinalized }) else { return }
        active = rec
        let now = clock.now
        let closedAt = rec.log.openClosure
        let restarted = closedAt.map { c in bootDate().map { $0 > c } ?? false } ?? false
        if restarted { rec.append(.restartExcused, at: now) }
        rec.append(.appLaunched, at: now)
        save()
        if closedAt != nil, servicesEnabled { Notifications.cancelClosed() }       // the owner is back
        startServices(for: rec)
        // came back in time after a "SleepHole was closed" warning → the same "phew" as after "Come back!"
        if let c = closedAt, !restarted, now < rec.wake, let graceEnds, c >= graceEnds,
           PausePolicy.activeUntil(rec.log, at: c) == nil, collapsedAt == nil {
            buzz(.relief)
        }
    }

    private func startServices(for rec: NightRecord) {
        // the sound from Settings plays from the start – unless the owner stopped it during an earlier night
        // (B19): then the engine still starts (it keeps the app alive) but silent, and there is no sleep timer
        let ambience: AudioKeeper.Ambience = settings.playsAtStart ? settings.ambience : .silence
        if ambience != .silence {
            sleepSound = (ambience, settings.ambienceSeconds.map { (rec.startedAt ?? clock.now) + $0 })
        }
        guard servicesEnabled else { return }
        UIApplication.shared.isIdleTimerDisabled = false
        try? audio.start(ambience: ambience, volume: settings.volume)
        if ambience != .silence, let total = settings.ambienceSeconds {   // sleep timer from the start of the night
            let elapsed = clock.now.timeIntervalSince(rec.startedAt ?? clock.now)
            audio.sleepTimer(seconds: max(0, total - elapsed), volume: settings.volume)
        }
        audio.onInterruption = { [weak self] text in
            self?.append(text.hasSuffix("began") ? .audioInterrupted : .audioResumed)
        }
        monitor.onEvent = { [weak self] kind, date in self?.append(kind, at: date) }
        monitor.onTerminate = { [weak self] in self?.appWillTerminate() }
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
        waitingForReturn = false
        backupNotificationsOn = false                       // cancelled with the night's other notifications below
        guard servicesEnabled else { return }
        alarmTask?.cancel()
        alarmTask = nil
        monitor.stop()
        monitor.onEvent = nil
        monitor.onTerminate = nil
        audio.stop()
        Notifications.cancelNight()
    }

    private func ringAlarm() {
        guard active != nil else { return }
        append(.alarmFired)
        guard servicesEnabled else { return }
        Notifications.alarmScreen()                     // light up the lock screen
        startAlarmSound()
    }

    /// Starts the in-app alarm, or tries again (called every second while the alarm should ring). The backup
    /// notifications are cancelled only once the sound really plays: a phone call or another app's alarm at wake
    /// time can keep our audio from starting, and then they are the alarm (audit 2026-10-03, B1).
    private func startAlarmSound() {
        guard servicesEnabled, let rec = active, !rec.log.has(.alarmStopped) else { return }
        if audio.isAlarmRinging {
            if audio.isEngineRunning { return }
            audio.stopAlarm()                           // the engine was stopped under the alarm → ring again
        }
        // after a kill the alarm may be late: ring only for what is left of the 2 minutes
        let left = rec.rules.alarmDuration - clock.now.timeIntervalSince(rec.wake)
        guard left > 0 else { return }
        let ringing = audio.ringAlarm(file: settings.alarmSound.fileName, ramp: settings.alarmSound.rampSeconds,
                                      maxDuration: left) { [weak self] in
            self?.append(.alarmStopped)
        }
        if ringing { alarmSoundStarted() }
    }

    /// Our own alarm really sounds (called by `startAlarmSound`; a seam for tests, which have no audio). The app is
    /// alive and audible → the backup notifications are cancelled; and the system alarm moves behind our two minutes,
    /// so it takes over when the owner sleeps through them.
    func alarmSoundStarted() {
        if servicesEnabled { Notifications.cancelBackupAlarm() }
        backupNotificationsOn = false
        moveSystemAlarmBehindOurs()
    }

    /// iOS tells the running app that it is being terminated (`LifecycleMonitor.onTerminate`). Owner 2026-10-04, R4:
    /// SleepHole swiped away in the app switcher during a night / nap counts as leaving the app, from now until it is
    /// opened again – a swipe delivers this notice, a kill by iOS (memory) or a crash does not. A phone restart delivers
    /// it too; the next launch tells the two apart by the boot time (`resumeActiveNight`). After the wake time, or
    /// with nothing running, closing the app is just closing it.
    /// `append` stores the event synchronously (`context.save()`) before it returns – the process is about to die –
    /// and sends the warning, exactly where leaving the app would.
    func appWillTerminate() {
        guard let rec = active, clock.now < rec.wake else { return }
        append(.closedByOwner)
    }

    /// Appends a night event (from the lifecycle monitor; internal for tests).
    func append(_ kind: NightEventKind) { append(kind, at: clock.now) }

    /// How many "Vráť sa" warnings were sent this app session (diagnostics + tests).
    private(set) var nudgesSent = 0
    /// The seconds the last warning promised (10, or less when the night's budget is nearly used up).
    private(set) var lastNudgeSeconds = 0

    // MARK: - night pause (owner 2026-10-02, D17)

    /// The end of the pause that is on now, if any.
    func pauseEnds(at t: Date? = nil) -> Date? {
        active.flatMap { PausePolicy.activeUntil($0.log, at: t ?? clock.now) }
    }

    /// Price of the next pause tonight: the first is free, then 50, 100, 150 … (test nights never pay).
    var nextPausePrice: Int {
        guard let rec = active, !rec.isDebug else { return 0 }
        return PausePolicy.price(number: (rec.pauses ?? 0) + 1)
    }

    /// Why a pause can't be started now (nil = it can).
    func pauseBlock(at t: Date? = nil) -> PausePolicy.Block? {
        guard let rec = active else { return .collapsed }
        return PausePolicy.block(rec.log, rules: rec.rules, at: t ?? clock.now, coins: rec.isDebug ? .max : coins,
                                 isNap: rec.isNap)
    }

    /// Seconds spent out of the app tonight after the setup (outside pauses and calls) and the night's budget.
    func awayBudgetUse(at t: Date? = nil) -> (used: TimeInterval, budget: TimeInterval)? {
        guard let rec = active, let budget = rec.rules.awayBudget else { return nil }
        return (NightEvaluator.awayAfterSetup(rec.log, rules: rec.rules, until: t ?? clock.now), budget)
    }

    func startPause() {
        guard let rec = active, pauseBlock() == nil else { return }
        let price = nextPausePrice
        if price > 0 { spend(price, reason: "pause-\(rec.keyString)") }
        append(.pauseStarted)
        fx("fx_pop", volume: 0.5)
    }

    func append(_ kind: NightEventKind, at date: Date) {
        guard let rec = active else { return }
        // Must be evaluated BEFORE the event is stored: an open `.leftApp` interval counts until the
        // wake time, so afterwards the building always looks collapsed and no warning was ever sent
        // (bug found by the owner 2026-09-29).
        let alreadyCollapsed = collapsedAt != nil
        rec.append(kind, at: date)
        save()
        switch kind {
        case .leftApp, .closedByOwner:
            // no vibration here: the app is in the background now and iOS only lets the notification vibrate
            if let pauseEnds = PausePolicy.activeUntil(rec.log, at: date) {
                // inside a pause (D17) leaving is free – only remind when it is about to end
                if servicesEnabled { Notifications.pauseEnding(at: pauseEnds) }
            } else if let graceEnds, date >= graceEnds, !alreadyCollapsed {
                // what is left for this trip: 13 s, or less when the night's budget is nearly used up
                let left = NightEvaluator.allowance(rec.log, rules: rec.rules, at: date) - rec.rules.noticeDelay
                guard left >= 1 else { break }                // the warning would come too late
                nudgesSent += 1
                lastNudgeSeconds = Int(left)
                if kind == .closedByOwner {
                    // the process dies now: the notice is all that is left, and the relaunch ends the trip
                    if servicesEnabled { Notifications.closed(tolerance: left) }
                } else {
                    waitingForReturn = true
                    if servicesEnabled { Notifications.nudge(tolerance: left) }
                }
            }
        case .returned, .locked:
            if servicesEnabled {
                Notifications.cancelNudge()
                Notifications.cancelPauseNotices()
            }
            if kind == .returned, waitingForReturn, collapsedAt == nil { buzz(.relief) }
            waitingForReturn = false
        default:
            break
        }
    }

    // MARK: - vibrations (owner 2026-09-30, idea XS)

    /// Every vibration requested this app session, in order (diagnostics + tests). Only in the foreground:
    /// iOS does not let apps vibrate in the background (owner test 2026-09-30) – there the notifications
    /// ("⏳ 15 s of setup left", "⚠️ Come back!") vibrate the phone through their sound.
    private(set) var haptics: [Haptic] = []
    /// A "Come back!" warning was sent and the owner has not returned yet.
    private var waitingForReturn = false

    private func buzz(_ h: Haptic) {
        haptics.append(h)
        if servicesEnabled { Haptics.play(h) }
    }

    /// Sound effect (Settings → Sound effects); `after` seconds late so effects can follow an animation.
    func fx(_ name: String, volume: Float = 0.8, after: Double = 0) {
        guard servicesEnabled, settings.soundEffects else { return }
        guard after > 0 else { return SoundFX.play(name, volume: volume) }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(after))
            SoundFX.play(name, volume: volume)
        }
    }

    /// The friendly voice (Settings → Voice).
    func say(_ line: Voice.Line, after: Double = 0) {
        guard servicesEnabled, settings.voice else { return }
        let text = line.text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(after))
            Voice.say(text)
        }
    }


    private func finalize(_ rec: NightRecord) {
        let before = builtNights
        let coinsBefore = coins
        let achievedBefore = Set(achievements.map(\.achievement))
        let log = rec.log
        let result = NightEvaluator.result(for: log, key: log.key, rules: rec.isNap ? NapPlan.rules : rec.rules)
        rec.outcomeRaw = result.outcome.rawValue
        rec.awaySeconds = result.awaySeconds
        rec.finalizedAt = clock.now
        save()
        stopServices()
        active = nil
        settleSystemAlarm(for: rec)
        shownResult = rec
        levelUp = rec.isDebug || rec.isNap ? nil : Progression.levelUp(builtBefore: before, builtAfter: builtNights)
        if !rec.isDebug && !rec.isNap { rebuildTown() }
        lastReward = rec.isDebug ? 0 : coins - coinsBefore
        newAchievements = achievements.map(\.achievement).filter { !achievedBefore.contains($0) }
        finishedWeek = nil
        if !rec.isDebug, !rec.isNap, let key = NightKey(rec.keyString) {
            let previous = realResults().last { $0.id != rec.id && $0.bedtime < rec.bedtime }.flatMap { NightKey($0.keyString) }
            finishedWeek = WeeklyJournal.finishedWeek(after: key, previous: previous, calendar: calendar)
                .map(journalWeek(monday:)).flatMap { $0.nights > 0 ? $0 : nil }
        }
        if !rec.isDebug { writeAutoBackup() }
        let entry = rec.isDebug || rec.isNap ? nil
            : Economy.ledger(coreResults(), calendar: calendar, breaks: streakBreaks, catalog: catalog)
                .last { $0.key.description == rec.keyString }
        lastStreakBonus = entry?.streakBonus ?? 0
        lastUndisturbedBonus = entry?.undisturbedBonus ?? 0
        phase = .result
        if servicesEnabled {
            switch result.outcome {
            case .complete where rec.isNap:
                fx("fx_sparkle")
                say(.napDone, after: Motion.t(1.2))
            case .complete:                                  // the WOW (phase UI-2): fanfare, coins, voice
                fx("fx_wow")
                fx("fx_coins", after: Motion.t(1.1))
                say(.buildingDone, after: Motion.t(2.4))
            case .unfinished: fx("building_unfinished")
            default: fx("building_ruin")
            }
            if levelUp != nil { fx("level_up", after: Motion.t(3.2)) }
            if !newAchievements.isEmpty { fx("fx_sparkle", after: Motion.t(1.8)) }
        }
    }

    private func save() { try? context.save() }
}
