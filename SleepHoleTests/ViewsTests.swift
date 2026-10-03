import Foundation
import SleepCore
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import SleepHole

/// Renders every screen in every phase (evaluates the SwiftUI bodies) with a FakeClock-driven model.
@MainActor
struct ViewsTests {
    let sprites = SpriteLibrary.loadFromBundle()
    let cal = Calendar.current

    init() { AudioKeeper.muted = true }

    func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }

    func makeModel(at now: Date, language: AppLanguage = .en) -> (AppModel, FakeClock, ModelContainer) {
        let c = try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self, JokerRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let clock = FakeClock(now)
        var s = AppSettings()
        s.wakeCode = "1234"
        let m = AppModel(context: c.mainContext, catalog: sprites.catalog, clock: clock, settings: s, servicesEnabled: false)
        m.language = language
        return (m, clock, c)
    }

    func render<V: View>(_ view: V, _ model: AppModel) {
        let host = UIHostingController(rootView: view.environment(model).environment(sprites))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date() + 0.15)
        window.isHidden = true
    }

    @Test(arguments: AppLanguage.allCases) func todayInEveryPhase(language: AppLanguage) {
        let (m, clock, _) = makeModel(at: date(5, 12), language: language)
        render(TodayView(), m)                                      // idle
        clock.now = date(5, 22, 25); m.refresh()
        render(TodayView(), m)                                      // canStart
        m.startNight()
        render(TodayView(), m)                                      // building, setup grace
        clock.now = date(5, 23); m.refresh()
        render(TodayView(), m)                                      // building, locked phone
        render(SleepSoundSheet(), m)
        m.playSleepSound(.rainTent, minutes: 30)
        render(TodayView(), m)                                      // sleep sound label
        m.stopSleepSound()
        m.append(.leftApp)
        clock.now += 60; m.refresh()
        render(TodayView(), m)                                      // collapsed
        clock.now = date(6, 6, 10); m.refresh()
        render(TodayView(), m)                                      // confirm window open
        clock.now = date(6, 6, 31); m.refresh()
        #expect(m.phase == .alarm)
        render(TodayView(), m)                                      // alarm
        m.confirm()
        render(TodayView(), m)                                      // result: ruins
        m.acknowledgeResult()
        for (day, late) in [(6, 60.0), (7, 1800.0)] {               // complete, unfinished
            clock.now = date(day, 22, 25); m.refresh(); m.startNight()
            clock.now = date(day + 1, 6, 30) + late; m.refresh(); m.confirm()
            render(TodayView(), m)
            render(ResultView(), m)
            m.acknowledgeResult()
        }
        clock.now = date(8, 13, 30); m.refresh()
        render(TodayView(), m)                                      // home: nap available, sleep disabled
        m.startNap(); render(TodayView(), m)                        // nap screen (setup)
        clock.now += 5 * 60; m.refresh(); render(TodayView(), m)    // resting
        m.append(.leftApp); clock.now += 30; m.append(.returned); render(TodayView(), m)   // interrupted
        clock.now = date(8, 14, 0); m.refresh(); m.confirm()
        render(TodayView(), m)                                      // nap result
        m.acknowledgeResult()
        clock.now = date(8, 23, 30); m.refresh(); render(TodayView(), m)   // too late for tonight
        m.startTestNight(); render(TodayView(), m)                  // debug canStart
        m.startNight(); clock.now += 240; m.refresh(); m.confirm()
        render(TodayView(), m)                                      // debug result
    }

    @Test(arguments: AppLanguage.allCases) func settingsTownRootAndDebugScreens(language: AppLanguage) {
        let (m, clock, _) = makeModel(at: date(5, 12), language: language)
        render(SettingsView(), m)
        render(NightLogView(), m)
        render(TownTab(), m)                                        // empty town
        for d in 5...9 {
            clock.now = date(d, 22, 25); m.refresh(); m.startNight()
            clock.now = date(d + 1, 6, 31); m.refresh(); m.confirm(); m.acknowledgeResult()
        }
        render(TownTab(), m)                                        // town with buildings
        render(NightLogView(), m)
        render(RootView(), m)
        render(PlaceholderView(title: "x", text: "y"), m)
        render(NavigationStack { DetectionTestView() }, m)
        render(ConstructionSite(buildingId: "l3-police", progress: 0.5), m)
        render(NightSky(), m)
        render(LevelInfo(), m)
        render(NavigationStack { CreditsView() }, m)
    }

    @Test(arguments: AppLanguage.allCases) func effectsAndJokers(language: AppLanguage) {
        let (m, clock, _) = makeModel(at: date(5, 12), language: language)
        render(JokerCard(), m)
        render(JokerSheet(), m)
        m.useJoker(.bronze)
        render(JokerCard(), m)                                      // active joker
        render(JokerSheet(), m)                                     // "Used" list, blocked tiers
        render(GoodNightSplash(nap: false) {}, m)
        render(GoodNightSplash(nap: true) {}, m)
        render(ZStack { SunRays(); DustPuff(); SparkleBurst() }.frame(width: 340, height: 300), m)
        render(NavigationStack { SoundEffectsTestView() }, m)
        render(TownIslandView(crane: true).frame(height: 210), m)
        render(LivingSky(), m)
        clock.now = date(6, 22, 25); m.refresh()
        render(LivingSky(), m)                                      // dusk palette
        for theme in AppTheme.allCases { m.settings.theme = theme; theme.apply() }
        #expect(m.settings.theme == .dark)
    }

    @Test(arguments: AppLanguage.allCases) func pauseAndExpiry(language: AppLanguage) {
        let (m, clock, _) = makeModel(at: date(5, 22, 25), language: language)
        m.refresh(); m.startNight()
        clock.now = date(6, 1, 0); m.refresh()
        render(TodayView(), m)                                      // "Pause · free"
        m.startPause()
        render(TodayView(), m)                                      // pause running, the crane rests
        clock.now = date(6, 1, 20); m.append(.leftApp); clock.now += 9; m.append(.returned)
        render(TodayView(), m)                                      // "Out of the app tonight: 9 s of 30 s", 2nd pause too dear
        clock.now = date(6, 6, 31); m.refresh(); m.confirm(code: "1234")
        render(TodayView(), m)                                      // result without the no-pause bonus
        m.acknowledgeResult()
        render(NightDetail(key: NightKey(year: 2026, month: 10, day: 6)), m)      // 🌙 Pauses: 1×
        render(JournalCard(), m)                                    // "Night pauses: 1"
        render(ExpiryCard(expiry: clock.now + 20 * 3600, now: clock.now), m)
        render(ExpiryCard(expiry: clock.now + 600, now: clock.now), m)
        #expect(NightView.countdown(588) == "9:48" && NightView.countdown(-3) == "0:00")
        #expect(!GuideText.pause.isEmpty && !GuideText.night.isEmpty)
    }
}
