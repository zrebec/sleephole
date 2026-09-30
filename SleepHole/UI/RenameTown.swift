import SleepCore
import SwiftUI

/// Renaming the town – always through this dialog, which says what it costs (owner 2026-09-30: the first name and
/// one rename a year are free, a typo can be fixed for 10 minutes, otherwise 5 000 🪙).
struct RenameTownAlert: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool
    @State private var draft = ""
    @State private var failed = false

    func body(content: Content) -> some View {
        let cost = model.renameCost()
        let affordable = model.coins >= cost.coins
        content
            .alert(L("Town name"), isPresented: $isPresented) {
                TextField(L("My Town"), text: $draft)
                Button(cost.coins > 0 ? L("Rename for \(cost.coins) 🪙") : L("Save")) {
                    failed = model.renameTown(draft) == .notEnoughCoins
                }
                .disabled(!affordable)
                Button(L("Cancel"), role: .cancel) {}
            } message: {
                Text(Self.costText(cost, coins: model.coins, nextFree: model.nextFreeRename))
            }
            .alert(L("Not enough coins"), isPresented: $failed) {
                Button(L("OK"), role: .cancel) {}
            }
            .onChange(of: isPresented) { _, shown in if shown { draft = model.customTownName ?? "" } }
    }

    static func costText(_ cost: RenamePolicy.Cost, coins: Int, nextFree: Date?) -> String {
        switch cost {
        case .free(.firstNaming): return L("Naming your town is free.")
        case .free(.typoFix): return L("You can fix a typo for free for 10 minutes after renaming.")
        case .free(.yearly): return L("Free – you can rename your town for free once a year.")
        case .paid(let price):
            let next = nextFree.map { L("Free again on \(Fmt.fullDate(NightKey(date: $0, calendar: .current))).") } ?? ""
            let short = coins < price ? " " + L("You have \(coins) 🪙 – \(price - coins) more needed.") : ""
            return L("Renaming costs \(price) 🪙.") + " " + next + short
        }
    }
}

extension View {
    func renameTownAlert(isPresented: Binding<Bool>) -> some View {
        modifier(RenameTownAlert(isPresented: isPresented))
    }
}
