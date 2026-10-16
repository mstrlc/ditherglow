import Foundation

/// `UserDefaults` keys and defaults for the user-tunable look of the sky.
nonisolated enum Preferences {
    /// Whether the animated wallpaper is on. Remembered so it comes back on launch.
    static let wallpaperEnabledKey = "wallpaperEnabled"
    static let defaultWallpaperEnabled = true

    /// Size of one dither pixel, in points.
    static let blockSizeKey = "blockSize"
    static let defaultBlockSize = 4.0
    static let blockSizeRange = 2.0...16.0

    /// Animation-time units per real second, see `DitherglowView.speed`.
    static let speedKey = "speed"
    static let defaultSpeed = 0.05
    static let speedRange = 0.01...0.5

    /// Where the sky follows the sun, see `Sun.location()`.
    enum LocationMode: String, CaseIterable, Sendable {
        /// The time zone's reference city: no permission needed, but can be far off in a wide zone.
        case timeZone
        /// A city picked from zone.tab, for when the time zone's city is too far away.
        case city
        /// Core Location, opt-in; the last fix is saved below.
        case current
    }

    static let locationModeKey = "locationMode"
    static let defaultLocationMode = LocationMode.timeZone

    /// A zone.tab identifier such as "America/Los_Angeles", used in `.city` mode.
    static let cityKey = "city"

    /// The last Core Location fix, used in `.current` mode. Saved so the sky is right
    /// at launch and offline, before (or without) a new fix.
    static let currentLatitudeKey = "currentLatitude"
    static let currentLongitudeKey = "currentLongitude"
    static let currentPlaceKey = "currentPlace"

    /// Roughly how long a blob takes to complete one loop at `speed`.
    /// The shader's path frequencies are ~0.2 rad per time unit.
    static func loopDuration(speed: Double) -> Duration {
        .seconds(2 * Double.pi / 0.2 / speed)
    }
}
