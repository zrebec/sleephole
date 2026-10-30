import SleepCore
import SwiftUI

/// Step 11b4b: the cat unwraps a parcel right after the purchase. Pure presentation of a result that is already stored
/// (the prize was decided and written by `buyBox`): only the real prize ever appears – no other prizes flicker past,
/// no spinning, no "almost", no countdown, no reel sounds. A tap skips it; Reduce Motion shows the end at once.
enum ParcelOpening {
    enum Phase: Int, Comparable {
        case wobble, pop, reveal, done
        static func < (a: Phase, b: Phase) -> Bool { a.rawValue < b.rawValue }
    }

    /// Unpaced boundaries in seconds (× `Motion.pace`): the parcel wobbles twice, pops open, the prize rises and the
    /// card fades in – 1.4 s in all, 2.24 s at the current pace.
    static let popAt = 0.7
    static let revealAt = 1.0
    static let doneAt = 1.4

    static func phase(at elapsed: Double, reduceMotion: Bool, skipped: Bool = false, pace: Double = Motion.pace) -> Phase {
        if reduceMotion || skipped { return .done }
        let u = elapsed / pace
        if u < popAt { return .wobble }
        if u < revealAt { return .pop }
        if u < doneAt { return .reveal }
        return .done
    }

    /// Debug only (`-openingAt <seconds>`): freezes the timeline at that moment, for screenshots.
    static var frozenAt: Double? { DevArgs.value(after: "-openingAt").flatMap(Double.init) }
    /// Debug only (`-openingStill`): the Reduce Motion path.
    static var forcedStill: Bool { DevArgs.list.contains("-openingStill") }
}

extension BoxPurchase: @retroactive Identifiable {}

struct ParcelOpeningView: View {
    let box: BoxPurchase
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.scenePhase) private var scenePhase
    @State private var start = Date()
    @State private var skipped = false
    /// The end state was reached by itself: the timeline stops redrawing (battery, B8).
    @State private var ended = false

    private var reduceMotion: Bool { systemReduceMotion || ParcelOpening.forcedStill }
    private var still: Bool { reduceMotion || voiceOver }

    var body: some View {
        let text = BoxPrizeText.make(for: box, catalog: model.catalog)
        TimelineView(.animation(paused: skipped || ended || still || ParcelOpening.frozenAt != nil)) { context in
            let elapsed = ParcelOpening.frozenAt ?? context.date.timeIntervalSince(start)
            let phase = ParcelOpening.phase(at: elapsed, reduceMotion: still, skipped: skipped)
            Stage(box: box, text: text, elapsed: elapsed, phase: phase, still: still, onDone: { dismiss() })
                .onChange(of: phase) { old, new in
                    if old < .pop, new >= .pop, !skipped { model.fx("fx_pop", volume: 0.5) }
                    if old < .reveal, new >= .reveal, !skipped { model.fx("fx_sparkle", volume: 0.4) }
                    if new == .done { ended = true; announce(text) }
                }
                .onAppear { if phase == .done { announce(text) } }
        }
        .contentShape(Rectangle())
        .onTapGesture { if !skipped { skipped = true } }
        .onChange(of: scenePhase) { _, new in if new != .active { skipped = true } }   // nothing is lost: the prize is stored
        .skyBackground()
        .environment(\.locale, Lang.current.locale)
    }

    private func announce(_ text: BoxPrizeText) {
        guard voiceOver else { return }
        AccessibilityNotification.Announcement(text.spoken).post()
    }

    /// Everything drawn, as a function of the elapsed time.
    private struct Stage: View {
        let box: BoxPurchase
        let text: BoxPrizeText
        let elapsed: Double
        let phase: ParcelOpening.Phase
        let still: Bool
        let onDone: () -> Void
        @Environment(AppModel.self) private var model

        private var u: Double { elapsed / Motion.pace }
        private var open: Bool { phase >= .pop }
        /// 0…1 over the pop and reveal: the lid lifts, the prize rises.
        private var rise: Double {
            if phase == .done { return 1 }
            return min(1, max(0, (u - ParcelOpening.popAt) / (ParcelOpening.doneAt - ParcelOpening.popAt)))
        }
        private var wobble: Double {
            phase == .wobble ? 7 * sin(2 * .pi * 2 * u / ParcelOpening.popAt) : 0
        }
        private var cardOpacity: Double {
            if phase == .done { return 1 }
            return min(1, max(0, (u - ParcelOpening.revealAt) / (ParcelOpening.doneAt - ParcelOpening.revealAt)))
        }

        var body: some View {
            VStack(spacing: 14) {
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    BuddyView.centred(
                        BuddyView(state: .awake, cloud: true, hold: open ? .purr : nil, outfit: model.buddyOutfit)
                            .id(open)
                            .frame(width: 190))
                        .frame(height: 170)
                        .padding(.bottom, 24)
                    parcel
                }
                .accessibilityHidden(true)
                Text(L("The cat opened your parcel."))
                    .font(.subheadline).cardCaption()
                    .opacity(cardOpacity)
                VStack(spacing: 12) {
                    BoxPrizeCard(box: box)
                    Button(L("Done"), action: onDone)
                        .glassButton(prominent: true).tint(.indigo)
                        .frame(maxWidth: .infinity)
                }
                .padding().glassCard()
                .opacity(cardOpacity)
                .allowsHitTesting(phase == .done)
                .padding(.horizontal)
                Spacer(minLength: 0)
            }
            .animation(still ? .easeInOut(duration: 0.25) : nil, value: phase)
        }

        private let w: CGFloat = 96
        private var parcel: some View {
            ZStack(alignment: .bottom) {
                // the prize rises out of the open parcel
                Text(verbatim: text.emoji).font(.system(size: 54))
                    .opacity(open ? min(1, rise * 2.5) : 0)
                    .offset(y: -w * 0.6 - 40 * rise)
                    .overlay(alignment: .top) { sparkles }
                // the body with its ribbon
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.62, green: 0.72, blue: 0.95))
                    Rectangle().fill(Color(red: 0.98, green: 0.86, blue: 0.55)).frame(width: 16)
                }
                .frame(width: w, height: w * 0.72)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                // the lid with the bow
                ZStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.52, green: 0.62, blue: 0.90))
                        Rectangle().fill(Color(red: 0.98, green: 0.86, blue: 0.55)).frame(width: 16)
                    }
                    .frame(width: w + 10, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    HStack(spacing: 2) {
                        Ellipse().fill(Color(red: 0.98, green: 0.80, blue: 0.40)).frame(width: 24, height: 17).rotationEffect(.degrees(-20))
                        Ellipse().fill(Color(red: 0.98, green: 0.80, blue: 0.40)).frame(width: 24, height: 17).rotationEffect(.degrees(20))
                    }
                    .offset(y: -12)
                }
                .offset(x: open ? 52 * rise : 0, y: -w * 0.72 + 12 - (open ? 38 * rise : 0))
                .rotationEffect(.degrees(open ? 24 * rise : 0))
            }
            .frame(width: w + 60, height: w * 1.8, alignment: .bottom)
            .rotationEffect(.degrees(wobble), anchor: .bottom)
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        }

        @ViewBuilder
        private var sparkles: some View {
            if open {
                ZStack {
                    ForEach(0..<5, id: \.self) { i in
                        let a = Double(i) / 5 * 2 * .pi
                        Text(verbatim: "✨").font(.system(size: 16))
                            .offset(x: cos(a) * 48 * (0.4 + rise * 0.6), y: sin(a) * 30 - 8)
                            .opacity(phase == .done ? 0.0 : 1 - rise * 0.6)
                    }
                }
                .frame(width: 1, height: 1)
            }
        }
    }
}
