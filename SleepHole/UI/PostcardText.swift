import Foundation
import SleepCore

/// The words of the 30 postcards from the sleep buddy (step 11b5a): the stamp, the title and the tip of each, as
/// localized text. The order of the postcards, the source of each tip and the date they were checked live in
/// `Postcards` (SleepCore); the ids are `BoxCatalog.ids(.postcard)` and are persisted, so a postcard's content never changes
/// position. Every text is a literal `L("…")` so the i18n tool finds it; the Slovak text is in the String Catalog.
enum PostcardText {
    /// The English keys of every postcard text, exactly as they stand in the String Catalog (the Debug "Texts" screen
    /// filters by this list; a test keeps it in step with the mapping).
    static let keys: [String] = [
        "Same time, every day",
        "Going to bed and getting up at similar times, even on days off, teaches your body when it's time to sleep.",
        "Weekends, gently",
        "Try keeping weekend bedtimes within about an hour of your weeknight ones – your body clock will thank you.",
        "Seven hours or more",
        "Most adults feel their best with at least 7 hours of sleep a night. Plan your evening backwards from the morning.",
        "Make time for sleep",
        "Planning enough time for sleep helps protect your health and well-being – give it a spot in your day.",
        "Screens off for an hour",
        "Phones, tablets and computers are best put away an hour before bed – their light can make falling asleep harder.",
        "A calm bedtime routine",
        "Reading, soothing music or an audiobook, repeated each evening, tells your body that sleep is near.",
        "A warm bath",
        "A warm bath 30 minutes to 2 hours before bed can help you relax into sleep.",
        "A wind-down reminder",
        "Set a gentle reminder for 1.5 hours before bed, then start dimming the lights and slowing down.",
        "Park your worries",
        "Write your worries down, or list tomorrow's tasks, before bed. Then they can wait on the page.",
        "Try a relaxing trick",
        "Guided imagery, soft music, gentle yoga or meditation can help you let go of the day's stress.",
        "Late coffee lingers",
        "Caffeine can stay with you for up to 8 hours, so an afternoon coffee may still be awake at bedtime.",
        "Heavy talks by daylight",
        "Upsetting conversations are best kept for the daytime, so your evening stays calm.",
        "A warm evening drink",
        "Swap evening coffee or black tea for a warm milky drink or a herbal tea.",
        "A comfy bed",
        "A comfortable mattress and pillow make your bedroom a nicer place to sleep.",
        "Sweet things in moderation",
        "Sugary drinks and snacks can make it harder to fall or stay asleep – go easy on them.",
        "A light dinner",
        "Make dinner your lightest meal and finish eating 3 to 4 hours before bed.",
        "Drink earlier",
        "Try limiting liquids in the last few hours before sleep, and drink your fill earlier in the day.",
        "A cool bedroom",
        "A cool room is cosy for sleeping – aim for around 18–20 °C (65–68 °F).",
        "Make it dark",
        "Blackout curtains or an eye mask keep the light off your eyes while you sleep.",
        "Quiet or softly noisy",
        "Soft earplugs help with noise, and gentle sounds like rain can make the room cosy.",
        "Phone face down",
        "Turn your phone face down, so its glow doesn't reach you at night.",
        "Bed is for sleep",
        "Try using your bed just for sleep – no eating or working in it – so it says “sleep” to your brain.",
        "The 20-minute rule",
        "Still awake after about 20 minutes? Get up and do something calm, like reading a book, then come back when sleep returns.",
        "Turn the clock away",
        "Turn clocks away from the bed – not seeing the minutes tick by is one less thing to think about.",
        "Every bit of movement",
        "Even a little regular activity can help your sleep, and you can build it up gradually.",
        "Exercise earlier",
        "Try to finish exercising at least 3 hours before your planned bedtime.",
        "Catch some daylight",
        "About 30 minutes outside early in the day helps – even a cloudy sky beats dim indoor light.",
        "Sleep helps you learn",
        "While you sleep, your brain stores memories – good sleep helps learning and clear thinking.",
        "Naps before 3 p.m.",
        "Try to finish any nap before 3 p.m., so the evening can get properly sleepy.",
        "Keep the light low",
        "If you get up in the night, keep the lights low – a dim night light is fine.",
        "Postcard %lld of %lld",
        "– your sleep buddy 🐾",
        "Source: %@",
        "Postcard from your buddy",
        "Open the source",
    ]

    private static let stamps = ["⏰", "🛋️", "🌙", "🗓️", "📵", "📖", "🛁", "🔔", "📝", "🧘", "☕️", "💬", "🍵", "🛏️", "🍪", "🍽️", "💧", "❄️", "🌑", "🌧️", "📴", "🛌", "🚶", "🕰️", "🏃", "⏳", "☀️", "🧠", "🕒", "🕯️"]

    /// The 1-based number in `postcard-07` → 7; nil for anything else.
    static func number(of id: String) -> Int? {
        guard id.hasPrefix("postcard-"), let n = Int(id.dropFirst("postcard-".count)), (1...stamps.count).contains(n) else { return nil }
        return n
    }

    /// The emoji "stamp" in the corner of the postcard.
    static func stamp(for id: String) -> String { number(of: id).map { stamps[$0 - 1] } ?? "💌" }

    static func title(for id: String) -> String {
        switch number(of: id) {
        case 1: L("Same time, every day")
        case 2: L("Weekends, gently")
        case 3: L("Seven hours or more")
        case 4: L("Make time for sleep")
        case 5: L("Screens off for an hour")
        case 6: L("A calm bedtime routine")
        case 7: L("A warm bath")
        case 8: L("A wind-down reminder")
        case 9: L("Park your worries")
        case 10: L("Try a relaxing trick")
        case 11: L("Late coffee lingers")
        case 12: L("Heavy talks by daylight")
        case 13: L("A warm evening drink")
        case 14: L("A comfy bed")
        case 15: L("Sweet things in moderation")
        case 16: L("A light dinner")
        case 17: L("Drink earlier")
        case 18: L("A cool bedroom")
        case 19: L("Make it dark")
        case 20: L("Quiet or softly noisy")
        case 21: L("Phone face down")
        case 22: L("Bed is for sleep")
        case 23: L("The 20-minute rule")
        case 24: L("Turn the clock away")
        case 25: L("Every bit of movement")
        case 26: L("Exercise earlier")
        case 27: L("Catch some daylight")
        case 28: L("Sleep helps you learn")
        case 29: L("Naps before 3 p.m.")
        case 30: L("Keep the light low")
        default: ""
        }
    }

    static func tip(for id: String) -> String {
        switch number(of: id) {
        case 1: L("Going to bed and getting up at similar times, even on days off, teaches your body when it's time to sleep.")
        case 2: L("Try keeping weekend bedtimes within about an hour of your weeknight ones – your body clock will thank you.")
        case 3: L("Most adults feel their best with at least 7 hours of sleep a night. Plan your evening backwards from the morning.")
        case 4: L("Planning enough time for sleep helps protect your health and well-being – give it a spot in your day.")
        case 5: L("Phones, tablets and computers are best put away an hour before bed – their light can make falling asleep harder.")
        case 6: L("Reading, soothing music or an audiobook, repeated each evening, tells your body that sleep is near.")
        case 7: L("A warm bath 30 minutes to 2 hours before bed can help you relax into sleep.")
        case 8: L("Set a gentle reminder for 1.5 hours before bed, then start dimming the lights and slowing down.")
        case 9: L("Write your worries down, or list tomorrow's tasks, before bed. Then they can wait on the page.")
        case 10: L("Guided imagery, soft music, gentle yoga or meditation can help you let go of the day's stress.")
        case 11: L("Caffeine can stay with you for up to 8 hours, so an afternoon coffee may still be awake at bedtime.")
        case 12: L("Upsetting conversations are best kept for the daytime, so your evening stays calm.")
        case 13: L("Swap evening coffee or black tea for a warm milky drink or a herbal tea.")
        case 14: L("A comfortable mattress and pillow make your bedroom a nicer place to sleep.")
        case 15: L("Sugary drinks and snacks can make it harder to fall or stay asleep – go easy on them.")
        case 16: L("Make dinner your lightest meal and finish eating 3 to 4 hours before bed.")
        case 17: L("Try limiting liquids in the last few hours before sleep, and drink your fill earlier in the day.")
        case 18: L("A cool room is cosy for sleeping – aim for around 18–20 °C (65–68 °F).")
        case 19: L("Blackout curtains or an eye mask keep the light off your eyes while you sleep.")
        case 20: L("Soft earplugs help with noise, and gentle sounds like rain can make the room cosy.")
        case 21: L("Turn your phone face down, so its glow doesn't reach you at night.")
        case 22: L("Try using your bed just for sleep – no eating or working in it – so it says “sleep” to your brain.")
        case 23: L("Still awake after about 20 minutes? Get up and do something calm, like reading a book, then come back when sleep returns.")
        case 24: L("Turn clocks away from the bed – not seeing the minutes tick by is one less thing to think about.")
        case 25: L("Even a little regular activity can help your sleep, and you can build it up gradually.")
        case 26: L("Try to finish exercising at least 3 hours before your planned bedtime.")
        case 27: L("About 30 minutes outside early in the day helps – even a cloudy sky beats dim indoor light.")
        case 28: L("While you sleep, your brain stores memories – good sleep helps learning and clear thinking.")
        case 29: L("Try to finish any nap before 3 p.m., so the evening can get properly sleepy.")
        case 30: L("If you get up in the night, keep the lights low – a dim night light is fine.")
        default: ""
        }
    }

    static func numberLine(_ n: Int, of total: Int) -> String { L("Postcard \(n) of \(total)") }
    static var signature: String { L("– your sleep buddy 🐾") }
    static func sourceLine(_ name: String) -> String { L("Source: \(name)") }
    static var header: String { L("Postcard from your buddy") }
    static var openSource: String { L("Open the source") }
}
