import Foundation
import Observation

/// Phase SYNC, step S2a: reads the other devices' files, merges them, and writes this device's file – at the right
/// moments. `AppModel` only owns the engine and calls it (`noteLocalChange()` after a save or a settings change,
/// `activityEnded()` when a night or nap is over, `noteAppActive()`, `launch()`). The transport is replaceable
/// (`SyncTransport`); the rule of the merge lives in `SleepCore/SyncMerge.swift` and `Sync.swift`.
///
/// Never during a night or a nap: a sync that is due then is remembered ("owed") and runs when the night is over.
/// Errors of the transport never reach the user as an alert – they are remembered in `lastSyncError` for a screen
/// that may show them, and the engine tries again by itself (10 s, 30 s, 2 min, then every 5 min; never during a night,
/// never with the switch off). With the switch off nothing runs: no read, no write, no watching of the transport.
@MainActor
@Observable
final class SyncEngine {
    /// The first-contact flag lives in the install's `UserDefaults` (not in `AppSettings`, never synced).
    static let firstReadKey = "sync.firstReadDone"

    /// When the last sync got through (read, merge and, when needed, write); nil = none yet in this run.
    private(set) var lastSyncAt: Date?
    /// A short text of the last transport error; nil after a good sync. English and raw – for a developer screen, never
    /// for users (`SyncStatus` is what Settings shows).
    private(set) var lastSyncError: String?
    /// Whether the sync place could be used at the last attempt (`unknown` before the first one). Settings reads this
    /// instead of asking the transport.
    private(set) var place: SyncPlace = .unknown
    /// How many other devices' files the last good sync read (a developer screen).
    private(set) var othersRead = 0
    /// True while a fresh install waits for its first read before the first-run guide may be shown (see `launch()`).
    private(set) var holdsGuide = false
    /// How many times in a row a sync failed and was scheduled again (0 = the last one got through, or none failed yet).
    private(set) var retryAttempt = 0
    /// How many times the engine encoded a sync file (tests: a quiet sync encodes once, a writing one twice).
    private(set) var encodes = 0

    @ObservationIgnored let transport: any SyncTransport
    @ObservationIgnored private let defaults: UserDefaults
    /// Local changes within this many seconds give one sync.
    @ObservationIgnored private let settleDelay: TimeInterval
    /// The longest the guide waits for the first read.
    @ObservationIgnored private let guideWait: TimeInterval
    /// Seconds to wait before the next try after the n-th failure in a row (0 = the first failure); tests use milliseconds.
    @ObservationIgnored private let retryDelay: (Int) -> TimeInterval
    @ObservationIgnored private weak var model: AppModel?

    @ObservationIgnored private var running = false
    @ObservationIgnored private var runAgain = false
    @ObservationIgnored private var owed = false
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var watcher: Task<Void, Never>?
    @ObservationIgnored private var guideTimer: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    /// `launch()` has been called: from then on the transport is watched while syncing is switched on.
    @ObservationIgnored private var launched = false
    /// The content (without `exportedAt`) of the file this engine wrote last: an unchanged state is not written again.
    @ObservationIgnored private var lastWritten: Data?

    /// A failed sync is tried again by the engine itself: after 10 s, 30 s, 2 min, then every 5 min.
    nonisolated static func standardRetryDelay(_ failures: Int) -> TimeInterval {
        let steps: [TimeInterval] = [10, 30, 120]
        return failures < steps.count ? steps[failures] : 300
    }

    init(transport: any SyncTransport = NoSyncTransport(), defaults: UserDefaults = .standard,
         settleDelay: TimeInterval = 2, guideWait: TimeInterval = 4,
         retryDelay: @escaping (Int) -> TimeInterval = SyncEngine.standardRetryDelay) {
        self.transport = transport
        self.defaults = defaults
        self.settleDelay = settleDelay
        self.guideWait = guideWait
        self.retryDelay = retryDelay
    }

    /// Called once by `AppModel.init`, after the progress is loaded: decides whether the guide has to wait for the first
    /// read (a fresh store, the guide not finished, a transport that may be there, syncing on).
    func attach(_ model: AppModel) {
        self.model = model
        holdsGuide = isConfigured(model) && !model.onboardingDone && model.records().isEmpty
    }

    // MARK: - first contact

    /// "The first read of the sync place has finished" on this install. Until then this device's settings carry no
    /// stamp (`AppModel.settings.didSet`): a new device must not overwrite the settings of the one the user has.
    var firstReadDone: Bool {
        get { defaults.bool(forKey: Self.firstReadKey) }
        set { defaults.set(newValue, forKey: Self.firstReadKey) }
    }

    // MARK: - triggers

    /// Sync is wanted at all: the user's switch is on and there is a transport that may work.
    private func isConfigured(_ model: AppModel) -> Bool {
        model.settings.usesSync && !(transport is NoSyncTransport)
    }

    /// A save or a change of the settings: sync after a short delay (several changes in a row give one sync). Cheap
    /// during a night: nothing is built or read, the sync is only remembered.
    func noteLocalChange() {
        guard !merging, let model, isConfigured(model) else { return }
        if model.active != nil { owed = true; return }
        schedule(after: settleDelay)
    }

    /// The night or nap is over (`active` is nil again): the sync owed since it started runs now.
    func activityEnded() {
        guard owed else { return }
        owed = false
        schedule(after: settleDelay)
    }

    /// The app became active again.
    func noteAppActive() {
        guard let model, isConfigured(model) else { return }
        schedule(after: 0)
    }

    private func schedule(after delay: TimeInterval) {
        debounce?.cancel()
        debounce = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, let self else { return }
            debounce = nil                                   // later changes start a new wait, they never cancel a running sync
            await syncNow()
        }
    }

    /// Launch: starts watching the transport, syncs once and lets the guide go when that is done – or after at most
    /// `guideWait` seconds, whichever comes first (the sync itself then goes on in the background).
    func launch() async {
        launched = true
        if model?.settings.usesSync == true { watch() }      // switched off: nothing is watched, nothing is downloaded
        if holdsGuide {
            guideTimer = Task { [weak self, guideWait] in
                try? await Task.sleep(for: .seconds(guideWait))
                guard !Task.isCancelled else { return }
                self?.releaseGuide()
            }
        }
        await syncNow()
    }

    /// Stops watching and everything that is scheduled (tests; the app lives as long as the process).
    func stop() {
        unwatch()
        debounce?.cancel(); debounce = nil
        guideTimer?.cancel(); guideTimer = nil
        cancelRetry()
    }

    /// The user turned the sync switch on or off (`AppModel.settings`). Off: the transport is no longer watched (with
    /// iCloud that ends the metadata query and the downloads of the other devices' files) and no retry is pending. On:
    /// watching starts again – once the app has launched; the sync that follows a switch is `noteLocalChange()`'s.
    func switchChanged() {
        guard let model else { return }
        if model.settings.usesSync {
            if launched { watch() }
        } else {
            unwatch()
            cancelRetry()
        }
    }

    private func watch() {
        guard watcher == nil else { return }
        let changes = transport.changes
        watcher = Task { [weak self] in
            for await _ in changes {
                guard let self else { return }
                await syncNow()
            }
        }
    }

    private func unwatch() {
        watcher?.cancel(); watcher = nil
    }

    /// Is the transport being watched for changes of the other devices? (tests)
    var isWatching: Bool { watcher != nil }

    // MARK: - trying again

    /// After a failed sync: one more `syncNow` after a growing delay. Not during a night (the sync is owed then, and
    /// runs when it ends) and not with the switch off.
    private func scheduleRetry() {
        guard let model, model.settings.usesSync else { return }
        guard model.active == nil else { owed = true; return }
        retryTask?.cancel()
        let delay = retryDelay(retryAttempt)
        retryAttempt += 1
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            retryTask = nil
            await syncNow()
        }
    }

    private func cancelRetry() {
        retryTask?.cancel(); retryTask = nil
        retryAttempt = 0
    }

    /// Is another try pending? (tests)
    var isRetrying: Bool { retryTask != nil }

    private func releaseGuide() {
        guideTimer?.cancel(); guideTimer = nil
        holdsGuide = false
    }

    /// Waits until no sync is scheduled or running (tests).
    func settled() async {
        for _ in 0..<5_000 {
            if debounce == nil, !running { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    /// Is a sync owed because a night or nap was running when one was due? (tests)
    var isOwed: Bool { owed }

    // MARK: - the sync

    /// True while the engine itself merges: the saves a merge causes are no reason to sync again.
    @ObservationIgnored private var merging = false

    /// One sync: read the others → merge → first contact → write this device's file when its content changed. Only one
    /// runs at a time; a call that arrives while one runs makes it run once more afterwards.
    func syncNow() async {
        if running { runAgain = true; return }
        running = true
        repeat {
            runAgain = false
            await runOnce()
        } while runAgain
        running = false
    }

    private func runOnce() async {
        defer { releaseGuide() }
        guard let model, model.settings.usesSync else { return }
        guard model.active == nil else { owed = true; return }
        owed = false
        guard await transport.isAvailable() else { place = .unavailable; return }
        guard model.settings.usesSync else { return }        // the switch may have been turned off while we asked
        place = .available
        do {
            let datas = try await transport.readOthers()
            // a night may have started, or the switch may have been turned off, while the files were read
            guard model.settings.usesSync else { return }
            guard model.active == nil else { owed = true; return }
            // a file that does not decode, or comes from a newer version, is skipped – never an error for the user …
            let files = datas.compactMap { try? BackupFile.decodeSync($0) }.filter { $0.version <= BackupFile.currentVersion }
            // … but a read that held one is no first contact: the account may hold more than could be seen (the next sync tries again)
            let firstContact = !firstReadDone && files.count == datas.count
            // counted before the merge: a device that has just received the account's nights is not "established" by them
            let established = model.establishedNights
            let stamp = firstContact ? model.firstContactStamp() : nil
            try merge(files, into: model, firstContactStamp: stamp, adoptAccountWeek: firstContact && established == 0)
            if firstContact {
                // nothing of the account beat this device's unstamped settings: they get the (minimal) first-contact stamp
                if let stamp, model.settings.changedAt == nil { model.stampSettingsForSync(at: stamp) }
                firstReadDone = true
                if established == 0 { adoptHealthSwitch(from: files, on: model) }     // only a new phone or a reinstall
            }
            let file = model.makeSyncFile()
            var comparable = file
            comparable.exportedAt = .distantPast             // differs on every call
            let content = try encode(comparable)             // the only encode of a quiet sync
            if content != lastWritten {
                try await transport.write(try encode(file))
                lastWritten = content
            }
            lastSyncAt = model.clock.now
            lastSyncError = nil
            othersRead = datas.count
            cancelRetry()                                    // a good sync ends the series of tries
        } catch AppModel.BackupError.nightRunning {
            owed = true
        } catch is CancellationError {
            // the switch was turned off, or the engine stopped, while a read was waiting
        } catch {
            lastSyncError = error.localizedDescription
            scheduleRetry()
        }
    }

    private func encode(_ file: BackupFile) throws -> Data {
        encodes += 1
        return try file.encodedForSync()
    }

    /// A NEW install (no finalized real night or nap of its own before the merge – a new phone or a reinstall) takes the
    /// position of the Apple Health switch from the account, once, at its first contact. An established device never
    /// does: its switch may be off on purpose. The switch is this device's own afterwards: a sync never turns it off,
    /// and never turns it on again. iOS shows its permission sheet once and the sleep values are read; the switch is not
    /// switched on where Health cannot be read. Not awaited: the sheet waits for the user, the sync must not.
    private func adoptHealthSwitch(from files: [BackupFile], on model: AppModel) {
        guard !model.settings.usesHealth, model.sleepSource.isAvailable, files.contains(where: { $0.settings.usesHealth }) else { return }
        Task { [weak model] in await model?.setHealth(on: true) }
    }

    private func merge(_ files: [BackupFile], into model: AppModel, firstContactStamp: Date?, adoptAccountWeek: Bool) throws {
        merging = true
        defer { merging = false }
        try model.mergeSync(files, firstContactStamp: firstContactStamp, adoptAccountWeek: adoptAccountWeek)
    }
}

/// Whether the sync place (the user's iCloud, a test folder) could be used the last time the engine looked.
enum SyncPlace: Equatable, Sendable {
    /// No attempt yet in this run.
    case unknown
    case available
    /// Not signed in to iCloud, iCloud Drive off, no container – the transport said "not available".
    case unavailable
}

/// What the status line in Settings → iCloud says. A pure mapping of the engine's state, so it is tested without a view;
/// `nil` = no line at all (the switch is off).
enum SyncStatus: Equatable, Sendable {
    /// iCloud cannot be used right now: the user has something to do in the iPhone's Settings.
    case unavailable
    /// The last attempt failed; the engine tries again by itself. The raw error is never shown.
    case failed
    case synced(Date)
    case notYet

    static func of(enabled: Bool, place: SyncPlace, error: String?, lastSyncAt: Date?) -> SyncStatus? {
        guard enabled else { return nil }
        switch place {
        case .unavailable: return .unavailable
        case .unknown: return .notYet
        case .available:
            if error != nil { return .failed }
            if let lastSyncAt { return .synced(lastSyncAt) }
            return .notYet
        }
    }
}
