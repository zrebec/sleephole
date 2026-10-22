import Foundation

/// The town camera a device remembers (owner 2026-10-22, B30): the scale, the centre and the newest building the
/// camera has already been shown. A big town is not shrunk to fit – the user scrolls, and the app comes back to
/// where they were and glides once to every new building. A per-device view preference: never synced or backed up.
public struct TownCamera: Codable, Equatable, Sendable {
    public var scale: Double
    public var x: Double
    public var y: Double
    /// The newest building the camera has been brought to (its night key), nil = none yet.
    public var seenBuilding: String?

    public init(scale: Double, x: Double, y: Double, seenBuilding: String? = nil) {
        self.scale = scale; self.x = x; self.y = y; self.seenBuilding = seenBuilding
    }

    /// The same camera with the scale inside [minScale, maxScale] and the centre inside the town bounds.
    public func restored(in bounds: SceneRect, minScale: Double, maxScale: Double) -> TownCamera {
        let c = TownRender.clamp(ScenePoint(x: x, y: y), to: bounds)
        var r = self
        r.scale = min(max(scale.isFinite ? scale : minScale, minScale), maxScale)
        r.x = c.x; r.y = c.y
        return r
    }

    /// Notes the town's newest building and says whether the camera should glide to it: only when a different
    /// building was remembered. Nothing remembered yet (fresh install, first launch after the update) → remember
    /// it with no glide; no building at all (an empty town) → nothing changes.
    public mutating func noteNewest(_ id: String?) -> Bool {
        guard let id else { return false }
        defer { seenBuilding = id }
        guard let seen = seenBuilding else { return false }
        return seen != id
    }
}
