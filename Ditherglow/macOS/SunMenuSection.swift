import SwiftUI

/// The menu's sun section: place and phase as the header, then sunrise and sunset with a countdown
/// on whichever comes next, and day length. Golden or blue hour only appears when it's close.
struct SunMenuSection: View {
    let sun: SunTimes

    /// How soon golden or blue hour has to start to earn a line of its own.
    private static let bandLeadTime: TimeInterval = 3600

    var body: some View {
        Section(sun.place.map { "\($0) — \(sun.phase)" } ?? sun.phase) {
            Group {
                if sunrise == nil, sunset == nil {
                    Text("No Sunrise or Sunset Today")
                }
                if let sunrise {
                    Label(event(sunrise, isSunrise: true), systemImage: "sunrise")
                }
                if let sunset {
                    Label(event(sunset, isSunrise: false), systemImage: "sunset")
                }
                if let length = sun.dayLength {
                    Label(dayLength(length, change: sun.dayLengthChange), systemImage: "sun.max")
                }
                if let band = sun.goldenHour, isSoon(band) {
                    Label(describe("Golden hour", band), systemImage: "sun.horizon")
                } else if let band = sun.blueHour, isSoon(band) {
                    Label(describe("Blue hour", band), systemImage: "moon.haze")
                }
            }
            // Menus drop a label's icon by default; the symbols are what make these lines scannable.
            .labelStyle(.titleAndIcon)
            .help(help)
        }
    }

    /// The next sunrise when it's the coming event (tomorrow's, after sunset), otherwise today's.
    private var sunrise: Date? {
        if let next = sun.next, next.isSunrise { return next.date }
        return sun.sunrise
    }

    private var sunset: Date? {
        if let next = sun.next, !next.isSunrise { return next.date }
        return sun.sunset
    }

    /// "18:01 · in 15m" for the coming event, the bare time otherwise.
    private func event(_ date: Date, isSunrise: Bool) -> String {
        guard let next = sun.next, next.isSunrise == isSunrise, next.date == date else { return time(date) }
        return "\(time(date)) · in \(duration(date.timeIntervalSinceNow))"
    }

    private func isSoon(_ band: SunTimes.Band) -> Bool {
        band.isNow || band.date.timeIntervalSinceNow < Self.bandLeadTime
    }

    private func describe(_ name: String, _ band: SunTimes.Band) -> String {
        band.isNow ? "\(name) until \(time(band.date))" : "\(name) from \(time(band.date))"
    }

    /// Both twilight times are always one hover away, even when neither is close enough for a line.
    private var help: String {
        let bands = [
            sun.goldenHour.map { describe("Golden hour", $0) },
            sun.blueHour.map { describe("Blue hour", $0) },
        ].compactMap(\.self)
        let place = "The sky's colours follow the sun here. The place comes from your time zone, so no location access is needed."
        return bands.isEmpty ? place : "\(bands.joined(separator: ", ")).\n\(place)"
    }

    private func dayLength(_ length: TimeInterval, change: TimeInterval?) -> String {
        let text = "\(duration(length)) of daylight"
        // Under a minute rounds to "0m", which says nothing.
        guard let change, abs(change) >= 60 else { return text }
        return "\(text) (\(change > 0 ? "+" : "−")\(duration(abs(change))))"
    }

    /// Clock time, with "Tomorrow" when it isn't today (e.g. the next sunrise after sunset).
    private func time(_ date: Date) -> String {
        let clock = date.formatted(.dateTime.hour().minute())
        return Calendar.current.isDateInToday(date) ? clock : "Tomorrow \(clock)"
    }

    /// Hours and minutes, e.g. "2h 41m".
    private func duration(_ interval: TimeInterval) -> String {
        Duration.seconds(max(interval, 0)).formatted(.units(allowed: [.hours, .minutes], width: .narrow, maximumUnitCount: 2))
    }
}
