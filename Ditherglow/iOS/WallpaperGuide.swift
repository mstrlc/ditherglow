import SwiftUI

/// How to get a wallpaper that follows the sun: iOS doesn't let apps set the wallpaper, but Shortcuts can,
/// with Render Sky feeding Set Wallpaper Photo from time-of-day automations.
struct WallpaperGuide: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                Text("iOS doesn't let apps change the wallpaper, but Shortcuts can. ")
                    + Text("Ditherglow adds a Render Sky action; one shortcut and a few automations keep your wallpaper in step with the sky.")
            }

            Section("1. Make the shortcut") {
                Step(number: 1, text: "In Shortcuts, tap + to make a new shortcut and name it Ditherglow Sky.")
                Step(number: 2, text: "Add Ditherglow's Render Sky action.")
                Step(number: 3, text: "Add Set Wallpaper Photo after it, pick your wallpaper and turn off Show Preview.")
                Button("Open Shortcuts", systemImage: "arrow.up.forward.app") {
                    openURL(URL(string: "shortcuts://")!)
                }
            }

            Section {
                Step(number: 1, text: "In Shortcuts' Automation tab, make a new Time of Day automation for each time below.")
                Step(number: 2, text: "Choose Run Immediately, then Run Shortcut › Ditherglow Sky.")
                ForEach(SuggestedTime.today(), id: \.label) { time in
                    LabeledContent(time.label) {
                        VStack(alignment: .trailing) {
                            Text(time.date, format: .dateTime.hour().minute())
                                .monospacedDigit()
                            Text(time.phase)
                                .font(.caption)
                        }
                    }
                }
            } header: {
                Text("2. Run it through the day")
            } footer: {
                Text("Times are for today at your location. Shortcuts finds sunrise and sunset itself, so its times may differ a little.")
            }
        }
        .navigationTitle("Wallpaper That Follows the Sun")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct Step: View {
    let number: Int
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(.tint, in: .circle)
        }
    }
}

/// A time-of-day trigger worth automating, with when it falls today and what the sky looks like then.
private struct SuggestedTime {
    let label: String
    let date: Date
    let phase: String

    /// Offsets from sunrise and sunset that land on each named phase, plus midday.
    /// Empty in polar day or night, when the sun doesn't rise or set.
    static func today() -> [Self] {
        let location = Sun.location()
        let (rise, set) = Sun.riseAndSet(on: .now, location)
        guard let rise, let set else { return [] }
        let midday = rise.addingTimeInterval(set.timeIntervalSince(rise) / 2)
        let times: [(String, Date)] = [
            ("Sunrise − 30 min", rise.addingTimeInterval(-30 * 60)),
            ("Sunrise", rise),
            ("Sunrise + 1 h", rise.addingTimeInterval(3600)),
            ("Midday", midday),
            ("Sunset − 1 h", set.addingTimeInterval(-3600)),
            ("Sunset", set),
            ("Sunset + 30 min", set.addingTimeInterval(30 * 60)),
            ("Sunset + 1 h 30 min", set.addingTimeInterval(90 * 60)),
        ]
        return times.map { Self(label: $0.0, date: $0.1, phase: Sky.phase(altitude: Sky.altitude(at: $0.1))) }
    }
}

#Preview {
    NavigationStack {
        WallpaperGuide()
    }
}
