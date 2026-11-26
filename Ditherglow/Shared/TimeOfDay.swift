import Foundation

/// Hours since midnight, for the time-of-day scrubbers in the Mac preview and the iOS ambient screen.
nonisolated enum TimeOfDay {
    /// Hours since local midnight, in 0..<24.
    static func hour(of date: Date, calendar: Calendar = .current) -> Double {
        date.timeIntervalSince(calendar.startOfDay(for: date)) / 3600
    }

    /// `hour` hours past midnight on `day`.
    static func date(hour: Double, on day: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: day).addingTimeInterval(hour * 3600)
    }

    /// The time, the sky's phase and the sun's altitude, e.g. "9:41 PM · Blue Hour -5°".
    static func summary(of date: Date) -> String {
        let altitude = Sky.altitude(at: date)
        return "\(date.formatted(date: .omitted, time: .shortened)) · \(Sky.phase(altitude: altitude)) "
            + String(format: "%.0f°", altitude)
    }
}
