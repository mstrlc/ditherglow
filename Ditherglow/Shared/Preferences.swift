import Foundation

/// `UserDefaults` keys and defaults for the user-tunable look of the sky.
nonisolated enum Preferences {
    /// Size of one dither pixel, in points.
    static let blockSizeKey = "blockSize"
    static let defaultBlockSize = 4.0
    static let blockSizeRange = 2.0...16.0

    /// Animation-time units per real second, see `DitherglowView.speed`.
    static let speedKey = "speed"
    static let defaultSpeed = 0.05
    static let speedRange = 0.01...0.5

    /// Roughly how long a blob takes to complete one loop at `speed`.
    /// The shader's path frequencies are ~0.2 rad per time unit.
    static func loopDuration(speed: Double) -> Duration {
        .seconds(2 * Double.pi / 0.2 / speed)
    }
}
