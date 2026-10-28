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

    /// The source of a postcard; nil for an unknown id (e.g. one added by a later build).
    public static func source(for id: String) -> PostcardSource? { sources[id] }

    /// The domains a source may come from (the owner's list of authorities; subdomains are fine).
    public static let allowedDomains = [
        "nhs.uk", "cdc.gov", "nih.gov", "medlineplus.gov", "aasm.org", "sleepeducation.org",
        "mayoclinic.org", "sleep.hms.harvard.edu", "healthysleep.med.harvard.edu",
    ]
}
