import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = ProcessInfo.processInfo.arguments.contains("town") ? 1 : 0
    /// Screenshot / agent modes skip the first-run guide.
    private let screenshotMode = ProcessInfo.processInfo.arguments.contains { $0 == "-seedNights" || $0 == "-startTestNight" }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Dnes", systemImage: "moon.stars.fill", value: 0) { TodayView() }
            Tab("Mesto", systemImage: "building.2.fill", value: 1) { TownTab() }
            Tab("Štatistiky", systemImage: "chart.bar.fill", value: 2) { PlaceholderView(title: "Štatistiky", text: "Séria, kalendár a pravidelnosť spánku.") }
            Tab("Nastavenia", systemImage: "gearshape.fill", value: 3) { SettingsView() }
        }
        .fullScreenCover(isPresented: Binding(get: { !model.onboardingDone && !screenshotMode }, set: { _ in })) {
            GuideView()
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


