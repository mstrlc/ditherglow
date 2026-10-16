import SwiftUI

/// The menu's sun section: the sky's phase and a countdown, today's times, golden and blue hour, and day length.
struct SunMenuSection: View {
    let sun: SunTimes

    var body: some View {
        Section(sun.place.map { "Sun in \($0)" } ?? "Sun Today") {
            Group {
                if let next = sun.next {
                    Text("\(sun.phase) · \(next.isSunrise ? "Sunrise" : "Sunset") in \(duration(next.date.timeIntervalSinceNow))")
                } else {
                    Text(sun.phase)
                }
                Text(riseAndSet)
                if let length = sun.dayLength {
                    Text(dayLength(length, change: sun.dayLengthChange))
                }
            }
            .help("The sky's colours follow the sun here. The place comes from your time zone, so no location access is needed.")
            // Tucked into a submenu: handy, but not worth two more lines every time the menu opens.
            if sun.goldenHour != nil || sun.blueHour != nil {
                Menu("Golden & Blue Hour") {
                    if let band = sun.goldenHour {
                        Text(describe("Golden Hour", band))
                    }
                    if let band = sun.blueHour {
                        Text(describe("Blue Hour", band))
                    }
                }
            }
        }
    }

    /// Both of today's times on one line, e.g. "Sunrise 07:25 · Sunset 18:09".
    private var riseAndSet: String {
        let parts = [sun.sunrise.map { "Sunrise \(time($0))" }, sun.sunset.map { "Sunset \(time($0))" }].compactMap(\.self)
        return parts.isEmpty ? "No Sunrise or Sunset Today" : parts.joined(separator: " · ")
    }

    private func describe(_ name: String, _ band: SunTimes.Band) -> String {
        band.isNow ? "\(name) until \(time(band.date))" : "\(name) \(time(band.date))"
    }

    private func dayLength(_ length: TimeInterval, change: TimeInterval?) -> String {
        let text = "Daylight \(duration(length))"
        // Under a minute rounds to "0m", which says nothing.
        guard let change, abs(change) >= 60 else { return text }
        return "\(text), \(duration(abs(change))) \(change > 0 ? "longer" : "shorter")"
    }

    /// Clock time, with "Tomorrow" when it isn't today (e.g. golden hour after the evening's has passed).
    private func time(_ date: Date) -> String {
        let clock = date.formatted(.dateTime.hour().minute())
        return Calendar.current.isDateInToday(date) ? clock : "Tomorrow \(clock)"
    }

    /// Hours and minutes, e.g. "2h 41m".
    private func duration(_ interval: TimeInterval) -> String {
        Duration.seconds(max(interval, 0)).formatted(.units(allowed: [.hours, .minutes], width: .narrow, maximumUnitCount: 2))
    }
}
