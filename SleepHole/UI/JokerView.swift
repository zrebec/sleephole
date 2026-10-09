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
    @State private var confirm: JokerTier?

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
                                if u.automatic { Text(L("automatic")).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }
            .navigationTitle(L("Jokers 🛡️"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } } }
            .confirmationDialog(confirm.map { L("Switch on the \($0.title)?") } ?? "", isPresented: Binding(
                get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible) {
                if let tier = confirm {
                    Button(tier.price > 0 ? L("Switch on for \(tier.price) 🪙") : L("Switch on for free")) {
                        model.useJoker(tier)
                        model.fx("fx_sparkle")
                        dismiss()
                    }
                }
            } message: {
                if let tier = confirm {
                    Text(L("It protects \(Plural.nights(tier.nights)) from \(Fmt.dayMonth(first)). This kind is used up for this month."))
                }
            }
        }
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
                case nil: EmptyView()
                }
            }
            Spacer()
            Button(L("Use")) { confirm = tier }
                .glassButton(prominent: true)
                .tint(tier.tint)
                .disabled(block != nil)
        }
        .padding(.vertical, 4)
    }
}
