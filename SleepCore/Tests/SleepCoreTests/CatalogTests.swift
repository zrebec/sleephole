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
