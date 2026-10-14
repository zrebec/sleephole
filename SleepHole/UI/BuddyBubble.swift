import SleepCore
import SwiftUI

/// The sleep buddy's speech bubble on Today (phase TALK, owner 2026-10-14): one sentence of the day about the town;
/// a tap shows the next one and, after the last, the first again. An overlay – it never changes Today's layout.
struct BuddyBubble: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let now: Date
    @State private var lines: [BuddyLine] = []
    @State private var index = AppModel.forcedBuddyLine ?? 0

    var body: some View {
        Group {
            if !lines.isEmpty {
                let i = min(index, lines.count - 1)
                let sentence = text(lines[i])
                Button {
                    let go = { index = BuddyTalk.next(after: i, count: lines.count) }
                    if reduceMotion { go() } else { withAnimation(.easeInOut(duration: Motion.t(0.3))) { go() } }
                } label: {
                    Text(sentence)
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(4)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .glassCard(cornerRadius: 16)
                        .background(alignment: .topLeading) { BubbleTail().offset(x: 30, y: -8) }
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
        BuddyTalkText.text(for: line) { id in model.catalog?[id]?.displayName ?? L("building") }
    }
}

/// The little tail of the bubble, pointing down towards the cat.
private struct BubbleTail: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Triangle()
            .fill(CardBacking.color(dark: scheme == .dark).opacity(0.9))
            .frame(width: 14, height: 9)
            .scaleEffect(y: -1)               // points up, towards the cat
    }
    private struct Triangle: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.minX + r.width * 0.3, y: r.maxY)); p.closeSubpath()
            return p
        }
    }
}
