import Foundation
import Testing
@testable import SleepHole

/// B46 (13x): the setup countdown keeps one two-line shape; the height reserve covers every form.
@MainActor
struct SetupCountdownTests {
    let ends = Date(timeIntervalSinceReferenceDate: 100_000)

    @Test func napHasOneFormWithTheWidestNumber() {
        let forms = SetupLine.forms(.nap, graceEnds: ends)
        #expect(forms.count == 1)
        #expect(forms[0].contains("\(SetupLine.napMaxSeconds)"))
        #expect(SetupLine.napMaxSeconds >= 100)
    }

    @Test func nightHasBothFormsAndSwitchesAtSixtySeconds() {
        let forms = SetupLine.forms(.night, graceEnds: ends)
        #expect(forms.count == 2)
        #expect(forms[0] != forms[1])
        #expect(SetupLine.countdown(.night, left: 59, graceEnds: ends) == forms[1])
        #expect(SetupLine.countdown(.night, left: 60, graceEnds: ends).contains(Fmt.time(ends)))
        #expect(SetupLine.countdown(.night, left: 59, graceEnds: ends).contains("59"))
    }

    @Test func hintDoesNotChangeAndIsShortOfTheCountdown() {
        #expect(SetupLine.hint(.nap) != SetupLine.hint(.night))
        #expect(!SetupLine.hint(.nap).contains("%"))
        #expect(!SetupLine.countdown(.nap, left: 90, graceEnds: ends).contains(SetupLine.hint(.nap)))
    }
}
