import Foundation
import SleepCore
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import SleepHole

/// The first-run guide, the first-night checklist and their database flags (`UserProgress`).
@MainActor
struct GuideTests {
    let sprites = SpriteLibrary.loadFromBundle()
    let cal = Calendar.current

    init() { AudioKeeper.muted = true }

    func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }

    func makeModel(_ c: ModelContainer, at now: Date) -> (AppModel, FakeClock) {
        let clock = FakeClock(now)
        let m = AppModel(context: c.mainContext, catalog: sprites.catalog, clock: clock, settings: AppSettings(),
                         servicesEnabled: false)
        return (m, clock)
    }

    func store() -> ModelContainer {
        try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self, JokerRecord.self,
                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    func render<V: View>(_ view: V, _ model: AppModel) {
        let host = UIHostingController(rootView: view.environment(model).environment(sprites))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date() + 0.15)
        window.isHidden = true
    }

    @Test func guideIsStoredInTheDatabase() {
        let c = store()
        let (m, _) = makeModel(c, at: date(5, 12))
        #expect(!m.onboardingDone)
        m.completeOnboarding()
        #expect(m.onboardingDone)
        let rows = (try? c.mainContext.fetch(FetchDescriptor<UserProgress>())) ?? []
        #expect(rows.count == 1 && rows[0].onboardingCompletedAt != nil)
        let (again, _) = makeModel(c, at: date(6, 12))                  // relaunch keeps it
        #expect(again.onboardingDone)
    }

    @Test func firstNightBriefingOnlyBeforeTheFirstRealNight() {
        let c = store()
        let (m, clock) = makeModel(c, at: date(5, 22, 25))
        m.refresh()
        #expect(m.needsFirstNightBriefing)
        m.startTestNight()                                               // debug nights never need it
        #expect(!m.needsFirstNightBriefing)
        m.cancelFastNight()
        m.acknowledgeFirstNightBriefing()
        #expect(!m.needsFirstNightBriefing && m.firstNightBriefed)
        m.resetGuide()
        #expect(!m.onboardingDone && m.needsFirstNightBriefing)
        m.startNight()                                                   // a started real night also ends it
        #expect(!m.needsFirstNightBriefing)
        _ = clock
    }

    @Test func guideTextUsesTheRealRules() {
        Lang.current = .sk
        defer { Lang.current = .en }
        #expect(GuideText.startWindow.contains("10 minút") && GuideText.startWindow.contains("5 minút"))
        #expect(GuideText.setup.contains("5 minút"))
        #expect(GuideText.night.contains("10 sekúnd"))
        #expect(GuideText.alarm.contains("2 minúty") && GuideText.alarm.contains("30 minút"))
        #expect(GuideText.outcomes.count == 3 && GuideText.levels.count == 4)
        #expect(GuideText.levels[1].when.contains("5 nocí") && GuideText.levels[3].when.contains("30 nocí"))
        #expect(Plural.minutes(60) == "1 minútu" && Plural.seconds(3) == "3 sekundy" && Plural.nights(1) == "1 noc")
    }

    @Test func guideTextInEnglish() {
        Lang.current = .en
        #expect(GuideText.startWindow.contains("10 minutes") && GuideText.startWindow.contains("5 minutes"))
        #expect(GuideText.night.contains("10 seconds"))
        #expect(GuideText.alarm.contains("2 minutes") && GuideText.alarm.contains("30 minutes"))
        #expect(GuideText.levels[1].when == "after 5 nights" && GuideText.levels[0].what == "houses and apartment blocks")
        #expect(Plural.minutes(60) == "1 minute" && Plural.seconds(3) == "3 seconds" && Plural.nights(1) == "1 night")
    }

    @Test func guideAndBriefingRender() {
        let c = store()
        let (m, _) = makeModel(c, at: date(5, 22, 25))
        m.refresh()
        render(GuideView(), m)
        render(GuideView(replay: true), m)
        render(ScheduleFields(schedule: .constant(Schedule())), m)
        render(FirstNightBriefing(), m)
        render(HomeView(), m)
        render(RootView(), m)                                             // shows the guide cover
        m.completeOnboarding()
        render(RootView(), m)
    }

    @Test func finishingTheGuideMarksItDone() {
        let c = store()
        let (m, _) = makeModel(c, at: date(5, 12))
        GuideView.complete(replay: true, model: m)
        #expect(!m.onboardingDone)                                        // a replay changes nothing
        GuideView.complete(replay: false, model: m)
        #expect(m.onboardingDone)
    }
}
