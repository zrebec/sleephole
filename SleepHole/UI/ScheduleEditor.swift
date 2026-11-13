import SwiftUI
import SleepCore

/// The schedule editor under the change-week rules (owner 2026-10-15): the status line, bedtime / wake / reminder on a
/// draft, Cancel / Save, the "Start a change week?" alert and the paid unlock. Settings → Schedule is the only user:
/// the guide opened again from Settings no longer edits the schedule (owner 2026-10-22, build 10f).
/// It returns several rows, so it can sit directly in a List section or in a VStack.
struct ScheduleEditor: View {
    @Environment(AppModel.self) private var model
    /// The unsaved draft lives on the model: a language switch rebuilds Settings and a `@State` would be lost (L5).
    private var draft: Schedule? {
        get { model.scheduleDraft }
        nonmutating set { model.scheduleDraft = newValue }
    }
    @State private var confirmSchedule: Bool
    @State private var confirmUnlock = false

    init() {
        #if DEBUG
        _confirmSchedule = State(initialValue: DevArgs.list.contains("-openScheduleDialog"))   // screenshots of the first-change dialog
        #else
        _confirmSchedule = State(initialValue: false)
        #endif
    }

    /// What "Save" does with a draft: a new bedtime / wake in `open` asks first (it opens a change week).
    enum SaveStep: Equatable { case confirm, apply }
    static func saveStep(old: Schedule, draft: Schedule, state: SchedulePolicy.State) -> SaveStep {
        let timesChanged = draft.bedtime != old.bedtime || draft.wake != old.wake
        return timesChanged && state == .open ? .confirm : .apply
    }

    private var changed: Bool { draft.map { $0 != model.editableSchedule } ?? false }

    var body: some View {
        Group {
            status.id("schedule")
            ScheduleFields(schedule: Binding(get: { draft ?? model.editableSchedule }, set: { draft = $0 }),
                           timesLocked: !SchedulePolicy.allowsChange(model.scheduleState))
            if changed {
                HStack {
                    Button(L("Cancel")) { draft = nil }
                        .buttonStyle(.borderless)
                        .disabled(!changed)
                    Spacer()
                    Button(L("Save")) { if let draft { save(draft) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(!changed)
                }
            }
        }
        // An alert (not a dialog): modal, both buttons always visible, no tap outside dismisses it.
        .alert(L("Start a change week?"), isPresented: $confirmSchedule) {
            Button(L("Confirm")) {
                if let draft { model.applySchedule(draft) }
                draft = nil
            }
            // Same undo as "Cancel": drop the draft, the pickers show the stored times again.
            Button(L("Cancel"), role: .cancel) { draft = nil }
        } message: {
            let plan = model.changeWeekPlan
            Text(L("For 7 days (until \(Fmt.fullDate(plan.lastDay))) you can try different times. After that your schedule stays until \(Fmt.fullDate(plan.lockLastDay)) – changing it sooner costs 2,000 🪙."))
        }
        .confirmationDialog(L("Unlock your schedule for 2,000 🪙?"), isPresented: $confirmUnlock,
                            titleVisibility: .visible) {
            Button(L("Unlock now · 2,000 🪙")) { model.unlockSchedule() }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            let plan = model.changeWeekPlan
            Text(L("A new change week opens (until \(Fmt.fullDate(plan.lastDay))). After it your schedule stays until \(Fmt.fullDate(plan.lockLastDay))."))
        }
    }

    private func save(_ draft: Schedule) {
        switch Self.saveStep(old: model.editableSchedule, draft: draft, state: model.scheduleState) {
        case .confirm: confirmSchedule = true
        case .apply:
            model.applySchedule(draft)
            self.draft = nil
        }
    }

    /// What state the schedule is in (change week) and, while it is locked, the paid unlock.
    @ViewBuilder private var status: some View {
        stateStatus
    }

    @ViewBuilder private var stateStatus: some View {
        switch model.scheduleState {
        case .open:
            Text(L("You can change your schedule. The first change opens a change week (7 days); after it your schedule stays the same for a month."))
                .font(.footnote).foregroundStyle(.secondary)
        case .changeWeek(let lastDay):
            let changeWeek = L("🔧 Change week: \(SettingsView.daysLeft(until: lastDay, now: model.clock.now)) left (until \(Fmt.fullDate(lastDay))). Change it as often as you like.")
            Text(changeWeek)
                .font(.footnote)
                .accessibilityLabel(changeWeek.withoutLeadingSymbol)
        case .locked(let lastDay, let freeFrom):
            let locked = L("🔒 Your schedule is set until \(Fmt.fullDate(lastDay)). A free change week again from \(Fmt.fullDate(freeFrom)).")
            Text(locked)
                .font(.footnote)
                .accessibilityLabel(locked.withoutLeadingSymbol)
            let missing = max(0, SchedulePolicy.unlockPrice - model.coins)
            Button(L("Unlock now · 2,000 🪙")) { confirmUnlock = true }
                .disabled(missing > 0)
            if missing > 0 {
                Text(L("You have \(model.coins) 🪙 – \(missing) more needed."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

extension String {
    /// The text without a leading emoji / symbol and the space after it, so VoiceOver does not read "wrench" (the look is unchanged).
    var withoutLeadingSymbol: String {
        String(drop(while: { !($0.isLetter || $0.isNumber) }))
    }
}
