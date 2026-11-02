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
        "A calm ritual each evening – like soothing music – tells your body that sleep is near.",
        "A warm bath",
        "A warm bath 1 to 2 hours before bed can help you relax into sleep.",
        "A wind-down reminder",
        "Set a gentle reminder for 1.5 hours before bed, then start dimming the lights and slowing down.",
        "Park your worries",
        "Write your worries down, or list tomorrow's tasks, before bed. Then they can wait on the page.",
        "Try a relaxing trick",
        "Guided imagery, soft music, gentle yoga or meditation can help you let go of the day's stress.",
        "Late coffee lingers",
        "Caffeine can stay with you for 8 hours or more, so an afternoon coffee may still be awake at bedtime.",
        "Heavy talks by daylight",
        "Upsetting conversations are best kept for the daytime, so your evening stays calm.",
        "A warm evening drink",
        "Swap evening coffee or black tea for a warm milky drink or a herbal tea.",
        "A comfy bed",
        "A comfortable mattress and pillow make your bedroom a nicer place to sleep.",
        "Sweet things in moderation",
        "Lots of sugary drinks and snacks may make sleep lighter and more restless – go easy on them.",
        "Dinner, a bit earlier",
        "Try to finish dinner a few hours before bed rather than right before lights out – your night may be calmer.",
        "Drink earlier",
        "Try limiting liquids in the last few hours before sleep, and drink your fill earlier in the day.",
        "A cool bedroom",
        "A cool room is cosy for sleeping – very warm bedrooms tend to go with less restful nights.",
        "Make it dark",
        "Blackout curtains or an eye mask keep the light off your eyes while you sleep.",
        "Quiet or softly noisy",
        "Soft earplugs can dull noise, and some people like gentle sounds such as rain – see what suits you.",
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
        "Why it helps",
        "The study",
        "How strong is the evidence",
        "%@ et al., %@, %@",
        "%@ and %@, %@, %@",
        "Open the study on PubMed",
        "Your body clock loves a rhythm. When bedtime and wake-up time stay similar, it learns when to make you sleepy and when to wake you up. Irregular days blur that signal.",
        "In a 2017 study, 61 university students kept sleep diaries for 30 days. Irregular sleep went along with a later body clock and lower academic performance.",
        "Only 61 students, and it shows a link, not a cause – regularity may go along with other habits.",
        "Sleeping in much later on days off can nudge your body clock later, like a tiny jet lag. A gentler lie-in keeps the clock steadier, so Monday morning feels easier.",
        "In a 2010 study, teenagers who followed a typical weekend schedule (bed 1.5 hours later, up 3 hours later) had their body clock shift about 45 min later over the weekend.",
        "Only 12 and 33 teenagers, so adults may differ. Even waking just 1 hour later plus a nap shifted the clock – an hour is a gentle aim, not a proven limit.",
        "Sleep does a lot of quiet work: it sorts memories, steadies your mood and helps your body recover. Most adults need around 7 hours or more for that, so planning backwards from the morning gives it room.",
        "In 2015, two large US sleep societies reviewed the evidence and agreed that adults should regularly sleep 7 hours or more a night for the best health.",
        "This is an expert consensus, not a single experiment, and a general guide for ages 18 to 60 – how much sleep each person needs varies.",
        "When sleep is cut short night after night, the lost rest piles up like a debt – and your own feeling of tiredness reports it poorly. A fixed slot for sleep in your day keeps that debt from growing.",
        "In a 2003 lab experiment with healthy adults, 14 nights of 6 hours or less in bed slowly dulled their mental performance, and they were largely unaware of the decline.",
        "A carefully controlled lab experiment, but small: 48 healthy adults aged 21 to 38 in all. It shows what can happen, not what happens to everyone.",
        "Light from screens is rich in blue, which tells your brain that it is still daytime. It holds back the body's own sleep hormone and shifts your body clock later, so sleep arrives later.",
        "In a 2015 lab study, 12 young adults read on a glowing e-reader for five evenings and from printed books for another five. With the e-reader they took nearly 10 min longer to fall asleep and were less alert next morning.",
        "Only 12 young adults, and a bright e-reader for about 4 hours each evening, so it does not show what one hour on a phone does.",
        "A repeated, soothing ritual becomes a cue: your mind learns that these gentle minutes mean sleep is near. Calm music also helps you let go of the day.",
        "In a 2008 trial, 94 students with sleep complaints listened to 45 min of relaxing classical music at bedtime for 3 weeks. Their sleep quality improved; for those who heard an audiobook, or nothing, it did not significantly improve.",
        "One trial of 94 students who already slept poorly. Music helped, the audiobook did not, and reading was not tested.",
        "A warm bath draws blood to your hands and feet. When you step out, your body gives off heat faster and your core temperature drops – the same dip that comes with falling asleep.",
        "A 2019 review of 17 studies found that a warm bath or shower (40 to 42.5 °C) went with better self-rated sleep quality, and taken 1 to 2 hours before bed, even 10 min helped people fall asleep sooner.",
        "Only 13 of the 17 studies had data to combine, and the authors say more research is needed, especially on the best timing and duration.",
        "Even ordinary room light tells your brain that it is still day and holds back the body's own sleep hormone. Dimmer lights in the evening let it rise on time.",
        "In a 2011 study, 116 healthy volunteers aged 18 to 30 were compared after evenings in room light or in dim light. Room light before bedtime delayed the sleep hormone's rise in nearly everyone and shortened it by about 90 min.",
        "It measured the sleep hormone, not sleep itself, in healthy 18 to 30 year olds, and the lighting lasted 8 to 16 hours – far longer than an evening wind-down.",
        "Unfinished tasks keep circling in your head at night. Putting them on paper hands the job to the page, so your mind can stop rehearsing them – and falling asleep tends to go faster.",
        "In a 2018 sleep-lab study, 57 healthy young adults wrote for 5 min before bed, either a to-do list or a list of things already done. The to-do group fell asleep significantly faster, especially with a specific list.",
        "One lab study of 57 healthy 18 to 30 year olds, with a few minutes of writing before one night's sleep. It tested to-do lists, not worry journals.",
        "Slow, calm practices ease the body's stress response – breathing slows, muscles soften and thoughts stop racing. That makes it easier to let go of the day when you lie down.",
        "A 2019 review of 18 randomized trials in people with sleep problems found that mindfulness meditation improved sleep quality compared with groups given the same time and attention, but not more than established sleep programmes.",
        "Moderate at best: it beat attention-matched groups, not established sleep programmes, and the authors call it preliminary. Music, imagery and yoga were not part of it.",
        "Caffeine blocks the signal that builds up through the day and tells you it is time to rest. It fades slowly, so an afternoon cup can still be working when you lie down.",
        "Heavy talks can leave your mind buzzing and your body on alert, and alert is the opposite of sleepy. Saving them for daylight lets your evening wind down.",
        "Caffeine keeps your brain alert for hours, even after you stop feeling it. A warm, caffeine-free drink gives you the cosy ritual of an evening cup without the buzz.",
        "When the bed supports you well, you spend less time shifting around for a comfy spot, so it is easier to drift off and to stay asleep.",
        "Food is not only fuel for the day – what you eat can also shape how deeply you sleep. A little sugar is fine; it is the everyday habit of a lot that is worth watching.",
        "Digesting a meal keeps your body busy. Finishing dinner a few hours earlier gives it time to settle before you lie down.",
        "Your body cools down a little as you fall asleep. A cool room helps that along, while a warm one can get in the way and wake you more often.",
        "Light tells your brain it is daytime and holds back your body's own sleep hormone. Keeping your eyes in the dark lets that hormone do its work through the night.",
        "Steady, soft sounds can cover sudden noises, which is why some people like rain or a fan. But a quiet room is the safest start, because noise can also get in the way of good sleep.",
        "A 2023 review of 24 studies found that caffeine cut sleep by about 45 min. To avoid that loss, it estimated that a regular cup of coffee should be drunk at least 8.8 hours before bed.",
        "In a 2024 study, 74 university students wore a wrist monitor for 14 nights. On nights after an unpleasant conversation before bed, they slept about 14 min less than on other nights.",
        "In a 2013 trial, 12 healthy adults took 400 mg of caffeine (about four cups of coffee) right at bedtime, or 3 or 6 hours before. Each time, a headband monitor showed over an hour less sleep than with a placebo.",
        "A 2015 review of 24 controlled trials concluded that a medium-firm mattress, especially one you can adjust yourself, is best for sleep comfort and sleep quality.",
        "In a 2016 sleep-lab study, 26 adults of normal weight chose their own food for one day. Getting more of their energy from sugar went with more brief wake-ups (arousals) that night.",
        "In a 2026 trial, 13 healthy young women ate the same dinner either 5 hours or 1 hour before bed for 4 days. After the late dinners, they slept less and were awake more during the night.",
        "In a 2023 study, 62 adults wore a wrist monitor at home for 14 nights while their bedrooms were measured. In the warmest fifth of readings, sleep efficiency (time in bed spent asleep) was about 3 percent lower than in the coolest.",
        "In a 2010 sleep-lab study, 14 healthy volunteers slept with recorded hospital noise and the light on, with and without an eye mask and earplugs. With them, they had more REM sleep and fewer brief wake-ups.",
        "A 2021 review of 38 studies on steady background noise, like white noise, as a sleep aid found mixed results, from helping sleep to disturbing it. The authors rated the evidence that it improves sleep as very low quality.",
        "It pools 24 studies, so it is broader than one trial. The 8.8 hours is an estimate for a regular cup of coffee (250 mL), not an exact limit for everyone.",
        "A link, not a cause: 74 students, sleep judged by a wrist monitor, habits reported by themselves. Many other habits in the study showed no link at all.",
        "Only 12 adults, a high dose, and a company grant paid for it. Warm milk and herbal tea were not tested – the sure gain is skipping the caffeine.",
        "The trials were rated moderate to high quality, but findings on the ideal mattress still differ, and pillows were not studied.",
        "Only 26 adults and one day of self-chosen food, so a link, not a cause. Other studies are mixed – some found carb-rich meals made people sleepier.",
        "Only 13 young women, and only 1 hour vs 5 hours was tested. Another lab study with 20 adults found no clear harm from a late dinner, so the evidence is mixed.",
        "A link, not a cause: 62 adults, and the study names no best temperature. Most rated their room “just right” whatever it measured, so people may not notice the difference.",
        "Only 14 people, a mask and earplugs tested together, in a noisy room with the light on. It does not prove a mask alone helps at home.",
        "Very low quality evidence and mixed results, so soft sounds are a matter of taste, not proven benefit. The review did not look at earplugs.",
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
        case 16: L("Dinner, a bit earlier")
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
        case 6: L("A calm ritual each evening – like soothing music – tells your body that sleep is near.")
        case 7: L("A warm bath 1 to 2 hours before bed can help you relax into sleep.")
        case 8: L("Set a gentle reminder for 1.5 hours before bed, then start dimming the lights and slowing down.")
        case 9: L("Write your worries down, or list tomorrow's tasks, before bed. Then they can wait on the page.")
        case 10: L("Guided imagery, soft music, gentle yoga or meditation can help you let go of the day's stress.")
        case 11: L("Caffeine can stay with you for 8 hours or more, so an afternoon coffee may still be awake at bedtime.")
        case 12: L("Upsetting conversations are best kept for the daytime, so your evening stays calm.")
        case 13: L("Swap evening coffee or black tea for a warm milky drink or a herbal tea.")
        case 14: L("A comfortable mattress and pillow make your bedroom a nicer place to sleep.")
        case 15: L("Lots of sugary drinks and snacks may make sleep lighter and more restless – go easy on them.")
        case 16: L("Try to finish dinner a few hours before bed rather than right before lights out – your night may be calmer.")
        case 17: L("Try limiting liquids in the last few hours before sleep, and drink your fill earlier in the day.")
        case 18: L("A cool room is cosy for sleeping – very warm bedrooms tend to go with less restful nights.")
        case 19: L("Blackout curtains or an eye mask keep the light off your eyes while you sleep.")
        case 20: L("Soft earplugs can dull noise, and some people like gentle sounds such as rain – see what suits you.")
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

    /// The study part of a postcard (step 13c): why it helps, what ONE study found, how strong the evidence is. nil = none yet.
    static func why(for id: String) -> String? {
        switch number(of: id) {
        case 1: L("Your body clock loves a rhythm. When bedtime and wake-up time stay similar, it learns when to make you sleepy and when to wake you up. Irregular days blur that signal.")
        case 2: L("Sleeping in much later on days off can nudge your body clock later, like a tiny jet lag. A gentler lie-in keeps the clock steadier, so Monday morning feels easier.")
        case 3: L("Sleep does a lot of quiet work: it sorts memories, steadies your mood and helps your body recover. Most adults need around 7 hours or more for that, so planning backwards from the morning gives it room.")
        case 4: L("When sleep is cut short night after night, the lost rest piles up like a debt – and your own feeling of tiredness reports it poorly. A fixed slot for sleep in your day keeps that debt from growing.")
        case 5: L("Light from screens is rich in blue, which tells your brain that it is still daytime. It holds back the body's own sleep hormone and shifts your body clock later, so sleep arrives later.")
        case 6: L("A repeated, soothing ritual becomes a cue: your mind learns that these gentle minutes mean sleep is near. Calm music also helps you let go of the day.")
        case 7: L("A warm bath draws blood to your hands and feet. When you step out, your body gives off heat faster and your core temperature drops – the same dip that comes with falling asleep.")
        case 8: L("Even ordinary room light tells your brain that it is still day and holds back the body's own sleep hormone. Dimmer lights in the evening let it rise on time.")
        case 9: L("Unfinished tasks keep circling in your head at night. Putting them on paper hands the job to the page, so your mind can stop rehearsing them – and falling asleep tends to go faster.")
        case 10: L("Slow, calm practices ease the body's stress response – breathing slows, muscles soften and thoughts stop racing. That makes it easier to let go of the day when you lie down.")
        case 11: L("Caffeine blocks the signal that builds up through the day and tells you it is time to rest. It fades slowly, so an afternoon cup can still be working when you lie down.")
        case 12: L("Heavy talks can leave your mind buzzing and your body on alert, and alert is the opposite of sleepy. Saving them for daylight lets your evening wind down.")
        case 13: L("Caffeine keeps your brain alert for hours, even after you stop feeling it. A warm, caffeine-free drink gives you the cosy ritual of an evening cup without the buzz.")
        case 14: L("When the bed supports you well, you spend less time shifting around for a comfy spot, so it is easier to drift off and to stay asleep.")
        case 15: L("Food is not only fuel for the day – what you eat can also shape how deeply you sleep. A little sugar is fine; it is the everyday habit of a lot that is worth watching.")
        case 16: L("Digesting a meal keeps your body busy. Finishing dinner a few hours earlier gives it time to settle before you lie down.")
        case 18: L("Your body cools down a little as you fall asleep. A cool room helps that along, while a warm one can get in the way and wake you more often.")
        case 19: L("Light tells your brain it is daytime and holds back your body's own sleep hormone. Keeping your eyes in the dark lets that hormone do its work through the night.")
        case 20: L("Steady, soft sounds can cover sudden noises, which is why some people like rain or a fan. But a quiet room is the safest start, because noise can also get in the way of good sleep.")
        default: nil
        }
    }

    static func finding(for id: String) -> String? {
        switch number(of: id) {
        case 1: L("In a 2017 study, 61 university students kept sleep diaries for 30 days. Irregular sleep went along with a later body clock and lower academic performance.")
        case 2: L("In a 2010 study, teenagers who followed a typical weekend schedule (bed 1.5 hours later, up 3 hours later) had their body clock shift about 45 min later over the weekend.")
        case 3: L("In 2015, two large US sleep societies reviewed the evidence and agreed that adults should regularly sleep 7 hours or more a night for the best health.")
        case 4: L("In a 2003 lab experiment with healthy adults, 14 nights of 6 hours or less in bed slowly dulled their mental performance, and they were largely unaware of the decline.")
        case 5: L("In a 2015 lab study, 12 young adults read on a glowing e-reader for five evenings and from printed books for another five. With the e-reader they took nearly 10 min longer to fall asleep and were less alert next morning.")
        case 6: L("In a 2008 trial, 94 students with sleep complaints listened to 45 min of relaxing classical music at bedtime for 3 weeks. Their sleep quality improved; for those who heard an audiobook, or nothing, it did not significantly improve.")
        case 7: L("A 2019 review of 17 studies found that a warm bath or shower (40 to 42.5 °C) went with better self-rated sleep quality, and taken 1 to 2 hours before bed, even 10 min helped people fall asleep sooner.")
        case 8: L("In a 2011 study, 116 healthy volunteers aged 18 to 30 were compared after evenings in room light or in dim light. Room light before bedtime delayed the sleep hormone's rise in nearly everyone and shortened it by about 90 min.")
        case 9: L("In a 2018 sleep-lab study, 57 healthy young adults wrote for 5 min before bed, either a to-do list or a list of things already done. The to-do group fell asleep significantly faster, especially with a specific list.")
        case 10: L("A 2019 review of 18 randomized trials in people with sleep problems found that mindfulness meditation improved sleep quality compared with groups given the same time and attention, but not more than established sleep programmes.")
        case 11: L("A 2023 review of 24 studies found that caffeine cut sleep by about 45 min. To avoid that loss, it estimated that a regular cup of coffee should be drunk at least 8.8 hours before bed.")
        case 12: L("In a 2024 study, 74 university students wore a wrist monitor for 14 nights. On nights after an unpleasant conversation before bed, they slept about 14 min less than on other nights.")
        case 13: L("In a 2013 trial, 12 healthy adults took 400 mg of caffeine (about four cups of coffee) right at bedtime, or 3 or 6 hours before. Each time, a headband monitor showed over an hour less sleep than with a placebo.")
        case 14: L("A 2015 review of 24 controlled trials concluded that a medium-firm mattress, especially one you can adjust yourself, is best for sleep comfort and sleep quality.")
        case 15: L("In a 2016 sleep-lab study, 26 adults of normal weight chose their own food for one day. Getting more of their energy from sugar went with more brief wake-ups (arousals) that night.")
        case 16: L("In a 2026 trial, 13 healthy young women ate the same dinner either 5 hours or 1 hour before bed for 4 days. After the late dinners, they slept less and were awake more during the night.")
        case 18: L("In a 2023 study, 62 adults wore a wrist monitor at home for 14 nights while their bedrooms were measured. In the warmest fifth of readings, sleep efficiency (time in bed spent asleep) was about 3 percent lower than in the coolest.")
        case 19: L("In a 2010 sleep-lab study, 14 healthy volunteers slept with recorded hospital noise and the light on, with and without an eye mask and earplugs. With them, they had more REM sleep and fewer brief wake-ups.")
        case 20: L("A 2021 review of 38 studies on steady background noise, like white noise, as a sleep aid found mixed results, from helping sleep to disturbing it. The authors rated the evidence that it improves sleep as very low quality.")
        default: nil
        }
    }

    static func evidence(for id: String) -> String? {
        switch number(of: id) {
        case 1: L("Only 61 students, and it shows a link, not a cause – regularity may go along with other habits.")
        case 2: L("Only 12 and 33 teenagers, so adults may differ. Even waking just 1 hour later plus a nap shifted the clock – an hour is a gentle aim, not a proven limit.")
        case 3: L("This is an expert consensus, not a single experiment, and a general guide for ages 18 to 60 – how much sleep each person needs varies.")
        case 4: L("A carefully controlled lab experiment, but small: 48 healthy adults aged 21 to 38 in all. It shows what can happen, not what happens to everyone.")
        case 5: L("Only 12 young adults, and a bright e-reader for about 4 hours each evening, so it does not show what one hour on a phone does.")
        case 6: L("One trial of 94 students who already slept poorly. Music helped, the audiobook did not, and reading was not tested.")
        case 7: L("Only 13 of the 17 studies had data to combine, and the authors say more research is needed, especially on the best timing and duration.")
        case 8: L("It measured the sleep hormone, not sleep itself, in healthy 18 to 30 year olds, and the lighting lasted 8 to 16 hours – far longer than an evening wind-down.")
        case 9: L("One lab study of 57 healthy 18 to 30 year olds, with a few minutes of writing before one night's sleep. It tested to-do lists, not worry journals.")
        case 10: L("Moderate at best: it beat attention-matched groups, not established sleep programmes, and the authors call it preliminary. Music, imagery and yoga were not part of it.")
        case 11: L("It pools 24 studies, so it is broader than one trial. The 8.8 hours is an estimate for a regular cup of coffee (250 mL), not an exact limit for everyone.")
        case 12: L("A link, not a cause: 74 students, sleep judged by a wrist monitor, habits reported by themselves. Many other habits in the study showed no link at all.")
        case 13: L("Only 12 adults, a high dose, and a company grant paid for it. Warm milk and herbal tea were not tested – the sure gain is skipping the caffeine.")
        case 14: L("The trials were rated moderate to high quality, but findings on the ideal mattress still differ, and pillows were not studied.")
        case 15: L("Only 26 adults and one day of self-chosen food, so a link, not a cause. Other studies are mixed – some found carb-rich meals made people sleepier.")
        case 16: L("Only 13 young women, and only 1 hour vs 5 hours was tested. Another lab study with 20 adults found no clear harm from a late dinner, so the evidence is mixed.")
        case 18: L("A link, not a cause: 62 adults, and the study names no best temperature. Most rated their room “just right” whatever it measured, so people may not notice the difference.")
        case 19: L("Only 14 people, a mask and earplugs tested together, in a noisy room with the light on. It does not prove a mask alone helps at home.")
        case 20: L("Very low quality evidence and mixed results, so soft sounds are a matter of taste, not proven benefit. The review did not look at earplugs.")
        default: nil
        }
    }

    /// True when the postcard has a study and all three texts of the study part.
    static func hasStudy(_ id: String) -> Bool {
        Postcards.study(for: id) != nil && why(for: id) != nil && finding(for: id) != nil && evidence(for: id) != nil
    }

    /// "Chang et al., PNAS, 2015" or, for two authors, "Crowley and Carskadon, Chronobiol Int, 2010".
    static func citation(for s: PostcardStudy) -> String {
        if let second = s.secondAuthor { return L("\(s.firstAuthor) and \(second), \(s.journal), \(String(s.year))") }
        return L("\(s.firstAuthor) et al., \(s.journal), \(String(s.year))")
    }
    static var whyItHelps: String { L("Why it helps") }
    static var studyHeading: String { L("The study") }
    static var evidenceHeading: String { L("How strong is the evidence") }
    static var openStudy: String { L("Open the study on PubMed") }

    static func numberLine(_ n: Int, of total: Int) -> String { L("Postcard \(n) of \(total)") }
    static var signature: String { L("– your sleep buddy 🐾") }
    static func sourceLine(_ name: String) -> String { L("Source: \(name)") }
    static var header: String { L("Postcard from your buddy") }
    static var openSource: String { L("Open the source") }
}
