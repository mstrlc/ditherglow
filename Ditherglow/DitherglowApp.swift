import SwiftUI

@main
struct DitherglowApp: App {
    @State private var desktop = DesktopWindowController()
    @State private var updater = Updater()
    @State private var sunTimes = SunTimes()
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
            Section(sunTimes.place.map { "Sun in \($0)" } ?? "Sun Today") {
                Group {
                    if let sunrise = sunTimes.sunrise {
                        Text("Sunrise \(sunrise, format: .dateTime.hour().minute())")
                    }
                    if let sunset = sunTimes.sunset {
                        Text("Sunset \(sunset, format: .dateTime.hour().minute())")
                    }
                    if sunTimes.sunrise == nil, sunTimes.sunset == nil {
                        Text("No Sunrise or Sunset Today")
                    }
                }
                .help("The sky's colours follow the sun here. The place comes from your time zone, so no location access is needed.")
            }
            Toggle("Animated Wallpaper", isOn: Binding(
                get: { desktop.isEnabled },
                set: { desktop.setEnabled($0) }
            ))
            Button("Show Preview") {
                openWindow(id: "preview")
                NSApp.activate()
            }
            Divider()
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
