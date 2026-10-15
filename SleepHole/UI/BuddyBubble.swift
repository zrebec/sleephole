import SleepCore
import SwiftUI

/// The sleep buddy's speech bubble on Today (phase TALK, owner 2026-10-14): one sentence of the day about the town;
/// a tap shows the next one and, after the last, the first again. An overlay – it never changes Today's layout.
struct BuddyBubble: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    let now: Date
    @State private var lines: [BuddyLine] = []
    @State private var index = AppModel.forcedBuddyLine ?? 0

    /// Solid colours, no transparency (owner): white paper with dark ink by day, a deep blue paper with white ink at night.
    private var paper: Color { scheme == .dark ? Color(red: 0.17, green: 0.19, blue: 0.30) : .white }
    private var ink: Color { scheme == .dark ? .white : Color(red: 0.10, green: 0.11, blue: 0.18) }

    var body: some View {
        Group {
            if !lines.isEmpty {
                let i = min(index, lines.count - 1)
                let sentence = text(lines[i])
                Button {
                    let go = { index = BuddyTalk.next(after: i, count: lines.count) }
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
                        .id(i)
                        .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(sentence)
                .accessibilityHint(L("next sentence"))
            }
        }
        .onAppear { reload() }
        .onChange(of: now) { _, _ in reload() }
        .onChange(of: model.townVersion) { _, _ in reload() }
    }

    private func reload() { lines = model.buddyLines(now: now) }

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
