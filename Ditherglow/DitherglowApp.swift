import SwiftUI

@main
struct DitherglowApp: App {
    @State private var desktop = DesktopWindowController()
    @State private var updater = Updater()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some Scene {
        Window("Ditherglow Preview", id: "preview") {
            ContentView()
        }
        .suppressedAtLaunch()

        Settings {
            SettingsView()
                .environment(updater)
        }

        MenuBarExtra {
            Toggle("Animated Wallpaper", isOn: Binding(
                get: { desktop.isEnabled },
                set: { desktop.setEnabled($0) }
            ))
            Button("Show Preview") {
                openWindow(id: "preview")
                NSApp.activate()
            }
            Button("Settings…") {
                openSettings()
                NSApp.activate()
            }
            .keyboardShortcut(",")
            Button("Check for Updates…") {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)
            Divider()
            Button("Quit Ditherglow") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(nsImage: MenuBarIcon.image(enabled: desktop.isEnabled))
                .accessibilityLabel("Ditherglow")
        }
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
