import SwiftData
import SwiftUI

@main
struct SleepHoleApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer
    @State private var sprites: SpriteLibrary
    @State private var model: AppModel

    init() {
        // SYNC: with an iCloud container among the entitlements SwiftData would switch on CloudKit mirroring by itself
        // (`.automatic`) and refuse to load this store – the town travels as files (`ICloudSyncTransport`), never through
        // CloudKit. The configuration has no name, so it is the same `default.store` as before.
        let container = try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self, JokerRecord.self,
                                            configurations: ModelConfiguration(cloudKitDatabase: .none))
        let sprites = SpriteLibrary.loadFromBundle()
        self.container = container
        _sprites = State(initialValue: sprites)
        // the real system alarm (AlarmKit) only on a real iPhone: the simulator, the tests and `-mute` get a stand-in
        // that cannot ring (see `SystemAlarms.forLaunch`)
        let model = AppModel(context: container.mainContext, catalog: sprites.catalog,
                             systemAlarm: SystemAlarms.forLaunch(),
                             keepAlive: UIKitKeepAlive(),
                             sleepSource: AppModel.launchSleepSource() ?? HealthKitSleepSource(),
                             weather: WeatherStore.forLaunch(),
                             timeSensitiveCheck: Notifications.timeSensitiveCheckForLaunch(),
                             syncTransport: SyncTransports.forLaunch())
        // a guide finished on another device and adopted by ANY sync (the launch's or a later one) is not shown here, and
        // the guide is where the notification permission is asked – so it is asked when the sync brings the finished guide
        model.onGuideAdoptedBySync = { [weak model] in
            guard let model else { return }
            await Self.askForNotificationsIfGuideDone(model)
        }
        _model = State(initialValue: model)
    }
    /// Dev aid: launch with `-audioSmokeTest` to start the background audio immediately
    /// (lets agents verify the audio thread in the simulator without tapping through the UI).
    @State private var smokeAudio: AudioKeeper? = {
        guard DevArgs.list.contains("-audioSmokeTest") else { return nil }
        let keeper = AudioKeeper()
        try? keeper.start(ambience: .brownNoise, volume: 0.05)
        return keeper
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(sprites)
                .environment(model)
                .modelContainer(container)
                .task {
                    await model.refreshTimeSensitive()
                    await Self.askForNotificationsIfGuideDone(model)
                }
                .task {
                    // phase SYNC: the first read of the sync place (a fresh install waits for it before the guide)
                    await model.sync.launch()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    model.refresh()
                    model.appBecameActive()
                    model.sync.noteAppActive()
                    Task { await model.refreshTimeSensitive() }
                }
        }
    }

    /// Asks for the notification permission and schedules the reminders – only once the guide is done (before that the
    /// guide asks at the right moment) and never in screenshot mode (-startTestNight must not be covered by the alert).
    @MainActor
    private static func askForNotificationsIfGuideDone(_ model: AppModel) async {
        let args = DevArgs.list
        guard !args.contains("-startTestNight"), !args.contains("-seedNights"), !args.contains("-screenshot") else { return }
        guard model.onboardingDone else { return }
        if await Notifications.requestAuthorization() {
            model.rescheduleReminders()
            Notifications.scheduleExpiry(AppExpiry.date)
        }
        await model.refreshTimeSensitive()
    }
}
