import SwiftUI

@main
struct DitherglowApp: App {
    @State private var desktop = DesktopWindowController()
    @State private var updater = Updater()
    @State private var sunTimes = SunTimes()
    @State private var currentLocation = CurrentLocation()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Ditherglow", id: "main") {
            ContentView()
                .environment(updater)
                .environment(currentLocation)
        }
        .windowResizability(.contentSize)
        .suppressedAtLaunch()

        Window("About Ditherglow", id: "about") {
            AboutView()
                .environment(updater)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .suppressedAtLaunch()

        MenuBarExtra {
            SunMenuSection(sun: sunTimes)
            Section {
                Toggle("Animated Wallpaper", isOn: Binding(
                    get: { desktop.isEnabled },
                    set: { desktop.setEnabled($0) }
                ))
            }
            Section {
                Button("Preview & Settings…") {
                    bringToFront("main") { openWindow(id: "main") }
                }
                .keyboardShortcut(",")
                Button("About Ditherglow") {
                    bringToFront("about") { openWindow(id: "about") }
                }
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }
            Section {
                Button("Quit Ditherglow") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        } label: {
            Image(nsImage: MenuBarIcon.image(enabled: desktop.isEnabled))
                .accessibilityLabel("Ditherglow")
        }
    }
}

/// A menu bar app isn't active when its menu is used, and macOS's cooperative activation can leave
/// a window it opens behind the frontmost app. So activate first, then raise the window once it exists.
/// `identifier` is the prefix of the window's `NSWindow.identifier`, which SwiftUI derives from the scene.
@MainActor
private func bringToFront(_ identifier: String, open: () -> Void) {
    NSApp.activate()
    open()
    DispatchQueue.main.async {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(identifier) == true }) else { return }
        window.orderFrontRegardless()
        window.makeKey()
    }
}

private extension Scene {
    /// A menu bar app shouldn't open a window on launch, but SwiftUI opens the first `Window` scene unless told not to.
    func suppressedAtLaunch() -> some Scene {
        if #available(macOS 15, *) {
            return defaultLaunchBehavior(.suppressed)
        } else {
            return self
        }
    }
}
