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
    /// "Go to sleep early" is possible right now (phase EARLY): the window is in [bedtime − 3 h, start opens) and
    /// nothing else blocks a start. Set by `refresh`.
    private(set) var canStartEarly = false
    /// Tonight's night is already in the records (it ran, or was cancelled / collapsed), so it cannot be started again.
    private(set) var tonightPlayed = false

    var settings: AppSettings {
        didSet {
            // the user changed a setting (not Health or sync, which are per device): stamp it, the newest settings win a
            // merge of the devices (phase SYNC). A merge, a launch argument or an unchanged value never stamps – and
            // neither does a device that has not yet finished its first read of the sync place (first contact: its
            // settings must not overwrite those of the device the user already has). Assigning inside the observer does
            // not run it again.
            if !applyingMergedSettings {
                let changed = !settings.hasSameSyncedValues(as: oldValue)
                if changed, sync.firstReadDone { settings.changedAt = clock.now }
                if settings.usesSync != oldValue.usesSync { sync.switchChanged() }   // watching starts / ends with the switch
                if changed || settings.usesSync != oldValue.usesSync { sync.noteLocalChange() }
            }
            settings.save()
            // during a night, Settings switch the sound that is playing (a stopped sound stays stopped)
            if active != nil, sleepSoundPlaying,
               settings.ambience != oldValue.ambience || settings.volume != oldValue.volume {
                sleepSound = settings.ambience == .silence ? nil : (settings.ambience, sleepSound?.endsAt)
                if servicesEnabled { audio.setVolume(settings.volume, ambience: settings.ambience) }
            }
            guard servicesEnabled else { return }
            if settings.schedule != oldValue.schedule { rescheduleReminders() }
        }
    }

    /// True while a merge assigns the other device's settings (they keep their own change stamp).
    @ObservationIgnored private var applyingMergedSettings = false

    /// Phase SYNC: reads, merges and writes the files of the user's devices at the right moments (never during a night).
    let sync: SyncEngine

    let catalog: Catalog?
    let audio = AudioKeeper()
    private let context: ModelContext
    /// ModelContext does not retain its container – keep it alive as long as the model lives.
    private let container: ModelContainer
    private let calendar = Calendar.current
    private let monitor = LifecycleMonitor()
    private let lockLab = LockLab()
    private var alarmTask: Task<Void, Never>?
    private var ticker: Timer?

    static let debugGrace: TimeInterval = 15

    /// Dev aid – launch arguments (e.g. via `xcrun devicectl device process launch … sk.zrebec.sleephole -clearNights`):
    ///   -clearNights                  delete all night records
    ///   -forgiveNight                 forgive everything out of the app so far in the running night (after a fault of the app)
    ///   -revokeForgiveness            judge the latest finalized night that was forgiven as if it never had been (re-derives its outcome)
    ///   -bedtime HH:MM -wake HH:MM    set the schedule
    ///   -ambience silence|brown       set the night sound
    ///   -startTestNight               immediately start a 4-min debug night (screenshots in the simulator)
    ///   -focusWakeCode                DEBUG: focus the wake-code field when the confirm panel appears (shows the keyboard in the simulator)
    ///   -lockLab                      DEBUG nights only: record the lock-screen lab (Darwin / UIKit signals, motion, a line
    ///                                 per second) to Application Support/lock-lab.log – pull it with devicectl
    ///   -startNap                     screenshots: open the nap window around now and start a nap
    ///   -testNightCounts              with -startTestNight: a real night (pays; "another building" costs coins)
    ///   -testNightGrace S             with -startTestNight: the setup lasts S seconds (default 15)
    ///   -forceBuilding had            DEBUG builds only, with -startTestNight: tonight's building is one already in the town (the newest
    ///                                 finished night's), so the "New in town" label is absent (screenshots, 11b6b)
    ///   -testNightMinutes N           with -startTestNight: a debug night of N minutes (> 30 keeps the normal night layout)
    ///   -seedNights N                 SIMULATOR ONLY: replace all nights with N fake finished nights
    ///   -showResult [unfinished]      SIMULATOR ONLY, with -seedNights: show the result screen of the newest complete seeded night
    ///                                 (with `unfinished`: of the newest unfinished one, which was confirmed 30 min after the alarm)
    ///   -openTab town|boxes           start on the Mesto / Boxes tab
    ///   -openBoxContents [postcards|decorations|cat|skies]   DEBUG only: open Settings > Developer > Box contents at once (11b5e)
    ///   -boxCatFull                   DEBUG only: the Box contents cat starts with a full outfit (first head, face and bed item)
    ///   -boxCatAsleep                 DEBUG only: the Box contents cat starts asleep
    ///   -showAllDecorations           DEBUG only: the Town view shows all 12 town decorations (11b5c; screenshots, preview)
    ///   -nightSky sky-02              DEBUG only: show that night sky (sky-01 … sky-04, 11b5d) on Today and the Town tab
    ///   -skyClock 12.5|still          DEBUG only: pin the night sky effect's clock (seconds) / show its frozen Reduce Motion frame
    ///   -townFit                      screenshots: the Town view frames the built-up part of the town (no zoom cap)
    ///   -lang en|sk                   switch the UI language (stored like the Settings picker)
    ///   -theme system|light|dark      set the appearance (Settings → Theme)
    ///   -screenshot                   no permission alert, no first-run guide (use with a pulled store, tools/sim_shot.sh)
    ///   -thenTab 1|island|abandon|pause|warning   4 s after launch: select a tab / open the Town tab / cancel the
    ///                                 running night and close its result / start a pause once the setup is over
    ///   -thenTab buybox               DEBUG only: 5 s after launch (4 s, then the tab opens and 1 s more) buy today's box (with -boxSeed N: that draw seed; needs a
    ///                                 complete night of today – see -seedTodayNight)
    ///   -seedTodayNight complete|unfinished|none   SIMULATOR ONLY, with -seedNights: force the newest seeded night (the one
    ///                                 with today's key) to be complete / unfinished / absent (shop screenshots, 11b4a)
    ///   -seedBoxBefore                SIMULATOR ONLY, with -seedNights: an earlier box (price 700, no prize coins) three days ago,
    ///                                 so the shop shows the 1 000 🪙 reserve line (11b4a screenshots)
    ///   -seedCollection               SIMULATOR ONLY, with -seedNights: eleven earlier boxes (4–14 days ago) giving 3 postcards, 2 town
    ///                                 decorations, 3 cat accessories (nightcap, sunglasses, rug), 2 night skies and a silver joker
    ///                                 (collection screenshots, 11b4c)
    ///   -openCollection postcards|postcard|decorations|cat|skies|jokers   DEBUG only, Boxes tab: open that collection screen / the
    ///                                 first postcard / the joker sheet at once (screenshots, 11b4c)
    ///   -boxScroll / -boxConfirm      DEBUG only, Boxes tab: scroll to the odds list / open the buy confirmation (screenshots)
    ///   -thenTab reroll               (with a paying night) draw another building once, 4 s after launch
    ///   -rerollDialog                 open the "Another building" confirmation 2 s after the night screen shows
    ///   -expiresIn HOURS              pretend the provisioning profile runs out then (AppExpiry)
    ///   -mute                         silence every sound (alarm, effects) – for screenshots of a night's end
    ///   -buddy awake|asleep           force the sleep buddy's state (screenshots)
    ///   -buddyReaction purr|arch|wink show that tap reaction's hold frame (hearts / sparkle too) on Today (screenshots)
    ///   -skyCity "Name,lat,lon"       set the city of the real sky for this run (e.g. "Bratislava,48.1486,17.1077")
    ///   -skyDate YYYY-MM-DD           pin the sky's day (the moon's phase follows the date)
    ///   -skyTime HH:MM                pin the sky's time of day; -skyArc 0.3 / -skyBody sun|moon|none / -skyMoon 0.5
    ///                                 force the drawn arc / body / moon's lit fraction (see `SkyOverrides`)
    ///   -cityQuery Brat               pre-fill Settings → Sky → city so the real Apple Maps search runs
    ///   -scrollTo sky                 scroll Settings to the Sky section (also: sounds, notifications, health, icloud)
    ///   -systemAlarm allowed|denied|notAsked   SIMULATOR ONLY: pretend that consent for the system alarm (a silent
    ///                                 stand-in – nothing is ever scheduled with AlarmKit in the simulator)
    ///   -weather clear|cloudy|fog|rain|heavyRain|thunder|snow, -weatherTemp N, -weatherSnowCover   simulate the weather
    ///   -weatherWind N                 with -weather: the simulated wind in m/s, from the west (default 0)
    ///   -weatherSource met            ask MET Norway live instead of the launch's default source (simulator and device,
    ///                                 never under test)
    ///                                 for this run (see `WeatherSimulation`); -openWeatherTest opens Developer → Weather test
    ///   -timeSensitive off|on         SIMULATOR ONLY: pretend that iOS's "Time Sensitive Notifications" switch is off / on
    ///   -scheduleState open|week|locked   DEBUG builds only: force the change-week state shown in Settings (screenshots)
    ///   -sleepSim N                   use a simulated sleep source (Health stand-in): asleep N minutes after the build
    ///                                 start, a staged night (default 18 when N is missing); switch "Apple Health" on to read it
    ///   -selectChartNight K           Stats: select the night K places before the newest on the sleep chart (0 = newest)
    ///   -healthOn                     switch Settings → Apple Health on for this run (with -sleepSim: seeded nights get sleep data)
    ///   -openSystemAlarmTest          with -openTab settings: open Developer → System alarm test at once
    ///   -openSyncTest                 DEBUG builds only, with -openTab settings: open Developer → Sync test at once
    ///   -syncFolder PATH              DEBUG builds only, phase SYNC: sync with the other devices through this plain folder
    ///                                 (one file per device; without it a real iPhone uses its iCloud container, the
    ///                                 simulator syncs with nobody)
    ///   -syncDevice NAME              with -syncFolder: this launch's device id (the file is NAME.json; default: the
    ///                                 install's random id)
    static func applyLaunchArguments(to settings: inout AppSettings, context: ModelContext,
                                     args: [String] = DevArgs.list) {
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
        if args.contains("-healthOn") { settings.usesHealth = true }
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
                                            history: history, rng: &rng)
                if e.kind == .roadLit { town.upgradeStreets() } else { town.place(e) }
                history.append(e.id)
                let rec = NightRecord(window: w, buildingId: e.id, isDebug: false, setupGrace: 300)
                rec.append(.started, at: w.bedtime)
                var roll = Int.random(in: 0..<10, using: &rng)
                if i == n - 1, let forced = value("-seedTodayNight") {   // the newest seeded night carries today's key
                    if forced == "none" { continue }
                    roll = forced == "unfinished" ? 0 : 5
                }
                rec.append(.confirmed, at: w.wake + (roll == 0 ? 30 * 60 : 60))
                rec.outcomeRaw = roll == 9 ? Outcome.ruins.rawValue : roll == 0 ? Outcome.unfinished.rawValue
                    : Outcome.complete.rawValue
                rec.finalizedAt = w.wake + 120
                context.insert(rec)
            }
            if args.contains("-seedBoxBefore") {
                let key = NightKey(date: cal.date(byAdding: .day, value: -3, to: Date())!, calendar: cal)
                context.insert(BoxRecord(BoxPurchase(id: "seed-box", at: Date().addingTimeInterval(-3 * 86400), nightKey: key,
                                                     price: 700, seed: 1, tableVersion: 1, prize: .coins, payout: 0)))
            }
            if args.contains("-seedCollection") {                 // 11b4c screenshots: a little of everything, won on earlier days
                let prizes: [BoxPrize] = [
                    .collectible(.postcard, id: "postcard-03"), .collectible(.postcard, id: "postcard-07"),
                    .collectible(.postcard, id: "postcard-12"), .collectible(.decoration, id: "decoration-02"),
                    .collectible(.decoration, id: "decoration-05"), .collectible(.accessory, id: "nightcap"),
                    .collectible(.accessory, id: "sunglasses"), .collectible(.accessory, id: "rug"),
                    .collectible(.sky, id: "sky-01"), .collectible(.sky, id: "sky-03"), .joker(.silver),
                ]
                for (i, prize) in prizes.enumerated() {
                    let ago = 4 + i                                // 4 … 14 days ago: before tonight, so a joker is usable
                    let at = Date().addingTimeInterval(-Double(ago) * 86400)
                    let key = NightKey(date: cal.date(byAdding: .day, value: -ago, to: Date())!, calendar: cal)
                    context.insert(BoxRecord(BoxPurchase(id: "seed-collection-\(i)", at: at, nightKey: key, price: 400 + 10 * i,
                                                         seed: UInt64(i + 1), tableVersion: 1, prize: prize, payout: 0)))
                }
            }
            try? context.save()
        }
        #endif
        settings.save()
    }

    #if DEBUG
    /// `-scheduleState open|week|locked` → the forced change-week state (screenshots); nil without the argument.
    static func launchScheduleState(args: [String] = DevArgs.list) -> SchedulePolicy.State? {
        guard let i = args.firstIndex(of: "-scheduleState"), args.indices.contains(i + 1) else { return nil }
        let cal = Calendar.current
        let now = Date()
        switch args[i + 1] {
        case "open": return .open
        case "week":
            return .changeWeek(lastDay: NightKey(date: now, calendar: cal).adding(days: 4, calendar: cal))
        case "locked":
            let free = NightKey(date: now, calendar: cal).adding(days: 23, calendar: cal)
            return .locked(lastDay: free.adding(days: -1, calendar: cal), freeFrom: free)
        default: return nil
        }
    }
    #endif

    /// `-sleepSim [minutes]` → the simulated sleep source; nil without the argument.
    static func launchSleepSource(args: [String] = DevArgs.list) -> (any SleepSource)? {
        guard let i = args.firstIndex(of: "-sleepSim") else { return nil }
        let minutes = args.indices.contains(i + 1) ? Double(args[i + 1]) : nil
        return SimulatedSleepSource(fallAsleepMinutes: minutes ?? 18)
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

    static func launchLanguage(args: [String] = DevArgs.list) -> AppLanguage? {
        args.firstIndex(of: "-lang").flatMap { args.indices.contains($0 + 1) ? AppLanguage(rawValue: args[$0 + 1]) : nil }
    }

    /// Injected time (tests use `FakeClock`).
    let clock: any Clock
    /// false in unit tests: no audio, lifecycle monitor, notifications, timers or sounds.
    let servicesEnabled: Bool
    /// The system alarm (phase F6b). The default does nothing: only `SleepHoleApp` passes the real one.
    let systemAlarm: any SystemAlarm
    /// Keeps the app running while the lock-screen warning alarm rings (B28). The default does nothing: only
    /// `SleepHoleApp` passes the real UIKit one.
    let keepAlive: any KeepAlive
    /// Where the real fall-asleep time comes from (phase HEALTH). The default has no data; `-sleepSim` picks a simulated one.
    let sleepSource: any SleepSource
    /// The weather over the owner's city (TOWN-W); `SleepHoleApp` passes the launch's store, the default has no source.
    let weather: WeatherStore
    /// Asks whether iOS's "Time Sensitive Notifications" switch is off (the default never does – tests stay off the system).
    private let timeSensitiveCheck: @MainActor () async -> Bool
    /// Health cannot be read while the phone is locked (protected data); tests pass a fake.
    private let protectedDataAvailable: @MainActor () -> Bool
    /// True while notifications are allowed but their Time Sensitive switch is off (warning on Today and in Settings).
    private(set) var timeSensitiveOff = false

    func refreshTimeSensitive() async { timeSensitiveOff = await timeSensitiveCheck() }
    private let defaults: UserDefaults
    /// When the phone last booted – a closure of the app before that was a restart, not the owner (R4). Tests pass a
    /// fake to simulate a restart.
    private let bootDate: () -> Date?

    init(context: ModelContext, catalog: Catalog?, clock: any Clock = SystemClock(),
         settings initialSettings: AppSettings? = nil, servicesEnabled: Bool = true,
         systemAlarm: any SystemAlarm = NoSystemAlarm(), keepAlive: any KeepAlive = NoKeepAlive(), sleepSource: (any SleepSource)? = nil,
         weather: WeatherStore? = nil, timeSensitiveCheck: @escaping @MainActor () async -> Bool = { false },
         protectedDataAvailable: @escaping @MainActor () -> Bool = { UIApplication.shared.isProtectedDataAvailable }, defaults: UserDefaults = .standard,
         bootDate: @escaping () -> Date? = { DeviceBoot.date() },
         syncTransport: any SyncTransport = NoSyncTransport(), syncDelay: TimeInterval = 2, syncGuideWait: TimeInterval = 4,
         syncRetryDelay: @escaping (Int) -> TimeInterval = SyncEngine.standardRetryDelay) {
        self.context = context
        self.container = context.container
        self.catalog = catalog
        self.clock = clock
        self.servicesEnabled = servicesEnabled
        self.systemAlarm = systemAlarm
        self.keepAlive = keepAlive
        self.sleepSource = sleepSource ?? Self.launchSleepSource() ?? NoSleepSource()
        self.weather = weather ?? WeatherStore(source: NoWeather(), defaults: defaults)
        self.timeSensitiveCheck = timeSensitiveCheck
        self.protectedDataAvailable = protectedDataAvailable
        self.defaults = defaults
        self.bootDate = bootDate
        self.sync = SyncEngine(transport: syncTransport, defaults: defaults, settleDelay: syncDelay, guideWait: syncGuideWait,
                               retryDelay: syncRetryDelay)
        let memory = SystemAlarmMemory(defaults: defaults)
        systemAlarmAt = memory.at
        systemAlarmIsSafety = memory.isSafety
        var settings = initialSettings ?? AppSettings.load()
        if initialSettings == nil { Self.applyLaunchArguments(to: &settings, context: context) }
        self.settings = settings
        self.window = settings.schedule.window(containing: clock.now, calendar: .current)
        loadProgress()
        #if DEBUG
        if initialSettings == nil { debugScheduleState = Self.launchScheduleState() }
        // `-pendingSchedule`: a pending (applies-from-tomorrow) change, for screenshots; nothing is saved.
        if initialSettings == nil, DevArgs.list.contains("-pendingSchedule") {
            var later = self.settings.schedule; later.bedtime = TimeOfDay(23, 0)
            self.settings.pendingSchedule = PendingSchedule(
                schedule: later, fromNight: NightKey(date: clock.now, calendar: .current).adding(days: 3, calendar: .current))
        }
        #endif
        sync.attach(self)
        if initialSettings == nil, let lang = Self.launchLanguage() { language = lang }
        resumeActiveNight()
        if DevArgs.list.contains("-forgiveNight") { forgiveNight() }
        if DevArgs.list.contains("-revokeForgiveness") { revokeForgiveness() }
        tidySystemAlarm(now: clock.now, atLaunch: true)
        rebuildTown()
        refresh()
        #if targetEnvironment(simulator)
        let wantedResult: Outcome = DevArgs.list.firstIndex(of: "-showResult").map {
            DevArgs.list.indices.contains($0 + 1) && DevArgs.list[$0 + 1] == "unfinished" } == true ? .unfinished : .complete
        if DevArgs.list.contains("-showResult"), active == nil, initialSettings == nil,
           let rec = realResults().last(where: { $0.outcome == wantedResult }) {       // store screenshots: the morning screen
            let entry = Economy.ledger(coreResults(), calendar: calendar, breaks: streakBreaks, catalog: catalog, boxes: boxes())
                .last { $0.key.description == rec.keyString }
            shownResult = rec
            lastReward = entry?.coins ?? 0
            lastReceipt = entry.flatMap { Economy.Receipt($0, calmTotal: rec.result?.calmHoursTotal) }
            if DevArgs.list.contains("-calmDemo"), let r = lastReceipt {     // screenshots: a night with 7 of 8 calm hours
                var lines = r.lines.filter { if case .calmHours = $0.kind { false } else { true } }
                let calm = Economy.Receipt.Line(kind: .calmHours(calm: 7, total: 8), amount: 7 * Economy.calmHourBonus)
                lines.insert(calm, at: min(lines.count, lines.firstIndex { if case .streak = $0.kind { true } else { false } } ?? lines.count))
                lastReceipt = Economy.Receipt(lines: lines)
                lastReward = lines.reduce(0) { $0 + $1.amount }
            }
            phase = .result
        }
        #endif
        guard servicesEnabled else { return }
        if DevArgs.list.contains("-startTestNight"), active == nil {
            let a = DevArgs.list
            let minutes = a.firstIndex(of: "-testNightMinutes").flatMap { a.indices.contains($0 + 1) ? Double(a[$0 + 1]) : nil }
            let grace = a.firstIndex(of: "-testNightGrace").flatMap { a.indices.contains($0 + 1) ? Double(a[$0 + 1]) : nil }
            startTestNight(minutes: minutes ?? 4, grace: grace ?? AppModel.debugGrace)
            #if DEBUG
            if DevArgs.list.contains("-testNightCounts") { nextTestNightCounts = true }    // a real (paying) night
            #endif
            startNight()
        }
        if DevArgs.list.contains("-startNap"), active == nil { startNap() }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    // MARK: - queries

    /// Bumped after every write to the store. SwiftData rows are not observed by SwiftUI, and `refresh()` assigns
    /// equal values (no notification), so every fetch helper below reads this: a save redraws every view whose
    /// value is derived from stored rows (streak, coins, jokers, stats, the buddy's lines …).
    private(set) var dataRevision = 0

    // MARK: derived values, cached (B8)

    /// Every input of the cached values below: the stored rows (`dataRevision` – every write goes through `save()` or
    /// bumps it itself), the Health reads, the night in `window` and today's key (the day rolling over changes the last
    /// night that is over), and the town (the achievements read its repairs). The calendar and the catalog are constants
    /// of the model. A change of any part drops everything cached.
    private struct DerivedKey: Equatable {
        var revision: Int, sleepReads: Int, townVersion: Int
        var window: NightKey, today: NightKey
    }

    private struct Derived {
        var key: DerivedKey?
        var jokerState: (results: [NightResult], uses: [JokerUse])?
        var coinsEarned: Int?, streak: Int?
        var stats: StatsSummary?
    }

    /// Not observed: filling the cache inside a view body must not invalidate that view. The reads of `dataRevision`
    /// and the others in `validateDerived()` still register the dependencies, so views redraw exactly as before.
    @ObservationIgnored private var derived = Derived()

    private func validateDerived() {
        let key = DerivedKey(revision: dataRevision, sleepReads: sleepReads, townVersion: townVersion,
                             window: window.key, today: NightKey(date: clock.now, calendar: calendar))
        if derived.key != key { derived = Derived(key: key) }
    }

    func records() -> [NightRecord] {
        _ = dataRevision
        return (try? context.fetch(FetchDescriptor<NightRecord>(sortBy: [SortDescriptor(\.bedtime)]))) ?? []
    }

    /// Finalized real nights, oldest first (debug nights never count).
    func realResults() -> [NightRecord] {
        records().filter { !$0.isDebug && !$0.isNap && $0.isFinalized }
    }

    /// The "New in town" label of the setup (11b6b): the picker's own notion of fresh, see `BuildingPicker.isNew`.
    func isNewInTown(_ rec: NightRecord) -> Bool {
        !rec.isNap && !rec.buildingId.isEmpty
            && BuildingPicker.isNew(rec.buildingId, history: realResults().map(\.buildingId))
    }

    // MARK: - sleep from the source (phase HEALTH)

    /// A night's sleep is read again until this long after its wake time (a watch may sync late).
    static let sleepRereadUntil: TimeInterval = 3 * 86400
    /// ...but not more often than this.
    static let sleepRereadEvery: TimeInterval = 3600

    /// The switch in Settings → Apple Health: on = ask for access once (the iOS sheet), then read. Off keeps what is stored.
    func setHealth(on: Bool) async {
        settings.usesHealth = on
        sync.noteLocalChange()                       // the switch's position travels in the sync file (no stamp: not a setting)
        guard on else { return }
        _ = await sleepSource.requestAccess()
        await refreshSleepIfIdle()
    }

    /// `refreshSleep` at a safe moment only: never while a night or nap runs, never while the phone is locked.
    func refreshSleepIfIdle() async {
        guard active == nil, protectedDataAvailable() else { return }
        await refreshSleep(now: clock.now)
    }

    /// Bumped after every read that stored something, so a view showing `sleepStatus` redraws (SwiftData rows are not observed).
    private(set) var sleepReads = 0

    /// Nights with a stored fall-asleep time of all finalized real nights, and whether any was read at all.
    var sleepStatus: (withData: Int, total: Int, anyRead: Bool) {
        _ = sleepReads
        let nights = realResults()
        return (nights.filter { $0.fellAsleepAt != nil }.count, nights.count, nights.contains { $0.sleepReadAt != nil })
    }

    /// How many reads are running right now (a count: a read can start while another one is still waiting for Health).
    private(set) var sleepReadsRunning = 0
    var isReadingSleep: Bool { sleepReadsRunning > 0 }

    /// The "Read sleep again" button in Settings → Apple Health is shown while the switch is on and the source can be read.
    var showsReadSleepAgain: Bool { settings.usesHealth && sleepSource.isAvailable }
    /// … and works while no night or nap runs and no read is already going on.
    var canReadSleepAgain: Bool { showsReadSleepAgain && active == nil && !isReadingSleep }

    /// The button: every finalized real night is read once more, also those past their re-read window.
    func readSleepAgain() async {
        guard canReadSleepAgain else { return }
        await refreshSleep(now: clock.now, force: true)
    }

    /// Asks the sleep source about every finalized real night that is due and stores what it says. Does nothing while
    /// Health is switched off or the source is not available. A source that throws leaves that night untouched.
    /// `force` reads every night, whatever its read time and age (the Settings button) – the stored dates stay as they are
    /// until the read stores new ones.
    func refreshSleep(now: Date, force: Bool = false) async {
        guard settings.usesHealth, sleepSource.isAvailable else { return }
        sleepReadsRunning += 1
        defer { sleepReadsRunning -= 1 }
        var changed = false
        for night in realResults() {
            // a night stored under another rule version (nil = none) is read again, whatever its age
            if !force, let read = night.sleepReadAt, night.sleepRuleVersion == SleepAnalysis.ruleVersion {
                guard read < night.wake.addingTimeInterval(Self.sleepRereadUntil),
                      now.timeIntervalSince(read) >= Self.sleepRereadEvery else { continue }
            }
            let w = SleepAnalysis.window(nightStart: night.startedAt ?? night.bedtime, wake: night.wake,
                                         confirmedAt: night.confirmedAt)
            guard let samples = try? await sleepSource.samples(from: w.from, to: w.to) else { continue }
            let list = SleepAnalysis.sources(samples: samples, from: w.from, to: w.to)
            let summary = SleepAnalysis.chosen(from: list).map {
                SleepSummary(fellAsleepAt: $0.fellAsleepAt, wokeAt: $0.wokeAt, asleepSeconds: $0.asleepSeconds,
                             awakeSeconds: $0.awakeSeconds, source: $0.name, hasStages: $0.hasStages)
            }
            night.fellAsleepAt = summary?.fellAsleepAt
            night.sleepEndedAt = summary?.wokeAt
            night.asleepSeconds = summary?.asleepSeconds
            night.awakeSeconds = summary?.awakeSeconds
            night.sleepSourceName = summary?.source
            night.sleepReadAt = now
            night.sleepSourcesData = try? JSONEncoder().encode(list)
            night.sleepRuleVersion = SleepAnalysis.ruleVersion
            changed = true
        }
        if changed { try? context.save(); dataRevision += 1; sleepReads += 1 }
    }

    /// The real results as every rule sees them: nights protected by a joker are `.excused` (owner 2026-10-02).
    func coreResults() -> [NightResult] { jokerState.results }

    /// Jokers in effect (switched on + automatic bronze) and the protected results.
    var jokerState: (results: [NightResult], uses: [JokerUse]) {
        validateDerived()
        if let cached = derived.jokerState { return cached }
        let value = computeJokerState()
        derived.jokerState = value
        return value
    }

    private func computeJokerState() -> (results: [NightResult], uses: [JokerUse]) {
        Jokers.apply(results: realResults().compactMap(\.result), manual: jokerRecords().compactMap(\.use),
                     lastNight: window.key.adding(days: -1, calendar: calendar), calendar: calendar,
                     breaks: streakBreaks, boxes: boxes())
    }

    func jokerRecords() -> [JokerRecord] {
        _ = dataRevision
        return (try? context.fetch(FetchDescriptor<JokerRecord>(sortBy: [SortDescriptor(\.at)]))) ?? []
    }

    /// The night a joker switched on now would start with (last night if it went wrong, else tonight).
    var jokerFirstNight: NightKey {
        let last = window.key.adding(days: -1, calendar: calendar)
        return Jokers.firstNight(tonight: window.key, lastNightResult: coreResults().last { $0.key == last },
                                 calendar: calendar)
    }

    /// - Parameter fromBox: the id of the box whose joker would be spent (no coins, not the month's own slot).
    func jokerBlock(_ tier: JokerTier, fromBox boxId: String? = nil) -> Jokers.Block? {
        Jokers.block(tier, firstNight: jokerFirstNight, uses: jokerState.uses, coins: coins,
                     boxId: boxId, boxes: boxes(), calendar: calendar)
    }

    /// The jokers won from parcels that can be switched on now (valid, not used), bronze first.
    func heldBoxJokers() -> [BoxPurchase] {
        let held = Boxes.heldJokers(boxes: boxes(), uses: jokerState.uses, at: jokerFirstNight, calendar: calendar)
        return JokerTier.allCases.compactMap { held[$0] }
    }

    /// The joker protecting tonight or a night around now, if any (shown on Today).
    var activeJoker: JokerUse? {
        let tonight = window.key
        return jokerState.uses.last {
            $0.covers(tonight, calendar: calendar) || $0.covers(tonight.adding(days: -1, calendar: calendar), calendar: calendar)
        }
    }

    func useJoker(_ tier: JokerTier, fromBox boxId: String? = nil) {
        guard jokerBlock(tier, fromBox: boxId) == nil else { return }
        if tier.price > 0, boxId == nil { spend(tier.price, reason: "joker-\(tier.rawValue)") }
        context.insert(JokerRecord(at: clock.now, tier: tier, firstNight: jokerFirstNight, boxId: boxId))
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
        Economy.ledger(coreResults(), calendar: calendar, breaks: streakBreaks, catalog: catalog, boxes: boxes())
            .last { $0.key == key }?.coins
    }

    /// The results Stats averages over. A counted test night (`bonus-…`) stays a night of the streak, the town and the
    /// coins, but its clock times are artificial (a daytime start), so they never enter the TIME statistics –
    /// average start / getting up, regularity, falling asleep, sleep length (B13).
    func statsInput() -> [NightResult] {
        coreResults().map { $0.isTestNight == true ? $0.withoutClockTimes : $0 }
    }

    /// Everything for the Štatistiky tab.
    var stats: StatsSummary {
        validateDerived()                           // reads `sleepReads`: a finished Health read redraws Stats
        if let cached = derived.stats { return cached }
        let value = Stats.summary(statsInput(), today: NightKey(date: clock.now, calendar: calendar),
                                  calendar: calendar, breaks: streakBreaks, catalog: catalog, boxes: boxes())
        derived.stats = value
        return value
    }

    /// Coin balance 🪙: earned (replayed from the real nights, naps and achievements) − spent (`CoinSpend`).
    /// Never negative: two devices may have spent the same coins before they synced (phase SYNC).
    var coins: Int { max(0, coinsEarned - coinsSpent + Boxes.coinDelta(boxes())) }

    var coinsEarned: Int {
        validateDerived()
        if let cached = derived.coinsEarned { return cached }
        let value = computeCoinsEarned()
        derived.coinsEarned = value
        return value
    }

    private func computeCoinsEarned() -> Int {
        Economy.earned(coreResults(), calendar: calendar, breaks: streakBreaks, catalog: catalog, boxes: boxes())
            + napResults().compactMap(\.outcome).reduce(0) { $0 + NapPlan.reward($1) }
            + Achievements.coins(achievements)
    }

    var coinsSpent: Int { spends().reduce(0) { $0 + $1.amount } }          // one small fetch: not cached

    func spends() -> [CoinSpend] {
        _ = dataRevision
        return (try? context.fetch(FetchDescriptor<CoinSpend>(sortBy: [SortDescriptor(\.at)]))) ?? []
    }

    /// The mystery boxes bought so far, oldest first (one small fetch, never cached). A record this version cannot read is skipped.
    func boxes() -> [BoxPurchase] {
        _ = dataRevision
        return ((try? context.fetch(FetchDescriptor<BoxRecord>(sortBy: [SortDescriptor(\.at)]))) ?? []).compactMap(\.purchase)
    }

    private func spend(_ amount: Int, reason: String) {
        context.insert(CoinSpend(at: clock.now, amount: amount, reason: reason))
        save()
    }

    /// Schedule changes, oldest first; the ones that were not free reset the streak (`streakBreaks`).
    func scheduleChanges() -> [ScheduleChange] {
        _ = dataRevision
        return (try? context.fetch(FetchDescriptor<ScheduleChange>(sortBy: [SortDescriptor(\.at)]))) ?? []
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
                            calendar: calendar, breaks: streakBreaks, catalog: catalog, boxes: boxes())
    }

    func journalWeek(monday: NightKey) -> WeekSummary {
        WeeklyJournal.week(monday: monday, results: coreResults(),
                           naps: napResults().compactMap(\.result), calendar: calendar, breaks: streakBreaks,
                           catalog: catalog, boxes: boxes())
    }

    /// Monday of the week we are in now.
    var currentMonday: NightKey { WeeklyJournal.monday(of: NightKey(date: clock.now, calendar: calendar), calendar: calendar) }

    /// The week that just ended, shown once on the result screen (Monday morning after "I'm up").
    private(set) var finishedWeek: WeekSummary?
    /// What the night in `shownResult` paid (reward + bonuses + achievements).
    private(set) var lastReward = 0
    /// The coin receipt of the night in `shownResult` (11a); nil for naps, for nights that paid nothing and whenever
    /// its lines would not add up to `lastReward`.
    private(set) var lastReceipt: Economy.Receipt?

    /// Current 🔥 streak: complete nights in a row up to the most recent night that could be finished.
    var streak: Int {
        validateDerived()
        if let cached = derived.streak { return cached }
        let results = coreResults()
        let lastPossible = window.key.adding(days: -1, calendar: calendar)
        let last = max(results.map(\.key).max() ?? lastPossible, lastPossible)
        let value = Progression.currentStreak(results, lastNight: last, calendar: calendar, breaks: streakBreaks)
        derived.streak = value
        return value
    }

    /// The sleep buddy's AVAILABLE sentences now (phase TALK); the bubble draws from them at random (`BuddyBag`).
    func buddyLines(now: Date) -> [BuddyLine] {
        let town = townSnapshot ?? buildSnapshot()
        let results = coreResults()
        let last = results.last.map { r -> BuddyTalkInput.LastNight in
            let b = town.buildings.first { $0.nightKey == r.key }
            let id = r.outcome == .complete || r.outcome == .unfinished ? b?.buildingId : r.buildingId
            return BuddyTalkInput.LastNight(key: r.key, outcome: r.outcome, buildingId: id,
                                            residents: r.outcome == .complete ? b.map(Population.residents(of:)) ?? 0 : 0)
        }
        var now = now
        #if DEBUG
        // dev aid: the sentences follow `-skyDate` like the sky does
        if let (y, mo, d) = LivingSky.pinnedDay {
            var parts = calendar.dateComponents([.hour, .minute], from: now)
            (parts.year, parts.month, parts.day) = (y, mo, d)
            now = calendar.date(from: parts) ?? now
        }
        #endif
        let south = settings.city.map { $0.place.latitude < 0 }
            ?? Sky.isSouthernRegion(Locale.current.region?.identifier)
        return BuddyTalk.lines(BuddyTalkInput(
            now: now, calendar: calendar, town: town, lastNight: last, streak: streak,
            bestStreak: Progression.bestStreak(results, calendar: calendar, breaks: streakBreaks),
            builtNights: builtNights, unlockedMaxLevel: Progression.unlockedMaxLevel(builtBefore: builtNights),
            nextBedtime: window.bedtime > now ? window.bedtime : nil, southernHemisphere: south))
    }

    /// Dev aid: `-buddyLine N` opens the buddy's bubble with the N-th available sentence (tier order, modulo the count;
    /// screenshots). Taps afterwards are random as usual.
    static let forcedBuddyLine: Int? = {
        let a = DevArgs.list
        guard let i = a.firstIndex(of: "-buddyLine"), a.indices.contains(i + 1) else { return nil }
        return Int(a[i + 1])
    }()

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
    /// Identifies the newest building (its night key) – the camera glides to it once per new one (B30).
    private(set) var townNewest: String?

    /// The town decorations won from boxes, in the order won; with the debug flag `-showAllDecorations` all twelve.
    private func ownedDecorations() -> [String] {
        #if DEBUG
        if DevArgs.list.contains("-showAllDecorations") { return BoxCatalog.ids(.decoration) }
        #endif
        return Boxes.ownedInOrder(.decoration, boxes: boxes())
    }

    func rebuildTown() {
        guard let catalog else { return }
        let snap = buildSnapshot()
        townSnapshot = snap
        townRender = TownRender.build(snap, catalog: catalog, today: NightKey(date: clock.now, calendar: calendar),
                                      calendar: calendar, decorations: ownedDecorations())
        townFocus = snap.buildings.last.map { IsoProjection.scenePoint(x: $0.placement.centre.x, z: $0.placement.centre.z) }
        townNewest = snap.buildings.last.map { $0.nightKey.description }
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
                              setupGrace: NapPlan.rules.setupGrace, isNap: true,
                              strictLockScreen: settings.strictMode,
                              lockScreenTolerance: SleepRules.lockScreenToleranceNow,
                              accidentalTolerance: SleepRules.accidentalToleranceNow)
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
    /// The first-run guide is due: not finished, and not held back while a fresh install makes its first read of the
    /// sync place (a guide finished on another device is then not shown at all – phase SYNC).
    var needsGuide: Bool { !onboardingDone && !sync.holdsGuide }
    private(set) var firstNightBriefed = false

    private func progress() -> UserProgress {
        _ = dataRevision
        if let p = try? context.fetch(FetchDescriptor<UserProgress>()).first { return p }
        let p = UserProgress()
        context.insert(p)
        try? context.save()          // no `dataRevision` bump: this may run inside a view body (lazy default row)
        sync.noteLocalChange()
        return p
    }

    private var loadingProgress = false

    private func loadProgress() {
        let p = progress()
        onboardingDone = p.onboardingCompletedAt != nil
        firstNightBriefed = p.firstNightBriefingAt != nil
        loadingProgress = true                       // reading the stored choice must never write the default back (B12)
        language = p.languageRaw.flatMap(AppLanguage.init(rawValue:)) ?? .fallback
        loadingProgress = false
        customTownName = p.townName
        changeWeekStart = p.changeWeekStart
        schedulePromptAnswered = p.schedulePromptMonth
    }

    // MARK: - schedule changes: the change week (owner 2026-10-15, build 8; `SchedulePolicy`)

    /// When the last change week was opened (nil = never, also for everyone who updated from before build 8).
    private(set) var changeWeekStart: Date?
    /// The lock whose end the "You can open a change week again" card was answered for (`NightKey` text).
    private(set) var schedulePromptAnswered: String?
    /// Bumped by "Adjust" on the card → the root view opens Settings.
    private(set) var settingsRequest = 0
    /// Bumped to open the Town tab (the Today island did it; `-thenTab island` still does) → RootView switches to it.
    private(set) var townRequest = 0
    func showTown() { townRequest += 1 }
    /// Bumped by the warning triangle on Today → RootView opens Settings, which scrolls to the notifications section.
    private(set) var notificationsRequest = 0
    private var notificationsScrollPending = false
    func showNotificationSettings() { notificationsRequest += 1; notificationsScrollPending = true }
    /// One-shot: true exactly once per `showNotificationSettings()` – Settings scrolls to the notifications section
    /// only then (not on every later appearance of the tab, not after a language switch).
    func takeNotificationsScroll() -> Bool {
        defer { notificationsScrollPending = false }
        return notificationsScrollPending
    }

    /// `open`, the running change week or the lock – derived from the stored date, never from a timer.
    var scheduleState: SchedulePolicy.State {
        debugScheduleState ?? SchedulePolicy.state(at: clock.now, weekStart: changeWeekStart, calendar: calendar)
    }

    /// The days a change week opened today would have (for the confirmation dialog).
    var changeWeekPlan: SchedulePolicy.Plan { SchedulePolicy.plan(opening: clock.now, calendar: calendar) }

    /// Debug-only (`-scheduleState open|week|locked`): forces the state for screenshots; nil = the real one.
    var debugScheduleState: SchedulePolicy.State?

    /// The schedule the pickers start from: the pending times when some wait for their night, else the one in effect.
    var editableSchedule: Schedule {
        var s = settings.pendingSchedule?.schedule ?? settings.schedule
        s.reminderOffsets = settings.schedule.reminderOffsets
        return s
    }

    /// The new times are applied once their night has come (the evening rule). Called by `refresh` and before a change.
    private func applyPendingScheduleIfDue(now: Date) {
        guard active == nil, let pending = settings.pendingSchedule,
              pending.isDue(at: now, current: settings.schedule, calendar: calendar) else { return }
        var s = settings
        s.schedule = Schedule(bedtime: pending.schedule.bedtime, wake: pending.schedule.wake,
                              reminderOffsets: settings.schedule.reminderOffsets)
        s.pendingSchedule = nil
        settings = s
    }

    enum ScheduleResult: Equatable {
        case unchanged
        case applied            // the new times are in effect now
        case fromTomorrow       // saved; they start with the next night (the evening rule)
        case locked             // refused: the schedule is locked
    }

    /// Saves a new schedule. Bedtime / wake follow the change week: `open` opens a week (the UI has asked first),
    /// `changeWeek` is free, `locked` refuses. A change never touches the 🔥 streak. If tonight's building can already
    /// be started the new times wait for the next night (`SchedulePolicy.startsFrom`); the reminder minutes always
    /// apply at once. During the first-run guide nothing counts (no week is opened).
    @discardableResult
    func applySchedule(_ new: Schedule) -> ScheduleResult {
        guard active == nil else { return .unchanged }
        applyPendingScheduleIfDue(now: clock.now)
        let old = settings.schedule
        let base = editableSchedule
        guard new != base else { return .unchanged }
        var s = settings
        s.schedule.reminderOffsets = new.reminderOffsets             // the reminder is free, at once
        s.pendingSchedule?.schedule.reminderOffsets = new.reminderOffsets
        guard new.bedtime != base.bedtime || new.wake != base.wake else {
            settings = s
            refresh()
            return .applied
        }
        var result = ScheduleResult.applied
        if onboardingDone {
            let state = scheduleState
            guard SchedulePolicy.allowsChange(state) else { return .locked }
            if state == .open { openChangeWeek() }
            context.insert(ScheduleChange(at: clock.now, from: "\(base.bedtime)–\(base.wake)",
                                          to: "\(new.bedtime)–\(new.wake)", free: true, breakKey: nil, rule: 1))
            save()
            if new.bedtime == old.bedtime && new.wake == old.wake {                 // back to the times in effect
                s.pendingSchedule = nil
            } else if let from = SchedulePolicy.startsFrom(changedAt: clock.now, current: old, new: new, calendar: calendar) {
                s.pendingSchedule = PendingSchedule(schedule: new, fromNight: from)
                result = .fromTomorrow
            } else {
                s.schedule = new
                s.pendingSchedule = nil
            }
        } else {
            s.schedule = new
            s.pendingSchedule = nil
        }
        settings = s
        refresh()
        return result
    }

    private func openChangeWeek() {
        progress().changeWeekStart = clock.now
        save()
        changeWeekStart = clock.now
        rescheduleReminders()                                         // the "lock ended" notification follows the week
    }

    enum UnlockResult: Equatable { case unlocked, notLocked, notEnoughCoins(missing: Int) }

    /// The paid early unlock (2 000 🪙): only while locked; opens a new change week today (and the usual lock after it).
    @discardableResult
    func unlockSchedule() -> UnlockResult {
        guard active == nil else { return .notLocked }
        switch SchedulePolicy.unlock(state: scheduleState, coins: coins) {
        case .notLocked: return .notLocked
        case .notEnoughCoins(let missing): return .notEnoughCoins(missing: missing)
        case .ok:
            spend(SchedulePolicy.unlockPrice, reason: "schedule-unlock")
            openChangeWeek()
            debugScheduleState = nil
            return .unlocked
        }
    }

    /// The day the finished lock allows a new week: the card and the notification are for this day (nil = not now).
    private var lockEndedDay: NightKey? {
        SchedulePolicy.lockEnded(at: clock.now, weekStart: changeWeekStart, calendar: calendar)
    }

    /// "You can open a change week again 🌙 Does your bedtime still fit?" – once, after a lock has ended.
    var showsChangeWeekCard: Bool {
        onboardingDone && active == nil && (lockEndedDay.map { schedulePromptAnswered != $0.description } ?? false)
    }

    /// `adjust` = open Settings to change the schedule.
    func answerChangeWeekCard(adjust: Bool) {
        guard let day = lockEndedDay else { return }
        progress().schedulePromptMonth = day.description
        save()
        schedulePromptAnswered = day.description
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
        p.townNameChangedAt = clock.now                  // the newest name wins a merge of the devices (phase SYNC)
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
            if !loadingProgress && p.languageRaw != language.rawValue {
                p.languageRaw = language.rawValue
                save()
            }
            rescheduleReminders()
        }
    }

    func completeOnboarding() {
        let p = progress()
        p.onboardingCompletedAt = clock.now
        if p.changeWeekStart == nil { p.changeWeekStart = clock.now }       // the guide set the first schedule: day 1 of the first change week
        save()
        onboardingDone = true
        changeWeekStart = p.changeWeekStart
        rescheduleReminders()
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
                              .init(at: $0.at, from: $0.from, to: $0.to, free: $0.free, breakKey: $0.breakKey, rule: $0.rule)
                          },
                          jokers: jokerRecords().map { .init(at: $0.at, tier: $0.tierRaw, firstNight: $0.firstNight, boxId: $0.boxId) },
                          townNameChangedAt: p.townNameChangedAt, schedulePromptMonth: p.schedulePromptMonth,
                          changeWeekStart: p.changeWeekStart,
                          boxes: boxRecords().map { .init(id: $0.id, at: $0.at, nightKey: $0.nightKey, price: $0.price,
                                                          seed: String($0.seed), tableVersion: $0.tableVersion,
                                                          prize: $0.prizeRaw, payout: $0.payout) },
                          outfitChoice: p.outfitChoice, outfitChosenAt: p.outfitChosenAt,
                          nightSkyChoice: p.nightSkyChoice, nightSkyChosenAt: p.nightSkyChosenAt)
    }

    /// Every stored box row, readable or not (the backup keeps what it cannot read).
    func boxRecords() -> [BoxRecord] {
        _ = dataRevision
        return (try? context.fetch(FetchDescriptor<BoxRecord>(sortBy: [SortDescriptor(\.at)]))) ?? []
    }

    /// Stores one bought box (the only write path for 11b4's shop): `save()` bumps `dataRevision`, so the cached balance,
    /// the joker state and the stats are dropped and the sync notices the change.
    func recordBox(_ purchase: BoxPurchase) {
        context.insert(BoxRecord(purchase))
        save()
        rebuildTown()                                           // a won decoration appears in the town at once
    }

    // MARK: - the box shop (11b4a)

    /// The day the shop looks at: today's date as a night key (the night that ended this morning has this key).
    var boxDay: NightKey { NightKey(date: clock.now, calendar: calendar) }

    /// What the shop may offer now. `coreResults()` holds only real finished nights (no naps, no test nights) after jokers,
    /// so an excused night never opens a box.
    func boxOffer() -> BoxOffer {
        let day = boxDay
        return BoxRules.offer(today: day, todaysNight: coreResults().last { $0.key == day }?.outcome,
                              boxes: boxes(), balance: coins)
    }

    /// The box bought for today, if any.
    func todaysBox() -> BoxPurchase? {
        let day = boxDay
        return boxes().last { $0.nightKey == day }
    }

    /// Buys today's box: re-checks the offer at this very moment and buys only on `.available`. The seed is random
    /// (the system generator) unless a test or a Debug hook passes one. Returns nil, writing nothing, in every other case.
    @discardableResult
    func buyBox(seed: UInt64? = nil) -> BoxPurchase? {
        guard case .available(let price, _) = boxOffer() else { return nil }
        let purchase = BoxRules.purchase(id: UUID().uuidString, at: clock.now, nightKey: boxDay, price: price,
                                         seed: seed ?? UInt64.random(in: .min ... .max), boxes: boxes(),
                                         uses: jokerState.uses, calendar: calendar)
        recordBox(purchase)
        return purchase
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
        // the backup is the whole truth: a missing language or town name clears the current one (nil → the app's
        // default language / "My Town"); an unknown language code is cleared too (B12)
        p.languageRaw = b.language.flatMap { AppLanguage(rawValue: $0) != nil ? $0 : nil }
        p.townName = b.townName
        // a restore is the user's own act: the name counts as just written; no name, no stamp
        p.townNameChangedAt = b.townName == nil ? nil : clock.now
        if let d = b.lastRenameAt { p.lastRenameAt = d }
        if let d = b.lastFreeRenameAt { p.lastFreeRenameAt = d }
        if let d = b.scheduleCalibrationStart { p.scheduleCalibrationStart = d }
        if let m = b.schedulePromptMonth { p.schedulePromptMonth = m }
        p.changeWeekStart = b.changeWeekStart                // an older backup has none: the schedule is `open`
        p.outfitChoice = b.outfitChoice                      // the backup is the whole truth: none = never chosen
        p.outfitChosenAt = b.outfitChoice == nil ? nil : (b.outfitChosenAt ?? clock.now)
        p.nightSkyChoice = b.nightSkyChoice
        p.nightSkyChosenAt = b.nightSkyChoice == nil ? nil : (b.nightSkyChosenAt ?? clock.now)
        // the backup is the whole truth: an older one (no spends / changes) had none
        try context.delete(model: CoinSpend.self)
        for s in b.spends ?? [] { context.insert(CoinSpend(at: s.at, amount: s.amount, reason: s.reason)) }
        try context.delete(model: ScheduleChange.self)
        for c in b.scheduleChanges ?? [] {
            context.insert(ScheduleChange(at: c.at, from: c.from, to: c.to, free: c.free, breakKey: c.breakKey, rule: c.rule))
        }
        try context.delete(model: JokerRecord.self)
        for j in b.jokers ?? [] {
            guard let tier = JokerTier(rawValue: j.tier), let key = NightKey(j.firstNight) else { continue }
            let r = JokerRecord(at: j.at, tier: tier, firstNight: key, boxId: j.boxId)
            context.insert(r)
        }
        try context.delete(model: BoxRecord.self)
        for box in b.boxes ?? [] {
            guard let record = BoxRecord(backup: box) else { continue }
            context.insert(record)
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

    // MARK: - sync between the user's devices (phase SYNC, step S1 – the transport is S2)

    /// What this device offers the others: the whole state without debug and running nights, sleep values and the
    /// per-device settings.
    func makeSyncFile() -> BackupFile { makeBackup().forSync() }

    /// Merges the sync files of other devices into this store; returns whether anything changed. A merge only adds or
    /// replaces (see `SyncMerge`), the files are merged one after another and their order does not matter. Refused while
    /// a night or nap runs; a file from a newer version of the app is skipped.
    ///
    /// `firstContactStamp` is passed by the engine at this install's FIRST CONTACT only, while the settings carry no stamp
    /// yet: for the comparison they then count as stamped with it (`firstContactStamp()`), and the account wins a tie.
    /// Nothing is written into the settings here – `stampSettingsForSync(at:)` does that after the last file.
    ///
    /// When a night was added or replaced and Apple Health is on, its sleep values are read at once (not awaited): a new
    /// install or a second device has none for the nights it just received – they are never part of a sync file.
    @discardableResult
    func mergeSync(_ files: [BackupFile], firstContactStamp: Date? = nil, adoptAccountWeek: Bool = false) throws -> Bool {
        guard active == nil else { throw BackupError.nightRunning }
        let guideWasDone = onboardingDone
        var changed = false, nightsChanged = false
        // B35: a NEW install (first contact, no nights of its own) must not bring its own fresh change week – the guide it
        // just finished opened one – so the account's week replaces it outright; the normal "latest wins" merge below then
        // keeps it. Without any week in the account (a truly new user) the local one stays. Established devices skip this.
        if adoptAccountWeek,
           let week = files.filter({ $0.version <= BackupFile.currentVersion }).compactMap(\.changeWeekStart).max(),
           progress().changeWeekStart != week {
            progress().changeWeekStart = week
            changed = true
        }
        for file in files where file.version <= BackupFile.currentVersion {
            let merged = try SyncStore.merge(file, into: context, progress: progress())
            nightsChanged = nightsChanged || merged.nightsChanged
            changed = mergeSyncSettings(file.settings, firstContactStamp: firstContactStamp) || merged.changed || changed
        }
        guard changed else { return false }
        dataRevision += 1                                // the merge wrote rows: drop the cached derived values
        loadProgress()
        rescheduleReminders()                            // a week opened on another device moves the "lock ended" notification
        rebuildTown()
        refresh()                                        // `shownResult` stays: the user may be reading this morning's result
        if nightsChanged, settings.usesHealth { Task { await refreshSleepIfIdle() } }
        // the guide was finished on another device: the notification permission is asked here, the guide would have done it
        if !guideWasDone, onboardingDone, let adopted = onGuideAdoptedBySync { Task { await adopted() } }
        return true
    }

    /// Called (not awaited) when a merge finishes the first-run guide on this device because another device had finished
    /// it. `SleepHoleApp` asks for the notification permission there – the guide itself asks when the user goes through it.
    @ObservationIgnored var onGuideAdoptedBySync: (@MainActor () async -> Void)?

    /// The stamp this install's settings get at first contact when the user has changed nothing since: older than any
    /// real change, higher the more finalized, non-debug nights and naps the device holds (`SyncMerge.firstContactStamp`).
    /// Counted BEFORE the first merge – a device that has just received nights from the account is not "established".
    func firstContactStamp() -> Date {
        SyncMerge.firstContactStamp(established: establishedNights)
    }

    /// How many finalized, non-debug nights and naps this device's own store holds – how established the device is. Zero
    /// means a new phone or a reinstall (`SyncEngine` takes over the Health switch only then).
    var establishedNights: Int {
        records().filter { !$0.isDebug && $0.isFinalized }.count
    }

    /// The newest settings win; the Health switch is per device and stays. Assigning them runs the usual `didSet`
    /// (saving, the reminders when the schedule changed) but not the stamp – the winner keeps its own `changedAt`.
    private func mergeSyncSettings(_ remote: AppSettings, firstContactStamp: Date?) -> Bool {
        let remoteWins: Bool
        if let first = firstContactStamp, settings.changedAt == nil {
            remoteWins = remote.changedAt.map { $0 >= first } ?? false
        } else {
            remoteWins = SyncMerge.newer((false, settings.changedAt), (true, remote.changedAt)).value
        }
        guard remoteWins else { return false }
        var merged = remote
        merged.healthOn = settings.healthOn
        merged.syncOff = settings.syncOff
        merged.systemAlarmOff = settings.systemAlarmOff
        guard merged != settings else { return false }
        applyingMergedSettings = true
        settings = merged
        applyingMergedSettings = false
        return true
    }

    /// First contact (`SyncEngine`): no setting of any other device was newer than `firstContactStamp()`, so this
    /// device's own settings get that stamp. Not a change of the user – it neither stamps twice nor starts a sync.
    func stampSettingsForSync(at stamp: Date) {
        applyingMergedSettings = true
        settings.changedAt = stamp
        applyingMergedSettings = false
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
        applyPendingScheduleIfDue(now: now)
        // the lock-screen warning ends with its promised seconds, at the wake time and with the night
        if let deadline = lockWarningDeadline, now >= deadline || active.map({ now >= $0.wake }) != false { endLockWarning() }
        if let rec = active {
            setEarlyFlags(canStartEarly: false, tonightPlayed: false)
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
            setEarlyFlags(canStartEarly: false, tonightPlayed: false)
            phase = .result
            return
        }
        window = debugWindow ?? settings.schedule.window(containing: now, calendar: calendar)
        let alreadyPlayed = debugWindow == nil && records().contains { $0.id == window.key.description }
        phase = !alreadyPlayed && window.canStart(at: now, rules: nextNightRules) ? .canStart : .idle
        setEarlyFlags(canStartEarly: debugWindow == nil && !alreadyPlayed && window.canStartEarly(at: now),
                      tonightPlayed: alreadyPlayed)
    }

    /// Writes the two flags only when they change, so an unchanged value never notifies observers.
    private func setEarlyFlags(canStartEarly new: Bool, tonightPlayed played: Bool) {
        if canStartEarly != new { canStartEarly = new }
        if tonightPlayed != played { tonightPlayed = played }
    }

    /// The reminders to schedule, in one place. A night started early must not be woken by its own bedtime reminder:
    /// until that bedtime the reminders repeat weekly on every weekday except tonight's (`Notifications.reminderTriggers`).
    func rescheduleReminders() {
        guard servicesEnabled else { return }
        Notifications.scheduleReminders(settings.schedule, quietUntil: reminderQuietUntil, lockEndsOn: lockEndNotificationDay)
    }

    /// The day the schedule lock ends (the first day a change week can be opened again), while a week or a lock runs:
    /// the day of the one "you can open a change week again" notification. nil = none.
    private var lockEndNotificationDay: NightKey? {
        switch SchedulePolicy.state(at: clock.now, weekStart: changeWeekStart, calendar: calendar) {
        case .open: return nil
        case .changeWeek: return changeWeekStart.map { SchedulePolicy.plan(opening: $0, calendar: calendar).freeFrom }
        case .locked(_, let freeFrom): return freeFrom
        }
    }

    /// Tonight's bedtime while its reminder must stay quiet: the running night when it was started early and that
    /// bedtime has not come yet, or – with no night running – an early night that was cancelled / collapsed before
    /// its bedtime (tonight is in the records). Otherwise nil.
    var reminderQuietUntil: Date? {
        if let rec = active {
            guard !rec.isNap, !rec.isDebug, let started = rec.startedAt,
                  rec.window.isEarlyStart(started), clock.now < rec.window.bedtime else { return nil }
            return rec.window.bedtime
        }
        let tonight = settings.schedule.window(containing: clock.now, calendar: calendar)
        guard clock.now < tonight.bedtime, records().contains(where: { $0.id == tonight.key.description }) else { return nil }
        return tonight.bedtime
    }

    /// The rules a night started now would get (the setup time from Settings) – for texts about tonight's setup.
    var nextNightRules: SleepRules {
        var r = SleepRules.forNewNights
        r.setupGrace = settings.setupGrace
        if !settings.strictMode { r.startDeadline = SleepRules.gentleStartDeadline }
        return r
    }

    // MARK: - actions

    func startNight(early: Bool = false) {
        guard phase == .canStart || (early && canStartEarly), let catalog else { return }
        let now = clock.now
        let isBonus = debugWindow != nil && nextTestNightCounts
        let isDebug = debugWindow != nil && !isBonus
        if isBonus { nextTestNightCounts = false }
        let real = realResults()
        var rng = SystemRandomNumberGenerator()
        var entry = BuildingPicker.pick(
            maxLevel: Progression.unlockedMaxLevel(builtBefore: builtNights), catalog: catalog,
            history: real.map(\.buildingId), rng: &rng)
        #if DEBUG
        if DevArgs.list.contains("-forceBuilding"), let had = real.last.flatMap({ catalog[$0.buildingId] }) { entry = had }
        #endif
        let rec = NightRecord(window: window, buildingId: entry.id, isDebug: isDebug,
                              setupGrace: debugWindow != nil ? debugGrace : settings.setupGrace,
                              idPrefix: isBonus ? "bonus" : nil, strictLockScreen: settings.strictMode,
                              calmHoursRule: CalmHours.currentRule,
                              lockScreenTolerance: SleepRules.lockScreenToleranceNow,
                              accidentalTolerance: SleepRules.accidentalToleranceNow)
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
        rescheduleReminders()                        // after an early start tonight's reminder must stay quiet
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

    /// When a too-early shake was refused (nil = no note); the night screen shows a kind note for `earlyShakeNoteSeconds`.
    private(set) var earlyShakeAt: Date?
    static let earlyShakeNoteSeconds: TimeInterval = 5

    /// A shake on the night screen. Once confirming is open the confirm panel's own handler reacts, so this only
    /// notes a shake that came too early – it logs no event and cannot change a night's outcome.
    func shakeBeforeConfirm() {
        guard let rec = active, clock.now < rec.window.confirmOpens else { return }
        earlyShakeAt = clock.now
    }

    func abandonNight() {
        guard active != nil else { return }
        append(.abandoned)
        if let rec = active { finalize(rec) }
    }

    func acknowledgeResult() {
        shownResult = nil
        lastReceipt = nil
        levelUp = nil
        newAchievements = []
        finishedWeek = nil
        refresh()
    }

    /// Setup grace of the pending debug night.
    private(set) var debugGrace: TimeInterval = AppModel.debugGrace

    /// Debug night: bedtime now, wake in `minutes`, setup grace `grace` s (so the setup ends `grace` s after the start). Never counts for the town.
    func startTestNight(minutes: Double = 4, grace: TimeInterval = AppModel.debugGrace) {
        guard active == nil else { return }
        let now = clock.now
        debugWindow = NightWindow(key: NightKey(date: now, calendar: calendar), bedtime: now,
                                  wake: now + minutes * 60, earlyConfirmOverride: NightWindow.testNightConfirmLead)
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
        let a = DevArgs.list
        guard let i = a.firstIndex(of: "-buddy"), a.indices.contains(i + 1) else { return nil }
        switch a[i + 1] {
        case "awake": return .awake
        case "asleep": return .asleep
        default: return nil
        }
    }()

    /// Dev aid: `-buddyReaction purr|arch|wink` shows that reaction's hold frame on Today (screenshots).
    static let forcedBuddyReaction: BuddyReaction? = {
        let a = DevArgs.list
        guard let i = a.firstIndex(of: "-buddyReaction"), a.indices.contains(i + 1) else { return nil }
        switch a[i + 1] {
        case "purr": return .purr
        case "arch": return .arch
        case "wink": return .wink
        default: return nil
        }
    }()

    /// Dev aid: `-buddyOutfit nightcap,sunglasses,fish-bowl` dresses the cat (Debug only; `DevArgs` is empty in Release).
    static let forcedBuddyOutfit: CatOutfit? = {
        guard let v = DevArgs.value(after: "-buddyOutfit") else { return nil }
        return CatOutfit(ids: v.split(separator: ",").map(String.init))
    }()

    /// What the cat on Today wears: the Debug argument when given, else the owner's choice (11b4c) – never chosen means the
    /// newest owned item of each slot.
    var buddyOutfit: CatOutfit {
        Self.forcedBuddyOutfit ?? Collection.effectiveOutfit(choice: progress().outfitChoice, boxes: boxes())
    }

    /// The id of the night sky shown (nil = the plain sky): the Debug argument when given, else the owner's choice.
    var nightSkyId: String? {
        Self.forcedNightSky ?? Collection.effectiveSky(choice: progress().nightSkyChoice, boxes: boxes())
    }

    /// Wears `id` in `slot` (nil = nothing in that slot). The other slots keep what they wear now, also what was worn
    /// automatically. Stores the choice with its moment; the sync and the automatic backup pick it up through `save()`.
    func chooseAccessory(_ id: String?, slot: AccessorySlot) {
        let p = progress()
        p.outfitChoice = Collection.storedOutfit(changing: slot, to: id, current: buddyOutfitChosen)
        p.outfitChosenAt = clock.now
        save()
        refresh()
    }

    /// The outfit the stored choice gives (ignores the Debug argument, which must not leak into a stored choice).
    private var buddyOutfitChosen: CatOutfit {
        Collection.effectiveOutfit(choice: progress().outfitChoice, boxes: boxes())
    }

    /// Shows `id` at night (nil = the plain sky).
    func chooseNightSky(_ id: String?) {
        let p = progress()
        p.nightSkyChoice = Collection.storedSky(id)
        p.nightSkyChosenAt = clock.now
        save()
        refresh()
    }

    /// Dev aid: `-nightSky sky-02` (Debug only; `DevArgs` is empty in Release).
    static let forcedNightSky: String? = DevArgs.value(after: "-nightSky")

    /// The night sky effect shown on Today and the Town tab (`nightSkyId`).
    var nightSky: NightSkyEffect? { NightSkies.effect(forId: nightSkyId) }

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
        active.flatMap { NightEvaluator.collapsedAt($0.log, rules: $0.rules) }
    }

    /// End of the setup time, see `NightWindow.setupEnds`: bedtime + grace, start + grace when started after bedtime,
    /// start + 15 min for an early start.
    var graceEnds: Date? {
        active.flatMap { rec in
            rec.startedAt.map { rec.window.setupEnds(start: $0, rules: rec.rules) }
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

    /// Stops every system alarm that rings right now; waiting ones stay (B27: a ringing alarm must be easy to silence).
    func stopRingingSystemAlarms() {
        enqueueSystemAlarm { [weak self] in self?.systemAlarm.stopRinging() }
    }

    /// The app became active: with no night / nap running, opening SleepHole silences a ringing safety / test alarm.
    func appBecameActive() {
        guard active == nil else { return }
        stopRingingSystemAlarms()
        Task { await refreshSleepIfIdle() }
    }

    // MARK: lock-screen warning alarm

    /// When the lock-screen warning ends by itself (the seconds it promised), nil = none is on. Driven by `refresh`
    /// (the 1 s ticker, and `lockWarningTask` at the exact moment – the audio session keeps the app running at night).
    private(set) var lockWarningDeadline: Date?
    /// The warning rings as a system alarm (else the app's own sound plays).
    private var lockWarningIsSystem = false
    @ObservationIgnored private var lockWarningTask: Task<Void, Never>?
    /// The open keep-alive of the running warning (B28), nil = none.
    @ObservationIgnored private var keepAliveToken: Int?

    /// Rings the warning for `seconds`: the system alarm when allowed (it covers the Camera), else the app's own sound.
    /// `shown` = the seconds the title / notification promise; `ringFor` = the whole trip allowance (from the trip's
    /// start), so the warning rings until the real collapse moment (B33: the alarm starts sounding ~2.5 s late).
    private func startLockWarning(shown seconds: TimeInterval, ringFor: TimeInterval, at date: Date) {
        endLockWarning()
        lockWarningDeadline = date + ringFor
        // B28: the system alarm interrupts our audio session and iOS then suspends the app ~4 s later, so the deadline
        // would never run; a background task keeps it alive until the warning has ended
        keepAliveToken = keepAlive.begin(name: "lock-warning") { [weak self] in self?.keepAliveExpired() }
        lockLab.note("keep-alive began")
        lockLab.note("lock warning started · system=\(systemAlarm.consent == .allowed) · seconds=\(Int(seconds)) · ringFor=\(Int(ringFor))")
        if systemAlarm.consent == .allowed {
            lockWarningIsSystem = true
            let file = "alarm_alert.caf"                  // the file the app's own warning sound uses
            let shown = Int(seconds)                      // the same number the notification shows
            enqueueSystemAlarm { [weak self] in _ = await self?.systemAlarm.ringWarning(soundFile: file, seconds: shown) }
        } else if servicesEnabled {
            SoundFX.previewAlarm("alarm_alert", seconds: ringFor)
        }
        if servicesEnabled {
            lockWarningTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(ringFor))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    private func endLockWarning() {
        guard lockWarningDeadline != nil else { return }
        lockWarningDeadline = nil
        lockWarningTask?.cancel()
        lockWarningTask = nil
        lockLab.note("lock warning ended")
        let token = keepAliveToken
        keepAliveToken = nil
        if lockWarningIsSystem {
            lockWarningIsSystem = false
            // the keep-alive ends only after the stop has really run (the app must not be suspended before it)
            let (keepAlive, lab) = (keepAlive, lockLab)
            enqueueSystemAlarm { [weak self] in
                self?.systemAlarm.stopWarning()
                if let token { keepAlive.end(token); lab.note("keep-alive ended") }
            }
        } else {
            if servicesEnabled { SoundFX.stopPreview() }
            if let token { keepAlive.end(token); lockLab.note("keep-alive ended") }
        }
    }

    /// iOS is about to take the background time away: close the task (an open one would kill the app).
    private func keepAliveExpired() {
        lockLab.note("keep-alive EXPIRED")
        guard let token = keepAliveToken else { return }
        keepAliveToken = nil
        keepAlive.end(token)
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
            Notifications.scheduleNight(wake: rec.wake, alarmFile: settings.alarmSound.fileName)
        }
        // the night starts with SleepHole in front: no "setup is running out" reminder until the user leaves it
        outsideApp = false
        setupEndsAt = setupEnds
        setupReminderAt = nil
        if servicesEnabled { Notifications.cancelSetupReminder() }
        guard settings.usesSystemAlarm else { return }        // switched off in Settings: no backup, no question
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

    /// The Settings switch for the morning system alarm (B36). It works at once: off cancels a scheduled backup /
    /// safety alarm; on, during a night / nap whose wake time is still ahead, schedules the backup (asking for consent
    /// first when it was not asked yet, like `armAlarm`). The Strict-mode warning does not depend on it.
    func setSystemAlarm(on: Bool) {
        guard settings.usesSystemAlarm != on else { return }
        settings.usesSystemAlarm = on
        if !on {
            cancelSystemAlarm()
            return
        }
        let rec = active.flatMap { $0.wake > clock.now ? $0 : nil }     // a night / nap whose own alarm has not rung yet
        if rec != nil { systemAlarmMoved = false }
        switch systemAlarm.consent {
        case .allowed:
            if let rec { scheduleSystemAlarm(at: rec.wake + SystemAlarmPlan.afterWake) }
        case .notAsked:                                           // switching it on asks, also with no night running
            consentTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let answer = await self.systemAlarm.requestConsent()
                guard answer == .allowed, let rec, self.settings.usesSystemAlarm, self.active?.id == rec.id,
                      rec.wake > self.clock.now else { return }
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
    /// time and stays as a safety alarm. Without consent there is no safety alarm. A nap confirmed early (its last
    /// 20 %) leaves none: it is cancelled like any nap's alarm.
    private func settleSystemAlarm(for rec: NightRecord) {
        systemAlarmMoved = false
        let early = !rec.isNap && rec.log.confirmedAt.map { $0 < rec.wake } == true
        if early, settings.usesSystemAlarm, systemAlarm.consent == .allowed, rec.wake > clock.now {
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
        // a cold launch puts the user in the app: no setup reminder (it is set again if he leaves during the setup)
        outsideApp = false
        setupEndsAt = rec.startedAt.map { rec.window.setupEnds(start: $0, rules: rec.rules) }
        setupReminderAt = nil
        if servicesEnabled { Notifications.cancelSetupReminder() }
        if closedAt != nil, servicesEnabled { Notifications.cancelClosed() }       // the owner is back
        if closedAt != nil { cancelCollapseNotice() }
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
        audio.onInterruption = { [weak self] report in
            self?.append(report.journalKind)
        }
        monitor.onEvent = { [weak self] kind, date in self?.append(kind, at: date) }
        monitor.onTerminate = { [weak self] in self?.appWillTerminate() }
        monitor.start()
        if LockLab.shouldRecord(arguments: DevArgs.list, isDebugNight: rec.isDebug) {
            monitor.onRaw = { [weak self] text in self?.lockLab.note(text) }
            lockLab.start()
        }
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
        if lockLab.isRunning { lockLab.stop(); monitor.onRaw = nil }
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

    /// Developer aid (`-forgiveNight`): forgives everything out of the app so far in the running night / nap.
    /// The collapse is derived from the event log, so an explicit `.forgiven` event undoes it without editing data.
    func forgiveNight() {
        guard let rec = active, clock.now < rec.wake, !rec.log.has(.abandoned) else { return }
        append(.forgiven)
        if servicesEnabled { Notifications.cancelNudge(); Notifications.cancelClosed() }
        cancelCollapseNotice()
        waitingForReturn = false
    }

    /// Developer aid (`-revokeForgiveness`): takes back the forgiveness of the most recent finalized real night that has
    /// one. `.forgivenessRevoked` makes the rules ignore every `.forgiven` of that log; the stored outcome and away time
    /// are re-derived with the rules the night was finalized with. Everything else (events, building, `finalizedAt`)
    /// stays; coins, streak, jokers and the town follow because they are derived from the records. Idempotent.
    func revokeForgiveness() {
        guard active == nil,
              let rec = realResults().last(where: { $0.log.has(.forgiven) && !$0.log.has(.forgivenessRevoked) })
        else { return }
        rec.append(.forgivenessRevoked, at: clock.now)
        let log = rec.log
        let result = NightEvaluator.result(for: log, key: log.key, rules: rec.rules)
        rec.outcomeRaw = result.outcome.rawValue
        rec.awaySeconds = result.awaySeconds
        save()
        rebuildTown()
        refresh()
    }

    /// Appends a night event (from the lifecycle monitor; internal for tests).
    func append(_ kind: NightEventKind) { append(kind, at: clock.now) }

    /// How many "Vráť sa" warnings were sent this app session (diagnostics + tests).
    private(set) var nudgesSent = 0
    /// The seconds the last warning promised (always the full tolerance, 15 for new nights – the night's budget never shortens a warning;
    /// with the budget used up no warning is sent at all).
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

    /// How much of the night's budget is left (nil without a budget) – the night screen warns when it runs low.
    func awayBudgetState(at t: Date? = nil) -> AwayBudgetState? {
        guard let rec = active else { return nil }
        return NightEvaluator.budgetState(rec.log, rules: rec.rules, at: t ?? clock.now)
    }

    // MARK: - another building (build 11b6, owner 2026-10-26)

    /// What the night screen offers during the setup: a draw of another building. nil = nothing to show.
    enum RerollOffer: Equatable {
        case available(price: Int, left: Int)      // price 0 = a test night (free)
        case notEnoughCoins(price: Int)
        case usedUp
    }

    /// Draws of tonight's building that a test night made (a test night stores no `CoinSpend`; counts for nothing).
    private var testNightDraws: (night: PersistentIdentifier?, ids: [String]) = (nil, [])

    /// Buildings drawn away from tonight – derived from the `CoinSpend` reasons, never counted.
    private func drawnAwayTonight(_ rec: NightRecord) -> [String] {
        rec.isDebug ? (testNightDraws.night == rec.persistentModelID ? testNightDraws.ids : []) : Reroll.drawnAway(nightKey: rec.keyString, reasons: spends().map(\.reason))
    }

    func rerollOffer(at t: Date? = nil) -> RerollOffer? {
        let now = t ?? clock.now
        guard let rec = active, !rec.isNap, collapsedAt.map({ $0 > now }) ?? true,
              let graceEnds, graceEnds > now else { return nil }
        let made = drawnAwayTonight(rec).count
        guard let price = Reroll.price(drawsMade: made) else { return .usedUp }
        if rec.isDebug { return .available(price: 0, left: Reroll.maxPerNight - made) }
        return coins >= price ? .available(price: price, left: Reroll.maxPerNight - made) : .notEnoughCoins(price: price)
    }

    /// Draws another building for tonight: spends the coins (a test night draws free), never repeats a building drawn
    /// earlier tonight, same pool and history as the evening draw.
    func rerollBuilding() {
        guard let rec = active, let catalog, case .available(let price, _)? = rerollOffer() else { return }
        let old = rec.buildingId
        var tried = Set(drawnAwayTonight(rec)); tried.insert(old)
        var rng = SystemRandomNumberGenerator()
        let entry = BuildingPicker.pick(
            maxLevel: Progression.unlockedMaxLevel(builtBefore: builtNights), catalog: catalog,
            history: realResults().map(\.buildingId), excluding: tried, rng: &rng)
        if rec.isDebug {
            testNightDraws = (rec.persistentModelID, drawnAwayTonight(rec) + [old])
        } else if price > 0 {
            spend(price, reason: Reroll.reason(nightKey: rec.keyString, from: old))
        }
        rec.buildingId = entry.id
        save()
        fx("fx_pop", volume: 0.5)
        refresh()
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
        // B26: picking up the ringing phone (lit lock screen + Face ID) is not "using the phone" – nothing from the
        // lock screen counts at or after the alarm / the wake time; it stays in the raw log only
        if kind == .usedLockScreen, date >= (rec.log.first(.alarmFired)?.at ?? rec.wake) {
            lockLab.note("(usedLockScreen at/after the alarm ignored)")
            return
        }
        // Must be evaluated BEFORE the event is stored: an open `.leftApp` interval counts until the
        // wake time, so afterwards the building always looks collapsed and no warning was ever sent
        // (bug found by the owner 2026-09-29).
        let alreadyCollapsed = collapsedAt != nil
        let lockTripWasOpen = Self.lockScreenTripOpen(rec.log)
        rec.append(kind, at: date)
        save()
        updateSetupReminder(after: kind, at: date)
        switch kind {
        case .leftApp where lockTripWasOpen && rec.rules.lockScreenCollapses:
            break           // strict: the lock-screen trip is counted and warned about since it began; nothing new
        case .usedLockScreen where !rec.rules.lockScreenCollapses:
            // gentle mode (owner 2026-10-09): the lock-screen use is only logged and met with one calm reminder – no
            // system alarm, no keep-alive, no deadline, no collapse notice, no "come back" state; the building stays
            if let graceEnds, date >= graceEnds, date < rec.wake, !alreadyCollapsed,
               PausePolicy.activeUntil(rec.log, at: date) == nil {
                lockRemindersSent += 1
                if servicesEnabled { Notifications.lockScreenReminder() }
            }
        case .leftApp, .closedByOwner, .usedLockScreen:
            // no vibration here: the app is in the background now and iOS only lets the notification vibrate
            if let pauseEnds = PausePolicy.activeUntil(rec.log, at: date) {
                // inside a pause (D17) leaving is free – only remind when it is about to end
                if servicesEnabled { Notifications.pauseEnding(at: pauseEnds) }
                scheduleProjectedCollapseNotice(after: date)      // out when the pause runs out → it can collapse then
            } else if let graceEnds, date >= graceEnds, !alreadyCollapsed, date < rec.wake {
                // nothing counts after the wake time (away intervals are clipped to it): picking up the ringing
                // phone must not produce "Come back … or the building collapses"
                // a trip that starts with budget left is a full one (18 s for new nights); with the budget used up there is no time
                // for a warning (left = 0) and the building has already collapsed
                // owner 2026-10-09: the collapse always comes with a notice, scheduled now because the app may be dead
                // or suspended when it happens (also with the budget used up: then it fires at once)
                let lockTrip = kind == .usedLockScreen
                if let fire = Notifications.collapseNoticeTime(log: rec.log, rules: rec.rules, at: date,
                                                               alreadyCollapsed: alreadyCollapsed, lockScreen: lockTrip) {
                    collapseNoticeAt = fire
                    if servicesEnabled { Notifications.collapsed(isNap: rec.isNap, at: fire) }
                }
                // the whole trip (lock-screen trips are longer: 3 s + 15 s) and the seconds the warning promises
                let tripAllowance = NightEvaluator.allowance(rec.log, rules: rec.rules, at: date, lockScreen: lockTrip)
                let left = tripAllowance - rec.rules.noticeDelay
                guard left >= 1 else { break }                // the warning would come too late
                nudgesSent += 1
                lastNudgeSeconds = Int(left)
                if kind == .closedByOwner {
                    // the process dies now: the notice is all that is left, and the relaunch ends the trip
                    if servicesEnabled { Notifications.closed(tolerance: left) }
                } else if kind == .usedLockScreen {
                    // "come back" is the wrong advice on the lock screen (Face ID wants the passcode): switch the screen off.
                    // The notification may reach only the Apple Watch, so the phone sounds the warning itself.
                    waitingForReturn = true
                    lastWarning = .lockScreen
                    if servicesEnabled { Notifications.lockScreenNudge(tolerance: left) }
                    startLockWarning(shown: left, ringFor: tripAllowance, at: date)
                } else {
                    waitingForReturn = true
                    lastWarning = .comeBack
                    if servicesEnabled { Notifications.nudge(tolerance: left) }
                }
            }
        case .returned, .locked:
            if servicesEnabled {
                Notifications.cancelNudge()
                Notifications.cancelPauseNotices()
            }
            cancelCollapseNotice()
            endLockWarning()
            if kind == .returned, waitingForReturn, collapsedAt == nil { buzz(.relief) }
            waitingForReturn = false
        case .callStarted, .pauseStarted:
            cancelCollapseNotice()                      // a call or a pause excuses the trip that is running
            // ... but if the owner is still out when the pause runs out, the trip goes on and so does the notice
            if kind == .pauseStarted { scheduleProjectedCollapseNotice(after: date) }
        case .callEnded:
            scheduleProjectedCollapseNotice(after: date)    // still out after the call → the trip counts again
        default:
            break
        }
    }

    /// The "15s of setup left" reminder is pending only while the user is outside SleepHole during the setup
    /// (`SetupReminder`, owner 2026-10-15). Observable for tests through `setupReminderAt`.
    private func updateSetupReminder(after kind: NightEventKind, at date: Date) {
        outsideApp = SetupReminder.outsideApp(after: kind, wasOutside: outsideApp)
        let wanted = setupEndsAt.flatMap { SetupReminder.fireDate(setupEnds: $0, now: date, outsideApp: outsideApp) }
        guard wanted != setupReminderAt else { return }
        setupReminderAt = wanted
        guard servicesEnabled else { return }
        if let wanted { Notifications.setupReminder(at: wanted) } else { Notifications.cancelSetupReminder() }
    }

    /// The last trip-relevant event of the log is `.usedLockScreen`: a lock-screen trip is open.
    static func lockScreenTripOpen(_ log: NightLog) -> Bool {
        let ends: Set<NightEventKind> = [.usedLockScreen, .leftApp, .closedByOwner, .returned, .locked, .confirmed,
                                         .appLaunched, .restartExcused, .forgiven]
        return log.sortedEvents.last { ends.contains($0.kind) }?.kind == .usedLockScreen
    }

    /// The evaluator already knows the collapse moment of a trip that is still open (an open `.leftApp` runs to the
    /// wake time, calls and pauses are cut out of it): when that moment is still ahead, the notice is set for it.
    private func scheduleProjectedCollapseNotice(after date: Date) {
        guard let rec = active, let fire = collapsedAt, fire > date else { return }
        collapseNoticeAt = fire
        if servicesEnabled { Notifications.collapsed(isNap: rec.isNap, at: fire) }
    }

    /// The trip ended in time or is excused: the pending collapse notice is withdrawn (a delivered one stays).
    private func cancelCollapseNotice() {
        collapseNoticeAt = nil
        if servicesEnabled { Notifications.cancelCollapsed() }
    }

    // MARK: - vibrations (owner 2026-09-30, idea XS)

    /// Every vibration requested this app session, in order (diagnostics + tests). Only in the foreground:
    /// iOS does not let apps vibrate in the background (owner test 2026-09-30) – there the notifications
    /// ("⏳ 15 s of setup left", "⚠️ Come back!") vibrate the phone through their sound.
    private(set) var haptics: [Haptic] = []
    /// Which "come back" style warning was sent last (tests): the usual one, or "switch the screen off" for the lock screen.
    enum Warning: Equatable { case comeBack, lockScreen }
    private(set) var lastWarning: Warning?
    /// How many gentle lock-screen reminders (`Notifications.lockScreenReminder`) were asked for this app session (tests).
    private(set) var lockRemindersSent = 0
    /// Setup reminder state (see `updateSetupReminder`): the user is in another app / when the setup ends / when the
    /// pending "15s of setup left" notification fires (nil = none pending).
    private var outsideApp = false
    private var setupEndsAt: Date?
    private(set) var setupReminderAt: Date?
    /// When the "building collapsed" notice is set to fire for the trip that is running (nil = none). Kept even without
    /// services so tests can see the decision; the notification itself is scheduled only with services.
    private(set) var collapseNoticeAt: Date?
    /// A "Come back!" warning was sent and the owner has not returned yet.
    private var waitingForReturn = false

    private func buzz(_ h: Haptic) {
        haptics.append(h)
        guard servicesEnabled else { return }
        // iOS plays haptics only in the foreground: the return is counted at willEnterForeground, when the app is not
        // active yet – the vibration waits for the next didBecomeActive
        if UIApplication.shared.applicationState != .active {
            pendingHaptic = h
            if reliefObserver == nil {
                reliefObserver = NotificationCenter.default.addObserver(
                    forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.playPendingHaptic() }
                }
            }
            return
        }
        Haptics.play(h)
    }
    private var pendingHaptic: Haptic?
    private var reliefObserver: NSObjectProtocol?
    private func playPendingHaptic() {
        if let o = reliefObserver { NotificationCenter.default.removeObserver(o); reliefObserver = nil }
        if let h = pendingHaptic { pendingHaptic = nil; Haptics.play(h) }
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
        let result = NightEvaluator.result(for: log, key: log.key, rules: rec.rules)
        rec.outcomeRaw = result.outcome.rawValue
        rec.awaySeconds = result.awaySeconds
        rec.finalizedAt = clock.now
        save()
        stopServices()
        active = nil
        collapseNoticeAt = nil                       // stopServices already withdrew the pending notice
        sync.activityEnded()                         // a sync owed since the night began runs now
        rescheduleReminders()                        // the daily reminders are back (an early night had one-shot ones)
        endLockWarning()
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
        if servicesEnabled, !rec.isDebug, !rec.isNap { Task { await refreshSleepIfIdle() } }   // the watch may not have synced yet: read again later
        let entry = rec.isDebug || rec.isNap ? nil
            : Economy.ledger(coreResults(), calendar: calendar, breaks: streakBreaks, catalog: catalog, boxes: boxes())
                .last { $0.key.description == rec.keyString }
        lastReceipt = entry.flatMap { Economy.Receipt($0, calmTotal: rec.result?.calmHoursTotal) }
            .map { $0.addingAchievements(newAchievements.reduce(0) { $0 + $1.reward }) }   // achievements pay coins too
            .flatMap { $0.total == lastReward ? $0 : nil }
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

    private func save() {
        try? context.save()
        dataRevision += 1
        sync.noteLocalChange()
    }
}
