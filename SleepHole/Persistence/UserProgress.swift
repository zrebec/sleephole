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
    /// The last counted rename (a typo fix within 10 min does not move it) and the last *yearly* free one.
    var lastRenameAt: Date?
    var lastFreeRenameAt: Date?
    /// Start of the free 7-day calibration of the schedule (the first launch with the limits).
    var scheduleCalibrationStart: Date?
    /// "2026-11": the month whose "does your bedtime still fit?" card was answered.
    var schedulePromptMonth: String?

    init() {}
}
