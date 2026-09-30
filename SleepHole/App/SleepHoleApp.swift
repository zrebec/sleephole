import SwiftData
import SwiftUI

@main
struct SleepHoleApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer
    @State private var sprites: SpriteLibrary
    @State private var model: AppModel

    init() {
        let container = try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self)
        let sprites = SpriteLibrary.loadFromBundle()
        self.container = container
        _sprites = State(initialValue: sprites)
        _model = State(initialValue: AppModel(context: container.mainContext, catalog: sprites.catalog))
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
                    // screenshot mode (-startTestNight) must not be covered by the permission alert
                    let args = ProcessInfo.processInfo.arguments
                    guard !args.contains("-startTestNight"), !args.contains("-seedNights") else { return }
                    // before the guide is done, the guide asks for the permission at the right moment
                    guard model.onboardingDone else { return }
                    if await Notifications.requestAuthorization() {
                        Notifications.scheduleReminders(model.settings.schedule)
                    }
                }
                .onChange(of: scenePhase) { _, phase in if phase == .active { model.refresh() } }
        }
    }
}
