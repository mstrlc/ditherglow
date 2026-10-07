import SwiftUI

@main
struct DitherglowApp: App {
    @State private var desktop = DesktopWindowController()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some Scene {
        Window("Ditherglow Preview", id: "preview") {
            ContentView()
        }

        Settings {
            SettingsView()
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
            Divider()
            Button("Quit Ditherglow") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(nsImage: Self.menuBarIcon(enabled: desktop.isEnabled))
                .accessibilityLabel("Ditherglow")
        }
    }

    /// Sparkles when the wallpaper is on, a single dimmed sparkle when it's off.
    /// The dimming is baked into the template image's alpha, since the status item renders the label as an image.
    private static func menuBarIcon(enabled: Bool) -> NSImage {
        let symbol = NSImage(systemSymbolName: enabled ? "sparkles" : "sparkle", accessibilityDescription: nil)!
        guard !enabled else { return symbol }
        let dimmed = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.4)
            return true
        }
        dimmed.isTemplate = true
        return dimmed
    }
}
