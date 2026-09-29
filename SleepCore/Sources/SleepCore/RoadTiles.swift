import Foundation

/// Maps a road cell's drawn neighbours to a road sprite (catalog `connects`, plan §7.1).
public enum RoadTiles {
    /// Open edges of a road cell, in canonical "NESW" order, e.g. "EW", "NES".
    public static func mask(at cell: Cell, roads: Set<Cell>) -> String {
        var m = ""
        if roads.contains(cell.offset(0, -1)) { m += "N" }
        if roads.contains(cell.offset(1, 0)) { m += "E" }
        if roads.contains(cell.offset(0, 1)) { m += "S" }
        if roads.contains(cell.offset(-1, 0)) { m += "W" }
        return m
    }

    /// Sprite id for a road cell. Lit straights use the lit sprites; crossings are not used here.
    public static func spriteId(at cell: Cell, roads: Set<Cell>, lit: Set<Cell>, catalog: Catalog) -> String {
        let m = mask(at: cell, roads: roads)
        if lit.contains(cell) {
            if m == "EW" { return "l2-road-lit-we" }
            if m == "NS" { return "l2-road-lit-ns" }
        }
        if m.isEmpty { return "t-road-crossroad-nesw" }
        return catalog.entries.first { $0.kind == .road && $0.connects == m && !$0.id.contains("crossing") }?.id
            ?? "t-road-crossroad-nesw"
    }
}
