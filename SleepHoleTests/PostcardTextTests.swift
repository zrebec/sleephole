import SleepCore
import SwiftUI
import Testing
@testable import SleepHole

/// Step 11b5a: the 30 postcards' texts in both languages, their limits, and (on request) screenshots for the review.
@MainActor
struct PostcardTextTests {
    private let ids = BoxCatalog.ids(.postcard)

    private func inLanguage<T>(_ lang: AppLanguage, _ body: () throws -> T) rethrows -> T {
        let saved = Lang.current
        defer { Lang.current = saved }
        Lang.current = lang
        return try body()
    }

    @Test func everyPostcardHasAStampATitleAndATipInBothLanguages() {
        #expect(ids.count == 30)
        let stamps = ids.map { PostcardText.stamp(for: $0) }
        #expect(Set(stamps).count == 30 && !stamps.contains("💌"))
        for lang in AppLanguage.allCases {
            let titles = inLanguage(lang) { ids.map { PostcardText.title(for: $0) } }
            let tips = inLanguage(lang) { ids.map { PostcardText.tip(for: $0) } }
            #expect(titles.allSatisfy { !$0.isEmpty && !$0.contains("%") }, "\(lang)")
            #expect(tips.allSatisfy { !$0.isEmpty && !$0.contains("%") }, "\(lang)")
            #expect(Set(titles).count == 30 && Set(tips).count == 30, "\(lang)")
            let (tMax, xMax) = lang == .sk ? (32, 160) : (28, 140)
            for (i, t) in titles.enumerated() { #expect(t.count <= tMax, "\(lang) \(ids[i]) title \(t.count)") }
            for (i, t) in tips.enumerated() { #expect(t.count <= xMax, "\(lang) \(ids[i]) tip \(t.count)") }
            // house rule: no space between a number and its seconds
            #expect(!tips.contains { $0.range(of: #"\d s\b"#, options: .regularExpression) != nil })
        }
        // English and Slovak really differ
        let en = inLanguage(.en) { ids.map { PostcardText.tip(for: $0) } }
        let sk = inLanguage(.sk) { ids.map { PostcardText.tip(for: $0) } }
        #expect(zip(en, sk).allSatisfy { $0 != $1 })
    }

    @Test func theNumberAndTheLinesResolve() {
        #expect(PostcardText.number(of: "postcard-07") == 7)
        #expect(PostcardText.number(of: "postcard-30") == 30 && PostcardText.number(of: "postcard-31") == nil)
        #expect(PostcardText.number(of: "decoration-01") == nil)
        inLanguage(.en) {
            #expect(PostcardText.numberLine(7, of: 30) == "Postcard 7 of 30")
            #expect(PostcardText.sourceLine("NHS") == "Source: NHS")
        }
        inLanguage(.sk) {
            #expect(PostcardText.numberLine(7, of: 30) == "Pohľadnica 7 z 30")
            #expect(PostcardText.sourceLine("NHS") == "Zdroj: NHS")
        }
    }

    @Test func theDebugKeysAreUniqueAndInTheCatalog() {
        #expect(Set(PostcardText.keys).count == PostcardText.keys.count)
        #expect(PostcardText.keys.count == 65)
        let entries = AppTexts.load()
        let have = Set(entries.map(\.key))
        #expect(PostcardText.keys.allSatisfy { have.contains($0) })
    }

    @Test func theCardKeepsADarkInkOnALightPaper() {
        func luminance(_ c: Color) -> Double {
            let r = UIColor(c).cgColor.components ?? [0, 0, 0]
            func lin(_ v: CGFloat) -> Double { let x = Double(v); return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
            return 0.2126 * lin(r[0]) + 0.7152 * lin(r[1]) + 0.0722 * lin(r[2])
        }
        for scheme in [ColorScheme.light, .dark] {
            let p = luminance(PostcardView.paper(scheme)), i = luminance(PostcardView.ink), s = luminance(PostcardView.softInk)
            #expect((p + 0.05) / (i + 0.05) >= 7, "\(scheme) ink")
            #expect((p + 0.05) / (s + 0.05) >= 4.5, "\(scheme) soft ink")
        }
    }

    /// Review screenshots (only when `TEST_RUNNER_POSTCARD_SHOTS=<dir>` is set for xcodebuild; nothing is written otherwise).
    @Test func screenshotsForTheReview() throws {
        guard let dir = ProcessInfo.processInfo.environment["POSTCARD_SHOTS"] else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        func write(_ name: String, lang: AppLanguage, scheme: ColorScheme, size: DynamicTypeSize, id: String) throws {
            try inLanguage(lang) {
                let view = PostcardView(id: id)
                    .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, size)
                    .frame(width: 350).padding(20)
                    .background(scheme == .dark ? Color(red: 0.05, green: 0.06, blue: 0.14) : Color(red: 0.88, green: 0.90, blue: 0.97))
                let r = ImageRenderer(content: view)
                r.scale = 2
                let png = try #require(r.uiImage?.pngData())
                try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
            }
        }
        for n in [1, 4, 7, 14, 15, 19, 28, 30] {
            let id = String(format: "postcard-%02d", n)
            try write("postcard-\(n)-en-light.png", lang: .en, scheme: .light, size: .large, id: id)
            try write("postcard-\(n)-sk-light.png", lang: .sk, scheme: .light, size: .large, id: id)
            try write("postcard-\(n)-sk-dark.png", lang: .sk, scheme: .dark, size: .large, id: id)
            guard [1, 7, 19, 30].contains(n) else { continue }
            try write("postcard-\(n)-sk-light-xxxl.png", lang: .sk, scheme: .light, size: .accessibility2, id: id)
        }
    }
}
