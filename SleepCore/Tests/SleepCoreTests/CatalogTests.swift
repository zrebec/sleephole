import Foundation
import Testing
@testable import SleepCore

/// Loads the real catalog shipped with the app (repo: assets/sprites/catalog.json).
func loadRealCatalog() throws -> Catalog {
    let url = URL(fileURLWithPath: #filePath)          // …/SleepCore/Tests/SleepCoreTests/CatalogTests.swift
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("assets/sprites/catalog.json")
    return try Catalog(jsonData: Data(contentsOf: url))
}

@Test func realCatalogDecodes() throws {
    let catalog = try loadRealCatalog()
    #expect(catalog.entries.count == 190)          // 174 + 16 crane frames
    #expect(catalog["l3-police"]?.nameSK == "Polícia")
    #expect(catalog["l3-police"]?.footprint == [2, 2])
}

@Test func everyUnlockLevelHasBuildings() throws {
    let catalog = try loadRealCatalog()
    for level in 1...4 {
        #expect(!catalog.buildable(level: level).isEmpty, "level \(level) is empty")
    }
}

@Test func roadsDeclareConnections() throws {
    let catalog = try loadRealCatalog()
    let roads = catalog.entries.filter { $0.kind == .road || $0.kind == .roadLit }
    #expect(!roads.isEmpty)
    #expect(roads.allSatisfy { ($0.connects ?? "").allSatisfy { "NESW".contains($0) } && $0.connects != nil })
}

@Test func namesAndSignFilesPerLanguage() throws {
    let catalog = try loadRealCatalog()
    #expect(catalog.entries.allSatisfy { $0.nameEN != nil })
    let police = try #require(catalog["l3-police"])
    #expect(police.name("sk") == "Polícia" && police.name("en") == "Police station" && police.name("cs") == "Police station")
    #expect(police.file("sk") == "L3/l3-police.png" && police.file("en") == "L3/l3-police.en.png")
    let house = try #require(catalog["l1-house-a-a"])
    #expect(house.fileEN == nil && house.file("en") == house.file)
    // an older catalog without the English fields still decodes and falls back to Slovak
    let old = #"[{"id":"x","level":1,"kind":"building","nameSK":"Dom","footprint":[1,1],"file":"L1/x.png","size":[1,1],"anchor":[0.5,0.5]}]"#
    let entry = try #require(Catalog(jsonData: Data(old.utf8))["x"])
    #expect(entry.name("en") == "Dom" && entry.file("en") == "L1/x.png")
}
