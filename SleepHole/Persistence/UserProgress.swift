import Foundation
import SwiftData

/// One row with what the owner has already seen (owner request: stored in the database).
@Model
final class UserProgress {
    @Attribute(.unique) var id: String = "me"
    /// Finished the first-run guide ("sprievodca").
    var onboardingCompletedAt: Date?
    /// Read the "Tvoja prvá noc" checklist before the first real night.
    var firstNightBriefingAt: Date?
    /// Chosen UI language (`AppLanguage` raw value); nil = never chosen → English (I18N Q1).
    var languageRaw: String?
    /// The owner's name for the town; nil = the default "My Town".
    var townName: String?
    /// When the name was last changed on some device (phase SYNC): the newest name wins a merge. nil = older store.
    var townNameChangedAt: Date?
    /// The last counted rename (a typo fix within 10 min does not move it) and the last *yearly* free one.
    var lastRenameAt: Date?
    var lastFreeRenameAt: Date?
    /// LEGACY (before build 8): start of the free 7-day calibration of the schedule. Still stored and synced so that
    /// older files keep decoding, but no rule reads it any more.
    var scheduleCalibrationStart: Date?
    /// Build 8: the "You can open a change week again" card was answered for the lock that ended on this day
    /// ("2027-01-23", `NightKey` text). Before build 8 it held a month ("2026-11"); such a value never matches.
    var schedulePromptMonth: String?
    /// Build 8 (owner 2026-10-15, `SchedulePolicy`): when the last change week was opened. nil = never (everyone
    /// who updated starts `open`). The whole change-week state is derived from this one date.
    var changeWeekStart: Date?

    init() {}
}
