import Foundation
import SleepCore
import CoreLocation
import MapKit
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import SleepHole

/// The city search never touches the network in tests.
@MainActor
final class FakeCitySearch: CitySearch {
    static let bratislava = SkyCity(name: "Bratislava", latitude: 48.1486, longitude: 17.1077)
    static let vienna = SkyCity(name: "Vienna", latitude: 48.2082, longitude: 16.3738)
    static let zilina = SkyCity(name: "Žilina", latitude: 49.2231, longitude: 18.7394)

    var cities = [bratislava, vienna, zilina]
    /// true = no network: nothing is suggested or found.
    var offline = false
    private(set) var asked: [String] = []
    private(set) var resolved: [String] = []

    func suggestions(for text: String) async -> [CitySuggestion] {
        asked.append(text)
        guard !offline else { return [] }
        let t = text.trimmingCharacters(in: .whitespaces)
        return cities.filter { $0.name.range(of: t, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil }
            .map { CitySuggestion(title: $0.name, subtitle: "Somewhere") }
    }

    func resolve(_ text: String) async -> SkyCity? {
        resolved.append(text)
        guard !offline else { return nil }
        return cities.first { CityField.same($0.name, text) || text == "\($0.name), Somewhere" }
    }
}

/// Collects what the field stores.
@MainActor
final class StoredCities {
    var values: [SkyCity?] = []
}

/// Plan SKY, W2: the city in Settings, the real sky, the semicircle.
@MainActor
struct SkyCityTests {
    let sprites = SpriteLibrary.loadFromBundle()
    let cal = Calendar.current
    let bratislava = FakeCitySearch.bratislava
    let vienna = FakeCitySearch.vienna

    init() { AudioKeeper.muted = true }

    func utc(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    func field(_ search: FakeCitySearch = FakeCitySearch(), city: SkyCity? = nil, debounce: Duration = .zero,
               into store: StoredCities = StoredCities()) -> CityField {
        CityField(search: search, city: city, debounce: debounce) { store.values.append($0) }
    }

    func makeModel(city: SkyCity? = nil, language: AppLanguage = .en) -> (AppModel, ModelContainer) {
        let c = try! ModelContainer(for: NightRecord.self, UserProgress.self, CoinSpend.self, ScheduleChange.self,
                                    JokerRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        var s = AppSettings()
        s.wakeCode = "1234"
        s.city = city
        let m = AppModel(context: c.mainContext, catalog: sprites.catalog,
                         clock: FakeClock(cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 12))!),
                         settings: s, servicesEnabled: false)
        m.language = language
        return (m, c)
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

    // MARK: the field's logic

    @Test func openingShowsTheStoredCityOrNothing() {
        let a = field(city: bratislava)
        #expect(a.text == "Bratislava" && a.status == .verified && a.city == bratislava)
        let b = field()
        #expect(b.text == "" && b.status == .empty && b.city == nil && !b.notFound && b.suggestions.isEmpty)
    }

    @Test func aPrefixSuggestsButStoresNothing() async {
        let store = StoredCities()
        let f = field(into: store)
        f.edit("bratis")
        #expect(f.status == .unverified)                           // at once, before any check
        await f.settle()
        #expect(f.status == .unverified && f.suggestions.map(\.title) == ["Bratislava"] && !f.notFound)
        #expect(f.text == "bratis" && store.values.isEmpty && f.city == nil)
    }

    @Test func aFullNameVerifiesStoresAndIsNormalised() async {
        let store = StoredCities()
        let f = field(into: store)
        f.edit("bratislava")
        await f.settle()
        #expect(f.status == .verified && f.text == "Bratislava" && f.suggestions.isEmpty && !f.notFound)
        #expect(store.values == [bratislava] && f.city == bratislava)
    }

    @Test func diacriticsAndCaseDoNotMatter() async {
        #expect(CityField.same("Žilina", "zilina") && CityField.same(" BRATISLAVA ", "Bratislava"))
        #expect(!CityField.same("Bratislava", "Bratislav"))
        let f = field()
        f.edit("zilina")
        await f.settle()
        #expect(f.status == .verified && f.text == "Žilina" && f.city == FakeCitySearch.zilina)
    }

    @Test func tappingASuggestionStoresItAndVerifies() async {
        let store = StoredCities()
        let f = field(into: store)
        f.edit("bra")
        await f.settle()
        let suggestion = try! #require(f.suggestions.first)
        f.choose(suggestion)
        #expect(f.status == .checking)
        await f.settle()
        #expect(f.status == .verified && f.text == "Bratislava" && f.suggestions.isEmpty)
        #expect(store.values == [bratislava])
    }

    @Test func aSuggestionThatCannotBeResolvedSaysNotFound() async {
        let search = FakeCitySearch()
        let f = field(search)
        f.edit("bra")
        await f.settle()
        let suggestion = try! #require(f.suggestions.first)
        search.offline = true
        f.choose(suggestion)
        await f.settle()
        #expect(f.status == .unverified && f.notFound && f.city == nil)
    }

    @Test func clearingTheFieldRemovesTheCity() async {
        let store = StoredCities()
        let f = field(city: bratislava, into: store)
        f.edit("")
        #expect(f.status == .empty && f.text == "" && f.city == nil)
        #expect(store.values == [nil])
        f.edit("  ")                                               // only blanks count as empty too
        #expect(f.status == .empty && store.values == [nil])       // already nil: nothing stored again
    }

    @Test func editingAwayKeepsTheStoredCityUntilANewOneIsVerified() async {
        let store = StoredCities()
        let f = field(city: bratislava, into: store)
        f.edit("Brat")
        #expect(f.status == .unverified && f.city == bratislava)
        await f.settle()
        #expect(f.status == .unverified && f.city == bratislava && store.values.isEmpty)
        f.edit("Vienna")
        await f.settle()
        #expect(f.status == .verified && f.city == vienna && store.values == [vienna])
    }

    @Test func unknownTextIsNotFound() async {
        let store = StoredCities()
        let f = field(into: store)
        f.edit("qqqq")
        await f.settle()
        #expect(f.status == .unverified && f.notFound && f.suggestions.isEmpty && store.values.isEmpty)
        f.edit("qqqqq")                                            // typing again clears the message until checked
        #expect(!f.notFound)
        let off = FakeCitySearch()
        off.offline = true
        let g = field(off)
        g.edit("Bratislava")
        await g.settle()
        #expect(g.status == .unverified && g.notFound)             // offline: nothing found
    }

    @Test func aSecondKeystrokeCancelsThePendingCheck() async {
        let search = FakeCitySearch()
        let f = field(search)
        f.edit("b"); f.edit("br"); f.edit("bratislava")            // nothing runs between the keystrokes
        await f.settle()
        #expect(search.resolved == ["bratislava"] && search.asked == ["bratislava"])
        #expect(f.status == .verified)
    }

    @Test func theCheckWaitsForTheDebounce() async {
        let search = FakeCitySearch()
        let f = field(search, debounce: .milliseconds(400))
        f.edit("brat")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(search.resolved.isEmpty && f.status == .unverified)    // still waiting
        f.edit("bratislava")                                       // restarts the wait
        try? await Task.sleep(for: .milliseconds(150))
        #expect(search.resolved.isEmpty)                           // 150 ms after the last keystroke: not yet
        await f.settle()
        #expect(search.resolved == ["bratislava"] && f.status == .verified)
    }

    @Test func aCityStoredElsewhereIsShown() {
        let f = field(city: bratislava)
        f.sync(with: vienna)
        #expect(f.text == "Vienna" && f.status == .verified && f.city == vienna)
        f.sync(with: nil)
        #expect(f.text == "" && f.status == .empty)
    }

    @Test func suggestionsStayAtFive() async {
        let search = FakeCitySearch()
        search.cities = (1...9).map { SkyCity(name: "Town \($0)", latitude: 0, longitude: 0) }
        let f = field(search)
        f.edit("Town")
        await f.settle()
        #expect(f.suggestions.count == 5)
        #expect(CitySuggestion(title: "Bratislava", subtitle: "Slovakia").query == "Bratislava, Slovakia")
        #expect(CitySuggestion(title: "Bratislava", subtitle: "").query == "Bratislava")
    }

    @available(iOS 26.0, *)
    @Test func aMapItemBecomesACity() async {
        let item = MKMapItem(location: CLLocation(latitude: 50.0755, longitude: 14.4378), address: nil)
        item.name = "Prague"
        #expect(MapKitCitySearch.city(from: item) == SkyCity(name: "Prague", latitude: 50.0755, longitude: 14.4378))
        let apple = MapKitCitySearch()                              // blank text never reaches the network
        let none = await apple.suggestions(for: "  ")
        let nothing = await apple.resolve("")
        #expect(none.isEmpty && nothing == nil)
    }

    // MARK: settings and backup

    @Test func oldSettingsWithoutACityStillLoad() throws {
        let data = try JSONEncoder().encode(AppSettings())
        #expect(!String(decoding: data, as: UTF8.self).contains("\"city\""))     // nil is not written …
        #expect(try JSONDecoder().decode(AppSettings.self, from: data).city == nil)   // … and reads back as nil
        var s = AppSettings()
        s.city = bratislava
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(back.city == bratislava && back.city?.place == GeoPoint(latitude: 48.1486, longitude: 17.1077))
    }

    @Test func theCityTravelsInTheBackup() throws {
        let (m1, c1) = makeModel(city: bratislava)
        defer { m1.settings.city = nil }
        let data = try m1.makeBackup().encoded()
        #expect(try BackupFile.decode(data).settings.city == bratislava)

        let (m2, c2) = makeModel()
        try m2.restore(try BackupFile.decode(data))
        #expect(m2.settings.city == bratislava)
        m2.settings.city = nil

        // a backup made before the city existed: no "city" key in its settings
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var settings = try #require(json["settings"] as? [String: Any])
        settings["city"] = nil
        json["settings"] = settings
        let old = try BackupFile.decode(JSONSerialization.data(withJSONObject: json))
        #expect(old.settings.city == nil)
        try m2.restore(old)
        #expect(m2.settings.city == nil)
        _ = (c1, c2)
    }

    @Test func launchArgumentsSetTheCity() {
        #expect(AppModel.parseCity("Bratislava,48.1486,17.1077") == bratislava)
        #expect(AppModel.parseCity("Frankfurt, Main,50.11,8.68")
                == SkyCity(name: "Frankfurt, Main", latitude: 50.11, longitude: 8.68))
        #expect(AppModel.parseCity("Nowhere,1") == nil && AppModel.parseCity("X,95,10") == nil
                && AppModel.parseCity(",48,17") == nil && AppModel.parseCity("X,a,b") == nil)
    }

    // MARK: the real sky

    @Test func withoutACityTheSkyFollowsTheSchedule() {
        let settings = AppSettings()
        for t in ["2026-10-03T04:00:00Z", "2026-10-03T10:00:00Z", "2026-10-03T19:30:00Z"].map(utc) {
            #expect(LivingSky.state(at: t, settings: settings, overrides: SkyOverrides())
                    == Sky.state(at: t, schedule: settings.schedule, calendar: .current))
        }
    }

    @Test func withACityTheSkyIsTheRealOne() {
        var settings = AppSettings()
        settings.city = bratislava
        let night = LivingSky.state(at: utc("2026-10-03T19:00:00Z"), settings: settings, overrides: SkyOverrides())
        #expect(night.phase == .night && night.body == .none)       // 21:00 local: the moon is not up yet
        let day = LivingSky.state(at: utc("2026-10-03T10:00:00Z"), settings: settings, overrides: SkyOverrides())
        #expect(day.phase == .day && day.body == .sun && abs(day.arc - 0.44) < 0.03)
        let late = LivingSky.state(at: utc("2026-10-03T01:00:00Z"), settings: settings, overrides: SkyOverrides())
        #expect(late.phase == .night && late.body == .moon && late.moon != nil)    // 03:00 local: the waning moon
        #expect(late.moon?.litOnRight == false)
    }

    @Test func theRealSkyIsComputedOncePerMinutePerPlace() {
        RealSky.reset()
        let t = utc("2026-10-03T10:00:10Z")
        let before = RealSky.computations
        let a = RealSky.state(at: t, place: bratislava.place)
        let b = RealSky.state(at: t + 30, place: bratislava.place)       // 10:00:40 – the same minute
        #expect(a == b && RealSky.computations == before + 1)
        _ = RealSky.state(at: t + 45, place: bratislava.place)           // 10:00:55 – still the same minute
        #expect(RealSky.computations == before + 1)
        _ = RealSky.state(at: t + 60, place: bratislava.place)           // 10:01:10 – a new minute
        #expect(RealSky.computations == before + 2)
        _ = RealSky.state(at: t + 60, place: vienna.place)               // the same minute, another city
        #expect(RealSky.computations == before + 3)
        _ = RealSky.state(at: t + 61, place: vienna.place)
        #expect(RealSky.computations == before + 3)
        RealSky.reset()
    }

    @Test func devOverridesForceTheDrawnState() {
        let base = SkyState(phase: .night, daylight: 0, glow: 0, arc: 0.8, body: .moon, moon: MoonLook(illuminated: 0.9, litOnRight: false))
        #expect(SkyOverrides().apply(to: base) == base)
        let o = SkyOverrides(args: ["-skyArc", "0.3", "-skyBody", "none", "-skyMoon", "0.5"])
        #expect(o == SkyOverrides(arc: 0.3, body: SkyBody.none, moon: 0.5))
        let forced = o.apply(to: base)
        #expect(forced.arc == 0.3 && forced.body == .none && forced.moon == MoonLook(illuminated: 0.5, litOnRight: false))
        #expect(forced.phase == .night)                                   // the colours are untouched
        #expect(SkyOverrides(args: ["-skyArc", "7", "-skyBody", "star"]) == SkyOverrides(arc: 1))   // clamped / ignored
        let schedule = SkyState(phase: .day, daylight: 1, glow: 0, arc: 0.2)
        #expect(SkyOverrides(moon: 0.4).apply(to: schedule).moon == MoonLook(illuminated: 0.4, litOnRight: true))
    }

    // MARK: the semicircle and the moon's phase

    func near(_ a: CGPoint, _ x: Double, _ y: Double) -> Bool { abs(a.x - x) < 0.01 && abs(a.y - y) < 0.01 }

    @Test func theBodyTravelsATrueSemicircle() {
        let (c, r) = SkyDrawing.semicircle(width: 402)
        #expect(c == CGPoint(x: 252, y: 180) && r == 95)                            // right of the title, above the badges
        #expect(near(SkyDrawing.semicirclePoint(arc: 0, width: 402), 157, 180))      // rises at the left end
        #expect(near(SkyDrawing.semicirclePoint(arc: 0.5, width: 402), 252, 85))     // top
        #expect(near(SkyDrawing.semicirclePoint(arc: 1, width: 402), 347, 180))      // sets at the right end
        for arc in stride(from: 0.0, through: 1.0, by: 0.1) {                        // always on the circle
            let p = SkyDrawing.semicirclePoint(arc: arc, width: 402)
            #expect(abs(hypot(p.x - 252, p.y - 180) - 95) < 0.001)
        }
        let narrow = SkyDrawing.semicircle(width: 320)                               // narrow screen: smaller radius
        #expect(narrow.centre == CGPoint(x: 170, y: 180) && narrow.radius == 30)
        #expect(narrow.centre.x - narrow.radius >= 140 && narrow.centre.x + narrow.radius <= 320 - 36)
        #expect(SkyDrawing.semicircle(width: 440).radius == 95)                      // a wide screen keeps 95 pt
        // the flat arc of the other screens is what it has always been
        let flat = SkyDrawing.flatPoint(arc: 0.5, size: CGSize(width: 402, height: 874))
        #expect(near(flat, 201, 874 * 0.09))
    }

    @Test func theLitPartOfTheMoon() {
        func box(_ f: Double, right: Bool = true) -> CGRect {
            SkyDrawing.litPart(centre: .zero, radius: 22, illuminated: f, litOnRight: right).boundingRect
        }
        func close(_ a: CGRect, _ x: Double, _ w: Double) -> Bool {
            abs(a.minX - x) < 0.01 && abs(a.width - w) < 0.01 && abs(a.height - 44) < 0.01
        }
        #expect(close(box(1), -22, 44))                       // full: the whole disc
        #expect(close(box(0.5), 0, 22))                       // half: the half disc on the lit side
        #expect(close(box(0.25), 0, 22))                      // crescent: still inside the lit half
        #expect(close(box(0.75), -11, 33))                    // gibbous: the half disc plus half an ellipse of 11 pt
        #expect(close(box(0.5, right: false), -22, 22))       // lit on the left
        #expect(close(box(0.75, right: false), -22, 33))
        let crescent = SkyDrawing.litPart(centre: .zero, radius: 22, illuminated: 0.25, litOnRight: true)
        #expect(crescent.contains(CGPoint(x: 20, y: 0)) && !crescent.contains(CGPoint(x: 3, y: 0)))
        let gibbous = SkyDrawing.litPart(centre: .zero, radius: 22, illuminated: 0.75, litOnRight: true)
        #expect(gibbous.contains(CGPoint(x: -5, y: 0)) && !gibbous.contains(CGPoint(x: -15, y: 0)))
    }

    // MARK: views

    @Test(arguments: AppLanguage.allCases) func settingsRenderWithAndWithoutACity(language: AppLanguage) async {
        let (m, c) = makeModel(language: language)
        render(SettingsView(), m)                                   // no city: ✕, the schedule footer
        m.settings.city = bratislava
        defer { m.settings.city = nil }
        render(SettingsView(), m)                                   // a city: ✓, the "for Bratislava" footer
        let search = FakeCitySearch()
        let f = field(search, city: nil)
        f.edit("bra")
        await f.settle()
        render(NavigationStack { Form { SkySection(field: f) } }, m)             // unverified + a suggestion
        f.choose(f.suggestions[0])
        render(NavigationStack { Form { SkySection(field: f) } }, m)             // checking
        await f.settle()
        render(NavigationStack { Form { SkySection(field: f) } }, m)             // verified
        search.offline = true
        f.edit("qqq")
        await f.settle()
        render(NavigationStack { Form { SkySection(field: f) } }, m)             // "No such city found"
        _ = c
    }

    @Test(arguments: [SkyBody.sun, SkyBody.moon, SkyBody.none]) func todayDrawsTheSemicircleForEachBody(body: SkyBody) {
        let (m, c) = makeModel(city: bratislava)
        defer { m.settings.city = nil }
        render(TodayView(), m)                                      // the real sky of the moment, semicircle
        render(LivingSky(semicircle: true), m)
        render(LivingSky(), m)                                      // the flat arc of Stats / Settings / Town
        let state = SkyState(phase: body == .sun ? .day : .night, daylight: body == .sun ? 1 : 0, glow: 0, arc: 0.3,
                             body: body, moon: body == .moon ? MoonLook(illuminated: 0.3, litOnRight: true) : nil)
        render(Canvas { gc, size in
            SkyDrawing.track(&gc, size: size, dark: false, daylight: state.daylight)
            SkyDrawing.sunOrMoon(&gc, size: size, sky: state, semicircle: true)
            SkyDrawing.sunOrMoon(&gc, size: size, sky: state)
        }.frame(width: 402, height: 874), m)
        _ = c
    }

    @Test func everyMoonPhaseAndTheOldCrescentDraw() {
        let (m, c) = makeModel()
        for f in [0.0, 0.02, 0.1, 0.5, 0.9, 1.0] {
            for right in [true, false] {
                let state = SkyState(phase: .night, daylight: 0, glow: 0, arc: 0.5, body: .moon,
                                     moon: MoonLook(illuminated: f, litOnRight: right))
                render(Canvas { gc, size in
                    SkyDrawing.sunOrMoon(&gc, size: size, sky: state)
                }.frame(width: 402, height: 300), m)
            }
        }
        render(Canvas { gc, size in
            SkyDrawing.sunOrMoon(&gc, size: size, sky: SkyState(phase: .night, daylight: 0, glow: 0, arc: 0.5))   // schedule crescent
        }.frame(width: 402, height: 300), m)
        _ = c
    }
}
