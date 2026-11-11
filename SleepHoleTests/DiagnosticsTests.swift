import Foundation
import SleepCore
import SwiftData
import Testing
import UIKit
@testable import SleepHole

/// 13ab: the tolerant journal (B61) and the diagnostic track – local only, never changing what a night counts.
@MainActor
struct DiagnosticsTests {
    let catalog = SpriteLibrary.loadFromBundle().catalog!
    let cal = Calendar.current

    init() { AudioKeeper.muted = true }

    func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }

    struct Rig {
        let container: ModelContainer
        let clock: FakeClock
        let model: AppModel
    }

    func rig(at now: Date) -> Rig {
        let c = try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self,
                                    JokerRecord.self, BoxRecord.self,
                                    configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let clock = FakeClock(now)
        var s = AppSettings(); s.wakeCode = "1234"
        let defaults = UserDefaults(suiteName: "sleephole-diag-\(UUID().uuidString)")!
        let model = AppModel(context: c.mainContext, catalog: catalog, clock: clock, settings: s, servicesEnabled: false, defaults: defaults)
        model.sync.firstReadDone = true
        return Rig(container: c, clock: clock, model: model)
    }

    /// A night started at 22:25 and left running.
    func running(_ r: Rig, day: Int = 5) -> NightRecord {
        r.clock.now = date(day, 22, 25); r.model.refresh(); r.model.startNight()
        return r.model.active!
    }

    func finish(_ r: Rig, day: Int = 5) {
        r.clock.now = date(day + 1, 6, 30) + 60; r.model.refresh()
        r.model.confirm(code: "1234")
        r.model.acknowledgeResult()
    }

    // MARK: B61 – an unknown event kind

    @Test func anUnknownKindKeepsTheEarlierEventsAfterAnAppend() {
        let r = rig(at: date(5, 12))
        let rec = running(r)
        let started = rec.log.events[0]
        let stored = "[{\"kind\":\"started\",\"at\":\(started.at.timeIntervalSinceReferenceDate)},{\"kind\":\"aKindFromTheFuture\",\"at\":5},{\"kind\":\"locked\",\"at\":\(started.at.timeIntervalSinceReferenceDate + 60)}]"
        rec.eventsData = Data(stored.utf8)
        #expect(rec.log.events.map(\.kind) == [.started, .locked])           // read, not "empty"
        #expect(rec.append(.returned, at: started.at + 90))
        #expect(rec.log.events.map(\.kind) == [.started, .locked, .returned])
    }

    @Test func aJournalThatIsNoArrayIsNeverOverwritten() {
        let r = rig(at: date(5, 12))
        let rec = running(r)
        let junk = Data("this is not json".utf8)
        rec.eventsData = junk
        #expect(rec.log.events.isEmpty)
        #expect(rec.append(.confirmed, at: r.clock.now) == false)
        #expect(rec.eventsData == junk)                                       // untouched
        #expect(rec.confirmedAt != nil)                                       // the side values still follow
        // through the model the refusal lands in the diagnostic track
        r.model.append(.returned)
        r.model.diag.flush()
        #expect(rec.eventsData == junk)
        #expect(rec.diagLog.entries.contains { $0.k == "journal" })
    }

    @Test func aSyncFileWithAnUnknownKindIsStillRead() throws {
        let a = rig(at: date(1, 12)), b = rig(at: date(1, 12))
        _ = running(a, day: 5); finish(a, day: 5)
        let data = try a.model.makeSyncFile().encodedForSync()
        // a newer build's file: one night holds an event kind this build has never heard of
        var root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var nights = try #require(root["nights"] as? [[String: Any]])
        var events = try #require(nights[0]["events"] as? [[String: Any]])
        events.insert(["kind": "diagnosticsFromTheFuture", "at": 1.0], at: 1)
        nights[0]["events"] = events
        root["nights"] = nights
        let edited = try JSONSerialization.data(withJSONObject: root)

        let file = try BackupFile.decodeSync(edited)                          // used to throw → the whole sync file was dropped
        #expect(file.nights.count == 1)
        #expect(!file.nights[0].events.contains { $0.at.timeIntervalSinceReferenceDate == 1.0 })
        #expect(file.nights[0].events.map(\.kind).first == .started)
        b.clock.now = a.clock.now; b.model.refresh()
        #expect(try b.model.mergeSync([file]))
        #expect(b.model.records().count == 1)
        #expect(b.model.records()[0].log.events.map(\.kind) == a.model.records()[0].log.events.map(\.kind))
    }

    @Test func aBackupWithAnUnknownKindImports() throws {
        let a = rig(at: date(1, 12)), b = rig(at: date(1, 12))
        _ = running(a, day: 5); finish(a, day: 5)
        let data = try a.model.makeBackup().encoded()
        var root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var nights = try #require(root["nights"] as? [[String: Any]])
        var events = try #require(nights[0]["events"] as? [[String: Any]])
        events.append(["kind": "unknownLater", "at": "2026-10-06T06:00:00Z"])
        nights[0]["events"] = events
        root["nights"] = nights
        let file = try BackupFile.decode(try JSONSerialization.data(withJSONObject: root))
        try b.model.restore(file)
        #expect(b.model.records().count == 1)
    }

    // MARK: the track never changes anything that counts

    @Test func theTrackStaysOutOfTheJournalTheSyncFileTheFingerprintAndTheRules() throws {
        let r = rig(at: date(1, 12))
        let rec = running(r)
        r.model.diag.flush()
        let eventsBefore = rec.eventsData
        let copyBefore = SyncStore.copy(of: rec.backup)
        let syncBefore = try r.model.makeSyncFile().encodedForSync()
        let backupBefore = try r.model.makeBackup().encoded()
        let resultBefore = NightEvaluator.result(for: rec.log, key: rec.log.key, rules: rec.rules)
        let revision = r.model.dataRevision

        for i in 0..<30 { r.model.diag.note("life", "inactive \(i)") }
        r.model.diag.notePower("locked")
        r.model.diag.flush()

        #expect(rec.eventsData == eventsBefore)
        #expect(SyncStore.copy(of: rec.backup) == copyBefore)
        #expect(try r.model.makeSyncFile().encodedForSync() == syncBefore)
        #expect(try r.model.makeBackup().encoded() == backupBefore)
        #expect(NightEvaluator.result(for: rec.log, key: rec.log.key, rules: rec.rules) == resultBefore)
        #expect(r.model.dataRevision == revision)                            // no revision bump, so no sync wake-up either
        #expect(rec.diagLog.entries.count > 30)
        #expect(!String(decoding: syncBefore, as: UTF8.self).contains("ctx.app"))
        #expect(!String(decoding: backupBefore, as: UTF8.self).contains("ctx.app"))
    }

    @Test func theRecordsCacheStillSeesTheNightAfterATrackSave() {
        let r = rig(at: date(1, 12))
        let rec = running(r)
        #expect(r.model.records().count == 1)
        r.model.diag.note("life", "active")
        r.model.diag.flush()
        let again = r.model.records()
        #expect(again.count == 1 && again[0] === rec)
        #expect(again[0].diagLog.entries.contains { $0.k == "life" })
    }

    // MARK: saving

    @Test func entriesAreSavedCoalescedAndFlushedAtTheMomentsThatMatter() {
        let r = rig(at: date(1, 12))
        _ = running(r)
        let base = r.model.diag.saves
        #expect(base >= 1)                                                    // the start snapshot
        for i in 0..<20 { r.model.diag.note("life", "x\(i)") }               // the same second: nothing is saved per entry
        #expect(r.model.diag.saves == base)
        #expect(r.model.diag.buffer.count == 20)

        r.model.diagFromMonitor("life", "background")                       // the app goes to the background: saved now
        #expect(r.model.diag.saves == base + 1 && r.model.diag.buffer.isEmpty)

        r.model.diag.note("life", "again")                                  // inside the interval: waits
        #expect(r.model.diag.saves == base + 1)
        r.clock.now += Diagnostics.flushInterval + 1
        r.model.diag.note("life", "later")                                  // the interval is over: this one saves both
        #expect(r.model.diag.saves == base + 2 && r.model.diag.buffer.isEmpty)

        r.model.diag.note("life", "waiting")
        r.model.appWillTerminate()                                          // termination saves at once
        #expect(r.model.diag.buffer.isEmpty)
    }

    @Test func theAlarmAndTheEndSaveAtOnce() {
        let r = rig(at: date(1, 12))
        let rec = running(r)
        r.clock.now = rec.wake + 1; r.model.refresh()                       // the alarm
        #expect(r.model.diag.buffer.isEmpty)
        #expect(rec.diagLog.entries.contains { $0.k == "power" && ($0.v ?? "").hasPrefix("alarm") })
        r.clock.now = rec.wake + 60
        r.model.confirm(code: "1234")
        #expect(!r.model.diag.isTracking)                                   // finalized: the track is closed
        let ks = rec.diagLog.entries.map(\.k)
        #expect(ks.contains("end"))
        #expect(rec.diagLog.entries.contains { $0.k == "power" && ($0.v ?? "").hasPrefix("confirmed") })
        let count = rec.diagLog.entries.count
        r.model.diag.note("life", "after the night")                        // nothing running: nothing is written
        r.model.diag.flush()
        #expect(rec.diagLog.entries.count == count)
    }

    // MARK: bounds

    @Test func atTheCapFurtherNotesCauseNoSave() {
        let r = rig(at: date(1, 12))
        let rec = running(r)
        let d = r.model.diag
        for i in 0..<(DiagLog.maxEntries + 20) {
            r.clock.now = r.clock.now + 20                                  // beyond the flush interval: every note saves
            d.note("e", "\(i)")
        }
        d.flush()
        #expect(rec.diagLog.isFull)
        let saves = d.saves, data = rec.diagData
        for _ in 0..<5 { r.clock.now = r.clock.now + 20; d.note("late", "x") }
        d.flush()
        #expect(d.saves == saves && d.buffer.isEmpty && rec.diagData == data)
    }

    @Test func aFinishedNightDropsTheTracksOlderThan30Days() {
        let r = rig(at: date(1, 12))
        let old = NightRecord(window: NightWindow(key: NightKey(date: date(2, 6), calendar: .current), bedtime: date(1, 22), wake: date(2, 6)), buildingId: "x", isDebug: false, setupGrace: 300)
        old.finalizedAt = date(2, 6)
        old.diagData = Data("[]".utf8)
        let events = old.eventsData
        let recent = NightRecord(window: NightWindow(key: NightKey(date: date(5, 6), calendar: .current), bedtime: date(4, 22), wake: date(5, 6)), buildingId: "x", isDebug: false, setupGrace: 300)
        recent.finalizedAt = date(5, 6)
        recent.diagData = Data("[]".utf8)
        r.container.mainContext.insert(old); r.container.mainContext.insert(recent)
        r.clock.now = date(1, 12) + 45 * 86_400
        r.model.diag.prune([old, recent])
        #expect(old.diagData == nil && old.eventsData == events)
        #expect(recent.diagData == nil)                                     // 45 days: both stale
        r.clock.now = date(5, 12) + 20 * 86_400
        let fresh = NightRecord(window: NightWindow(key: NightKey(date: date(26, 6), calendar: .current), bedtime: date(25, 22), wake: date(26, 6)), buildingId: "x", isDebug: false, setupGrace: 300)
        fresh.finalizedAt = date(25, 6)
        fresh.diagData = Data("[]".utf8)
        r.model.diag.prune([fresh])
        #expect(fresh.diagData != nil)
    }

    // MARK: the start snapshot

    @Test func aStartedNightHasTheContextLines() {
        let r = rig(at: date(1, 12))
        let rec = running(r)
        let entries = rec.diagLog.entries
        let by = Dictionary(grouping: entries, by: \.k)
        for k in ["ctx.app", "ctx.sound", "ctx.alarm", "ctx.device"] { #expect(by[k]?.count == 1, "\(k)") }
        let app = by["ctx.app"]?.first?.v ?? ""
        #expect(app.contains("nap=0") && app.contains("strict=0") && app.contains("setup=600") && app.contains("early=0"))
        #expect(app.contains("lang=en") && app.contains("ios="))
        #expect((by["ctx.sound"]?.first?.v ?? "").contains("vol=15"))
        let alarm = by["ctx.alarm"]?.first?.v ?? ""
        #expect(alarm.contains("sound=alarm_gentle") && alarm.contains("start=") && alarm.contains("end=") && alarm.contains("rise=") && alarm.contains("sys=on"))
        let device = by["ctx.device"]?.first?.v ?? ""
        for key in ["vo=", "lock=", "lpm=", "batt=", "state=", "vol=", "out=", "bright="] { #expect(device.contains(key), "\(key)") }
        #expect(by["ctx.resume"] == nil)
        // nothing personal: the wake code and a city never appear
        #expect(!entries.contains { ($0.v ?? "").contains("1234") })
    }

    @Test func aNapHasTheContextLinesToo() {
        let r = rig(at: date(5, 13, 30))
        r.model.startNap()
        let rec = r.model.active!
        #expect(rec.isNap)
        #expect((rec.diagLog.entries.first { $0.k == "ctx.app" }?.v ?? "").contains("nap=1"))
    }

    @Test func aRelaunchedNightContinuesItsTrackWithAResumeLine() {
        let r = rig(at: date(1, 12))
        let rec = running(r)
        let before = rec.diagLog.entries.count
        r.model.diag.end()
        // a new model over the same store = the app relaunched while the night runs
        let clock = r.clock
        var s = AppSettings(); s.wakeCode = "1234"
        clock.now += 600
        let again = AppModel(context: r.container.mainContext, catalog: catalog, clock: clock, settings: s, servicesEnabled: false,
                             defaults: UserDefaults(suiteName: "sleephole-diag-\(UUID().uuidString)")!)
        let entries = again.active!.diagLog.entries
        #expect(entries.count > before)
        #expect(entries.prefix(before).map(\.k) == rec.diagLog.entries.prefix(before).map(\.k))
        #expect(entries.dropFirst(before).first?.k == "ctx.resume")
        #expect(entries.filter { $0.k == "ctx.app" }.count == 2)
    }

    // MARK: lifecycle and calls from the monitor's seams

    func monitor() -> (LifecycleMonitor, () -> [String], FakeClock) {
        let m = LifecycleMonitor()
        let clock = FakeClock(date(1, 23))
        var lines: [String] = []
        m.now = { clock.now }
        m.onDiag = { k, v in lines.append("\(k) \(v)") }
        m.backgroundDelay = .milliseconds(60)
        return (m, { lines }, clock)
    }

    @Test func callShapesAreLoggedWithoutNumbersNamesOrApps() {
        let (m, lines, clock) = monitor()
        var events: [NightEventKind] = []
        m.onEvent = { kind, _ in events.append(kind) }
        let one = UUID(), two = UUID()
        m.callChanged(CallInfo(uuid: one, isOutgoing: false, hasConnected: false, hasEnded: false))
        clock.advance(3)
        m.callChanged(CallInfo(uuid: one, isOutgoing: false, hasConnected: true, hasEnded: false))
        m.callChanged(CallInfo(uuid: two, isOutgoing: true, hasConnected: false, hasEnded: false))
        clock.advance(7)
        m.callChanged(CallInfo(uuid: two, isOutgoing: true, hasConnected: false, hasEnded: true))
        m.callChanged(CallInfo(uuid: one, isOutgoing: false, hasConnected: true, hasEnded: true))
        #expect(lines() == [
            "call start dir=in live=1",
            "call connected after=3s",
            "call start dir=out live=2",
            "call end dur=7s connected=0",
            "call end dur=10s connected=1",
        ])
        #expect(events == [.callStarted, .callEnded])                         // the rule events stay as they were
    }

    @Test func lifecycleSignalsReachTheTrackAndRepeatsAreDropped() async {
        let (m, lines, clock) = monitor()
        m.isAppActive = { false }
        m.canTellLockFromLeaving = { true }
        m.screenWindow = .seconds(60)
        m.start()
        let nc = NotificationCenter.default
        // the system observers deliver on the main queue: let each post land before the next step
        func post(_ name: Notification.Name) async { nc.post(name: name, object: nil); try? await Task.sleep(for: .milliseconds(20)) }
        await post(UIApplication.willResignActiveNotification)
        await post(UIApplication.willResignActiveNotification)                       // the same line within 0.2 s: dropped
        clock.advance(1)
        await post(UIApplication.willResignActiveNotification)
        m.dataProtectionChanged(locked: true)
        m.dataProtectionChanged(locked: true)                                         // dropped too
        clock.advance(1)
        m.dataProtectionChanged(locked: false)
        m.didEnterBackground()
        m.willEnterForeground()                                                       // back before the decision
        m.didBecomeActive()
        try? await Task.sleep(for: .milliseconds(150))
        m.stop()
        #expect(lines().filter { $0.hasPrefix("life") } == [
            "life inactive", "life inactive", "life data=locked", "life data=unlocked", "life background",
            "life foreground", "life decision=short", "life active"])
    }

    @Test func theBackgroundDecisionIsWrittenDownForALockAndForALeave() async {
        let (m, lines, _) = monitor()
        m.isAppActive = { false }
        m.canTellLockFromLeaving = { true }
        m.screenWindow = .seconds(60)
        m.start()
        m.didEnterBackground()
        try? await Task.sleep(for: .milliseconds(200))                                // no lock signal: a real leave
        #expect(lines().filter { $0.hasPrefix("life") } == ["life background", "life decision=leave"])
        m.stop()

        let (n, more, _) = monitor()
        n.isAppActive = { false }
        n.canTellLockFromLeaving = { true }
        n.screenWindow = .seconds(60)
        n.start()
        n.dataProtectionChanged(locked: true)
        n.didEnterBackground()
        try? await Task.sleep(for: .milliseconds(200))
        n.stop()
        #expect(more().contains("life decision=lock"))
    }

    @Test func aPhoneThatCannotTellALockFromLeavingSaysSo() async {
        let (m, lines, _) = monitor()
        m.isAppActive = { false }
        m.canTellLockFromLeaving = { false }
        m.start()
        m.didEnterBackground()
        try? await Task.sleep(for: .milliseconds(200))
        m.stop()
        #expect(lines().contains("life decision=cannotTell"))
    }

    // MARK: the battery switch has more than one user

    @Test func theBatterySwitchStaysOnWhileAnyUserNeedsIt() {
        BatteryMonitoring.set("test-a", on: true)
        BatteryMonitoring.set("test-b", on: true)
        BatteryMonitoring.set("test-a", on: true)                             // twice is the same claim
        BatteryMonitoring.set("test-a", on: false)
        #expect(BatteryMonitoring.holds("test-b") && !BatteryMonitoring.holds("test-a"))    // test-b still holds it
        BatteryMonitoring.set("test-b", on: false)
        #expect(!BatteryMonitoring.holds("test-a") && !BatteryMonitoring.holds("test-b"))
    }
}
