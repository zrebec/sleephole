import SwiftUI
import SleepCore

/// The setup countdown on the night / nap screen (13x, B46). Two lines: the short countdown and a fixed hint.
/// Nothing below may move during the setup (11b6 lesson), so the block's height is reserved for the tallest form it can
/// take, at any text size and language: hidden copies of every form sit in a ZStack, the visible one is drawn over them.
enum SetupLine {
    enum Kind { case nap, night }

    /// The most seconds a setup can show in the "Setup: Ns left" form (a nap's 120s; a night shows it under 60s).
    static var napMaxSeconds: Int { Int(NapPlan.rules.setupGrace.rounded(.up)) }
    /// The longest setup of a real night (Settings: 5 / 10 / 15 min; an early start 15 min) – for the widest minutes text.
    static let longestNightSetup: TimeInterval = 15 * 60

    /// Line 1 for `left` seconds remaining.
    static func countdown(_ kind: Kind, left: Int, graceEnds: Date) -> String {
        switch kind {
        case .nap: return L("Setup: \(left)s left")
        case .night:
            return left >= 60 ? L("Setup until \(Fmt.time(graceEnds)) (\(Plural.minutes(Double(left))) left)")
                              : L("Setup: \(left)s left")
        }
    }

    /// Line 2 – the same for the whole setup.
    static func hint(_ kind: Kind) -> String {
        switch kind {
        case .nap: return L("for a story or sound")
        case .night: return L("for a podcast or story")
        }
    }

    /// Every first-line form that can occur during one setup (widest number / longest minutes text) – the height reserve.
    static func forms(_ kind: Kind, graceEnds: Date) -> [String] {
        switch kind {
        case .nap:
            return [countdown(.nap, left: napMaxSeconds, graceEnds: graceEnds)]
        case .night:
            return [countdown(.night, left: Int(longestNightSetup), graceEnds: graceEnds),
                    countdown(.night, left: 59, graceEnds: graceEnds)]
        }
    }

    /// DEBUG: `-pinSetupLeft S` shows S seconds whatever the clock says (screenshots).
    static func pinned() -> Int? {
        #if DEBUG
        let a = DevArgs.list
        if let i = a.firstIndex(of: "-pinSetupLeft"), a.indices.contains(i + 1) { return Int(a[i + 1]) }
        #endif
        return nil
    }
}

struct SetupCountdown: View {
    let kind: SetupLine.Kind
    let left: Int
    let graceEnds: Date

    var body: some View {
        let shown = SetupLine.pinned() ?? left
        let hint = SetupLine.hint(kind)
        let line = SetupLine.countdown(kind, left: shown, graceEnds: graceEnds)
        ZStack(alignment: .top) {
            ForEach(Array(SetupLine.forms(kind, graceEnds: graceEnds).enumerated()), id: \.offset) { _, form in
                block(form, hint).hidden().accessibilityHidden(true)
            }
            block(line, hint)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(line + ", " + hint)
        }
    }

    private func block(_ line: String, _ hint: String) -> some View {
        VStack(spacing: 2) {
            Text(line).monospacedDigit()
            Text(hint)
        }
        .font(.callout).foregroundStyle(.yellow).multilineTextAlignment(.center)
    }
}

/// "Pause: 9:59 left – you can leave SleepHole now": the digits do not change the width, the height is reserved for "10:00".
struct PauseCountdown: View {
    let remaining: TimeInterval

    var body: some View {
        let text = L("Pause: \(NightView.countdown(remaining)) left – you can leave SleepHole now")
        ZStack(alignment: .top) {
            line(L("Pause: \(NightView.countdown(PausePolicy.duration)) left – you can leave SleepHole now"))
                .hidden().accessibilityHidden(true)
            line(text)
        }
    }

    private func line(_ s: String) -> some View {
        Text(s).monospacedDigit().font(.callout).foregroundStyle(.yellow).multilineTextAlignment(.center)
    }
}
