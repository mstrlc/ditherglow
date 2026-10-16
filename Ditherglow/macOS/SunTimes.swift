import AppKit
import Observation

/// The sun at the place the sky's palette uses, for the menu: today's times, what's next and how long the day is.
/// Refreshed every minute so the countdown stays current, and at once on wake or a time zone change.
@Observable
final class SunTimes {
    /// Golden or blue hour: under way now until `date`, or next starting at `date`.
    struct Band: Equatable {
        let isNow: Bool
        let date: Date
    }

    /// Where the times are for, so a surprising time has an explanation.
    private(set) var place: String?
    /// The sky palette's phase right now, e.g. "Golden Hour".
    private(set) var phase = ""
    private(set) var sunrise: Date?
    private(set) var sunset: Date?
    /// The next sunrise or sunset, which may be tomorrow's; nil during polar day or night.
    private(set) var next: (isSunrise: Bool, date: Date)?
    private(set) var goldenHour: Band?
    private(set) var blueHour: Band?
    private(set) var dayLength: TimeInterval?
    /// Today's day length minus yesterday's.
    private(set) var dayLengthChange: TimeInterval?

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var ticker: Task<Void, Never>?

    init() {
        update()
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        })
        // The ticker's sleep doesn't count time the Mac spent asleep.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        })
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                // On the minute, so the countdown ticks over with the clock.
                let now = Date.now
                let minute = Calendar.current.nextDate(after: now, matching: DateComponents(second: 0), matchingPolicy: .nextTime) ?? now + 60
                try? await Task.sleep(for: .seconds(minute.timeIntervalSince(now)))
                self?.update()
            }
        }
    }

    private func update() {
        let now = Date.now
        let location = Sun.location()
        place = location.name
        let altitude = Sun.altitude(at: now, location)
        let rising = Sun.altitude(at: now + 600, location) > altitude
        // The palette uses one stop for morning and evening; name the one it is.
        phase = switch Sky.phase(altitude: altitude) {
        case "Sunrise & Sunset": rising ? "Sunrise" : "Sunset"
        case "Dusk" where rising: "Dawn"
        case let name: name
        }

        let today = Sun.riseAndSet(on: now, location)
        sunrise = today.rise
        sunset = today.set
        next = Sun.nextEvent(after: now, location).map { (!Sun.isUp(at: now, location), $0) }

        goldenHour = band(Sun.goldenHour, at: now, location)
        blueHour = band(Sun.blueHour, at: now, location)

        dayLength = length(today)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now).map { Sun.riseAndSet(on: $0, location) }
        if let dayLength, let before = yesterday.flatMap(length) {
            dayLengthChange = dayLength - before
        } else {
            dayLengthChange = nil
        }
    }

    private func band(_ range: ClosedRange<Double>, at now: Date, _ location: Sun.Location) -> Band? {
        let isNow = range.contains(Sun.altitude(at: now, location))
        return Sun.nextChange(after: now, location) { range.contains($0) }.map { Band(isNow: isNow, date: $0) }
    }

    /// Sunrise to sunset; nil when either is missing, as in polar day or night.
    private func length(_ day: (rise: Date?, set: Date?)) -> TimeInterval? {
        guard let rise = day.rise, let set = day.set, set > rise else { return nil }
        return set.timeIntervalSince(rise)
    }
}
