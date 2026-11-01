import SleepCore
import SwiftUI

extension JokerTier {
    var emoji: String {
        switch self {
        case .bronze: "🥉"
        case .silver: "🥈"
        case .gold: "🥇"
        }
    }

    var title: String {
        switch self {
        case .bronze: L("Bronze joker")
        case .silver: L("Silver joker")
        case .gold: L("Gold joker")
        }
    }

    var tint: Color {
        switch self {
        case .bronze: .brown
        case .silver: .gray
        case .gold: .yellow
        }
    }
}

/// Today: a small glass button "🛡️ Joker" – or, while a joker protects a night, what it covers.
struct JokerCard: View {
    @Environment(AppModel.self) private var model
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 10) {
                Text(verbatim: model.activeJoker.map(\.tier.emoji) ?? "🛡️").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    if let j = model.activeJoker {
                        Text(L("\(j.tier.title) protects your streak")).font(.subheadline.bold())
                        Text(L("Nights \(Fmt.dayMonth(j.firstNight)) – \(Fmt.dayMonth(j.lastNight(calendar: .current)))"))
                            .font(.caption).cardCaption()
                    } else {
                        Text(L("Ill or on holiday?")).font(.subheadline.bold())
                        Text(L("A joker protects your 🔥 streak")).font(.caption).cardCaption()
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).cardCaption()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCard(cornerRadius: 22)
        .sheet(isPresented: $open) { JokerSheet().presentationDetents([.large]) }
    }
}

/// Choose and switch on a joker (owner 2026-10-02): each kind once a month, independently.
struct JokerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// What the owner is about to switch on: a month's own joker, or (with a box) one won from a parcel.
    private struct Pending: Equatable { let tier: JokerTier; let box: BoxPurchase? }
    @State private var confirm: Pending?

    var body: some View {
        let first = model.jokerFirstNight
        NavigationStack {
            List {
                Section {
                    Text(L("Jokers keep your 🔥 streak while you are ill or away: the streak waits – it neither breaks nor grows. Each kind can be used once a month: the bronze one is free, the silver and the gold one cost coins. Protected nights build nothing and pay no coins; a good night still counts as usual."))
                        .font(.subheadline)
                    Text(L("If you miss a night and haven't used the bronze joker this month, it is used by itself."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                let held = model.heldBoxJokers()             // first: free, and they expire
                if !held.isEmpty {
                    Section(L("From parcels")) {
                        ForEach(held, id: \.id) { box in boxRow(box) }
                    }
                }
                Section {
                    ForEach(JokerTier.allCases, id: \.self) { tier in row(tier, first: first) }
                } footer: {
                    Text(L("A joker switched on now starts with the night of \(Fmt.dayMonth(first))."))
                }
                let uses = model.jokerState.uses.reversed()
                if !uses.isEmpty {
                    Section(L("Used")) {
                        ForEach(Array(uses.enumerated()), id: \.offset) { _, u in
                            HStack {
                                Text(verbatim: u.tier.emoji)
                                Text(L("\(Fmt.dayMonth(u.firstNight)) – \(Fmt.dayMonth(u.lastNight(calendar: .current)))"))
                                Spacer()
                                let notes = [u.automatic ? L("automatic") : nil, u.boxId != nil ? L("from a parcel") : nil].compactMap { $0 }
                                if !notes.isEmpty { Text(notes.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }
            .navigationTitle(L("Jokers 🛡️"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } } }
            .confirmationDialog(confirmTitle, isPresented: Binding(
                get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible) {
                if let pending = confirm {
                    let tier = pending.tier
                    Button(tier.price > 0 && pending.box == nil ? L("Switch on for \(tier.price) 🪙") : L("Switch on for free")) {
                        model.useJoker(tier, fromBox: pending.box?.id)
                        model.fx("fx_sparkle")
                        dismiss()
                    }
                }
            } message: {
                if let pending = confirm {
                    if pending.box != nil {
                        Text(L("It protects \(Plural.nights(pending.tier.nights)) from \(Fmt.dayMonth(first)). It costs nothing and does not use up this month's own joker."))
                    } else {
                        Text(L("It protects \(Plural.nights(pending.tier.nights)) from \(Fmt.dayMonth(first)). This kind is used up for this month."))
                    }
                }
            }
        }
    }

    private var confirmTitle: String {
        guard let pending = confirm else { return "" }
        return pending.box != nil ? L("Switch on the \(pending.tier.title) from a parcel?") : L("Switch on the \(pending.tier.title)?")
    }

    /// A joker won from a parcel: free, valid until the end of next month, not the month's own slot.
    private func boxRow(_ box: BoxPurchase) -> some View {
        let tier = Boxes.wonJoker(box) ?? .bronze
        let until = Fmt.fullDate(Boxes.expiry(of: box, calendar: .current))
        return HStack(spacing: 12) {
            Text(verbatim: tier.emoji).font(.largeTitle)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("\(tier.title) from a parcel")).font(.headline)
                Text(L("Protects \(Plural.nights(tier.nights))")).font(.subheadline)
                Text(L("Valid through \(until)")).font(.caption).foregroundStyle(.secondary)
                if tier == .bronze {
                    Text(L("Used by itself on a missed night once this month's own bronze is gone."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Button(L("Use")) { confirm = Pending(tier: tier, box: box) }
                .glassButton(prominent: true)
                .tint(tier.tint)
                .disabled(model.jokerBlock(tier, fromBox: box.id) != nil)
        }
        .padding(.vertical, 4)
    }

    private func row(_ tier: JokerTier, first: NightKey) -> some View {
        let block = model.jokerBlock(tier)
        return HStack(spacing: 12) {
            Text(verbatim: tier.emoji).font(.largeTitle)
            VStack(alignment: .leading, spacing: 2) {
                Text(tier.title).font(.headline)
                Text(L("Protects \(Plural.nights(tier.nights))")).font(.subheadline)
                Text(tier.price > 0 ? L("\(tier.price) 🪙") : L("Free")).font(.caption).foregroundStyle(.secondary)
                switch block {
                case .alreadyUsedThisMonth?: Text(L("Already used this month")).font(.caption).foregroundStyle(.orange)
                case .notEnoughCoins(let missing)?: Text(L("\(missing) 🪙 short")).font(.caption).foregroundStyle(.orange)
                case .notHeldFromBox?, nil: EmptyView()
                }
            }
            Spacer()
            Button(L("Use")) { confirm = Pending(tier: tier, box: nil) }
                .glassButton(prominent: true)
                .tint(tier.tint)
                .disabled(block != nil)
        }
        .padding(.vertical, 4)
    }
}
