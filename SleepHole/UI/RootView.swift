import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    /// `-openTab town|settings` (screenshots)
    @State private var tab: Int = {
        let a = ProcessInfo.processInfo.arguments
        return a.contains("town") ? 1 : a.contains("stats") ? 2 : a.contains("settings") ? 3 : 0
    }()
    /// Screenshot / agent modes skip the first-run guide.
    private let screenshotMode = ProcessInfo.processInfo.arguments.contains { $0 == "-seedNights" || $0 == "-startTestNight" }

    var body: some View {
        // `.id(language)`: a language switch rebuilds every screen so all `L(...)` texts are re-read at once
        // (the selected tab survives).
        let lang = model.language
        TabView(selection: $tab) {
            Tab(L("Today"), systemImage: "moon.stars.fill", value: 0) { TodayView().id(lang) }
            Tab(L("Town"), systemImage: "building.2.fill", value: 1) { TownTab().id(lang) }
            Tab(L("Stats"), systemImage: "chart.bar.fill", value: 2) { StatsView().id(lang) }
            Tab(L("Settings"), systemImage: "gearshape.fill", value: 3) { SettingsView().id(lang) }
        }
        .environment(\.locale, lang.locale)
        .onChange(of: model.settingsRequest) { _, _ in tab = 3 }          // "Adjust" on the monthly card
        .fullScreenCover(isPresented: Binding(get: { !model.onboardingDone && !screenshotMode }, set: { _ in })) {
            GuideView().id(lang).environment(\.locale, lang.locale)
        }
    }
}

struct PlaceholderView: View {
    let title: String
    let text: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: "hammer.fill", description: Text(text))
                .navigationTitle(title)
        }
    }
}


