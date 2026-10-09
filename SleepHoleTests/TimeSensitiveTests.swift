import Foundation
import SleepCore
import SwiftData
import SwiftUI
import Testing
import UIKit
import UserNotifications
@testable import SleepHole

/// TOWN-W step 0b: the warning for a switched-off "Time Sensitive Notifications". Nothing here touches the real
/// notification centre (its permission alert would block the test host).
@MainActor
struct TimeSensitiveTests {
    let sprites = SpriteLibrary.loadFromBundle()

    final class Box { var answer = false }

    @Test(arguments: [
        (UNAuthorizationStatus.authorized, UNNotificationSetting.disabled, true),
        (.authorized, .enabled, false),
        (.authorized, .notSupported, false),
        (.provisional, .disabled, true),
        (.ephemeral, .disabled, true),
        (.denied, .disabled, false),
        (.notDetermined, .disabled, false),
    ])
    func theRule(authorization: UNAuthorizationStatus, setting: UNNotificationSetting, expected: Bool) {
        #expect(Notifications.timeSensitiveOff(authorization: authorization, setting: setting) == expected)
    }

    @Test func theLaunchCheck() async {
        #expect(await Notifications.timeSensitiveCheckForLaunch(args: ["-timeSensitive", "off"], underTest: true)() == false)
        #if targetEnvironment(simulator)
        #expect(await Notifications.timeSensitiveCheckForLaunch(args: ["-timeSensitive", "off"], underTest: false)() == true)
        #expect(await Notifications.timeSensitiveCheckForLaunch(args: ["-timeSensitive", "on"], underTest: false)() == false)
        #endif
    }

    func container() -> ModelContainer {
        try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self, JokerRecord.self,
                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    func model(_ c: ModelContainer, check: (@MainActor () async -> Bool)? = nil) -> AppModel {
        let suite = "sleephole-ts-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        if let check {
            return AppModel(context: c.mainContext, catalog: sprites.catalog, clock: SystemClock(), settings: AppSettings(),
                            servicesEnabled: false, timeSensitiveCheck: check, defaults: d)
        }
        return AppModel(context: c.mainContext, catalog: sprites.catalog, clock: SystemClock(), settings: AppSettings(),
                        servicesEnabled: false, defaults: d)
    }

    @Test func theModelFollowsTheCheck() async {
        let c = container()
        #expect(model(c).timeSensitiveOff == false)
        let box = Box()
        let m = model(c, check: { box.answer })
        #expect(m.timeSensitiveOff == false)
        box.answer = true
        await m.refreshTimeSensitive()
        #expect(m.timeSensitiveOff == true)
        box.answer = false
        await m.refreshTimeSensitive()
        #expect(m.timeSensitiveOff == false)
    }

    func render<V: View>(_ view: V, _ model: AppModel, dark: Bool) {
        let host = UIHostingController(rootView: view.environment(model).environment(sprites)
            .preferredColorScheme(dark ? .dark : .light))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date() + 0.15)
        window.isHidden = true
    }

    @Test func theWarningTriangleRequestsTheNotificationSettings() {
        let m = model(container(), check: { true })
        #expect(m.notificationsRequest == 0)
        m.showNotificationSettings()
        m.showNotificationSettings()
        #expect(m.notificationsRequest == 2)
    }

    @Test func theNotificationsScrollIsAOneShot() {
        let m = model(container(), check: { true })
        #expect(!m.takeNotificationsScroll())
        m.showNotificationSettings()
        #expect(m.takeNotificationsScroll())
        #expect(!m.takeNotificationsScroll())
        m.showNotificationSettings()
        #expect(m.takeNotificationsScroll())
        #expect(!m.takeNotificationsScroll())
    }

    @Test(arguments: AppLanguage.allCases) func theWarningRendersOnTodayAndInSettings(language: AppLanguage) async {
        let c = container()
        let m = model(c, check: { true })
        await m.refreshTimeSensitive()
        #expect(m.timeSensitiveOff)
        m.language = language
        defer { m.language = .en }
        for dark in [false, true] {
            render(TodayView(), m, dark: dark)
            render(SettingsView(), m, dark: dark)
        }
        m.showNotificationSettings()
        render(SettingsView(), m, dark: false)         // opened by the request: scrolls to the notifications section
        // the switch on: no triangle
        let on = model(c, check: { false })
        await on.refreshTimeSensitive()
        #expect(!on.timeSensitiveOff)
        on.language = language
        defer { on.language = .en }
        for dark in [false, true] { render(TodayView(), on, dark: dark) }
    }
}
