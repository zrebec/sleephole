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

    init() {}
}
