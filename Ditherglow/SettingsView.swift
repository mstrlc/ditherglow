import ServiceManagement
import SwiftUI

/// Settings window: how big the dither pixels are, how fast the blobs drift, launching at login and update checks.
struct SettingsView: View {
    @AppStorage(Preferences.blockSizeKey) private var blockSize = Preferences.defaultBlockSize
    @AppStorage(Preferences.speedKey) private var speed = Preferences.defaultSpeed
    /// Mirrors `SMAppService` rather than `UserDefaults`, since the user can also change it in System Settings.
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Environment(Updater.self) private var updater

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin },
                set: setLaunchAtLogin
            ))
            Toggle("Automatically check for updates", isOn: Bindable(updater).automaticallyChecksForUpdates)
            LabeledContent("Pixel size") {
                Slider(value: $blockSize, in: Preferences.blockSizeRange, step: 1)
                Text("\(Int(blockSize)) pt")
                    .monospacedDigit()
                    .frame(width: 70, alignment: .trailing)
            }
            LabeledContent("Speed") {
                Slider(value: $speed, in: Preferences.speedRange)
                Text(Preferences.loopDuration(speed: speed), format: .units(allowed: [.minutes, .seconds], width: .narrow, maximumUnitCount: 1))
                    .monospacedDigit()
                    .frame(width: 70, alignment: .trailing)
            }
            .help("Roughly how long one blob takes to loop around")
            Button("Restore Defaults") {
                blockSize = Preferences.defaultBlockSize
                speed = Preferences.defaultSpeed
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Launch at login: \(error)")
        }
        // Re-read rather than trust `enabled`: registration can fail or need approval in System Settings.
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

#Preview {
    SettingsView()
        .environment(Updater())
}
