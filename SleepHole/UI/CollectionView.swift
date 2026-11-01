import SleepCore
import SwiftUI

/// The collection (step 11b4c), inside the Parcels tab: the postcards to read, the decorations (they stand in the town by
/// themselves), the cat's accessories with the choice of what is worn (one per slot), the night skies with a choice, and
/// the jokers won from parcels. Everything is read from the box records; the two choices are stored on the profile
/// (`AppModel.chooseAccessory`, `chooseNightSky`). The shop never pushes: "n of N", no locked placeholders, nothing "left".

/// The card "Your collection" between today's card and the odds card.
struct CollectionCard: View {
    @Environment(AppModel.self) private var model
    let boxes: [BoxPurchase]
    @State private var jokers = DevArgs.value(after: "-openCollection") == "jokers"      // screenshots (Debug only)
    @State private var autoOpen: String? = DevArgs.value(after: "-openCollection")

    var body: some View {
        let held = model.heldBoxJokers()
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Your collection")).font(.headline)
            link("💌", L("Postcards"), .postcard) { PostcardsListView() }
            Divider()
            link("🌳", L("Town decorations"), .decoration) { DecorationsListView() }
            Divider()
            link("🐱", L("For the cat"), .accessory) { CatOutfitView() }
            Divider()
            link("🌌", L("Night skies"), .sky) { NightSkiesView() }
            Divider()
            boughtLink
            ForEach(held, id: \.id) { box in
                Divider()
                heldRow(box)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassCard()
        .sheet(isPresented: $jokers) { JokerSheet().presentationDetents([.large]) }
    }

    private func link<Destination: View>(_ emoji: String, _ title: String, _ kind: CollectibleKind,
                                         @ViewBuilder destination: () -> Destination) -> some View {
        let count = L("\(Boxes.owned(kind, boxes: boxes).count) of \(BoxCatalog.size(kind))")
        return NavigationLink {
            destination()
        } label: {
            HStack(spacing: 10) {
                Text(verbatim: emoji).frame(width: 30)
                Text(title).font(.subheadline)
                Spacer(minLength: 8)
                Text(count).font(.caption.monospacedDigit()).cardCaption()
                Image(systemName: "chevron.right").font(.caption).cardCaption()
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(title), \(count)"))
        }
        .buttonStyle(.plain)
        .navigationDestination(isPresented: Binding(                 // screenshots: `-openCollection postcards|decorations|cat|skies`
            get: { autoOpen == Self.launchKey(kind) || (kind == .postcard && autoOpen == "postcard") }, set: { if !$0 { autoOpen = nil } })) { destination() }
    }

    /// "Parcels bought": every parcel ever bought, newest first.
    private var boughtLink: some View {
        let title = L("Parcels bought"), count = "\(boxes.count)"
        return NavigationLink {
            BoughtParcelsView()
        } label: {
            HStack(spacing: 10) {
                Text(verbatim: "📜").frame(width: 30)
                Text(title).font(.subheadline)
                Spacer(minLength: 8)
                Text(verbatim: count).font(.caption.monospacedDigit()).cardCaption()
                Image(systemName: "chevron.right").font(.caption).cardCaption()
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(title), \(count)"))
        }
        .buttonStyle(.plain)
        .navigationDestination(isPresented: Binding(                 // screenshots: `-openCollection bought|boughtSheet`
            get: { autoOpen == "bought" || autoOpen == "boughtSheet" }, set: { if !$0 { autoOpen = nil } })) { BoughtParcelsView() }
    }

    /// The `-openCollection` word of a kind (DevArgs is empty in Release, so this never fires there).
    private static func launchKey(_ kind: CollectibleKind) -> String {
        switch kind {
        case .postcard: "postcards"
        case .decoration: "decorations"
        case .accessory: "cat"
        case .sky: "skies"
        }
    }

    private func heldRow(_ box: BoxPurchase) -> some View {
        let tier = Boxes.wonJoker(box) ?? .bronze
        let until = Fmt.fullDate(Boxes.expiry(of: box, calendar: .current))
        let title = L("\(tier.title) from a parcel")
        let validity = L("Valid through \(until)")
        return HStack(spacing: 10) {
            Text(verbatim: tier.emoji).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                Text(validity).font(.caption).cardCaption()
            }
            Spacer(minLength: 8)
            Button(L("Use")) { jokers = true }
                .glassButton(prominent: false)
                .accessibilityLabel(Text(verbatim: [L("Use"), title, validity].joined(separator: ", ")))
        }
    }
}

// MARK: - the lists

private struct CollectionScreen<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) { content }.padding()
        }
        .skyBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// An empty collection: one kind sentence, no placeholders.
private struct EmptyNote: View {
    let text: String
    var body: some View {
        Text(text).font(.subheadline).cardCaption().fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading).padding().glassCard()
    }
}

/// The owned postcards, newest first; a tap opens the postcard.
struct PostcardsListView: View {
    @Environment(AppModel.self) private var model
    @State private var openFirst = DevArgs.value(after: "-openCollection") == "postcard"      // screenshots (Debug only)

    var body: some View {
        let wins = Collection.firstWins(.postcard, boxes: model.boxes()).reversed()
        CollectionScreen(title: L("Postcards")) {
            if openFirst, let first = wins.first {
                Color.clear.frame(height: 0).navigationDestination(isPresented: $openFirst) {
                    ScrollView { PostcardView(id: first.id).padding() }.skyBackground()
                }
            }
            if wins.isEmpty {
                EmptyNote(text: L("No postcards yet. Each one holds a sleep tip."))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(wins.enumerated()), id: \.element.id) { i, win in
                        if i > 0 { Divider() }
                        NavigationLink {
                            ScrollView { PostcardView(id: win.id).padding() }
                                .skyBackground()
                                .navigationTitle(PostcardText.title(for: win.id))
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            row(win.id, won: win.box)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal).padding(.vertical, 4)
                .glassCard()
            }
        }
    }

    private func row(_ id: String, won: BoxPurchase) -> some View {
        let title = PostcardText.title(for: id), date = Fmt.fullDate(won.nightKey)
        return HStack(spacing: 10) {
            Text(verbatim: PostcardText.stamp(for: id)).font(.title2).frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                Text(date).font(.caption).cardCaption()
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption).cardCaption()
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(title), \(date)"))
    }
}

/// The parcels bought: newest first and the two sums (plain numbers, no judgement).
struct BoughtParcels: Equatable {
    let newestFirst: [BoxPurchase]
    let spent: Int
    let back: Int

    init(_ boxes: [BoxPurchase]) {
        newestFirst = boxes.sorted { $0.at > $1.at }
        spent = boxes.reduce(0) { $0 + $1.price }
        back = boxes.reduce(0) { $0 + $1.payout }
    }
}

/// Every parcel ever bought, newest first; a tap opens that parcel's prize card in a sheet.
struct BoughtParcelsView: View {
    @Environment(AppModel.self) private var model
    @State private var shown: BoxPurchase?
    @State private var autoSheet = DevArgs.value(after: "-openCollection") == "boughtSheet"      // screenshots (Debug only)

    var body: some View {
        let all = BoughtParcels(model.boxes())
        CollectionScreen(title: L("Parcels bought")) {
            if all.newestFirst.isEmpty {
                EmptyNote(text: L("No parcels yet. One can be bought on the morning after a complete night."))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Spent on parcels: \(all.spent) 🪙")).font(.subheadline)
                    Text(L("Coins back from parcels: \(all.back) 🪙")).font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding().glassCard()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(L("Spent on parcels: \(all.spent) 🪙")). \(L("Coins back from parcels: \(all.back) 🪙"))"))
                VStack(spacing: 0) {
                    ForEach(Array(all.newestFirst.enumerated()), id: \.element.id) { i, box in
                        if i > 0 { Divider() }
                        Button { shown = box } label: { row(box) }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal).padding(.vertical, 4)
                .glassCard()
            }
        }
        .sheet(item: Binding(get: { shown.map(ParcelItem.init) }, set: { shown = $0?.box })) { item in
            NavigationStack {
                ScrollView {
                    BoxPrizeCard(box: item.box).padding().glassCard().padding()
                }
                .skyBackground()
                .navigationTitle(Fmt.fullDate(item.box.nightKey))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { shown = nil } } }
            }
            .environment(\.locale, Lang.current.locale)
        }
        .onAppear {
            if autoSheet { autoSheet = false; shown = all.newestFirst.first }
        }
    }

    private func row(_ box: BoxPurchase) -> some View {
        let text = BoxPrizeText.make(for: box, catalog: model.catalog)
        let date = [text.kind, Fmt.fullDate(box.nightKey)].compactMap { $0 }.joined(separator: " · ")      // "Postcard · 26 Oct"
        var caption = L("Price \(box.price) 🪙")
        if box.payout > 0 { caption += " · " + L("+\(box.payout) 🪙 back") }
        return HStack(spacing: 10) {
            Text(verbatim: text.emoji).font(.title2).frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: text.title).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                Text(date).font(.caption).cardCaption()
                Text(caption).font(.caption).cardCaption().fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption).cardCaption()
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(text.title), \(date), \(caption)"))
    }
}

private struct ParcelItem: Identifiable {
    let box: BoxPurchase
    var id: String { box.id }
}

/// The owned decorations: they stand in the town by themselves, nothing to choose.
struct DecorationsListView: View {
    @Environment(AppModel.self) private var model
    @Environment(SpriteLibrary.self) private var sprites

    var body: some View {
        let wins = Collection.firstWins(.decoration, boxes: model.boxes()).reversed()
        CollectionScreen(title: L("Town decorations")) {
            if wins.isEmpty {
                EmptyNote(text: L("No decorations yet. Each one you win stands in your town."))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(wins.enumerated()), id: \.element.id) { i, win in
                        if i > 0 { Divider() }
                        row(win.id)
                    }
                }
                .padding(.horizontal).padding(.vertical, 4)
                .glassCard()
            }
        }
    }

    private func row(_ id: String) -> some View {
        let name = CollectibleText.decorationName(id, catalog: sprites.catalog)
        let caption = L("It stands in your town by itself.")
        return HStack(spacing: 12) {
            Group {
                if let s = TownDecorations.spriteId(for: id), let img = sprites.image(for: s) {
                    Image(uiImage: img).resizable().scaledToFit()
                } else {
                    Image(systemName: "questionmark.square.dashed").font(.title).cardCaption()
                }
            }
            .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline)
                Text(caption).font(.caption).cardCaption().fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(name). \(caption)"))
    }
}

/// The cat: a preview of what it wears and, per slot, "Nothing" and each owned item with a check on the worn one.
struct CatOutfitView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let owned = Boxes.owned(.accessory, boxes: model.boxes())
        let worn = model.buddyOutfit
        CollectionScreen(title: L("For the cat")) {
            BuddyView(state: .awake, outfit: worn)
                .frame(width: 220)
                .padding(.top, 28)                 // head items rise above the layout box
                .frame(maxWidth: .infinity)
            if owned.isEmpty {
                EmptyNote(text: L("No cat accessories yet. The cat will wear what you win."))
            }
            slot(.head, title: L("Head"), owned: owned, worn: worn.head)
            slot(.face, title: L("Face"), owned: owned, worn: worn.face)
            slot(.bed, title: L("By the bed"), owned: owned, worn: worn.bed)
        }
    }

    @ViewBuilder
    private func slot(_ slot: AccessorySlot, title: String, owned: Set<String>, worn: String?) -> some View {
        let ids = BoxCatalog.ids(.accessory).filter { AccessorySlot.of($0) == slot && owned.contains($0) }
        if !ids.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.headline).padding(.vertical, 8)
                choice(L("Nothing"), checked: worn == nil) { model.chooseAccessory(nil, slot: slot) }
                ForEach(ids, id: \.self) { id in
                    Divider()
                    choice(CollectibleText.accessoryName(id), checked: worn == id) { model.chooseAccessory(id, slot: slot) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal).padding(.bottom, 4)
            .glassCard()
        }
    }

    private func choice(_ name: String, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(name).font(.subheadline)
                Spacer(minLength: 8)
                if checked { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}

/// The night skies: the plain sky and each owned one, a still preview, a check on the shown one.
struct NightSkiesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let owned = Collection.firstWins(.sky, boxes: model.boxes()).map(\.id)
        let shown = model.nightSkyId
        CollectionScreen(title: L("Night skies")) {
            if owned.isEmpty {
                EmptyNote(text: L("No night skies yet. A sky you win lights up your nights."))
            }
            VStack(spacing: 0) {
                choice(nil, name: L("Plain sky"), checked: shown == nil || !owned.contains(shown ?? ""))
                ForEach(BoxCatalog.ids(.sky).filter { owned.contains($0) }, id: \.self) { id in
                    Divider()
                    choice(id, name: CollectibleText.skyName(id), checked: shown == id)
                }
            }
            .padding(.horizontal).padding(.vertical, 4)
            .glassCard()
            Text(L("Shown on Today and in the town at night."))
                .font(.footnote).cardCaption().fixedSize(horizontal: false, vertical: true)
        }
    }

    private func choice(_ id: String?, name: String, checked: Bool) -> some View {
        Button { model.chooseNightSky(id) } label: {
            HStack(spacing: 12) {
                preview(id)
                Text(name).font(.subheadline)
                Spacer(minLength: 8)
                if checked { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }

    /// A still night: the stars and (for a sky) its effect in the frozen frame.
    private func preview(_ id: String?) -> some View {
        Canvas { gc, size in
            SkyDrawing.stars(&gc, size: size, opacity: 1, t: 0)
            if let effect = NightSkies.effect(forId: id) {
                NightSkyDrawing.draw(effect, &gc, size: size, opacity: 1, t: 0, still: true)
            }
        }
        .frame(width: 84, height: 56)
        .background(LinearGradient(colors: [Color(red: 0.03, green: 0.05, blue: 0.16), Color(red: 0.10, green: 0.12, blue: 0.30)],
                                   startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
    }
}
