import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    /// `-openTab town|settings` (screenshots)
    @State private var tab: Int = {
        switch DevArgs.value(after: "-openTab") {
        case "town": return 1
        case "stats": return 2
        case "settings": return 3
        default: return 0
        }
    }()
    /// Screenshot / agent modes skip the first-run guide.
    private let screenshotMode = DevArgs.list.contains {
        $0 == "-seedNights" || $0 == "-startTestNight" || $0 == "-screenshot"
    }

    /// The tab bar on iOS 18 and below (and wherever UIKit still draws it): an opaque bar (B15).
    private static func solidTabBar() {
        let a = UITabBarAppearance()
        a.configureWithOpaqueBackground()
        a.backgroundColor = .systemBackground
        UITabBar.appearance().standardAppearance = a
        UITabBar.appearance().scrollEdgeAppearance = a
    }

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
        // a solid tab bar (B15, owner: no transparency): the iOS 26 glass bar refracted the text scrolled under it
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(Color(uiColor: .systemBackground), for: .tabBar)
        .onChange(of: model.settingsRequest) { _, _ in tab = 3 }          // "Adjust" on the monthly card
        // the Today island. NOT inside withAnimation: an animated selection change left the TabView half-switched
        // (owner bug 2026-10-03: the sleeping cat of Today stayed on screen over the Town; in the simulator the tab
        // did not switch at all)
        .onChange(of: model.townRequest) { _, _ in tab = 1 }
        .onChange(of: model.notificationsRequest) { _, _ in tab = 3 }     // the warning triangle on Today (no animation!)
        .onAppear { model.settings.theme.apply(); Self.solidTabBar() }
        .task {
            // dev aid (see AppModel.applyLaunchArguments): `-thenTab 1|island|abandon`
            let a = DevArgs.list
            guard let i = a.firstIndex(of: "-thenTab"), a.indices.contains(i + 1) else { return }
            try? await Task.sleep(for: .seconds(4))
            if let t = Int(a[i + 1]) {
                tab = t
            } else if a[i + 1] == "pause" {
                for _ in 0..<120 {                             // wait for the setup of the quick night to end
                    if case .setup? = model.pauseBlock() { try? await Task.sleep(for: .seconds(1)) } else { break }
                }
                model.startPause()
            } else if a[i + 1] == "warning" {
                model.showNotificationSettings()
            } else if a[i + 1] == "abandon" {
                model.abandonNight()
                try? await Task.sleep(for: .seconds(2))
                model.acknowledgeResult()
            } else {
                model.showTown()
            }
        }
        .onChange(of: model.settings.theme) { _, theme in theme.apply() }
        .fullScreenCover(isPresented: Binding(get: { model.needsGuide && !screenshotMode }, set: { _ in })) {
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


