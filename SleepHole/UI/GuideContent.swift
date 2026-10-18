import SleepCore
import SwiftUI

/// Thousands separator by the UI language ("2,000" / "2 000") for prices inside guide sentences.
enum Num {
    static func group(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Lang.current.locale
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

/// The texts of the first-run guide (nine pages the sleep buddy narrates) and of the list "How SleepHole works".
/// Every number is produced from the code constant that rules the app, so the guide never lies (owner 2026-10-18);
/// `GuideTests` guards that. Titles and the buddy's sentences were approved by the owner (`docs/guide-texts-draft.json`).
enum GuideText {
    static let rules = SleepRules()
    static let pageCount = 9

    struct Page: Equatable {
        let art: String
        /// The sleep buddy's asset (`buddy-cat-…`).
        let cat: String
        let title: String
        let text: String
    }

    static func m(_ t: TimeInterval) -> String { Plural.minutes(t) }
    static func s(_ t: TimeInterval) -> String { L("\(Int(t.rounded()))s") }
    static func coins(_ n: Int) -> String { Num.group(n) }
    static var lockWindow: TimeInterval { TimeInterval(LifecycleMonitor.lockScreenWindow.components.seconds) }

    /// `setupMinutes`: the user's current "Setup time" setting (page 4).
    static func page(_ i: Int, setup: TimeInterval) -> Page {
        switch i {
        case 0:
            return Page(art: "🏗️🌙🏘️", cat: "buddy-cat-happy", title: L("Every night builds something"),
                        text: L("Hi, I'm your cat! In the evening we start a building, at night your phone rests, and in the morning it's finished."))
        case 1:
            return Page(art: "🛏️⏰", cat: "buddy-cat-awake", title: L("Your schedule"),
                        text: L("Pick your bedtime and wake-up. The first \(Plural.days(SchedulePolicy.weekDays)) are a change week – try as much as you like. Then it stays for a month."))
        case 2:
            return Page(art: "👆🌙", cat: "buddy-cat-awake", title: L("Start tonight's building"),
                        text: L("Tap “Go to sleep” from \(m(NightWindow.startLead)) before bedtime until \(m(rules.startDeadline)) after it. Tired sooner? You can start up to \(Plural.hours(NightWindow.earlyStartLead)) early."))
        case 3:
            return Page(art: "🎧📖", cat: "buddy-cat-wink", title: L("A moment to get ready"),
                        text: L("After the start there's time for a podcast or story, until bedtime + \(m(setup)). In another app? I'll call you \(s(SetupReminder.lead)) before the end."))
        case 4:
            return Page(art: "📱🔒", cat: "buddy-cat-awake", title: L("At night I guard the building"),
                        text: L("Keep SleepHole open and lock your phone. If you leave, you have \(s(rules.accidentalTolerance)) to come back. Phone calls don't count."))
        case 5:
            return Page(art: "🌙⏸️", cat: "buddy-cat-awake", title: L("When you need a moment"),
                        text: L("Want to read a message? Tap 🌙 Pause – \(m(PausePolicy.duration)) outside the app, the first one each night is free."))
        case 6:
            return Page(art: "⏰📳", cat: "buddy-cat-happy", title: L("Morning"),
                        text: L("Shake your phone or enter your code – from \(m(NightWindow.earlyConfirm)) before the alarm. Within \(m(NightWindow.onTimeConfirm)) after it, the building is done!"))
        case 7:
            return Page(art: "🪙🏙️", cat: "buddy-cat-happy", title: L("Rewards"),
                        text: L("A finished night pays \(coins(Economy.completeReward(level: 1)))–\(coins(Economy.completeReward(level: 4))) 🪙, +\(PausePolicy.undisturbedBonus) without a pause, +\(Economy.calmHourBonus) for every calm hour. Your town gets residents and taller buildings."))
        default:
            return Page(art: "🛡️🔌", cat: "buddy-cat-wink", title: L("When a night goes wrong"),
                        text: L("No worries – a joker protects your streak and the next good night repairs a ruin. Keep your phone on the charger overnight."))
        }
    }

    /// What each level unlocks (the level-up card).
    static var levelUnlocks: [String] {
        [L("houses and apartment blocks"), L("parks, lit streets, museums, libraries"),
         L("town hall, school, fire station, police, hospital"), L("skyscrapers")]
    }

    struct RuleGroup: Equatable {
        let title: String
        let items: [String]
    }

    /// "How SleepHole works": the nine groups of the owner's list plus "Tips" (the old tips page).
    static var ruleGroups: [RuleGroup] {
        let o = AppSettings.setupMinuteOptions
        let t = Progression.thresholds
        let sil = JokerTier.silver, gold = JokerTier.gold
        let nap = NapPlan.default
        return [
            RuleGroup(title: L("Schedule"), items: [
                L("Bedtime and wake-up are the same every day."),
                L("Your first change opens a change week (\(Plural.days(SchedulePolicy.weekDays))). Then the schedule stays for a month; unlocking it sooner costs \(coins(SchedulePolicy.unlockPrice)) 🪙."),
                L("A change saved in the evening, once tonight's building can start, applies from tomorrow."),
                L("The reminder, the nap window, sounds and the code can change any time."),
            ]),
            RuleGroup(title: L("Evening"), items: [
                L("“Go to sleep” works from \(m(NightWindow.startLead)) before bedtime until \(m(rules.startDeadline)) after it."),
                L("An early start works up to \(Plural.hours(NightWindow.earlyStartLead)) before bedtime: the night counts in full and the alarm rings as always."),
                L("The setup lasts until bedtime + your setup time (\(o[0]), \(o[1]) or \(o[2]) minutes in Settings), or \(m(rules.earlySetup)) from an early start."),
                L("If you're in another app during the setup, a notice comes \(s(SetupReminder.lead)) before it ends."),
            ]),
            RuleGroup(title: L("Night"), items: [
                L("SleepHole stays open; you can turn the screen off and lock the phone."),
                L("If you leave the app, a warning comes within seconds and you have \(s(rules.accidentalTolerance)) to come back. All trips together may last \(s(rules.awayBudget ?? 0)) a night."),
                L("Closing the app (swiping it away) counts as leaving."),
                L("On iOS 26, pulling down Notification Center counts as leaving the app – use 🌙 Pause to read a message."),
                L("A phone call doesn't count – come back to the app after it."),
                L("If you unlock the phone and use it outside the app for more than \(s(lockWindow)), we'll remind you gently."),
                L("Strict mode (Settings, off by default): a system-alarm warning, and using the phone brings the building down."),
                L("Without a passcode the phone can't tell locking from leaving, so trips aren't counted there (closing the app still is)."),
            ]),
            RuleGroup(title: L("Pause"), items: [
                L("🌙 Pause: \(m(PausePolicy.duration)) outside the app. The first of a night is free, then \(coins(PausePolicy.price(number: 2))), \(coins(PausePolicy.price(number: 3))), \(coins(PausePolicy.price(number: 4))) 🪙."),
                L("A pause can start only if it ends before the morning confirmation opens."),
                L("A night without a pause: +\(PausePolicy.undisturbedBonus) 🪙."),
            ]),
            RuleGroup(title: L("Morning"), items: [
                L("The alarm rings for \(m(rules.alarmDuration)), also in silent mode; if you allow the system alarm, it rings as a backup."),
                L("Confirm you're up by shaking the phone or entering the code, from \(m(NightWindow.earlyConfirm)) before the alarm."),
                L("Within \(m(NightWindow.onTimeConfirm)) after the alarm: a finished building. Within \(m(NightWindow.lateConfirm)): unfinished. Later: ruins."),
                L("Your next finished night repairs a ruin."),
            ]),
            RuleGroup(title: L("Coins and town"), items: [
                L("A finished night: \(coins(Economy.completeReward(level: 1))) 🪙 (level 1), \(coins(Economy.completeReward(level: 2))) (2), \(coins(Economy.completeReward(level: 3))) (3), \(coins(Economy.completeReward(level: 4))) (4). Unfinished: half."),
                L("No pause +\(PausePolicy.undisturbedBonus), every calm hour +\(Economy.calmHourBonus), every \(Economy.streakBonusEvery)th finished night in a row +\(Economy.streakBonus)."),
                L("A calm hour: a whole hour between the end of the setup and the alarm with no trip out of the app, no phone use and no pause."),
                L("Levels: nights 1–\(t[1].minBuilt) level 1, \(t[1].minBuilt + 1)–\(t[2].minBuilt) up to level 2, \(t[2].minBuilt + 1)–\(t[3].minBuilt) up to level 3, from night \(t[3].minBuilt + 1) up to level 4."),
                L("Every building has residents and the town grows with them."),
                L("Renaming the town: the first name is free, a typo fix within \(m(RenamePolicy.typoWindow)), once a year free, otherwise \(coins(RenamePolicy.price)) 🪙."),
            ]),
            RuleGroup(title: L("Jokers"), items: [
                L("Bronze: \(Plural.nights(JokerTier.bronze.nights)), free once a month; it is also used by itself on the first missed night."),
                L("Silver: \(Plural.nights(sil.nights)) for \(coins(sil.price)) 🪙. Gold: \(Plural.nights(gold.nights)) for \(coins(gold.price)) 🪙. Each kind once a month."),
                L("A protected night neither breaks nor extends your streak; it gives no building and no coins."),
            ]),
            RuleGroup(title: L("Nap"), items: [
                L("\(NapPlan.allowedMinutes[0]) or \(NapPlan.allowedMinutes[1]) minutes, between \(Fmt.time(nap.windowStart)) and \(Fmt.time(nap.windowEnd)) (changeable), once a day. Complete +\(NapPlan.reward(.complete)) 🪙, cut short +\(NapPlan.reward(.unfinished)) 🪙. It builds nothing."),
            ]),
            RuleGroup(title: L("Privacy"), items: [
                L("We collect nothing about you. Only the chosen city's location goes to the weather service."),
                L("The app only reads Apple Health. iCloud carries your town only between your own devices."),
            ]),
            RuleGroup(title: L("Tips"), items: tips),
        ]
    }

    /// The rows of the old tips page that the nine pages no longer show.
    static var tips: [String] {
        var t = [
            L("Keep a passcode with Face ID or Touch ID on your iPhone – without them the app can't tell locking the phone from leaving the app."),
            L("Keep your phone on the charger overnight."),
            L("The SleepHole alarm also rings in Do Not Disturb or Sleep focus, and the “SleepHole must stay open” warning arrives there too. If iOS asks about time-sensitive notifications from SleepHole, keep them allowed."),
            L("The alarm rings even in silent mode. Pick the sound in Settings."),
            L("iOS may install an update at night and restart your phone. The building is safe (it counts in your favour), but the in-app alarm can't ring then – the system alarm (if you allowed it) and the backup notifications ring instead. For calmer nights: Settings → General → Software Update → Automatic Updates → turn off installing."),
        ]
        if AppExpiry.date != nil {   // only builds installed from Xcode carry a profile; TestFlight / App Store have none
            t.append(L("SleepHole's signature runs out after a while – then connect your iPhone to the Mac and install SleepHole again. Your data stays."))
        }
        return t
    }
}

/// "How SleepHole works": every rule in one read-only list (opened from the guide's last page and from Settings).
struct RulesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(GuideText.ruleGroups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.items, id: \.self) { Text($0).fixedSize(horizontal: false, vertical: true) }
                    }
                }
            }
            .navigationTitle(L("How SleepHole works"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Close")) { dismiss() } } }
        }
    }
}
