import Foundation
import SleepCore

/// The sleep buddy's sentences (phase TALK, owner 2026-10-14): the core (`BuddyTalk`) decides which ones apply,
/// this turns them into localized text. Building names come from the catalog in the app's language.
enum BuddyTalkText {
    /// The English keys of every sentence of the buddy, exactly as they stand in the String Catalog (the Debug
    /// "Texts" screen filters by this list; a test keeps it in step with `text(for:)`).
    static let keys: [String] = [
        "%@ already has %lld residents.",
        "The whole town is talking about something new: %@.",
        "%@ is waiting for its last bricks – no rush, tonight is a new chance.",
        "The builders took a day off. Tonight we try again 🌙",
        "Your streak was safe – the town waited for you.",
        "Bedtime is at %@. The builders are already putting on their helmets.",
        "A whole week of good nights – the town is throwing a little party 🎉",
        "%lld nights in a row! The builders are proud of you.",
        "A new streak starts tonight. The town believes in you.",
        "We're a %@ now – %lld people live here.",
        "%lld more people and we'll be a %@!",
        "Our first neighbours are settling in. Every good night brings new ones.",
        "We have %lld lovely parks – people love an evening stroll.",
        "The library is full tonight – everyone is reading bedtime stories.",
        "The museum has a new painting: a cat sleeping on a cloud. I wonder who posed for it 🐾",
        "From the top of our tallest building you can see the whole town.",
        "The residents whisper: “Who would put out a fire? We have no fire station yet.”",
        "Overheard at the bakery: “If someone gets ill, where do we go? A hospital would be nice.”",
        "The neighbours say a police station would make the nights even calmer.",
        "The children keep asking when they'll get a school.",
        "Nobody knows who the mayor is. Maybe once we have a town hall…",
        "The firefighters polished their truck again. Twice today.",
        "The hospital is quiet tonight – just the way the doctors like it.",
        "Overheard on the street: “This town gets nicer every night.”",
        "The neighbours say the streets are quietest at night – just the way we like it.",
        "Someone asked if we'll ever get a cinema. Who knows!",
        "The baker says fresh bread tastes best after a good night's sleep.",
        "Tonight we build again. I'll keep an eye on the site 🐾",
    ]

    /// The size name for a sentence ("We're a village now"): the same name as the Town header, in lower case.
    static func sizeName(_ size: TownSize) -> String {
        TownStats.sizeName(residents: size.minResidents).localizedLowercase
    }

    static func text(for line: BuddyLine, buildingName: (String) -> String) -> String {
        switch line {
        case let .movedIn(id, people): L("\(buildingName(id)) already has \(people) residents.")
        case let .newSight(id): L("The whole town is talking about something new: \(buildingName(id)).")
        case let .waiting(id): L("\(buildingName(id)) is waiting for its last bricks – no rush, tonight is a new chance.")
        case .dayOff: L("The builders took a day off. Tonight we try again 🌙")
        case .streakSafe: L("Your streak was safe – the town waited for you.")
        case let .bedtimeSoon(at): L("Bedtime is at \(Fmt.time(at)). The builders are already putting on their helmets.")
        case .week: L("A whole week of good nights – the town is throwing a little party 🎉")
        case let .streak(n): L("\(n) nights in a row! The builders are proud of you.")
        case .newStreak: L("A new streak starts tonight. The town believes in you.")
        case let .size(size, people): L("We're a \(sizeName(size)) now – \(people) people live here.")
        case let .nextSize(missing, size): L("\(missing) more people and we'll be a \(sizeName(size))!")
        case .firstNeighbours: L("Our first neighbours are settling in. Every good night brings new ones.")
        case let .parks(n): L("We have \(n) lovely parks – people love an evening stroll.")
        case .library: L("The library is full tonight – everyone is reading bedtime stories.")
        case .museum: L("The museum has a new painting: a cat sleeping on a cloud. I wonder who posed for it 🐾")
        case .tallest: L("From the top of our tallest building you can see the whole town.")
        case .noFireStation: L("The residents whisper: “Who would put out a fire? We have no fire station yet.”")
        case .noHospital: L("Overheard at the bakery: “If someone gets ill, where do we go? A hospital would be nice.”")
        case .noPolice: L("The neighbours say a police station would make the nights even calmer.")
        case .noSchool: L("The children keep asking when they'll get a school.")
        case .noTownHall: L("Nobody knows who the mayor is. Maybe once we have a town hall…")
        case .fireStation: L("The firefighters polished their truck again. Twice today.")
        case .hospital: L("The hospital is quiet tonight – just the way the doctors like it.")
        case let .chatter(k):
            switch k {
            case 0: L("Overheard on the street: “This town gets nicer every night.”")
            case 1: L("The neighbours say the streets are quietest at night – just the way we like it.")
            case 2: L("Someone asked if we'll ever get a cinema. Who knows!")
            default: L("The baker says fresh bread tastes best after a good night's sleep.")
            }
        case .tonight: L("Tonight we build again. I'll keep an eye on the site 🐾")
        }
    }
}
