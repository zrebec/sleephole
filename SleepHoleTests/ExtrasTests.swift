import Foundation
import SleepCore
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import SleepHole

/// Owner extras 2026-09-30: achievements, town name (idea S) and the weekly journal (idea M).
@MainActor
struct ExtrasTests {
    let sprites = SpriteLibrary.loadFromBundle()
    let cal = Calendar.current

    init() { AudioKeeper.muted = true }

    func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }

    func store() -> ModelContainer {
        try! ModelContainer(for: NightRecord.self, UserProgress.self,
                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    func model(_ c: ModelContainer, at now: Date) -> (AppModel, FakeClock) {
        let clock = FakeClock(now)
        var s = AppSettings(); s.wakeCode = "1234"
        return (AppModel(context: c.mainContext, catalog: sprites.catalog, clock: clock, settings: s,
                         servicesEnabled: false), clock)
    }

    func night(_ m: AppModel, _ clock: FakeClock, day: Int) {
        clock.now = date(day, 22, 25); m.refresh(); m.startNight()
        clock.now = date(day + 1, 6, 31); m.refresh(); m.confirm(code: "1234")
        m.acknowledgeResult()
    }

    func render<V: View>(_ view: V, _ m: AppModel) {
        let host = UIHostingController(rootView: view.environment(m).environment(sprites))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date() + 0.15)
        window.isHidden = true
    }

    // MARK: town name

    @Test func townNameDefaultsToTheLanguageAndIsStored() throws {
        let c = store()
        let (m, _) = model(c, at: date(1, 12))
        #expect(m.townName == "My Town" && m.customTownName == nil)
        m.language = .sk
        #expect(m.townName == "Moje mesto")
        m.renameTown("   Zajačikovo   ")
        #expect(m.townName == "Zajačikovo")
        m.renameTown(String(repeating: "x", count: 50))
        #expect(m.townName.count == AppModel.townNameMaxLength)
        m.renameTown("Zajačikovo")
        let (again, _) = model(c, at: date(1, 12))                       // stored in the database
        #expect(again.townName == "Zajačikovo")
        // backup round trip
        let data = try again.makeBackup().encoded()
        let (other, _) = model(store(), at: date(1, 12))
        try other.restore(BackupFile.decode(data))
        #expect(other.townName == "Zajačikovo")
        other.renameTown("  ")                                            // empty = back to the default
        #expect(other.customTownName == nil && other.townName == "Moje mesto")
        other.language = .en
    }

    // MARK: achievements

    @Test func achievementsPayCoinsOnceAndShowOnTheResultScreen() {
        let (m, clock) = model(store(), at: date(1, 12))
        #expect(m.achievements.isEmpty)
        for d in 1...2 { night(m, clock, day: d) }
        clock.now = date(3, 22, 25); m.refresh(); m.startNight()
        clock.now = date(4, 6, 31); m.refresh(); m.confirm(code: "1234")
        #expect(m.newAchievements == [.streak3])
        render(ResultView(), m)
        m.acknowledgeResult()
        #expect(m.achievements.map(\.achievement) == [.firstBuilding, .streak3])
        #expect(m.coins == 300 + 100)
        render(StatsView(), m)
        render(AchievementsCard(), m)
        render(NewAchievements(achievements: Achievement.allCases), m)
        for a in Achievement.allCases { #expect(!a.icon.isEmpty && !a.title.isEmpty && !a.detail.isEmpty) }
    }

    @Test func townHeaderWithAName() {
        let (m, clock) = model(store(), at: date(1, 12))
        night(m, clock, day: 1)
        m.renameTown("Zajačikovo")
        render(TownTab(), m)
        render(SettingsView(), m)
    }

    // MARK: weekly journal

    @Test func finishedWeekOnTheResultScreenAfterSundayNight() {
        let (m, clock) = model(store(), at: date(5, 12))                  // Monday 5 Oct 2026
        for d in 5...10 { night(m, clock, day: d) }                        // Mon … Sat evenings
        #expect(m.finishedWeek == nil)
        clock.now = date(11, 22, 25); m.refresh(); m.startNight()          // Sunday evening
        clock.now = date(12, 6, 31); m.refresh(); m.confirm(code: "1234")
        let week = m.finishedWeek
        #expect(week?.monday == NightKey("2026-10-05") && week?.complete == 7 && week?.built == 7)
        render(ResultView(), m)
        m.acknowledgeResult()
        #expect(m.finishedWeek == nil)
        night(m, clock, day: 12)                                           // Monday evening: already shown
        #expect(m.finishedWeek == nil)
        #expect(m.journalWeeks.count == 2 && m.currentMonday == NightKey("2026-10-12"))
        render(StatsView(), m)
        render(JournalCard(), m)
    }

    @Test func journalSentencesAreNeverShaming() throws {
        let (m, clock) = model(store(), at: date(5, 12))
        night(m, clock, day: 5)
        let one = try #require(m.journalWeeks.first)
        let empty = m.journalWeek(monday: NightKey("2026-09-28")!)
        for lang in AppLanguage.allCases {
            m.language = lang
            #expect(!WeekJournalView.sentence(empty, previous: nil).isEmpty)
            #expect(WeekJournalView.sentence(one, previous: nil) != WeekJournalView.sentence(empty, previous: nil))
            #expect(WeekJournalView.sentence(one, previous: empty) == WeekJournalView.sentence(one, previous: nil))
            render(WeekJournalView(week: one, previous: one), m)
            render(JournalCard(), m)                                       // empty current week
        }
        m.language = .en
        #expect(WeekJournalView.range(one) == "10/5 – 10/11")
    }
}
