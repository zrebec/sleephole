import Foundation
import SleepCore
import SwiftData

/// Phase SYNC (one town on all of a user's devices), step S1: the sync file and the merge of other devices' files into
/// this device's store. No transport here (iCloud is step S2) – everything works on `BackupFile` values. The rule that
/// decides between two copies lives in `SleepCore/SyncMerge.swift`.
///
/// A merge only ever adds or replaces, it never deletes. Sleep values read from Apple Health never leave the device
/// (App Review guideline 5.1.3): a sync file has none, and a merge never writes any.

extension BackupFile.Night {
    /// The same night without what Apple Health said about it.
    func withoutSleepValues() -> BackupFile.Night {
        var n = self
        n.fellAsleepAt = nil
        n.sleepEndedAt = nil
        n.asleepSeconds = nil
        n.awakeSeconds = nil
        n.sleepSourceName = nil
        n.sleepReadAt = nil
        n.sleepSourcesData = nil
        n.sleepRuleVersion = nil
        return n
    }
}

extension BackupFile {
    /// What a device writes for the others: no debug nights, no night that is not finalized (a running one belongs to
    /// the device that runs it), no sleep values, and not the per-device switches (`syncOff`, `systemAlarmOff`). The UI language
    /// travels, but only so that a device that has never chosen one can adopt it (`UserProgress.merge`); a device that
    /// has its own language never takes another's. The POSITION of the Apple Health switch travels as a preference (it
    /// is not health data): a normal merge keeps the local switch, only a new install (no nights of its own) takes it over
    /// once, at its first contact with the sync place (`SyncEngine`).
    func forSync() -> BackupFile {
        var file = self
        file.nights = nights.filter { !$0.isDebug && $0.finalizedAt != nil }.map { $0.withoutSleepValues() }
        file.settings.syncOff = nil
        file.settings.systemAlarmOff = nil
        return file
    }

    /// The sync encoding: dates keep their fractions of a second (`encoded()` cuts them to whole seconds, which is fine
    /// for a file a person keeps but not for merging).
    func encodedForSync() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return try e.encode(self)
    }

    static func decodeSync(_ data: Data) throws -> BackupFile {
        try JSONDecoder().decode(BackupFile.self, from: data)
    }
}

extension AppSettings {
    /// Do the two have the same settings as far as syncing is concerned? The change stamp and the per-device switches
    /// (Health, sync – a merge never takes them) do not count.
    func hasSameSyncedValues(as other: AppSettings) -> Bool {
        var copy = self
        copy.changedAt = other.changedAt
        copy.healthOn = other.healthOn
        copy.syncOff = other.syncOff
        copy.systemAlarmOff = other.systemAlarmOff
        return copy == other
    }
}

/// The app side of the merge: turns the stored records into `SyncMerge` inputs and applies the verdicts.
@MainActor
enum SyncStore {
    /// What a merge did.
    struct Merged {
        /// Anything at all changed.
        var changed = false
        /// A night was added or replaced (a reason to read its sleep values from Apple Health).
        var nightsChanged = false
    }

    /// Merges everything of `file` except the settings (those belong to `AppModel`, whose `didSet` has to stay in the
    /// loop). Returns what changed.
    static func merge(_ file: BackupFile, into context: ModelContext, progress: UserProgress) throws -> Merged {
        var result = Merged()
        result.nightsChanged = try mergeNights(file.nights, into: context)
        var changed = result.nightsChanged
        changed = try mergeSpends(file.spends ?? [], into: context) || changed
        changed = try mergeBoxes(file.boxes ?? [], into: context) || changed       // before the jokers: they may spend a box
        changed = try mergeJokers(file.jokers ?? [], into: context) || changed
        changed = try mergeScheduleChanges(file.scheduleChanges ?? [], into: context) || changed
        changed = progress.merge(file) || changed
        if changed { try context.save() }
        result.changed = changed
        return result
    }

    // MARK: nights

    /// What the choice between two copies of a night looks at; the fingerprint is built from the same fields on both
    /// sides, so the two devices rank a pair the same way.
    static func copy(of n: BackupFile.Night) -> SyncMerge.NightCopy {
        let outcome = n.finalizedAt == nil ? nil : n.outcomeRaw.flatMap(Outcome.init(rawValue:))
        let finish = n.confirmedAt?.timeIntervalSinceReferenceDate ?? 0
        return SyncMerge.NightCopy(
            outcome: outcome, startedAt: n.startedAt, finalizedAt: n.finalizedAt, eventCount: n.events.count,
            fingerprint: "\(n.buildingId)|\(n.events.count)|\(n.outcomeRaw ?? "")|\(n.pauses ?? -1)|\(n.awaySeconds)|\(finish)")
    }

    static func mergeNights(_ remote: [BackupFile.Night], into context: ModelContext) throws -> Bool {
        var byId: [String: NightRecord] = [:]
        for r in try context.fetch(FetchDescriptor<NightRecord>()) { byId[r.id] = r }
        var changed = false
        for night in remote where !night.isDebug && night.finalizedAt != nil {
            let n = night.withoutSleepValues()               // whatever the file carries, Health values never come in
            if let local = byId[n.id] {
                guard !SyncMerge.keepsFirst(copy(of: local.backup), copy(of: n)) else { continue }
                local.adoptNight(n)                          // in place; the local sleep values stay as they are
            } else {
                let record = NightRecord(backup: n)
                context.insert(record)
                byId[n.id] = record
            }
            changed = true
        }
        return changed
    }

    // MARK: spends, jokers, schedule changes – a union; an entry is the same when its payload and its moment are

    /// Adds every remote entry that has no local counterpart. Each local entry answers at most ONE remote entry, so an
    /// entry that really exists twice stays twice; a counterpart is found by `matches`.
    private static func union<Local, Remote>(_ remote: [Remote], local: [Local], matches: (Local, Remote) -> Bool,
                                             add: (Remote) -> Void) -> Bool {
        var pool = local
        var changed = false
        for entry in remote {
            if let i = pool.firstIndex(where: { matches($0, entry) }) {
                pool.remove(at: i)
            } else {
                add(entry)
                changed = true
            }
        }
        return changed
    }

    static func mergeSpends(_ remote: [BackupFile.Spend], into context: ModelContext) throws -> Bool {
        union(remote, local: try context.fetch(FetchDescriptor<CoinSpend>()), matches: {
            $0.amount == $1.amount && $0.reason == $1.reason && SyncMerge.sameMoment($0.at, $1.at)
        }, add: { context.insert(CoinSpend(at: $0.at, amount: $0.amount, reason: $0.reason)) })
    }

    /// A box is one record with its own id: the union is by id (an id already present is skipped, nothing is replaced or
    /// deleted, so merging the same file twice adds nothing). An entry this version cannot read is skipped.
    static func mergeBoxes(_ remote: [BackupFile.Box], into context: ModelContext) throws -> Bool {
        var known = Set(try context.fetch(FetchDescriptor<BoxRecord>()).map(\.id))
        var changed = false
        for box in remote where !known.contains(box.id) {
            guard let record = BoxRecord(backup: box) else { continue }
            context.insert(record)
            known.insert(box.id)
            changed = true
        }
        return changed
    }

    /// Jokers: the union rule above, with the box id outside the comparison – two copies of the same use (tier, first night,
    /// moment) are ONE even when only one of them knows the box. A copy with a box id upgrades a local one without
    /// (an older device wrote it); a local box id is never replaced.
    static func mergeJokers(_ remote: [BackupFile.Joker], into context: ModelContext) throws -> Bool {
        // an entry this version cannot read (a tier or night it does not know) is skipped, as `restore` does
        let readable = remote.filter { JokerTier(rawValue: $0.tier) != nil && NightKey($0.firstNight) != nil }
        var pool = try context.fetch(FetchDescriptor<JokerRecord>())
        var changed = false
        for entry in readable {
            if let i = pool.firstIndex(where: {
                $0.tierRaw == entry.tier && $0.firstNight == entry.firstNight && SyncMerge.sameMoment($0.at, entry.at)
            }) {
                let local = pool.remove(at: i)
                if local.boxId == nil, let id = entry.boxId {
                    local.boxId = id
                    changed = true
                }
            } else {
                context.insert(JokerRecord(at: entry.at, tier: JokerTier(rawValue: entry.tier)!,
                                           firstNight: NightKey(entry.firstNight)!, boxId: entry.boxId))
                changed = true
            }
        }
        return changed
    }

    static func mergeScheduleChanges(_ remote: [BackupFile.Change], into context: ModelContext) throws -> Bool {
        union(remote, local: try context.fetch(FetchDescriptor<ScheduleChange>()), matches: {
            $0.from == $1.from && $0.to == $1.to && $0.free == $1.free && $0.breakKey == $1.breakKey && $0.rule == $1.rule
                && SyncMerge.sameMoment($0.at, $1.at)
        }, add: { context.insert(ScheduleChange(at: $0.at, from: $0.from, to: $0.to, free: $0.free, breakKey: $0.breakKey, rule: $0.rule)) })
    }
}

extension UserProgress {
    /// Merges the profile of a sync file in: the earliest first-time dates, the latest rename dates, the larger
    /// "YYYY-MM" prompt month, the newest town name. The UI language is a per-device choice: it is adopted from the file
    /// only by a device that has never chosen one (`languageRaw == nil`) and only when the file's value is a language the
    /// app knows; a device with its own language is never touched. Returns whether anything changed.
    func merge(_ file: BackupFile) -> Bool {
        var changed = false
        if languageRaw == nil, let theirs = file.language, AppLanguage(rawValue: theirs) != nil {
            languageRaw = theirs
            changed = true
        }
        // the name is decided first – it falls back to `lastRenameAt`, which is merged below
        let ours = townNameChangedAt ?? lastRenameAt, theirs = file.townNameChangedAt ?? file.lastRenameAt
        if SyncMerge.newer((false, ours), (true, theirs)).value,
           townName != file.townName || townNameChangedAt != theirs {
            townName = file.townName
            townNameChangedAt = theirs                       // the stamp travels with the name
            changed = true
        }
        func take(_ current: Date?, _ new: Date?, _ set: (Date?) -> Void) {
            if new != current { set(new); changed = true }
        }
        take(onboardingCompletedAt, SyncMerge.earliest(onboardingCompletedAt, file.onboardingCompletedAt)) { onboardingCompletedAt = $0 }
        take(firstNightBriefingAt, SyncMerge.earliest(firstNightBriefingAt, file.firstNightBriefingAt)) { firstNightBriefingAt = $0 }
        take(scheduleCalibrationStart, SyncMerge.earliest(scheduleCalibrationStart, file.scheduleCalibrationStart)) {
            scheduleCalibrationStart = $0
        }
        take(lastRenameAt, SyncMerge.latest(lastRenameAt, file.lastRenameAt)) { lastRenameAt = $0 }
        take(lastFreeRenameAt, SyncMerge.latest(lastFreeRenameAt, file.lastFreeRenameAt)) { lastFreeRenameAt = $0 }
        take(changeWeekStart, SyncMerge.latest(changeWeekStart, file.changeWeekStart)) { changeWeekStart = $0 }   // the newest week
        let month = [schedulePromptMonth, file.schedulePromptMonth].compactMap { $0 }.max()
        if month != schedulePromptMonth { schedulePromptMonth = month; changed = true }
        return changed
    }
}
