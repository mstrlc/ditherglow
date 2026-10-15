import Foundation

nonisolated extension Bundle {
    /// The bundle holding the shader and `zone.tab`. Not `Bundle.main`: inside the screen saver
    /// that is Apple's `legacyScreenSaver` host, which has none of our resources.
    static let ditherglow = Bundle(for: BundleToken.self)
}

private final class BundleToken {}
