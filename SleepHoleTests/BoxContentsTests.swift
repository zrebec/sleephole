#if DEBUG
import Foundation
import SleepCore
import Testing
import UIKit
@testable import SleepHole

/// Step 11b5e: the Developer "Box contents" screen lists exactly what the catalogs hold.
@MainActor
struct BoxContentsTests {
    @Test func listsCoverTheCatalogs() {
        #expect(BoxContents.postcardIds == BoxCatalog.ids(.postcard))
        #expect(BoxContents.postcardIds.count == 30)
        #expect(BoxContents.decorationIds.count == 12)
        #expect(BoxContents.accessoryIds.count == 6)
        #expect(BoxContents.skyIds.count == 4)
        #expect(BoxContents.Section.allCases.map(\.count) == [30, 12, 6, 4])
    }

    @Test func everyDecorationSpriteLoads() {
        let sprites = SpriteLibrary.loadFromBundle()
        for id in BoxContents.decorationIds {
            let sprite = BoxContents.sprite(of: id)
            #expect(sprite != nil, "no sprite for \(id)")
            #expect(sprite.flatMap { sprites.image(for: $0) } != nil, "sprite of \(id) does not load")
            #expect(CollectibleText.decorationName(id, catalog: sprites.catalog) != id)
        }
    }

    @Test func everyAccessoryHasASlotAndAllPoseImages() {
        for id in BoxContents.accessoryIds {
            #expect(AccessorySlot.of(id) != nil)
            for pose in BuddyView.Pose.allCases {
                #expect(UIImage(named: pose.accessoryImageName(id)) != nil, "missing \(pose.accessoryImageName(id))")
            }
        }
        let slotted = AccessorySlot.allCases.flatMap { BoxContents.accessories(for: $0) }
        #expect(Set(slotted) == Set(BoxContents.accessoryIds))
    }

    @Test func everySkyResolvesToAnEffect() {
        for id in BoxContents.skyIds { #expect(BoxContents.effect(of: id) != nil) }
    }
}
#endif
