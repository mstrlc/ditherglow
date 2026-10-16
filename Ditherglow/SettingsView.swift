import CoreLocation
import ServiceManagement
import SwiftUI

/// Settings, under the preview: where the sun is followed, how big the dither pixels are, how fast the blobs drift,
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
            Section {
                LabeledContent {
                    HStack {
                        Slider(value: $blockSize, in: Preferences.blockSizeRange, step: 1)
                        Text("\(Int(blockSize)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                    .frame(width: 220)
                } label: {
                    SettingLabel("Pixel size", systemImage: "square.grid.3x3.fill", color: .purple)
                }
                LabeledContent {
                    HStack {
                        Slider(value: $speed, in: Preferences.speedRange)
                        Text(Preferences.loopDuration(speed: speed), format: .units(allowed: [.minutes, .seconds], width: .narrow, maximumUnitCount: 1))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                    .frame(width: 220)
                } label: {
                    SettingLabel("Speed", systemImage: "hare.fill", color: .orange)
                }
                .help("Roughly how long one blob takes to loop around")
            } header: {
                Text("Appearance")
            } footer: {
                HStack {
                    Spacer()
                    Button("Restore Defaults", systemImage: "arrow.counterclockwise") {
                        blockSize = Preferences.defaultBlockSize
                        speed = Preferences.defaultSpeed
                    }
                    .disabled(blockSize == Preferences.defaultBlockSize && speed == Preferences.defaultSpeed)
                }
            }

            Section {
                Picker(selection: $locationMode) {
                    Text("Time Zone (\(Sun.location(in: .current).name ?? TimeZone.current.identifier))").tag(Preferences.LocationMode.timeZone)
                    Text("A City").tag(Preferences.LocationMode.city)
                    Text("Current Location").tag(Preferences.LocationMode.current)
                } label: {
                    SettingLabel("Follow the sun in", systemImage: "sun.horizon.fill", color: .yellow)
                }
                switch locationMode {
                case .timeZone:
                    EmptyView()
                case .city:
                    Picker(selection: $city) {
                        ForEach(Self.regions, id: \.name) { region in
                            Section(region.name) {
                                ForEach(region.cities) { city in
                                    Text("\(city.name), \(Locale.current.localizedString(forRegionCode: city.countryCode) ?? city.countryCode)")
                                        .tag(city.id)
                                }
                            }
                        }
                    } label: {
                        SettingLabel("City", systemImage: "building.2.fill", color: .blue)
                    }
                case .current:
                    LabeledContent {
                        currentLocationStatus
                    } label: {
                        SettingLabel("Location", systemImage: "location.fill", color: .blue)
                    }
                }
            } header: {
                Text("Sun")
            } footer: {
                if locationMode == .timeZone {
                    Text("Your time zone's city needs no permission, but can be hours of sunlight off in a wide time zone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("General") {
                Toggle(isOn: Binding(
                    get: { launchAtLogin },
                    // A closure, not the method itself: Swift 6.3 (Xcode 26) crashes generating code for the method reference.
                    set: { setLaunchAtLogin($0) }
                )) {
                    SettingLabel("Launch at login", systemImage: "power", color: .green)
                }
                Toggle(isOn: Bindable(updater).automaticallyChecksForUpdates) {
                    SettingLabel("Automatically check for updates", systemImage: "arrow.triangle.2.circlepath", color: .gray)
                }
            }
        }
        .formStyle(.grouped)
        // Sized to its sections rather than scrolling: the window fits its content.
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
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

/// A row title with its symbol on a coloured tile, as System Settings draws them.
private struct SettingLabel: View {
    let title: String
    let systemImage: String
    let color: Color

    init(_ title: String, systemImage: String, color: Color) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(color.gradient, in: .rect(cornerRadius: 5))
        }
    }
}

#Preview {
    SettingsView()
        .environment(Updater())
        .environment(CurrentLocation())
}
