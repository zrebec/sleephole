import Foundation
import SleepCore

/// In-app language (owner 2026-09-30, docs/IMPLEMENTATION_I18N.md): English by default, stored in SwiftData
/// (`UserProgress.languageRaw`). New languages = one case + translations in `Localizable.xcstrings`.
enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case en, sk

    static let fallback = AppLanguage.en
    var id: String { rawValue }

    /// Shown in the language pickers – never translated.
    var nativeName: String {
        switch self {
        case .en: "English"
        case .sk: "Slovenčina"   // i18n-ignore
        }
    }

    /// Formatting locale. EN keeps the iPhone's 12/24 h choice (Q3), SK is always 24 h.
    var locale: Locale {
        switch self {
        case .sk: return Locale(identifier: "sk_SK")
        case .en:
            var c = Locale.Components(identifier: "en_US")
            c.hourCycle = Fmt.systemUses12h ? .oneToTwelve : .zeroToTwentyThree
            return Locale(components: c)
        }
    }

    /// The `<lang>.lproj` folder of the app bundle – `L(...)` looks strings up there, not in the system language.
    var bundle: Bundle { Self.bundles[self] ?? .main }

    private static let bundles: [AppLanguage: Bundle] = Dictionary(uniqueKeysWithValues: allCases.compactMap { lang in
        Bundle.main.path(forResource: lang.rawValue, ofType: "lproj").flatMap(Bundle.init(path:)).map { (lang, $0) }
    })
}

/// The language all UI text is produced in. Written only by `AppModel` (main thread).
enum Lang {
    nonisolated(unsafe) static var current: AppLanguage = .fallback
}

/// The ONLY way UI text is produced: `L("Bedtime at \(time)")`. Keys are the English text; interpolations and
/// plural variations come from `Localizable.xcstrings`.
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: Lang.current.bundle, locale: Lang.current.locale)
}

/// Dates and times in the current language. SK always 24 h; EN follows the iPhone's 12/24 h setting (Q3).
enum Fmt {
    /// true when the iPhone is set to a 12-hour clock.
    nonisolated(unsafe) static var systemUses12h: Bool =
        DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? false

    static func time(_ date: Date) -> String { formatter(seconds: false).string(from: date) }
    static func timeSec(_ date: Date) -> String { formatter(seconds: true).string(from: date) }

    static func time(_ t: TimeOfDay) -> String { time(minutesOfDay: t.hour * 60 + t.minute) }

    /// Minutes after midnight (wraps around).
    static func time(minutesOfDay m: Int) -> String {
        let m = (m % 1440 + 1440) % 1440
        let date = Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: m / 60, minute: m % 60))!
        return time(date)
    }

    /// "30. 9." / "9/30"
    static func dayMonth(_ k: NightKey) -> String {
        Lang.current == .sk ? "\(k.day). \(k.month)." : "\(k.month)/\(k.day)"
    }

    /// "30. 9. 2026" / "Sep 30, 2026" – never with a grouping separator in the year.
    static func fullDate(_ k: NightKey) -> String {
        guard Lang.current != .sk else { return "\(k.day). \(k.month). \(k.year)" }
        let date = Calendar.current.date(from: DateComponents(year: k.year, month: k.month, day: k.day, hour: 12))!
        return date.formatted(.dateTime.year().month(.abbreviated).day().locale(Lang.current.locale))
    }

    /// "3. 10. 2027 20:39" / "Oct 3, 2027 at 8:39 PM" – a moment that can be months away (the app's expiry): the year is
    /// always there, so it never reads as a date in the past.
    static func dateTimeWithYear(_ date: Date) -> String {
        let day = fullDate(NightKey(date: date, calendar: .current)), clock = time(date)
        return Lang.current == .sk ? "\(day) \(clock)" : L("\(day) at \(clock)")
    }

    nonisolated(unsafe) private static var cache: [String: DateFormatter] = [:]

    private static func formatter(seconds: Bool) -> DateFormatter {
        let cacheKey = "\(Lang.current.rawValue)-\(systemUses12h)-\(seconds)"
        if let f = cache[cacheKey] { return f }
        let f = DateFormatter()
        cache[cacheKey] = f
        f.locale = Lang.current.locale
        if Lang.current == .sk || !systemUses12h {
            f.dateFormat = seconds ? "H:mm:ss" : "H:mm"
        } else {
            f.setLocalizedDateFormatFromTemplate(seconds ? "hmmss" : "hmm")
        }
        return f
    }
}

extension CatalogEntry {
    /// Building name in the current UI language.
    var displayName: String { name(Lang.current.rawValue) }
}
