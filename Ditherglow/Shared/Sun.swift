import Foundation
import os

/// Sunrise and sunset from low-precision almanac formulas. Pure functions of date and place.
nonisolated enum Sun {
    struct Location: Equatable, Sendable {
        let latitude: Double
        let longitude: Double
        /// A place name for the menu, e.g. "Prague"; nil when the location is only a guess from the offset.
        let name: String?

        init(latitude: Double, longitude: Double, name: String? = nil) {
            self.latitude = latitude
            self.longitude = longitude
            self.name = name
        }
    }

    /// Sun's centre this far below the horizon counts as set (refraction + disc radius).
    static let horizon = -0.833

    static func isUp(at date: Date, _ location: Location) -> Bool {
        altitude(at: date, location) > horizon
    }

    /// Sun's altitude during golden hour, warm low light (a common photographers' definition).
    static let goldenHour = -4.0...6.0
    /// Sun's altitude during blue hour, after sunset or before sunrise.
    static let blueHour = -6.0...(-4.0)

    /// Next sunrise or sunset within two days, to about 30 seconds; nil during polar day/night.
    static func nextEvent(after date: Date, _ location: Location) -> Date? {
        nextChange(after: date, location) { $0 > horizon }
    }

    /// When `condition` on the sun's altitude next flips, within two days, to about 30 seconds.
    /// Five-minute steps still catch the shortest twilight bands, about eight minutes near the equator.
    static func nextChange(after date: Date, _ location: Location, of condition: (Double) -> Bool) -> Date? {
        func holds(_ date: Date) -> Bool { condition(altitude(at: date, location)) }
        let initial = holds(date)
        var lo = date
        for step in stride(from: 300.0, through: 2 * 86400, by: 300) {
            var hi = date + step
            guard holds(hi) != initial else { lo = hi; continue }
            while hi.timeIntervalSince(lo) > 30 {
                let mid = lo + hi.timeIntervalSince(lo) / 2
                if holds(mid) == initial { lo = mid } else { hi = mid }
            }
            return hi
        }
        return nil
    }

    /// The day's sunrise and sunset in `calendar`'s time zone; either is nil if it doesn't happen that day.
    static func riseAndSet(on date: Date, _ location: Location, calendar: Calendar = .current) -> (rise: Date?, set: Date?) {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return (nil, nil) }
        var rise: Date?, set: Date?
        var cursor = start
        // At most one rise and one set per day outside the polar circles; a third event is tomorrow's.
        for _ in 0..<2 {
            guard let event = nextEvent(after: cursor, location), event < end else { break }
            if isUp(at: event, location) { rise = rise ?? event } else { set = set ?? event }
            cursor = event
        }
        return (rise, set)
    }

    /// Solar altitude in degrees (good to about a minute of time).
    static func altitude(at date: Date, _ location: Location) -> Double {
        let rad = Double.pi / 180
        let d = date.timeIntervalSince1970 / 86400 - 10957.5 // days since J2000.0
        let g = (357.529 + 0.98560028 * d) * rad
        let q = 280.459 + 0.98564736 * d
        let lambda = (q + 1.915 * sin(g) + 0.020 * sin(2 * g)) * rad
        let epsilon = (23.439 - 0.00000036 * d) * rad
        let ra = atan2(cos(epsilon) * sin(lambda), cos(lambda))
        let dec = asin(sin(epsilon) * sin(lambda))
        let gmst = (18.697374558 + 24.06570982441908 * d) * 15 * rad
        let hourAngle = gmst + location.longitude * rad - ra
        let lat = location.latitude * rad
        return asin(sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(hourAngle)) / rad
    }

    // MARK: Location

    private static let cache = OSAllocatedUnfairLock<[String: Location]>(initialState: [:])

    /// Where the sky follows the sun, as chosen in Settings: the time zone's city (the default),
    /// a city picked from the list, or the last fix from Core Location.
    /// Cheap enough to call every frame: one `UserDefaults` read and a cached zone.tab lookup.
    static func location(defaults: UserDefaults = .standard) -> Location {
        let mode = defaults.string(forKey: Preferences.locationModeKey).flatMap(Preferences.LocationMode.init) ?? Preferences.defaultLocationMode
        switch mode {
        case .city:
            if let city = defaults.string(forKey: Preferences.cityKey), let location = zoneLocation(city) { return location }
        case .current:
            // Nothing saved yet (no fix, or access denied): fall back to the time zone until there is.
            if defaults.object(forKey: Preferences.currentLatitudeKey) != nil {
                return Location(
                    latitude: defaults.double(forKey: Preferences.currentLatitudeKey),
                    longitude: defaults.double(forKey: Preferences.currentLongitudeKey),
                    name: defaults.string(forKey: Preferences.currentPlaceKey)
                )
            }
        case .timeZone:
            break
        }
        return location(in: .current)
    }

    /// The time zone to show times in: a chosen city's own, so its sunrise isn't shown as "15:59";
    /// otherwise the Mac's, which is where the user is.
    static func timeZone(defaults: UserDefaults = .standard) -> TimeZone {
        let mode = defaults.string(forKey: Preferences.locationModeKey).flatMap(Preferences.LocationMode.init) ?? Preferences.defaultLocationMode
        guard mode == .city, let city = defaults.string(forKey: Preferences.cityKey) else { return .current }
        return TimeZone(identifier: city) ?? .current
    }

    /// Approximated by the time zone's reference city, so no location permission is needed.
    static func location(in zone: TimeZone) -> Location {
        zoneLocation(zone.identifier)
            // Unknown zone (e.g. "UTC"): longitude from the offset, a mid latitude.
            ?? Location(latitude: 45, longitude: Double(zone.secondsFromGMT()) / 240)
    }

    /// A zone.tab identifier's reference city, e.g. "Europe/Prague"; cached, since it's read every frame.
    private static func zoneLocation(_ identifier: String) -> Location? {
        if let hit = cache.withLock({ $0[identifier] }) { return hit }
        guard let location = zoneTab.flatMap({ zoneTabLocation(identifier, in: $0) }) else { return nil }
        cache.withLock { $0[identifier] = location }
        return location
    }

    /// A bundled copy of tzdb's zone.tab (public domain): the system copy is undocumented
    /// and may be unreadable from a sandbox or absent on iOS.
    private static let zoneTab = Bundle.main.url(forResource: "zone", withExtension: "tab")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }

    /// A city to pick in Settings: one row of zone.tab.
    struct City: Identifiable, Hashable, Sendable {
        /// The zone identifier, e.g. "America/Los_Angeles".
        let id: String
        let name: String
        let countryCode: String
        /// The identifier's first component, e.g. "America", for grouping the list.
        var region: String { String(id.prefix { $0 != "/" }) }
    }

    /// Every city in zone.tab, sorted by name.
    static let cities: [City] = (zoneTab ?? "").split(separator: "\n").compactMap { line in
        let fields = line.split(separator: "\t")
        guard !line.hasPrefix("#"), fields.count >= 3 else { return nil }
        let id = String(fields[2])
        return City(id: id, name: cityName(id), countryCode: String(fields[0]))
    }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    /// The identifier's last component is the city, with underscores for spaces ("America/New_York").
    static func cityName(_ identifier: String) -> String {
        (identifier.split(separator: "/").last.map(String.init) ?? identifier).replacingOccurrences(of: "_", with: " ")
    }

    /// zone.tab rows look like `CZ  +5005+01426  Europe/Prague`, as ±DDMM[SS]±DDDMM[SS].
    static func zoneTabLocation(_ identifier: String, in table: String) -> Location? {
        for line in table.split(separator: "\n") where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t")
            guard fields.count >= 3, fields[2] == identifier else { continue }
            let coords = fields[1]
            guard let split = coords.dropFirst().firstIndex(where: { $0 == "+" || $0 == "-" }),
                  let lat = degrees(coords[..<split], degreeDigits: 2),
                  let lon = degrees(coords[split...], degreeDigits: 3) else { return nil }
            return Location(latitude: lat, longitude: lon, name: cityName(identifier))
        }
        return nil
    }

    private static func degrees(_ s: Substring, degreeDigits: Int) -> Double? {
        let sign: Double = s.first == "-" ? -1 : 1
        let digits = Array(s.dropFirst())
        guard digits.count >= degreeDigits + 2 else { return nil }
        var parts = [digits[..<degreeDigits], digits[degreeDigits..<(degreeDigits + 2)]]
        if digits.count >= degreeDigits + 4 { parts.append(digits[(degreeDigits + 2)..<(degreeDigits + 4)]) }
        let values = parts.compactMap { Double(String($0)) }
        guard values.count == parts.count else { return nil }
        return sign * zip(values, [1, 60, 3600]).reduce(0) { $0 + $1.0 / $1.1 }
    }
}
