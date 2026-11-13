import SleepCore
import SwiftUI

/// One postcard from the sleep buddy (step 11b5a): a solid paper card (no glass – the owner dislikes transparency)
/// with an emoji stamp, the title, one sourced sleep tip, the cat's signature, the number and the source as a link.
/// The ink is always dark and the paper always light-ish (a little dimmer in dark mode, never glaring), so the text
/// keeps its contrast in both modes. No fixed heights: it grows with Dynamic Type. VoiceOver reads it as one element.
struct PostcardView: View {
    let id: String
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    /// Paper and ink: dark ink (≈ 15:1 on the light paper, ≈ 11:1 on the dimmer one).
    static func paper(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.86, green: 0.82, blue: 0.73) : Color(red: 0.99, green: 0.96, blue: 0.88)
    }
    static let ink = Color(red: 0.17, green: 0.14, blue: 0.11)
    static let softInk = Color(red: 0.34, green: 0.29, blue: 0.24)
    private static let stampRed = Color(red: 0.62, green: 0.20, blue: 0.18)
    private static let linkBlue = Color(red: 0.10, green: 0.22, blue: 0.52)

    private var number: Int { PostcardText.number(of: id) ?? 0 }
    private var title: String { PostcardText.title(for: id) }
    private var tip: String { PostcardText.tip(for: id) }
    private var source: PostcardSource? { Postcards.source(for: id) }

    private var study: PostcardStudy? { Postcards.study(for: id) }
    private var hasStudy: Bool { PostcardText.hasStudy(id) }

    private var accessibilitySummary: String {
        var studyPart: [String] = []
        if hasStudy, let study {
            studyPart = [PostcardText.whyItHelps, PostcardText.why(for: id) ?? "", PostcardText.studyHeading, PostcardText.citation(for: study),
                    PostcardText.finding(for: id) ?? "", PostcardText.evidenceHeading, PostcardText.evidence(for: id) ?? ""]
        }
        return ([PostcardText.numberLine(number, of: BoxCatalog.size(.postcard)), title, tip, PostcardText.signature] + studyPart + [
         source.map { PostcardText.sourceLine($0.name) } ?? ""])
            .filter { !$0.isEmpty }.joined(separator: ". ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text(PostcardText.header)
                    .font(.caption.weight(.semibold)).textCase(.uppercase)
                    .foregroundStyle(Self.softInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: PostcardText.stamp(for: id))
                    .font(.largeTitle)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Self.stampRed.opacity(0.75), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    )
                    .rotationEffect(.degrees(4))
            }
            Text(title)
                .font(.title3.weight(.bold)).foregroundStyle(Self.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(tip)
                .font(.body).foregroundStyle(Self.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(PostcardText.signature)
                .font(.callout.italic()).foregroundStyle(Self.softInk)
                .frame(maxWidth: .infinity, alignment: .trailing)
            if hasStudy { whySections }
            Rectangle().fill(Self.softInk.opacity(0.35)).frame(height: 1)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(PostcardText.numberLine(number, of: BoxCatalog.size(.postcard)))
                    .font(.footnote).foregroundStyle(Self.softInk)
                Spacer(minLength: 8)
                if let source, let url = URL(string: source.url) {
                    Link(destination: url) {
                        Text(PostcardText.sourceLine(source.name))
                            .padding(.vertical, 13).contentShape(Rectangle()).padding(.vertical, -13)   // a bigger hit area, same layout (13e2)
                    }
                        .font(.footnote.weight(.semibold)).foregroundStyle(Self.linkBlue)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(18)
        .background(Self.paper(scheme), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Self.softInk.opacity(0.25), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAction(named: PostcardText.openSource) {
            if let s = source, let url = URL(string: s.url) { openURL(url) }
        }
        .accessibilityActions {
            if hasStudy, let s = study, let url = URL(string: s.url) {
                Button(PostcardText.openStudy) { openURL(url) }
            }
        }
    }

    private var rule: some View { Rectangle().fill(Self.softInk.opacity(0.35)).frame(height: 1) }

    /// The long part of a postcard that has a study (step 13c): why it helps, the study, how strong the evidence is.
    @ViewBuilder private var whySections: some View {
        rule
        Text(PostcardText.whyItHelps).font(.headline).foregroundStyle(Self.ink).fixedSize(horizontal: false, vertical: true)
        Text(PostcardText.why(for: id) ?? "").font(.body).foregroundStyle(Self.ink).fixedSize(horizontal: false, vertical: true)
        rule
        Text(PostcardText.studyHeading).font(.headline).foregroundStyle(Self.ink).fixedSize(horizontal: false, vertical: true)
        if let study {
            Text(PostcardText.citation(for: study)).font(.footnote.weight(.semibold)).foregroundStyle(Self.softInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        Text(PostcardText.finding(for: id) ?? "").font(.callout).foregroundStyle(Self.ink).fixedSize(horizontal: false, vertical: true)
        if let study, let url = URL(string: study.url) {
            Link(PostcardText.openStudy, destination: url)
                .font(.footnote.weight(.semibold)).foregroundStyle(Self.linkBlue)
                .frame(minHeight: 44, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        rule
        Text(PostcardText.evidenceHeading).font(.headline).foregroundStyle(Self.ink).fixedSize(horizontal: false, vertical: true)
        Text(PostcardText.evidence(for: id) ?? "").font(.callout).foregroundStyle(Self.ink).fixedSize(horizontal: false, vertical: true)
    }
}
