import AppKit
import SwiftUI

/// Puts a borderless window behind the desktop icons on every screen, hosting `DitherglowView`.
/// The system wallpaper API only takes still images, so this is how the sky gets animated.
@MainActor
@Observable
final class DesktopWindowController {
    private(set) var isEnabled = false
    @ObservationIgnored private var windows: [NSWindow] = []
    @ObservationIgnored private var screenObserver: (any NSObjectProtocol)?

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        enabled ? start() : stop()
    }

    private func start() {
        rebuildWindows()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildWindows() }
        }
    }

    private func stop() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
        windows.forEach { $0.orderOut(nil) }
        windows = []
    }

    /// Screens come and go (displays plugged in, resolution changes), so rebuild from scratch.
    private func rebuildWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.enumerated().map { makeWindow(for: $1, seed: Float($0) * 3.7) }
    }

    private func makeWindow(for screen: NSScreen, seed: Float) -> NSWindow {
        let window = NSWindow(
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
        window.contentView = NSHostingView(rootView: DitherglowView(seed: seed))
        window.setFrame(screen.frame, display: true)
        window.orderFront(nil)
        return window
    }
}
