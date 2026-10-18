import SwiftUI
import SleepCore

/// The schedule editor under the change-week rules (owner 2026-10-15): the status line, bedtime / wake / reminder on a
/// draft, Cancel / Save, the "Start a change week?" alert and the paid unlock. ONE place for the rules – Settings and the
/// guide opened again from Settings both use it (owner 2026-10-18: the guide must be able to set the times).
/// It returns several rows, so it can sit directly in a List section or in a VStack.
struct ScheduleEditor: View {
    @Environment(AppModel.self) private var model
    /// The guide: short status texts and a Cancel / Save row that is always there (disabled until something changed),
    /// so the page height stays the same.
    var compact = false
    @State private var draft: Schedule?
    @State private var confirmSchedule: Bool
    @State private var confirmUnlock = false

    init(compact: Bool = false) {
        self.compact = compact
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

    /// The compact (guide) status line: a pending change wins over the state text, because it says when the new times
    /// really start. false = show the state text.
    static func showsPendingNote(state: SchedulePolicy.State, pending: Bool, compact: Bool) -> Bool {
        compact && pending
    }

    private var changed: Bool { draft.map { $0 != model.editableSchedule } ?? false }

    var body: some View {
        Group {
            status.id("schedule")
            ScheduleFields(schedule: Binding(get: { draft ?? model.editableSchedule }, set: { draft = $0 }),
                           timesLocked: !SchedulePolicy.allowsChange(model.scheduleState))
            if changed || compact {
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
        if Self.showsPendingNote(state: model.scheduleState, pending: model.settings.pendingSchedule != nil,
                                 compact: compact) {
            Text(L("The new times apply from tomorrow – tonight's building can already start.")).font(.footnote).lineLimit(2, reservesSpace: true)
        } else { stateStatus }
    }

    @ViewBuilder private var stateStatus: some View {
        switch model.scheduleState {
        case .open:
            if compact {
                Text(L("Your first change opens a 7-day change week."))
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
            } else {
                Text(L("You can change your schedule. The first change opens a change week (7 days); after it your schedule stays the same for a month."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case .changeWeek(let lastDay):
            if compact {
                Text(L("🔧 Change week: \(SettingsView.daysLeft(until: lastDay, now: model.clock.now)) left. Change freely."))
                    .font(.footnote).lineLimit(2, reservesSpace: true)
            } else {
                Text(L("🔧 Change week: \(SettingsView.daysLeft(until: lastDay, now: model.clock.now)) left (until \(Fmt.fullDate(lastDay))). Change it as often as you like."))
                    .font(.footnote)
            }
        case .locked(let lastDay, let freeFrom):
            if compact {
                Text(L("🔒 Set until \(Fmt.fullDate(lastDay)). Free change from \(Fmt.fullDate(freeFrom))."))
                    .font(.footnote).lineLimit(2, reservesSpace: true)
            } else {
                Text(L("🔒 Your schedule is set until \(Fmt.fullDate(lastDay)). A free change week again from \(Fmt.fullDate(freeFrom))."))
                    .font(.footnote)
            }
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
