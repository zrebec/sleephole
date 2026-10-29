#if DEBUG   // developer aid: Debug builds only, like PlansView
import SleepCore
import SwiftUI

/// What the "Box contents" screen lists: always read from the shipped catalogs, never copied (step 11b5e).
enum BoxContents {
    static var postcardIds: [String] { BoxCatalog.ids(.postcard) }
    static var decorationIds: [String] { BoxCatalog.ids(.decoration) }
    static var accessoryIds: [String] { BoxCatalog.ids(.accessory) }
    static var skyIds: [String] { BoxCatalog.ids(.sky) }

    /// The accessories that can be worn in a slot, in catalog order.
    static func accessories(for slot: AccessorySlot) -> [String] { accessoryIds.filter { AccessorySlot.of($0) == slot } }

    /// The sprite id of a decoration (nil = unknown to this build).
    static func sprite(of decorationId: String) -> String? { TownDecorations.spriteId(for: decorationId) }

    /// The effect of a sky id.
    static func effect(of skyId: String) -> NightSkyEffect? { NightSkies.effect(forId: skyId) }

    /// Dev aid: `-openBoxContents [postcards|decorations|cat|skies]` opens the screen (and a section) at once.
    static var launchSection: Section? {
        guard DevArgs.list.contains("-openBoxContents") else { return nil }
        return Section(rawValue: DevArgs.value(after: "-openBoxContents") ?? "") ?? .postcards
    }

    enum Section: String, CaseIterable, Identifiable {
        case postcards, decorations, cat, skies
        var id: String { rawValue }
        var title: String {
            switch self {
            case .postcards: L("Postcards")
            case .decorations: L("Decorations")
            case .cat: L("Cat accessories")
            case .skies: L("Night skies")
            }
        }
        var count: Int {
            switch self {
            case .postcards: BoxContents.postcardIds.count
            case .decorations: BoxContents.decorationIds.count
            case .cat: BoxContents.accessoryIds.count
            case .skies: BoxContents.skyIds.count
            }
        }
    }
}

/// Settings → Developer → Box contents: every collectible a mystery box can hold, read-only (the picks are view state).
struct BoxContentsView: View {
    @Environment(SpriteLibrary.self) private var sprites
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var section: BoxContents.Section = BoxContents.launchSection ?? .postcards
    @State private var head: String?
    @State private var face: String?
    @State private var bed: String?
    @State private var asleep = false

    init() {
        let o = Self.launchOutfit
        _head = State(initialValue: o.head)
        _face = State(initialValue: o.face)
        _bed = State(initialValue: o.bed)
        _asleep = State(initialValue: DevArgs.list.contains("-boxCatAsleep"))
    }

    /// Dev aid: `-boxCatFull` starts with a full outfit (screenshots).
    private static var launchOutfit: CatOutfit {
        guard DevArgs.list.contains("-boxCatFull") else { return .none }
        return CatOutfit(head: BoxContents.accessories(for: .head).first, face: BoxContents.accessories(for: .face).first,
                         bed: BoxContents.accessories(for: .bed).first)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Picker(L("Parcel contents"), selection: $section) {
                    ForEach(BoxContents.Section.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)                 // a menu, not segments: four long names do not fit at large text sizes
                Text(verbatim: "\(section.title) (\(section.count))").font(.headline)
                switch section {
                case .postcards: postcards
                case .decorations: decorations
                case .cat: cat
                case .skies: skies
                }
            }
            .padding(16)
        }
        .navigationTitle(L("Parcel contents"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: postcards

    private var postcards: some View {
        ForEach(BoxContents.postcardIds, id: \.self) { PostcardView(id: $0) }
    }

    // MARK: decorations

    private var decorations: some View {
        ForEach(BoxContents.decorationIds, id: \.self) { id in
            HStack(spacing: 16) {
                Group {
                    if let s = BoxContents.sprite(of: id), let img = sprites.image(for: s) {
                        Image(uiImage: img).resizable().scaledToFit()
                    } else {
                        Image(systemName: "questionmark.square.dashed").font(.largeTitle).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 4) {
                    Text(CollectibleText.decorationName(id, catalog: sprites.catalog)).font(.body)
                    Text(id).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: cat

    private var outfit: CatOutfit { CatOutfit(head: head, face: face, bed: bed) }

    private var cat: some View {
        VStack(alignment: .leading, spacing: 16) {
            BuddyView(state: asleep ? .asleep : .awake, outfit: outfit)
                .id(asleep)
                .frame(width: 260)
                .padding(.top, 28)                  // head items rise up to ~17 pt above the layout box (nightcap pompom, +breathing)
                .frame(maxWidth: .infinity)
            Picker(L("Cat"), selection: $asleep) {
                Text(L("Awake")).tag(false)
                Text(L("Asleep")).tag(true)
            }
            .pickerStyle(.segmented)
            slotPicker(L("Head"), .head, $head)
            slotPicker(L("Face"), .face, $face)
            slotPicker(L("By the bed"), .bed, $bed)
            Divider()
            ForEach(BoxContents.accessoryIds, id: \.self) { id in
                HStack {
                    Text(CollectibleText.accessoryName(id))
                    Spacer()
                    Text(id).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func slotPicker(_ title: String, _ slot: AccessorySlot, _ sel: Binding<String?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Picker(title, selection: sel) {
                Text(L("None")).tag(String?.none)
                ForEach(BoxContents.accessories(for: slot), id: \.self) {
                    Text(CollectibleText.accessoryName($0)).tag(String?.some($0))
                }
            }
            .pickerStyle(.menu)
        }
    }

    // MARK: skies

    private var skies: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(BoxContents.skyIds, id: \.self) { id in
                VStack(alignment: .leading, spacing: 6) {
                    skyCard(id)
                    Text(CollectibleText.skyName(id)).font(.body)
                    Text(id).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            Text(L("Shooting stars: one every 6–12s. The comet crosses the sky once every \(Int(NightSkies.cometPeriod / 60)) min."))
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func skyCard(_ id: String) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                if let effect = BoxContents.effect(of: id) {
                    SkyDrawing.stars(&gc, size: size, opacity: 1, t: t)
                    NightSkyDrawing.draw(effect, &gc, size: size, opacity: 1, t: t, still: reduceMotion)
                }
            }
        }
        .frame(height: 220)
        .background(LinearGradient(colors: [Color(red: 0.03, green: 0.05, blue: 0.16), Color(red: 0.10, green: 0.12, blue: 0.30)],
                                   startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
#endif
