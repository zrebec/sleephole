import SwiftData
import SwiftUI

@main
struct SleepHoleApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer
    @State private var sprites: SpriteLibrary
    @State private var model: AppModel

    init() {
        let container = try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self, JokerRecord.self)
        let sprites = SpriteLibrary.loadFromBundle()
        self.container = container
        _sprites = State(initialValue: sprites)
        // the real system alarm (AlarmKit) only on a real iPhone: the simulator, the tests and `-mute` get a stand-in
        // that cannot ring (see `SystemAlarms.forLaunch`)
        _model = State(initialValue: AppModel(context: container.mainContext, catalog: sprites.catalog,
                                              systemAlarm: SystemAlarms.forLaunch(),
                                              keepAlive: UIKitKeepAlive(),
                                              sleepSource: AppModel.launchSleepSource() ?? HealthKitSleepSource(),
                                              weather: WeatherStore.forLaunch(),
                                              timeSensitiveCheck: Notifications.timeSensitiveCheckForLaunch()))
    }
    /// Dev aid: launch with `-audioSmokeTest` to start the background audio immediately
    /// (lets agents verify the audio thread in the simulator without tapping through the UI).
    @State private var smokeAudio: AudioKeeper? = {
        guard ProcessInfo.processInfo.arguments.contains("-audioSmokeTest") else { return nil }
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
                    // screenshot mode (-startTestNight) must not be covered by the permission alert
                    let args = ProcessInfo.processInfo.arguments
                    guard !args.contains("-startTestNight"), !args.contains("-seedNights"),
                          !args.contains("-screenshot") else { return }
                    // before the guide is done, the guide asks for the permission at the right moment
                    guard model.onboardingDone else { return }
                    if await Notifications.requestAuthorization() {
                        Notifications.scheduleReminders(model.settings.schedule)
                        Notifications.scheduleExpiry(AppExpiry.date)
                    }
                    await model.refreshTimeSensitive()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    model.refresh()
                    model.appBecameActive()
                    Task { await model.refreshTimeSensitive() }
                }
        }
    }
}
