import SleepCore
import SwiftUI

/// What a bought box gave, as plain words (step 11b4a). Independent of the shop: the opening animation of 11b4b puts
/// itself in front of the same card. Every text is a literal `L("…")` so the i18n tool finds it.
struct BoxPrizeText: Equatable {
    /// One emoji for the card.
    let emoji: String
    /// The headline: "+400 🪙", "Lucky night ×2", the name of the collectible, the joker.
    let title: String
    /// What kind of thing it is ("Postcard", "Night sky", …); nil for coins and the like.
    let kind: String?
    /// The sentence under the headline.
    let detail: String?
    /// Set for a postcard: the id the "Read" button opens.
    let postcardId: String?

    /// The words for one purchase in the app's current language.
    static func make(for box: BoxPurchase, catalog: Catalog?, calendar: Calendar = .current) -> BoxPrizeText {
        switch box.prize {
        case .coins:
            return BoxPrizeText(emoji: "🪙", title: L("+\(box.payout) 🪙"), kind: nil, detail: nil, postcardId: nil)
        case .luckyNight:
            return BoxPrizeText(emoji: "🍀", title: L("Lucky night ×2"), kind: nil,
                                detail: L("Your next complete night pays double."), postcardId: nil)
        case .collectible(let kind, let id):
            let duplicate = box.payout > 0
            let detail = duplicate ? L("Already in your collection – +\(box.payout) 🪙 instead.") : L("New in your collection.")
            let (emoji, name, label): (String, String, String) = {
                switch kind {
                case .postcard: (PostcardText.stamp(for: id), PostcardText.title(for: id), L("Postcard"))
                case .decoration: ("🌳", CollectibleText.decorationName(id, catalog: catalog), L("Town decoration"))
                case .accessory: ("🐱", CollectibleText.accessoryName(id), L("For the cat"))
                case .sky: ("🌌", CollectibleText.skyName(id), L("Night sky"))
                }
            }()
            return BoxPrizeText(emoji: emoji, title: name, kind: label, detail: detail,
                                postcardId: kind == .postcard ? id : nil)
        case .joker(let tier):
            if Boxes.wonJoker(box) != nil {
                let until = Fmt.fullDate(Boxes.expiry(of: box, calendar: calendar))
                return BoxPrizeText(emoji: tier.emoji, title: tier.title, kind: nil, detail: L("Yours until \(until)."), postcardId: nil)
            }
            return BoxPrizeText(emoji: tier.emoji, title: tier.title, kind: nil,
                                detail: L("You already hold one – +\(box.payout) 🪙 instead."), postcardId: nil)
        case .unknown:
            return BoxPrizeText(emoji: "🎁", title: L("A prize from a newer version of SleepHole."), kind: nil, detail: nil,
                                postcardId: nil)
        }
    }

    /// One sentence for VoiceOver.
    var spoken: String { [kind, title, detail].compactMap { $0 }.joined(separator: ". ") }
}

/// The result of a box as a card. Reusable: the shop shows it for today's box, 11b4b shows it after the opening.
struct BoxPrizeCard: View {
    let box: BoxPurchase
    @Environment(AppModel.self) private var model
    @State private var reading = false

    var body: some View {
        let text = BoxPrizeText.make(for: box, catalog: model.catalog)
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    Text(verbatim: text.emoji).font(.largeTitle)
                    VStack(alignment: .leading, spacing: 2) {
                        if let kind = text.kind { Text(kind).font(.caption).textCase(.uppercase).cardCaption() }
                        Text(verbatim: text.title).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let detail = text.detail {
                    Text(detail).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text.spoken)
            if text.postcardId != nil {
                Button(L("Read")) { reading = true }
                    .glassButton(prominent: false)
            }
            wearing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $reading) {
            if let id = text.postcardId {
                NavigationStack {
                    ScrollView { PostcardView(id: id).padding() }
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { reading = false } } }
                        .navigationBarTitleDisplayMode(.inline)
                }
                .environment(\.locale, Lang.current.locale)
            }
        }
    }

    /// A new accessory or sky: "Put it on" / "Show this sky", or a note that it is already shown. A repeat that turned
    /// into coins (payout > 0) has nothing to put on.
    @ViewBuilder
    private func wearing() -> some View {
        if box.payout == 0, case .collectible(let kind, let id) = box.prize {
            switch kind {
            case .accessory:
                if let slot = AccessorySlot.of(id) {
                    let worn = [model.buddyOutfit.head, model.buddyOutfit.face, model.buddyOutfit.bed].contains(id)
                    if worn {
                        Text(L("The cat has it now.")).font(.footnote).cardCaption()
                    } else {
                        Button(L("Put it on")) { model.chooseAccessory(id, slot: slot) }.glassButton(prominent: false)
                    }
                }
            case .sky:
                if model.nightSkyId == id {
                    Text(L("Shown at night.")).font(.footnote).cardCaption()
                } else {
                    Button(L("Show this sky")) { model.chooseNightSky(id) }.glassButton(prominent: false)
                }
            default: EmptyView()
            }
        }
    }
}
