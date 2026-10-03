import Foundation
import Testing
@testable import SleepCore

/// The sleep buddy rule (plan P2): awake on Today, during the setup, in a pause and from the alarm on; else asleep.
@Suite struct BuddyTests {
    // a night: setup until 22:35, a pause 02:00–02:10, wake 06:30
    let setupEnds = at(2026, 9, 28, 22, 35)
    let pauseEnds = at(2026, 9, 29, 2, 10)
    let wake = at(2026, 9, 29, 6, 30)

    private func state(_ now: Date, running: Bool = true, pause: Date? = nil) -> BuddyState {
        Buddy.state(at: now, running: running, setupEnds: setupEnds, pauseEnds: pause, wake: wake)
    }

    @Test func todayIsAlwaysAwake() {
        #expect(Buddy.state(at: at(2026, 9, 28, 13), running: false) == .awake)
        #expect(Buddy.state(at: at(2026, 9, 29, 3), running: false, setupEnds: setupEnds, wake: wake) == .awake)
    }

    @Test(arguments: [
        (at(2026, 9, 28, 22, 30), BuddyState.awake),        // the start
        (at(2026, 9, 28, 22, 34, 59), .awake),              // last second of the setup
        (at(2026, 9, 28, 22, 35), .asleep),                 // the setup is over (boundary)
        (at(2026, 9, 28, 23, 0), .asleep),
        (at(2026, 9, 29, 3, 0), .asleep),
        (at(2026, 9, 29, 6, 0), .asleep),                   // early-confirm window: the cat still sleeps
        (at(2026, 9, 29, 6, 29, 59), .asleep),
        (at(2026, 9, 29, 6, 30), .awake),                   // wake time (boundary): the alarm
        (at(2026, 9, 29, 6, 31), .awake),
        (at(2026, 9, 29, 7, 20), .awake),                   // unfinished window after the alarm
    ])
    func nightTimeline(now: Date, expected: BuddyState) {
        #expect(state(now) == expected)
    }

    @Test func pauseWakesTheCat() {
        let during = at(2026, 9, 29, 2, 5)
        #expect(state(during) == .asleep)                                    // no pause on
        #expect(state(during, pause: pauseEnds) == .awake)                   // pause on
        #expect(state(pauseEnds.addingTimeInterval(-1), pause: pauseEnds) == .awake)
        #expect(state(pauseEnds, pause: pauseEnds) == .asleep)               // the pause just ended (boundary)
        #expect(state(pauseEnds.addingTimeInterval(1), pause: pauseEnds) == .asleep)
    }

    @Test func napFollowsTheSameRule() {
        let start = at(2026, 9, 29, 13, 0)
        let napSetup = start.addingTimeInterval(80)
        let napWake = start.addingTimeInterval(30 * 60)
        func nap(_ t: Date) -> BuddyState {
            Buddy.state(at: t, running: true, setupEnds: napSetup, pauseEnds: nil, wake: napWake)
        }
        #expect(nap(start) == .awake)
        #expect(nap(napSetup) == .asleep)
        #expect(nap(start.addingTimeInterval(15 * 60)) == .asleep)
        #expect(nap(napWake) == .awake)
    }

    @Test func unknownTimesDoNotWakeTheCat() {
        // a running night with nothing known yet: asleep (nothing says otherwise)
        #expect(Buddy.state(at: at(2026, 9, 29, 3), running: true) == .asleep)
        #expect(Buddy.state(at: at(2026, 9, 29, 3), running: true, setupEnds: nil, pauseEnds: nil, wake: nil) == .asleep)
    }
}

/// The tap reactions of the awake buddy (plan P2b): purr → arched back → wink → purr …
@Suite struct BuddyReactionTests {
    @Test func theCycleIsPurrArchWink() {
        #expect(BuddyReaction.purr.next == .arch)
        #expect(BuddyReaction.arch.next == .wink)
        #expect(BuddyReaction.wink.next == .purr)
    }

    @Test func threeStepsReturnToTheStart() {
        for start in BuddyReaction.allCases {
            #expect(start.next.next.next == start)
            #expect(start.next != start)
        }
    }

    @Test func everyReactionIsInTheCycleOnce() {
        var seen: [BuddyReaction] = []
        var r = BuddyReaction.purr
        for _ in BuddyReaction.allCases {
            seen.append(r)
            r = r.next
        }
        #expect(seen == [.purr, .arch, .wink])
        #expect(Set(seen.map { "\($0)" }).count == BuddyReaction.allCases.count)
    }
}
