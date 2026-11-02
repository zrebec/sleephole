import Foundation

/// How much the night screen's construction site must shrink so the whole screen fits above the tab
/// bar (13e6 proposal). Pure arithmetic; the views measure the numbers.
public enum NightLayout {
    /// The smallest scale – the morning's compact scale (never smaller).
    public static let minSiteScale: Double = 0.6

    /// 1 when the content fits; otherwise the scale that removes the overflow, clamped to `minSiteScale…1`.
    /// - natural: the content's height with the site at scale 1 (without any slack a `Spacer` adds)
    /// - available: the room for the content above the tab bar
    /// - siteHeight: the site's natural (scale 1) height
    public static func siteScale(natural: Double, available: Double, siteHeight: Double) -> Double {
        guard siteHeight > 0, natural > available else { return 1 }
        let scale = (available - (natural - siteHeight)) / siteHeight
        return min(1, max(minSiteScale, scale))
    }
}
