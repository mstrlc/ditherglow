import Foundation

/// The app's settings, so the saver looks like the wallpaper. Apple's `legacyScreenSaver` host is
/// sandboxed with its own defaults, but may read any file, so this reads the app's preferences
/// file directly. Read once per `startAnimation`; changes show the next time the saver starts.
nonisolated struct AppSettings {
    var blockSize = Preferences.defaultBlockSize
    var speed = Preferences.defaultSpeed
    var location: Sun.Location

    /// The app's bundle identifier, which names its preferences file.
    private static let appIdentifier = "eu.mstrlc.ditherglow"

    static func load() -> AppSettings {
        let defaults = UserDefaults(suiteName: "\(appIdentifier).saver.app") ?? .standard
        // The registration domain is in-memory only, so nothing is written into the host's container.
        if let values = NSDictionary(contentsOf: preferencesURL) as? [String: Any] {
            defaults.register(defaults: values)
        }
        var settings = AppSettings(location: Sun.location(defaults: defaults))
        if defaults.object(forKey: Preferences.blockSizeKey) != nil {
            settings.blockSize = defaults.double(forKey: Preferences.blockSizeKey).clamped(to: Preferences.blockSizeRange)
        }
        if defaults.object(forKey: Preferences.speedKey) != nil {
            settings.speed = defaults.double(forKey: Preferences.speedKey).clamped(to: Preferences.speedRange)
        }
        return settings
    }

    /// `~/Library/Preferences/<app>.plist` in the real home: inside the sandbox,
    /// `NSHomeDirectory()` is the host's container.
    private static var preferencesURL: URL {
        let home = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(filePath: home).appending(path: "Library/Preferences/\(appIdentifier).plist")
    }
}

private nonisolated extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double { min(max(self, range.lowerBound), range.upperBound) }
}
