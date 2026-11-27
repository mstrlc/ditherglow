import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Keeps a still frame of the sky as each screen's desktop picture, refreshed as the sun moves.
/// macOS shows the real wallpaper whenever it hides desktop-level windows (editing widgets, Mission Control)
/// and after Ditherglow quits, so this keeps the desktop looking like Ditherglow then too.
/// Turning it off puts back the pictures it replaced.
@MainActor
final class StaticWallpaper {
    /// The palette follows the sun slowly; a few minutes between stills is invisible.
    private static let interval: TimeInterval = 10 * 60
    /// Our own stills, so an earlier one is never mistaken for the user's picture.
    private static let folder = URL.applicationSupportDirectory.appending(path: "Ditherglow/Wallpaper", directoryHint: .isDirectory)

    /// The settings a still depends on; a refresh is only worth it when one of them changes.
    private struct Look: Equatable {
        var enabled: Bool
        var blockSize: Double
        var grain: Double
        var location: [String?]
    }

    private var look: Look?
    private var timer: Timer?
    private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []
    private var pending: Task<Void, Never>?

    init() {
        let defaults = NotificationCenter.default
        observe(defaults, NSApplication.didFinishLaunchingNotification) { $0.settingsChanged() }
        // Also fires for window frames and Sparkle's own keys, so `Look` filters those out.
        observe(defaults, UserDefaults.didChangeNotification) { $0.settingsChanged() }
        observe(defaults, NSApplication.didChangeScreenParametersNotification) { $0.scheduleRefresh() }
        // The clock may have jumped a few hours while asleep.
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification) { $0.scheduleRefresh() }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping @MainActor (StaticWallpaper) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self)
            }
        }
        observers.append((center, token))
    }

    private static func currentLook() -> Look {
        let defaults = UserDefaults.standard
        return Look(
            enabled: defaults.object(forKey: Preferences.staticWallpaperKey) as? Bool ?? Preferences.defaultStaticWallpaper,
            blockSize: defaults.object(forKey: Preferences.blockSizeKey) as? Double ?? Preferences.defaultBlockSize,
            grain: defaults.object(forKey: Preferences.grainKey) as? Double ?? Preferences.defaultGrain,
            location: [
                Preferences.locationModeKey, Preferences.cityKey,
                Preferences.currentLatitudeKey, Preferences.currentLongitudeKey,
            ].map { defaults.object(forKey: $0).map { "\($0)" } }
        )
    }

    private func settingsChanged() {
        let new = Self.currentLook()
        guard new != look else { return }
        let wasEnabled = look?.enabled ?? false
        look = new
        if new.enabled {
            if timer == nil {
                timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.scheduleRefresh() }
                }
                timer?.tolerance = 60
            }
            scheduleRefresh()
        } else {
            timer?.invalidate()
            timer = nil
            pending?.cancel()
            if wasEnabled { restoreOriginals() }
        }
    }

    /// Coalesces bursts, such as dragging the pixel size slider.
    private func scheduleRefresh() {
        guard look?.enabled == true else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private func refresh() async {
        guard let look, look.enabled else { return }
        let workspace = NSWorkspace.shared
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        var written: Set<URL> = []

        // Same seeds as `DesktopWindowController`, so the still matches the animated sky underneath it.
        for (index, screen) in NSScreen.screens.enumerated() {
            guard let id = screen.displayID else { continue }
            rememberOriginal(of: screen, id: id)
            guard let image = Self.render(screen: screen, seed: Float(index) * 3.7, look: look) else { continue }
            // A new name each time: the Dock caches desktop pictures by URL.
            let url = Self.folder.appending(path: "sky-\(id)-\(stamp).heic")
            guard await Self.write(image, to: url) else { continue }
            guard !Task.isCancelled, self.look?.enabled == true else { return }
            try? workspace.setDesktopImageURL(url, for: screen, options: [
                .imageScaling: NSImageScaling.scaleAxesIndependently.rawValue,
                .allowClipping: true,
            ])
            written.insert(url)
        }
        removeStills(except: written)
    }

    private static func render(screen: NSScreen, seed: Float, look: Look) -> CGImage? {
        let scale = screen.backingScaleFactor
        let size = screen.frame.size
        let view = DitherglowView(seed: seed, blockSize: look.blockSize, grain: look.grain)
            .frame(width: size.width, height: size.height)
            .environment(\.displayScale, scale)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.cgImage
    }

    /// Encoded off the main actor: a 5K frame full of grain takes a moment to compress.
    private nonisolated static func write(_ image: CGImage, to url: URL) async -> Bool {
        await Task.detached(priority: .utility) {
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil) else { return false }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
            return CGImageDestinationFinalize(destination)
        }.value
    }

    private func removeStills(except keep: Set<URL>) {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        let keptNames = Set(keep.map(\.lastPathComponent))
        for file in files where !keptNames.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: Originals

    /// The user's own picture per display, saved the first time a still replaces it.
    private var originals: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: Preferences.originalWallpapersKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Preferences.originalWallpapersKey) }
    }

    private func rememberOriginal(of screen: NSScreen, id: UInt32) {
        guard let current = NSWorkspace.shared.desktopImageURL(for: screen),
              !current.path.hasPrefix(Self.folder.path) else { return }
        originals["\(id)"] = current.absoluteString
    }

    private func restoreOriginals() {
        let saved = originals
        for screen in NSScreen.screens {
            guard let id = screen.displayID,
                  let string = saved["\(id)"],
                  let url = URL(string: string),
                  FileManager.default.fileExists(atPath: url.path) else { continue }
            let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
        }
        // The last stills stay on disk: a display whose picture couldn't be restored still shows one.
        originals = [:]
    }
}

private extension NSScreen {
    /// Stable across launches and screen reordering, unlike the index in `NSScreen.screens`.
    var displayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
