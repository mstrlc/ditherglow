import AppKit
import SwiftUI

/// Puts a borderless window behind the desktop icons on every screen, hosting `DitherglowView`.
/// The system wallpaper API only takes still images, so this is how the sky gets animated.
@MainActor
@Observable
final class DesktopWindowController {
    private(set) var isEnabled = false
    /// True while every display sleeps or the session is locked or switched away: nobody can see any screen.
    private(set) var isSuspended = false
    @ObservationIgnored private var windows: [DesktopWindow] = []
    @ObservationIgnored private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []
    @ObservationIgnored private var launchObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var screensAsleep = false { didSet { updateSuspended() } }
    @ObservationIgnored private var sessionInactive = false { didSet { updateSuspended() } }
    @ObservationIgnored private var screenLocked = false { didSet { updateSuspended() } }

    /// Created with the `App`, before `NSApp` has finished launching, so restoring the saved state waits for that.
    init() {
        let saved = UserDefaults.standard.object(forKey: Preferences.wallpaperEnabledKey) as? Bool
        guard saved ?? Preferences.defaultWallpaperEnabled else { return }
        launchObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let launchObserver = self.launchObserver {
                    NotificationCenter.default.removeObserver(launchObserver)
                }
                self.launchObserver = nil
                self.setEnabled(true)
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Preferences.wallpaperEnabledKey)
        enabled ? start() : stop()
    }

    private func start() {
        rebuildWindows()
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { $0.rebuildWindows() }

        // Display sleep and fast user switching come from the workspace; locking only as a distributed notification.
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.screensAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.screensAsleep = false }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionInactive = true }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionInactive = false }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, .init("com.apple.screenIsLocked")) { $0.screenLocked = true }
        observe(distributed, .init("com.apple.screenIsUnlocked")) { $0.screenLocked = false }
    }

    private func stop() {
        observers.forEach { $0.center.removeObserver($0.token) }
        observers = []
        windows.forEach { $0.close() }
        windows = []
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping @MainActor (DesktopWindowController) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self)
            }
        }
        observers.append((center, token))
    }

    private func updateSuspended() {
        let suspended = screensAsleep || sessionInactive || screenLocked
        if suspended != isSuspended { isSuspended = suspended }
    }

    /// Screens come and go (displays plugged in, resolution changes), so rebuild from scratch.
    private func rebuildWindows() {
        windows.forEach { $0.close() }
        windows = NSScreen.screens.enumerated().map { DesktopWindow(screen: $1, seed: Float($0) * 3.7, controller: self) }
    }
}

/// One screen's sky window. Pauses on its own while fully covered, e.g. by a fullscreen app. A maximised
/// window doesn't count: the translucent menu bar still shows the sky. Other screens keep drawing.
@MainActor
@Observable
private final class DesktopWindow {
    private(set) var isOccluded = false
    @ObservationIgnored private let window: NSWindow
    @ObservationIgnored private var occlusionObserver: (any NSObjectProtocol)?

    init(screen: NSScreen, seed: Float, controller: DesktopWindowController) {
        window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        // Desktop level sits above the real wallpaper but below the desktop icons.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.contentView = NSHostingView(rootView: DesktopSkyView(seed: seed, window: self, controller: controller))
        window.setFrame(screen.frame, display: true)
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let occluded = !self.window.occlusionState.contains(.visible)
                if occluded != self.isOccluded { self.isOccluded = occluded }
            }
        }
        window.orderFront(nil)
    }

    func close() {
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
        }
        occlusionObserver = nil
        window.orderOut(nil)
        // The hosted view holds this object, so drop it to break the cycle through the window.
        window.contentView = nil
    }
}

/// The wallpaper's sky, kept in sync with the Settings window.
private struct DesktopSkyView: View {
    let seed: Float
    let window: DesktopWindow
    let controller: DesktopWindowController
    @AppStorage(Preferences.blockSizeKey) private var blockSize = Preferences.defaultBlockSize
    @AppStorage(Preferences.speedKey) private var speed = Preferences.defaultSpeed

    var body: some View {
        DitherglowView(
            speed: speed,
            seed: seed,
            blockSize: blockSize,
            isPaused: window.isOccluded || controller.isSuspended
        )
    }
}
