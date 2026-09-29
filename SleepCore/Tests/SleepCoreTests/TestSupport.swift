import Foundation
@testable import SleepCore

let bratislava: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Bratislava")!
    c.locale = Locale(identifier: "sk_SK")
    return c
}()

/// Local Bratislava date-time.
func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0, _ s: Int = 0) -> Date {
    bratislava.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
}

let defaultSchedule = Schedule()                     // 22:30 → 06:30
/// The night 28→29 Sep 2026 with the default schedule.
let night = defaultSchedule.window(containing: at(2026, 9, 28, 21), calendar: bratislava)

/// Builds a log from (minutes relative to bedtime, kind) pairs.
func log(_ events: [(Double, NightEventKind)], window: NightWindow = night) -> NightLog {
    var l = NightLog(window: window, buildingId: "l1-house-a-0")
    for (min, kind) in events { l.append(kind, at: window.bedtime + min * 60) }
    return l
}

let nightMinutes = 8.0 * 60                          // bedtime → wake with the default schedule
