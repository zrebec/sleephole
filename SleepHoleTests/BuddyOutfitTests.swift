import Foundation
import SleepCore
import Testing
import UIKit
@testable import SleepHole

/// Step 11b5b: the cat accessories – every layer image is in the app, BuddyView names them as the catalog does, and
/// the accessibility text says what the cat wears.
@MainActor
struct BuddyOutfitTests {
    @Test func everyAccessoryLayerExistsInTheBundle() {
        for id in BoxCatalog.ids(.accessory) {
            for pose in BuddyView.Pose.allCases {
                let img = UIImage(named: "buddy-acc-\(id)-\(pose.rawValue)")
                #expect(img != nil, "missing buddy-acc-\(id)-\(pose.rawValue)")
                // same canvas as the cat frame, so the layer stacks exactly
                let cat = UIImage(named: pose.imageName)
                #expect(img?.size == cat?.size)
            }
        }
    }

    @Test func viewUsesTheAssetNames() {
        #expect(BuddyView.Pose.arch1.accessoryImageName("top-hat") == "buddy-acc-top-hat-arch-1")
        #expect(BuddyView.Pose.asleep.accessoryImageName("rug") == "buddy-acc-rug-asleep")
        for id in BoxCatalog.ids(.accessory) {
            #expect(UIImage(named: BuddyView.Pose.awake.accessoryImageName(id)) != nil)
        }
    }

    @Test func everyAccessoryHasAName() {
        for id in BoxCatalog.ids(.accessory) { #expect(CollectibleText.accessoryName(id) != id) }
        #expect(CollectibleText.keys.count == 6)
    }

    @Test func accessibilityText() {
        let before = Lang.current
        defer { Lang.current = before }
        let outfit = CatOutfit(ids: ["nightcap", "sunglasses", "rug"])
        Lang.current = .en
        #expect(BuddyView.accessibilityText(state: .awake, outfit: .none) == "Your cat is looking at you")
        #expect(BuddyView.accessibilityText(state: .asleep, outfit: outfit)
            == "Your sleepy cat. Wearing: Nightcap, Sunglasses, Rug")
        Lang.current = .sk
        #expect(BuddyView.accessibilityText(state: .asleep, outfit: outfit)
            == "Tvoja ospalá mačka. Má na sebe: Nočná čiapka, Slnečné okuliare, Koberček")
    }
}

/// The Debug hook `-buddyOutfit a,b,c` goes through `DevArgs.value(after:)`; the parse is the outfit's id list.
struct BuddyOutfitArgTests {
    @Test func argumentParses() {
        let v = DevArgs.value(after: "-buddyOutfit", in: ["app", "-buddyOutfit", "nightcap,sunglasses,fish-bowl,bogus"])
        let outfit = CatOutfit(ids: (v ?? "").split(separator: ",").map(String.init))
        #expect(outfit == CatOutfit(head: "nightcap", face: "sunglasses", bed: "fish-bowl"))
        #expect(DevArgs.value(after: "-buddyOutfit", in: ["app"]) == nil)
    }
}
