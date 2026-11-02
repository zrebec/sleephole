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
        "Last night's building – %@ – lies in ruins. If tonight goes well, the builders will repair it 🔧",
        "Last night's building – %@ – lies in ruins. The builders will repair it when its turn comes 🔧",
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
        "The baker says fresh bread tastes best after a good night's sleep.",
        "Tonight we build again. I'll keep an eye on the site 🐾",
        "Full moon tonight 🌕 The whole town has a silver night.",
        "New moon tonight 🌑 The moon has a night off – only the stars are out.",
        "The longest night of the year – made for a long sleep 🌌",
        "The shortest night of the year – all the more reason to sleep on time ☀️",
        "Day and night are equally long today ⚖️",
        "Full moon tomorrow – the moon can hardly wait 🌕",
        "Full moon in %lld days 🌕",
        "A thin moon is growing 🌒 Like our town – a little every night.",
        "Half a moon tonight 🌓 It grows a little every night.",
        "The moon is nearly full 🌔 The streets glow softly at night.",
        "The moon is getting smaller 🌖 The nights get darker and cosier.",
        "Half a moon, getting smaller 🌗 Soon it takes a rest.",
        "Just a sliver of moon is left 🌘 It rises late, like a proper sleepyhead.",
        "The librarian's tip: a paper book in the evening – the screen can wait till morning 📖",
        "The museum has a new exhibit: the very first brick of our town 🧱",
        "The museum's night guard counts the paintings – and then the sheep 🐑",
        "Ducks have moved into the pond park. They go to bed early too 🦆",
        "The park fountain is switched off at night, so it can rest too ⛲",
        "Someone tied a scarf around the statue in the garden. It looks cosier already 🧣",
        "Fire drill today – the firefighters were ready in a flash, then had a well-earned nap 🚒",
        "A baby was born at the hospital today – our youngest resident 👶",
        "The night patrol reports: all quiet, everyone asleep, one cat on a roof 🌙",
        "At school today the children learned why sleep makes us smarter 🎒",
        "We finally have a mayor! The first decree: bedtime is sacred 📜",
        "At bedtime the skyscraper's lights go out floor by floor – like a giant saying goodnight 🏙️",
        "The library has its own cat, %@ – the fairy-tale shelf is its favourite bed 📚",
        "In the small park, a cat called %@ has claimed the sunniest bench ☀️",
        "The firefighters helped a cat down from a tree – %@ is safe and purring again 🐈",
        "The police found a lost cat called %@ – home again in time for bed 🐾",
        "The class has a cat called %@ – voted the best sleeper in the whole school 🏆",
        "The town hall has a new clerk: a cat called %@, who stamps papers with a paw 🐾",
        "A cat called %@ took the lift to the skyscraper's top floor – just for the view 🐈",
        "A cat called %@ visits a different doorstep every evening, just to say goodnight 🐈",
        "Our newest building – %@ – already looks as if it had always been here.",
        "The street lamps dim a little at bedtime, so the whole town knows it's time 🌙",
        "The milkman starts his round at dawn – so of course he goes to bed early 🥛",
        "Someone in town snores a little. Nobody minds – it sounds like a tiny purr 😺",
        "The bakers go to bed right after dinner – their day starts at three in the morning 🥐",
        "Mittens",
        "Whiskers",
        "Pumpkin",
        "Socks",
        "Biscuit",
        "Pepper",
        "Muffin",
        "Luna",
        "Tiger",
        "Smudge",
        "Ginger",
        "Snowball",
    ]

    /// The size name for a sentence ("We're a village now"): the same name as the Town header, in lower case.
    static func sizeName(_ size: TownSize) -> String {
        TownStats.sizeName(residents: size.minResidents).localizedLowercase
    }

    /// The cat names (English keys; the catalog holds sk / cs). Computed, so a language switch is followed.
    static var catNames: [String] {
        [
            L("Mittens"),
            L("Whiskers"),
            L("Pumpkin"),
            L("Socks"),
            L("Biscuit"),
            L("Pepper"),
            L("Muffin"),
            L("Luna"),
            L("Tiger"),
            L("Smudge"),
            L("Ginger"),
            L("Snowball"),
        ]
    }

    static func catName(_ i: Int) -> String {
        let all = catNames
        return all[((i % all.count) + all.count) % all.count]
    }

    static func text(for line: BuddyLine, buildingName: (String) -> String) -> String {
        switch line {
        case let .movedIn(id, people): L("\(buildingName(id)) already has \(people) residents.")
        case let .newSight(id): L("The whole town is talking about something new: \(buildingName(id)).")
        case let .waiting(id): L("\(buildingName(id)) is waiting for its last bricks – no rush, tonight is a new chance.")
        case let .ruined(id, repairsTonight):
            repairsTonight
                ? L("Last night's building – \(buildingName(id)) – lies in ruins. If tonight goes well, the builders will repair it 🔧")
                : L("Last night's building – \(buildingName(id)) – lies in ruins. The builders will repair it when its turn comes 🔧")
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
        case .owned(.library, 0): L("The librarian's tip: a paper book in the evening – the screen can wait till morning 📖")
        case .owned(.museum, 0): L("The museum has a new exhibit: the very first brick of our town 🧱")
        case .owned(.museum, 1): L("The museum's night guard counts the paintings – and then the sheep 🐑")
        case .owned(.pondPark, 0): L("Ducks have moved into the pond park. They go to bed early too 🦆")
        case .owned(.fountainPark, 0): L("The park fountain is switched off at night, so it can rest too ⛲")
        case .owned(.statueGarden, 0): L("Someone tied a scarf around the statue in the garden. It looks cosier already 🧣")
        case .owned(.fireStation, 0): L("Fire drill today – the firefighters were ready in a flash, then had a well-earned nap 🚒")
        case .owned(.hospital, 0): L("A baby was born at the hospital today – our youngest resident 👶")
        case .owned(.police, 0): L("The night patrol reports: all quiet, everyone asleep, one cat on a roof 🌙")
        case .owned(.school, 0): L("At school today the children learned why sleep makes us smarter 🎒")
        case .owned(.townHall, 0): L("We finally have a mayor! The first decree: bedtime is sacred 📜")
        case .owned(.skyscraper, 0): L("At bedtime the skyscraper's lights go out floor by floor – like a giant saying goodnight 🏙️")
        case .owned: ""   // every place and variant has a case above
        case let .catTale(.libraryCat, n): L("The library has its own cat, \(catName(n)) – the fairy-tale shelf is its favourite bed 📚")
        case let .catTale(.benchCat, n): L("In the small park, a cat called \(catName(n)) has claimed the sunniest bench ☀️")
        case let .catTale(.treeCat, n): L("The firefighters helped a cat down from a tree – \(catName(n)) is safe and purring again 🐈")
        case let .catTale(.lostCat, n): L("The police found a lost cat called \(catName(n)) – home again in time for bed 🐾")
        case let .catTale(.classCat, n): L("The class has a cat called \(catName(n)) – voted the best sleeper in the whole school 🏆")
        case let .catTale(.clerkCat, n): L("The town hall has a new clerk: a cat called \(catName(n)), who stamps papers with a paw 🐾")
        case let .catTale(.liftCat, n): L("A cat called \(catName(n)) took the lift to the skyscraper's top floor – just for the view 🐈")
        case let .catTale(.doorstepCat, n): L("A cat called \(catName(n)) visits a different doorstep every evening, just to say goodnight 🐈")
        case .catTale: ""
        case let .newest(id): L("Our newest building – \(buildingName(id)) – already looks as if it had always been here.")
        case let .chatter(k):
            switch k {
            case 0: L("Overheard on the street: “This town gets nicer every night.”")
            case 1: L("The neighbours say the streets are quietest at night – just the way we like it.")
            case 2: L("The baker says fresh bread tastes best after a good night's sleep.")
            case 3: L("The street lamps dim a little at bedtime, so the whole town knows it's time 🌙")
            case 4: L("The milkman starts his round at dawn – so of course he goes to bed early 🥛")
            case 5: L("Someone in town snores a little. Nobody minds – it sounds like a tiny purr 😺")
            default: L("The bakers go to bed right after dinner – their day starts at three in the morning 🥐")
            }
        case .tonight: L("Tonight we build again. I'll keep an eye on the site 🐾")
        case .fullMoonTonight: L("Full moon tonight 🌕 The whole town has a silver night.")
        case .newMoonTonight: L("New moon tonight 🌑 The moon has a night off – only the stars are out.")
        case .longestNight: L("The longest night of the year – made for a long sleep 🌌")
        case .shortestNight: L("The shortest night of the year – all the more reason to sleep on time ☀️")
        case .equinox: L("Day and night are equally long today ⚖️")
        case .fullMoonTomorrow: L("Full moon tomorrow – the moon can hardly wait 🌕")
        case let .fullMoonSoon(days): L("Full moon in \(days) days 🌕")
        case let .moonPhase(q):
            switch q {
            case .waxingCrescent: L("A thin moon is growing 🌒 Like our town – a little every night.")
            case .firstQuarter: L("Half a moon tonight 🌓 It grows a little every night.")
            case .waxingGibbous: L("The moon is nearly full 🌔 The streets glow softly at night.")
            case .waningGibbous: L("The moon is getting smaller 🌖 The nights get darker and cosier.")
            case .lastQuarter: L("Half a moon, getting smaller 🌗 Soon it takes a rest.")
            case .waningCrescent: L("Just a sliver of moon is left 🌘 It rises late, like a proper sleepyhead.")
            }
        }
    }
}
