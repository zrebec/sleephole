import SleepCore
import SwiftUI

/// The "Parcels" tab (step 11b4a): today's mystery box, what a box can hold with the odds, and the price rule. Boxes cost
/// coins only; the shop is always visible – at 0 coins too – and never pushes (no countdown, no near-miss).
/// On screen a box is a "parcel" (Slovak "balíček", step 11b4a2): the owner said on 2026-10-29 that the Slovak word for
/// a box is vulgar slang, and so is "box" in American English. The code, the records and the backup keep "box".
struct BoxShopView: View {
    @Environment(AppModel.self) private var model
    @State private var confirming = false

    var body: some View {
        let offer = model.boxOffer()
        let boxes = model.boxes()
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    todayCard(offer, boxes: boxes).appearIn(delay: 0)
                    CollectionCard(boxes: boxes).appearIn(delay: 0.05)
                    oddsCard(boxes: boxes).appearIn(delay: 0.1).id("odds")
                }
                .padding()
            }
            .task {                                            // screenshots: `-boxScroll`, `-boxConfirm` (Debug only: DevArgs is empty in Release)
                if DevArgs.list.contains("-boxScroll") {
                    try? await Task.sleep(for: .seconds(1.5))
                    withAnimation { proxy.scrollTo("odds", anchor: .top) }
                }
                if DevArgs.list.contains("-boxConfirm"), case .available = model.boxOffer() {
                    try? await Task.sleep(for: .seconds(1.5))
                    confirming = true
                }
            }
            }
            .skyBackground()
            .navigationTitle(L("Parcels"))
            .fullScreenCover(item: Bindable(model).openingParcel) { box in
                ParcelOpeningView(box: box)
            }
        }
    }

    // MARK: today

    @ViewBuilder
    private func todayCard(_ offer: BoxOffer, boxes: [BoxPurchase]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Today's parcel")).font(.headline)
            Text(L("Your coins: \(model.coins) 🪙")).font(.subheadline.monospacedDigit()).cardCaption()
            switch offer {
            case .available(let price, let boxNumber):
                Text(L("Parcel \(boxNumber) of \(BoxRules.maxPerMonth) this month")).font(.subheadline)
                Button { confirming = true } label: {
                    Text(L("Buy a parcel for \(price) 🪙")).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .glassButton(prominent: true)
                .tint(.indigo)
                .confirmationDialog(L("Buy this parcel?"), isPresented: $confirming, titleVisibility: .visible) {
                    Button(L("Buy")) { model.buyBox() }
                    Button(L("Cancel"), role: .cancel) {}
                } message: {
                    Text(L("It costs \(price) 🪙 – \(model.coins - price) 🪙 stay."))
                }
            case .notEnoughCoins(_, let missing, let boxNumber):
                Text(L("\(missing) 🪙 to go to parcel \(boxNumber)")).font(.subheadline.bold())
                if !boxes.isEmpty {
                    Text(L("\(BoxRules.reserve) 🪙 always stay for a silver joker.")).font(.footnote).cardCaption()
                }
            case .needsCompleteNight:
                Text(L("A parcel opens on the morning after a complete night.")).font(.subheadline)
            case .alreadyBoughtToday:
                if let box = model.todaysBox() {
                    BoxPrizeCard(box: box)
                    Divider()
                }
                Text(L("One parcel a day – the next one after your next complete night.")).font(.footnote).cardCaption()
            case .monthFull:
                Text(L("Nine parcels this month. The next ones from \(Fmt.fullDate(nextMonth)).")).font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassCard()
    }

    /// The 1st of the month after today's.
    private var nextMonth: NightKey {
        let d = model.boxDay
        return d.month == 12 ? NightKey(year: d.year + 1, month: 1, day: 1) : NightKey(year: d.year, month: d.month + 1, day: 1)
    }

    // MARK: the odds

    private func oddsCard(boxes: [BoxPurchase]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("What a parcel can hold")).font(.headline)
            ForEach(Array(BoxRules.odds.enumerated()), id: \.offset) { _, row in
                oddsRow(row, boxes: boxes)
                Divider()
            }
            Text(L("A collection item is always a new one until you have the whole collection; after that a repeat turns into a quarter of the price in coins. A joker from a parcel lasts until the end of next month; a second one of the same kind also turns into a quarter of the price. Coins are earned only by sleeping – they can never be bought."))
                .font(.footnote).cardCaption().fixedSize(horizontal: false, vertical: true)
            Text(L("Parcels 1–3 of a month cost 20% of your coins, parcels 4–6 cost 40%, parcels 7–9 cost 60% – never less than \(BoxRules.floorPrice) 🪙. At most nine a month."))
                .font(.footnote).cardCaption().fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassCard()
    }

    private func oddsRow(_ row: BoxRules.Odds, boxes: [BoxPurchase]) -> some View {
        let (emoji, name, kind) = Self.describe(row.roll)
        let chance = Fmt.permille(row.permille)
        let caption: String? = row.roll == .luckyNight ? L("Your next complete night pays double.") : nil
        let ownedText = kind.map { L("\(Boxes.owned($0, boxes: boxes).count) of \(BoxCatalog.size($0))") }
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: emoji).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                if let caption { Text(caption).font(.caption).cardCaption().fixedSize(horizontal: false, vertical: true) }
                if let ownedText { Text(ownedText).font(.caption).cardCaption() }
            }
            Spacer(minLength: 8)
            Text(verbatim: chance).font(.subheadline.monospacedDigit().bold())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([name, caption, ownedText, chance].compactMap { $0 }.joined(separator: ", "))
    }

    /// 25 tenths → "2.5" (the multiple of the price in the app's language).
    static func times(_ tenths: Int) -> String {
        let f = NumberFormatter()
        f.locale = Lang.current.locale
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        return f.string(from: NSNumber(value: Double(tenths) / 10)) ?? "\(tenths / 10)"
    }

    /// The emoji, the name and (for the four collections) the kind of one row of the odds table.
    static func describe(_ roll: BoxRoll) -> (emoji: String, name: String, kind: CollectibleKind?) {
        switch roll {
        case .coins(let tenths):
            let name: String = switch tenths {
            case 5: L("Half the price back")
            case 10: L("The price back")
            case 20: L("Twice the price")
            case 30: L("Three times the price")
            default: L("\(Self.times(tenths))× the price")
            }
            return ("🪙", name, nil)
        case .luckyNight: return ("🍀", L("Lucky night ×2"), nil)
        case .collectible(let kind):
            switch kind {
            case .postcard: return ("💌", L("A postcard with a sleep tip"), kind)
            case .decoration: return ("🌳", L("A town decoration"), kind)
            case .accessory: return ("🐱", L("Something for the cat"), kind)
            case .sky: return ("🌌", L("A night sky"), kind)
            }
        case .joker(let tier): return (tier.emoji, tier.title, nil)
        }
    }
}
