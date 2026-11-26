import SwiftUI

/// The ambient screen's settings: the look of the sky, the clock, staying awake, and where the sun is followed.
struct SettingsSheet: View {
    /// The moment the sky is showing, for sharing it as a wallpaper.
    var skyDate: Date
    @AppStorage(Preferences.blockSizeKey) private var blockSize = Preferences.defaultBlockSize
    @AppStorage(Preferences.speedKey) private var speed = Preferences.defaultSpeed
    @AppStorage(Preferences.showsClockKey) private var showsClock = Preferences.defaultShowsClock
    @AppStorage(Preferences.keepAwakeKey) private var keepAwake = Preferences.defaultKeepAwake
    @AppStorage(Preferences.locationModeKey) private var locationMode = Preferences.defaultLocationMode
    @AppStorage(Preferences.cityKey) private var city = TimeZone.current.identifier
    @Environment(\.dismiss) private var dismiss
    /// How far along the Live Photo is while it renders; `nil` when not saving one.
    @State private var livePhotoProgress: Double?
    @State private var livePhotoResult: LivePhotoResult?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        WallpaperGuide()
                    } label: {
                        Label("Wallpaper That Follows the Sun", systemImage: "sun.horizon")
                    }
                    ShareLink(
                        item: WallpaperFile(date: skyDate),
                        preview: SharePreview("Ditherglow Wallpaper", image: sharePreview)
                    ) {
                        Label("Share This Sky as a Wallpaper", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        saveLivePhoto()
                    } label: {
                        if let livePhotoProgress {
                            LabeledContent {
                                ProgressView(value: livePhotoProgress)
                                    .frame(width: 80)
                            } label: {
                                Label("Saving Live Photo…", systemImage: "livephoto")
                            }
                        } else {
                            Label("Save as Live Photo", systemImage: "livephoto")
                        }
                    }
                    .disabled(livePhotoProgress != nil)
                    #if DEBUG
                        // Temporary: saves the same sky at each white level, to pick `LivePhoto.white` by eye on a phone.
                        Button("Save Brightness Tests (203, 140, 100 nits)", systemImage: "sun.max") {
                            saveLivePhoto(whites: [203, 140, 100])
                        }
                        .disabled(livePhotoProgress != nil)
                    #endif
                } header: {
                    Text("Wallpaper")
                } footer: {
                    Text("Share saves a still. A Live Photo wallpaper drifts for a moment each time your phone wakes.")
                }

                Section {
                    LabeledContent("Pixel Size") {
                        Text("\(Int(blockSize)) pt")
                            .monospacedDigit()
                    }
                    Slider(value: $blockSize, in: Preferences.blockSizeRange, step: 1)
                    LabeledContent("Speed") {
                        Text(Preferences.loopDuration(speed: speed), format: .units(allowed: [.minutes, .seconds], width: .narrow, maximumUnitCount: 1))
                            .monospacedDigit()
                    }
                    Slider(value: $speed, in: Preferences.speedRange)
                    Button("Restore Defaults") {
                        blockSize = Preferences.defaultBlockSize
                        speed = Preferences.defaultSpeed
                    }
                    .disabled(blockSize == Preferences.defaultBlockSize && speed == Preferences.defaultSpeed)
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Speed is roughly how long one blob takes to loop around.")
                }

                Section {
                    Toggle("Show Clock", isOn: $showsClock)
                    Picker("Keep Screen On", selection: $keepAwake) {
                        Text("Never").tag(Preferences.KeepAwake.never)
                        Text("While Charging").tag(Preferences.KeepAwake.whileCharging)
                        Text("Always").tag(Preferences.KeepAwake.always)
                    }
                } header: {
                    Text("Ambient")
                } footer: {
                    Text("Keeps the sky up instead of auto-locking while Ditherglow is open.")
                }

                Section {
                    Picker("Follow the Sun In", selection: $locationMode) {
                        Text("Time Zone").tag(Preferences.LocationMode.timeZone)
                        Text("A City").tag(Preferences.LocationMode.city)
                    }
                    if locationMode == .city {
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
                        .pickerStyle(.navigationLink)
                    }
                } header: {
                    Text("Sun")
                } footer: {
                    if locationMode == .timeZone {
                        let zoneCity = Sun.location(in: .current).name ?? TimeZone.current.identifier
                        Text("Uses \(zoneCity), your time zone's city. It needs no permission, but can be hours of sunlight off in a wide time zone.")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .alert(livePhotoResult?.title ?? "", isPresented: Binding(
            get: { livePhotoResult != nil },
            set: { if !$0 { livePhotoResult = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(livePhotoResult?.message ?? "")
        }
    }

    /// Saves one Live Photo per white level, in order, so the last one saved is the newest in Photos.
    private func saveLivePhoto(whites: [Double] = [LivePhoto.white]) {
        livePhotoProgress = 0
        let date = skyDate
        let spec = Wallpaper.Spec()
        Task {
            do {
                for (i, white) in whites.enumerated() {
                    try await LivePhoto.save(at: date, spec: spec, white: white) { progress in
                        Task { @MainActor in livePhotoProgress = (Double(i) + progress) / Double(whites.count) }
                    }
                }
                livePhotoResult = .saved
            } catch LivePhoto.Failure.notAllowed {
                livePhotoResult = .notAllowed
            } catch {
                livePhotoResult = .failed
            }
            livePhotoProgress = nil
        }
    }

    private enum LivePhotoResult {
        case saved, notAllowed, failed

        var title: String {
            switch self {
            case .saved: "Saved to Photos"
            case .notAllowed: "Can't Save to Photos"
            case .failed: "Couldn't Make the Live Photo"
            }
        }

        var message: String {
            switch self {
            case .saved:
                "In Settings › Wallpaper, add a new wallpaper from Photos, pick it and keep Live Photo on. "
                    + "If the Live Photo button is dimmed, iOS won't animate this one."
            case .notAllowed: "Allow Ditherglow to add photos in Settings › Privacy & Security › Photos."
            case .failed: "Something went wrong while rendering. Try again."
            }
        }
    }

    /// A thumbnail of the wallpaper for the share sheet; small enough to render on the spot.
    private var sharePreview: Image {
        guard let image = SkyImage.render(at: skyDate, size: CGSize(width: 60, height: 130), scale: 2, blockSize: 2) else {
            return Image(systemName: "sun.horizon")
        }
        return Image(decorative: image, scale: 2)
    }

    /// zone.tab's cities by their identifier's region ("Africa", "America", …), so the long list has signposts.
    private static let regions: [(name: String, cities: [Sun.City])] = Dictionary(grouping: Sun.cities, by: \.region)
        .map { ($0.key, $0.value) }
        .sorted { $0.name < $1.name }
}

#Preview {
    SettingsSheet(skyDate: .now)
}
