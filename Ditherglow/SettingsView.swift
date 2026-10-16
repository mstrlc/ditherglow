import CoreLocation
import ServiceManagement
import SwiftUI

/// Settings window: where the sun is followed, how big the dither pixels are, how fast the blobs drift,
/// launching at login and update checks.
struct SettingsView: View {
    @AppStorage(Preferences.blockSizeKey) private var blockSize = Preferences.defaultBlockSize
    @AppStorage(Preferences.speedKey) private var speed = Preferences.defaultSpeed
    @AppStorage(Preferences.locationModeKey) private var locationMode = Preferences.defaultLocationMode
    @AppStorage(Preferences.cityKey) private var city = TimeZone.current.identifier
    @AppStorage(Preferences.currentPlaceKey) private var currentPlace: String?
    @AppStorage(Preferences.currentLatitudeKey) private var currentLatitude: Double?
    /// Mirrors `SMAppService` rather than `UserDefaults`, since the user can also change it in System Settings.
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Environment(Updater.self) private var updater
    @Environment(CurrentLocation.self) private var currentLocation

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin },
                // A closure, not the method itself: Swift 6.3 (Xcode 26) crashes generating code for the method reference.
                set: { setLaunchAtLogin($0) }
            ))
            Toggle("Automatically check for updates", isOn: Bindable(updater).automaticallyChecksForUpdates)
            Picker("Follow the sun in", selection: $locationMode) {
                Text("Time Zone (\(Sun.location(in: .current).name ?? TimeZone.current.identifier))").tag(Preferences.LocationMode.timeZone)
                Text("A City").tag(Preferences.LocationMode.city)
                Text("Current Location").tag(Preferences.LocationMode.current)
            }
            .help("Your time zone's city needs no permission, but can be hours of sunlight off in a wide time zone.")
            switch locationMode {
            case .timeZone:
                EmptyView()
            case .city:
                Picker("City", selection: $city) {
                    ForEach(Self.regions, id: \.name) { region in
                        Section(region.name) {
                            ForEach(region.cities) { city in
                                Text("\(city.name), \(Locale.current.localizedString(forRegionCode: city.countryCode) ?? city.countryCode)")
                                    .tag(city.id)
                            }
                        }
                    }
                }
            case .current:
                LabeledContent("Location") {
                    currentLocationStatus
                }
            }
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

    /// zone.tab's cities by their identifier's region ("Africa", "America", …), so the long list has signposts.
    private static let regions: [(name: String, cities: [Sun.City])] = Dictionary(grouping: Sun.cities, by: \.region)
        .map { ($0.key, $0.value) }
        .sorted { $0.name < $1.name }

    @ViewBuilder private var currentLocationStatus: some View {
        switch currentLocation.authorization {
        case .denied, .restricted:
            HStack {
                Text("Access denied")
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
                }
            }
        case .notDetermined:
            Text("Waiting for access…")
        default:
            if let currentPlace {
                Text(currentPlace)
            } else if currentLatitude != nil {
                Text("Found")
            } else {
                Text(currentLocation.failed ? "Couldn't find your location" : "Locating…")
            }
        }
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
        .environment(CurrentLocation())
}
