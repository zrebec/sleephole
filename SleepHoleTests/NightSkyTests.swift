import Foundation
import SleepCore
import Testing
@testable import SleepHole

/// Step 11b5d: the night skies – names, the dev argument and the default look.
@MainActor
struct NightSkyTests {
    @Test func everySkyHasAName() {
        let before = Lang.current
        defer { Lang.current = before }
        Lang.current = .en
        #expect(BoxCatalog.ids(.sky).map(CollectibleText.skyName) == ["Shooting stars", "Northern lights", "The Cat constellation", "Comet"])
        Lang.current = .sk
        #expect(BoxCatalog.ids(.sky).map(CollectibleText.skyName) == ["Padajúce hviezdy", "Polárna žiara", "Súhvezdie Mačky", "Kométa"])
        #expect(CollectibleText.skyName("sky-99") == "sky-99")
        #expect(CollectibleText.keys.count == 10)
    }

    @Test func devArgumentParses() {
        #expect(DevArgs.value(after: "-nightSky", in: ["app", "-nightSky", "sky-02"]) == "sky-02")
        #expect(NightSkies.effect(forId: DevArgs.value(after: "-nightSky", in: ["app", "-nightSky", "sky-04"])) == .comet)
        #expect(NightSkies.effect(forId: DevArgs.value(after: "-nightSky", in: ["app"])) == nil)
    }

    @Test func noSkyByDefault() {
        #expect(LivingSky().nightSky == nil)
        #expect(LivingSky.backdrop.nightSky == nil)
        #expect(LivingSky(nightSky: .comet).nightSky == .comet)
    }
}
