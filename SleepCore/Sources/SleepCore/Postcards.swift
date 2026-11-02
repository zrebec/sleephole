import Foundation

/// Where each postcard's sleep tip comes from (step 11b5a). A postcard is a collectible of a mystery box
/// (`BoxCatalog.ids(.postcard)` = `postcard-01` … `postcard-30`): a cute card from the sleep buddy with ONE
/// lifestyle tip and its source. The ids are persisted in box records and the content ORDER IS FIXED once shipped –
/// `postcard-07` must always be the same tip; a new tip is only ever added as a new id. The texts themselves
/// (title, tip, stamp, English + Slovak) live in the app (`PostcardText`); this table holds only the source of each,
/// so the app can show "Source: NHS" as a link. Every URL was opened and its page checked to state the point on
/// 2026-10-28. Allowed sources: NHS, CDC, NIH (NHLBI, MedlinePlus), AASM, Mayo Clinic, Harvard sleep medicine.
public struct PostcardSource: Equatable, Sendable {
    /// The short name shown to the reader ("NHS", "CDC", …).
    public let name: String
    /// The public page (https) that states the tip.
    public let url: String
}

/// The study behind a postcard (step 13c): the longer part of the same card explains why the tip helps, what ONE real study found
/// and how strong the evidence is. Only the citation lives here (it is not translated); the texts are in the app
/// (`PostcardText`). Every study was opened on PubMed and checked against the finding on the postcard.
public struct PostcardStudy: Equatable, Sendable {
    /// The first author's surname ("Chang"); the card reads "Chang et al., PNAS, 2015".
    public let firstAuthor: String
    /// The second author's surname when the study has exactly two authors ("Crowley and Carskadon"); nil otherwise.
    public let secondAuthor: String?
    /// A short journal name a reader knows ("PNAS").
    public let journal: String
    /// The year of publication.
    public let year: Int
    /// The PubMed id (digits only); the link is built from it, so it can only point to PubMed.
    public let pmid: String
    /// The study's PubMed page.
    public var url: String { "https://pubmed.ncbi.nlm.nih.gov/\(pmid)/" }

    public init(firstAuthor: String, secondAuthor: String? = nil, journal: String, year: Int, pmid: String) {
        self.firstAuthor = firstAuthor; self.secondAuthor = secondAuthor
        self.journal = journal; self.year = year; self.pmid = pmid
    }
}

public enum Postcards {
    /// The sources by postcard id; exactly `BoxCatalog.ids(.postcard)`.
    public static let sources: [String: PostcardSource] = [
        "postcard-01": PostcardSource(name: "NHS", url: "https://www.nhs.uk/every-mind-matters/mental-wellbeing-tips/how-to-fall-asleep-faster-and-sleep-better/"),  // keep a regular routine: similar bed/wake times incl. non-work days
        "postcard-02": PostcardSource(name: "NIH NHLBI", url: "https://www.nhlbi.nih.gov/health/sleep-deprivation/healthy-sleep-habits"),  // keep weekend and weeknight schedules within about 1 hour
        "postcard-03": PostcardSource(name: "CDC", url: "https://www.cdc.gov/sleep/about/index.html"),  // "7 or more hours" for adults 18-60 (table)
        "postcard-04": PostcardSource(name: "NIH NHLBI", url: "https://www.nhlbi.nih.gov/health/sleep-deprivation/healthy-sleep-habits"),  // "Making time to sleep will help you protect your health and well-being now and in the future."
        "postcard-05": PostcardSource(name: "NHS", url: "https://www.nhs.uk/every-mind-matters/mental-wellbeing-tips/how-to-fall-asleep-faster-and-sleep-better/"),  // no phones/tablets/computers for an hour before bed; blue light
        "postcard-06": PostcardSource(name: "Mayo Clinic", url: "https://diet.mayoclinic.org/us/blog/2022/healthy-habits-for-a-better-night-s-sleep/"),  // relaxing bedtime routine: reading, soothing music/audiobook, repeated
        "postcard-07": PostcardSource(name: "CDC", url: "https://www.cdc.gov/niosh/bulletin/2020/sleep.html"),  // warm bath 30 min to 2 h before bedtime promotes relaxation
        "postcard-08": PostcardSource(name: "CDC", url: "https://www.cdc.gov/niosh/bulletin/2020/sleep.html"),  // wind-down routine 1.5 h before bed, alarm as reminder, dim lighting
        "postcard-09": PostcardSource(name: "NHS", url: "https://www.nhs.uk/every-mind-matters/mental-wellbeing-tips/how-to-fall-asleep-faster-and-sleep-better/"),  // write worries down / list next day's tasks before sleep
        "postcard-10": PostcardSource(name: "NIH MedlinePlus", url: "https://medlineplus.gov/ency/patientinstructions/000757.htm"),  // relaxation techniques: guided imagery, music, yoga, meditation
        "postcard-11": PostcardSource(name: "NIH NHLBI", url: "https://www.nhlbi.nih.gov/health/sleep-deprivation/healthy-sleep-habits"),  // caffeine's effects can last up to 8 hours
        "postcard-12": PostcardSource(name: "Mayo Clinic", url: "https://diet.mayoclinic.org/us/blog/2022/healthy-habits-for-a-better-night-s-sleep/"),  // avoid emotional/upsetting conversations right before bed
        "postcard-13": PostcardSource(name: "NHS", url: "https://www.nhs.uk/every-mind-matters/mental-wellbeing-tips/how-to-fall-asleep-faster-and-sleep-better/"),  // try a warm milky drink or herbal tea instead of caffeine
        "postcard-14": PostcardSource(name: "CDC", url: "https://www.cdc.gov/niosh/bulletin/2020/sleep.html"),  // "Have a comfortable mattress and pillow."
        "postcard-15": PostcardSource(name: "Mayo Clinic", url: "https://diet.mayoclinic.org/us/blog/2022/healthy-habits-for-a-better-night-s-sleep/"),  // "Consuming sugary drinks and snacks can cause your blood glucose levels to spike, making it difficult to fall or stay asleep."
        "postcard-16": PostcardSource(name: "Mayo Clinic", url: "https://diet.mayoclinic.org/us/blog/2022/healthy-habits-for-a-better-night-s-sleep/"),  // dinner as lightest meal; stop eating 3-4 h before bed
        "postcard-17": PostcardSource(name: "CDC", url: "https://www.cdc.gov/niosh/bulletin/2020/sleep.html"),  // limit liquids several hours before sleep
        "postcard-18": PostcardSource(name: "CDC", url: "https://www.cdc.gov/niosh/bulletin/2020/sleep.html"),  // bedroom about 65-68 F
        "postcard-19": PostcardSource(name: "CDC", url: "https://www.cdc.gov/niosh/bulletin/2020/sleep.html"),  // opaque window coverings or an eye mask to block light
        "postcard-20": PostcardSource(name: "NHS", url: "https://www.nhs.uk/every-mind-matters/mental-wellbeing-tips/how-to-fall-asleep-faster-and-sleep-better/"),  // earplugs; background sounds like rain or white noise
        "postcard-21": PostcardSource(name: "NHS", url: "https://www.nhs.uk/every-mind-matters/mental-wellbeing-tips/how-to-fall-asleep-faster-and-sleep-better/"),  // silence phone, place face down
        "postcard-22": PostcardSource(name: "NIH MedlinePlus", url: "https://medlineplus.gov/ency/patientinstructions/000757.htm"),  // use your bed only for sleep; don't eat or work in bed
        "postcard-23": PostcardSource(name: "NHS", url: "https://www.nhs.uk/every-mind-matters/mental-wellbeing-tips/how-to-fall-asleep-faster-and-sleep-better/"),  // if awake after ~20 min, get up, relax, return when sleepy
        "postcard-24": PostcardSource(name: "NHS", url: "https://www.nhs.uk/every-mind-matters/mental-wellbeing-tips/how-to-fall-asleep-faster-and-sleep-better/"),  // hiding clocks listed as a bedroom tip
        "postcard-25": PostcardSource(name: "NHS", url: "https://www.nhs.uk/every-mind-matters/mental-wellbeing-tips/how-to-fall-asleep-faster-and-sleep-better/"),  // regular activity, even small amounts, can improve sleep; build gradually
        "postcard-26": PostcardSource(name: "CDC", url: "https://www.cdc.gov/niosh/bulletin/2020/sleep.html"),  // finish exercise at least 3 hours before sleep
        "postcard-27": PostcardSource(name: "CDC", url: "https://www.cdc.gov/niosh/bulletin/2020/sleep.html"),  // ~30 min outdoors in sunlight, esp. early; cloudy day beats indoors
        "postcard-28": PostcardSource(name: "NIH NHLBI", url: "https://www.nhlbi.nih.gov/health/sleep/why-sleep-important"),  // "Sleep helps with learning and the formation of long-term memories." (page: why-sleep-important; URL below)
        "postcard-29": PostcardSource(name: "NIH MedlinePlus", url: "https://medlineplus.gov/healthysleep.html"),  // don't nap after 3 p.m.
        "postcard-30": PostcardSource(name: "NIH NHLBI", url: "https://www.nhlbi.nih.gov/health/sleep-deprivation/healthy-sleep-habits"),  // "a dim night light is fine, if needed"
    ]

    /// The studies behind the postcards, by postcard id; a postcard not listed here has no study part yet.
    public static let studies: [String: PostcardStudy] = [
        "postcard-01": PostcardStudy(firstAuthor: "Phillips", journal: "Sci Rep", year: 2017, pmid: "28607474"),  // irregular sleep went with a later body clock and lower grades in 61 students; checked 2026-11-02
        "postcard-02": PostcardStudy(firstAuthor: "Crowley", secondAuthor: "Carskadon", journal: "Chronobiol Int", year: 2010, pmid: "20795887"),  // a typical weekend schedule shifted teenagers' body clock about 45 min later; checked 2026-11-02
        "postcard-03": PostcardStudy(firstAuthor: "Watson", journal: "Sleep", year: 2015, pmid: "26039963"),  // two US sleep societies agreed adults need 7 hours or more; checked 2026-11-02
        "postcard-04": PostcardStudy(firstAuthor: "Van Dongen", journal: "Sleep", year: 2003, pmid: "12683469"),  // 14 nights of 6 hours or less dulled performance while people did not notice; checked 2026-11-02
        "postcard-05": PostcardStudy(firstAuthor: "Chang", journal: "PNAS", year: 2015, pmid: "25535358"),  // reading on a light-emitting e-reader vs print: slower to fall asleep, less alert next morning; checked 2026-11-02
        "postcard-06": PostcardStudy(firstAuthor: "Harmat", journal: "J Adv Nurs", year: 2008, pmid: "18426457"),  // relaxing music at bedtime improved sleep quality in 94 students; an audiobook did not; checked 2026-11-02
        "postcard-07": PostcardStudy(firstAuthor: "Haghayegh", journal: "Sleep Med Rev", year: 2019, pmid: "31102877"),  // review of 17 studies: a warm bath 1 to 2 hours before bed went with better sleep; checked 2026-11-02
        "postcard-08": PostcardStudy(firstAuthor: "Gooley", journal: "J Clin Endocrinol Metab", year: 2011, pmid: "21193540"),  // room light before bedtime delayed and shortened the sleep hormone; checked 2026-11-02
        "postcard-09": PostcardStudy(firstAuthor: "Scullin", journal: "J Exp Psychol Gen", year: 2018, pmid: "29058942"),  // writing a to-do list for 5 min before bed helped people fall asleep faster; checked 2026-11-02
        "postcard-10": PostcardStudy(firstAuthor: "Rusch", journal: "Ann N Y Acad Sci", year: 2019, pmid: "30575050"),  // review of 18 trials: mindfulness meditation improved sleep quality; checked 2026-11-02
        "postcard-11": PostcardStudy(firstAuthor: "Gardiner", journal: "Sleep Med Rev", year: 2023, pmid: "36870101"),  // review of 24 studies: caffeine cut sleep by about 45 min; a cup of coffee at least 8.8 h before bed; checked 2026-11-02
        "postcard-12": PostcardStudy(firstAuthor: "McAlpine", journal: "J Behav Med", year: 2024, pmid: "37702911"),  // 74 students, wrist monitor: about 14 min less sleep after an unpleasant conversation before bed; checked 2026-11-02
        "postcard-13": PostcardStudy(firstAuthor: "Drake", journal: "J Clin Sleep Med", year: 2013, pmid: "24235903"),  // 12 adults, 400 mg caffeine at 0, 3 or 6 h before bed: over an hour less sleep each time; checked 2026-11-02
        "postcard-14": PostcardStudy(firstAuthor: "Radwan", journal: "Sleep Health", year: 2015, pmid: "29073401"),  // review of 24 controlled trials: a medium-firm, self-adjusted mattress was best for comfort and sleep quality; checked 2026-11-02
        "postcard-15": PostcardStudy(firstAuthor: "St-Onge", journal: "J Clin Sleep Med", year: 2016, pmid: "26156950"),  // 26 adults in a sleep lab: more energy from sugar went with more arousals that night; checked 2026-11-02
        "postcard-16": PostcardStudy(firstAuthor: "Enomoto", journal: "J Physiol Anthropol", year: 2026, pmid: "41975458"),  // 13 young women: dinner 1 h before bed vs 5 h – shorter, more broken sleep after the late dinners; checked 2026-11-02
        "postcard-18": PostcardStudy(firstAuthor: "Basner", journal: "Sleep Health", year: 2023, pmid: "37076419"),  // 62 adults at home: sleep efficiency about 3 percent lower in the warmest fifth of bedroom readings; checked 2026-11-02
        "postcard-19": PostcardStudy(firstAuthor: "Hu", journal: "Crit Care", year: 2010, pmid: "20398302"),  // 14 healthy volunteers in simulated hospital noise and light: an eye mask and earplugs gave more REM sleep, fewer arousals; checked 2026-11-02
        "postcard-20": PostcardStudy(firstAuthor: "Riedy", journal: "Sleep Med Rev", year: 2021, pmid: "33007706"),  // review of 38 studies: evidence that continuous noise improves sleep is very low; results vary; checked 2026-11-02
    ]

    /// The study of a postcard; nil when it has no study part (yet).
    public static func study(for id: String) -> PostcardStudy? { studies[id] }

    /// The source of a postcard; nil for an unknown id (e.g. one added by a later build).
    public static func source(for id: String) -> PostcardSource? { sources[id] }

    /// The domains a source may come from (the owner's list of authorities; subdomains are fine).
    public static let allowedDomains = [
        "nhs.uk", "cdc.gov", "nih.gov", "medlineplus.gov", "aasm.org", "sleepeducation.org",
        "mayoclinic.org", "sleep.hms.harvard.edu", "healthysleep.med.harvard.edu",
    ]
}
