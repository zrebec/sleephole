import Foundation
import SleepCore
import SwiftData
import Testing
@testable import SleepHole

#if DEBUG

/// A reinstall with iCloud switched off for the app, the first-run guide with other times, then iCloud on again: the
/// account's schedule and its change week / lock must win, and nothing of the new guide may reach the old device.
extension SyncEngineTests {
    private func reinstallScenario(day: Int, expectLocked: Bool) async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        // A: the user's phone – guide finished on day 1 (opens the first change week), times 21:30–6:00, synced since
        let a = device(folder, id: "A", at: date(1, 12), firstRead: true)
        defer { stopAll(a) }
        a.model.settings.schedule.bedtime = TimeOfDay(21, 30)
        a.model.settings.schedule.wake = TimeOfDay(6, 0)
        a.model.completeOnboarding()
        let weekStartA = a.model.changeWeekStart
        a.clock.now = date(day, 12); a.model.refresh()
        let stateA = a.model.scheduleState
        if expectLocked {
            if case .locked = stateA {} else { Issue.record("A should be locked, is \(stateA)") }
        } else {
            if case .changeWeek = stateA {} else { Issue.record("A should be in its change week, is \(stateA)") }
        }
        await a.sync.syncNow()

        // B: reinstall – iCloud for the app was switched off first (syncOn false), a fresh store, the guide runs
        let b = device(folder, id: "B", at: date(day, 12, 5), syncOn: false)
        defer { stopAll(b) }
        #expect(!b.sync.holdsGuide && b.model.needsGuide)
        b.model.settings.schedule.bedtime = TimeOfDay(22, 15)
        b.model.settings.schedule.wake = TimeOfDay(6, 45)
        b.model.completeOnboarding()
        #expect(b.model.settings.changedAt == nil)

        // iCloud switched on again: the first read of the account
        b.clock.now = date(day, 12, 10)
        b.model.settings.syncOff = false
        await b.sync.syncNow()
        #expect(b.sync.firstReadDone)
        #expect(b.model.settings.schedule.bedtime == TimeOfDay(21, 30) && b.model.settings.schedule.wake == TimeOfDay(6, 0))
        #expect(b.model.changeWeekStart == weekStartA)                                   // A's week, not a new one
        #expect(b.model.scheduleState == stateA)

        // nothing of B's guide reaches A
        await b.sync.syncNow()
        await a.sync.syncNow()
        #expect(a.model.settings.schedule.bedtime == TimeOfDay(21, 30) && a.model.settings.schedule.wake == TimeOfDay(6, 0))
        #expect(a.model.changeWeekStart == weekStartA)
        #expect(a.model.scheduleState == stateA)
    }

    @Test func aReinstallWithICloudOffDoesNotReplaceTheScheduleWhileTheOldChangeWeekRuns() async throws {
        try await reinstallScenario(day: 4, expectLocked: false)
    }

    @Test func aReinstallWithICloudOffDoesNotReplaceTheScheduleWhileTheOldDeviceIsLocked() async throws {
        try await reinstallScenario(day: 12, expectLocked: true)
    }

    /// Build 14 (step 14a3): a fresh install meets the old-build device's marker-less copy of a run (more events) and its own
    /// earlier marked copy of the same run – in either order, in one merge or in two – and the marker survives.
    @Test func aFreshInstallKeepsTheCoinRuleMarkerWhateverOrderTheCopiesComeIn() throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = device(folder, id: "A", at: date(1, 12), firstRead: true)
        defer { stopAll(a) }
        night(a, day: 1)
        let marked = a.model.makeSyncFile()
        #expect(marked.nights.count == 1 && marked.nights[0].coinRule == CoinRule.current)
        var old = marked                                                  // the same run, sent back by a build before 14
        old.nights[0].coinRule = nil
        old.nights[0].events.append(NightEvent(.audioResumed, at: date(2, 3)))
        for (index, order) in [[old, marked], [marked, old]].enumerated() {
            for oneMerge in [true, false] {
                let b = device(folder, id: "B\(index)\(oneMerge)", at: date(5, 12), firstRead: true)
                defer { stopAll(b) }
                if oneMerge {
                    try b.model.mergeSync(order)
                } else {
                    for file in order { try b.model.mergeSync([file]) }
                }
                let kept = b.model.records()
                #expect(kept.count == 1 && kept[0].coinRule == CoinRule.current)
                #expect(kept[0].backup.events.count == old.nights[0].events.count)     // the longer copy won
                #expect(try b.model.mergeSync(order) == false)                           // idempotent
            }
        }
    }

    /// A truly new user (nothing in the account): the week the guide opened stays.
    @Test func aNewUserWithAnEmptyAccountKeepsTheWeekTheGuideOpened() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let b = device(folder, id: "B", at: date(4, 12), syncOn: false)
        defer { stopAll(b) }
        b.model.completeOnboarding()
        let week = b.model.changeWeekStart
        #expect(week != nil)
        b.clock.now = date(4, 12, 10)
        b.model.settings.syncOff = false
        await b.sync.syncNow()
        #expect(b.sync.firstReadDone)
        #expect(b.model.changeWeekStart == week)
    }

    /// Devices that are in contact already keep "the latest week wins" (e.g. a paid unlock on the other device).
    @Test func aLaterRealWeekOnAnotherDeviceStillWinsOnAnAlreadySyncedDevice() async throws {
        let folder = tempFolder(); defer { try? FileManager.default.removeItem(at: folder) }
        let a = device(folder, id: "A", at: date(1, 12), firstRead: true)
        defer { stopAll(a) }
        let b = device(folder, id: "B", at: date(3, 12), firstRead: true)
        defer { stopAll(b) }
        a.model.completeOnboarding()
        b.model.completeOnboarding()
        let later = b.model.changeWeekStart
        #expect(later != a.model.changeWeekStart)
        await a.sync.syncNow(); await b.sync.syncNow(); await a.sync.syncNow()
        #expect(a.model.changeWeekStart == later && b.model.changeWeekStart == later)
    }
}

#endif
