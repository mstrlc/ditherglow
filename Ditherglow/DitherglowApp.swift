import SwiftUI

@main
struct DitherglowApp: App {
    @State private var desktop = DesktopWindowController()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Ditherglow Preview", id: "preview") {
            ContentView()
        }

        MenuBarExtra("Ditherglow", systemImage: "sun.horizon") {
            Toggle("Animated Wallpaper", isOn: Binding(
                get: { desktop.isEnabled },
                set: { desktop.setEnabled($0) }
            ))
            Button("Show Preview") {
                openWindow(id: "preview")
                NSApp.activate()
            }
            Divider()
            Button("Quit Ditherglow") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
