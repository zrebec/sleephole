import Foundation
import SleepCore
import Testing
@testable import SleepHole

/// Build 13e1: VoiceOver texts that come from small pure helpers.
@MainActor
struct AccessibilityTests {
    @Test func progressValueIsAPercentInTheLocalesFormat() {
        #expect(ThickProgressStyle.percentText(0.42, locale: Locale(identifier: "en")) == "42%")
        #expect(ThickProgressStyle.percentText(0.42, locale: Locale(identifier: "sk")).contains("42"))
        #expect(ThickProgressStyle.percentText(0.42, locale: Locale(identifier: "cs")).hasSuffix("%"))
        #expect(ThickProgressStyle.percentText(nil, locale: Locale(identifier: "en")) == "0%")
        #expect(ThickProgressStyle.percentText(1.7, locale: Locale(identifier: "en")) == "100%")
        #expect(ThickProgressStyle.percentText(-1, locale: Locale(identifier: "en")) == "0%")
    }

    @Test func calendarDayLabelHasTheDateAndTheOutcome() {
        let key = NightKey(year: 2026, month: 10, day: 3)
        #expect(CalendarGrid.dayLabel(key, .complete) == "\(Fmt.fullDate(key)), \(L("complete"))")
        #expect(CalendarGrid.dayLabel(key, nil) == Fmt.fullDate(key))
        #expect(CalendarGrid.dayLabel(key, .missed) == Fmt.fullDate(key))
    }

    @Test func leadingSymbolIsDroppedForVoiceOver() {
        #expect("🔧 Change week: 3 days".withoutLeadingSymbol == "Change week: 3 days")
        #expect("🔒 Your schedule".withoutLeadingSymbol == "Your schedule")
        #expect("Plain text".withoutLeadingSymbol == "Plain text")
    }

    @Test func newKeysHaveEnglishSlovakAndCzech() throws {
        let catalog = try CzechTests.catalog()
        for key in ["Progress", "Night progress", "Nap progress", "Volume", "Town name: %@"] {
            let loc = try #require(catalog[key], "\(key)")
            for lang in ["en", "sk", "cs"] {
                #expect(CzechTests.unitValue(loc[lang]) != nil, "\(key) / \(lang)")
            }
        }
    }
}
