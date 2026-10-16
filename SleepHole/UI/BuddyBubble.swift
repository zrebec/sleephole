import SleepCore
import SwiftUI

/// The sleep buddy's speech bubble on Today (phase TALK, owner 2026-10-14): a sentence about the town. It opens with
/// the news of the day (once a day each), then every tap shows a random sentence not heard yet in the round
/// (`BuddyBag`, owner 2026-10-15). An overlay – it never changes Today's layout.
struct BuddyBubble: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    let now: Date
    /// The sentences available now (refreshed on every tick; the bag keeps its own state).
    @State private var lines: [BuddyLine] = []
    @State private var bag = BuddyBag()
    @State private var usedForced = false

    /// Solid colours, no transparency (owner): white paper with dark ink by day, a deep blue paper with white ink at night.
    private var paper: Color { scheme == .dark ? Color(red: 0.17, green: 0.19, blue: 0.30) : .white }
    private var ink: Color { scheme == .dark ? .white : Color(red: 0.10, green: 0.11, blue: 0.18) }

    var body: some View {
        Group {
            if let line = bag.current {
                let sentence = text(line)
                Button {
                    let go = { var g = SystemRandomNumberGenerator(); bag.next(available: lines, using: &g) }
                    if reduceMotion { go() } else { withAnimation(.easeInOut(duration: Motion.t(0.3))) { go() } }
                } label: {
                    // a comic speech bubble (owner 2026-10-15: "the font is terribly small"): solid, outlined, readable
                    Text(sentence)
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.top, 11 + SpeechBubbleShape.tailHeight).padding(.bottom, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            SpeechBubbleShape().fill(paper)
                            SpeechBubbleShape().stroke(ink.opacity(0.85), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                        }
                        .id(line)
                        .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(sentence)
                .accessibilityHint(L("next sentence"))
            }
        }
        .onAppear { reload(fresh: true) }
        .onChange(of: scenePhase) { _, p in if p == .active { reload(fresh: true) } }
        .onChange(of: now) { _, _ in reload(fresh: false) }
        .onChange(of: model.townVersion) { _, _ in reload(fresh: false) }
    }

    /// `fresh`: the bubble starts showing (Today appears / the app returns) → open with the news or a random line.
    /// Otherwise only the available set is refreshed; the sentence on screen never changes by itself (unless the
    /// bubble has nothing to show yet).
    private func reload(fresh: Bool) {
        lines = model.buddyLines(now: now)
        guard fresh || bag.current == nil else { return }
        let log = BuddyNewsLog(calendar: .current)
        var g = SystemRandomNumberGenerator()
        if let forced = AppModel.forcedBuddyLine, !usedForced, !lines.isEmpty {
            usedForced = true
            bag.force(lines[forced % lines.count])
            return
        }
        if let line = bag.open(available: lines, ledToday: log.ledToday(now: now), using: &g), line.isNews {
            log.markLed(line, now: now)
        }
    }

    private func text(_ line: BuddyLine) -> String {
        Self.gluingTrailingEmoji(BuddyTalkText.text(for: line) { id in model.catalog?[id]?.displayName ?? L("building") })
    }

    /// A trailing emoji ("… posed for it 🐾") never wraps onto a line of its own: the space before it becomes a
    /// no-break space. Display only – the catalog texts stay as they are.
    static func gluingTrailingEmoji(_ s: String) -> String {
        guard let last = s.last, last.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) else { return s }
        var t = s
        t.removeLast()
        guard t.last == " " else { return s }
        t.removeLast()
        return t + "\u{00A0}" + String(last)
    }
}

/// A rounded speech bubble whose tail rises from its top edge, slightly left of the centre, towards the cat's mouth
/// (the bubble is centred under the cat's head). The shape includes the tail's height at the top.
struct SpeechBubbleShape: Shape {
    static let tailHeight: CGFloat = 16
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 20, t = rect.minY + Self.tailHeight
        let tipX = rect.midX - 6, baseL = rect.midX - 8, baseR = rect.midX + 14
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + r, y: t))
        p.addLine(to: CGPoint(x: baseL, y: t))
        p.addLine(to: CGPoint(x: tipX, y: rect.minY + 1))
        p.addLine(to: CGPoint(x: baseR, y: t))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: t))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: t), tangent2End: CGPoint(x: rect.maxX, y: t + r), radius: r)
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - r, y: rect.maxY), radius: r)
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - r), radius: r)
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: t), tangent2End: CGPoint(x: rect.minX + r, y: t), radius: r)
        p.closeSubpath()
        return p
    }
}

/// Which news sentences already opened the bubble today – a per-device convenience in `UserDefaults` (a failure to
/// read or write only means a news line may lead again).
struct BuddyNewsLog {
    var calendar: Calendar
    var defaults: UserDefaults = .standard
    static let key = "buddy.newsLed"

    private func day(_ now: Date) -> String { NightKey(date: now, calendar: calendar).description }

    func ledToday(now: Date) -> Set<String> {
        guard let d = defaults.dictionary(forKey: Self.key), d["day"] as? String == day(now),
              let keys = d["keys"] as? [String] else { return [] }
        return Set(keys)
    }

    func markLed(_ line: BuddyLine, now: Date) {
        var keys = ledToday(now: now)
        keys.insert(line.newsKey)
        defaults.set(["day": day(now), "keys": Array(keys).sorted()] as [String: Any], forKey: Self.key)
    }
}
