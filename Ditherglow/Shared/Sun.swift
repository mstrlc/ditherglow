import Foundation
import os

/// Sunrise and sunset from low-precision almanac formulas. Pure functions of date and place.
nonisolated enum Sun {
    struct Location: Equatable, Sendable {
        let latitude: Double
        let longitude: Double

        init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    /// Sun's centre this far below the horizon counts as set (refraction + disc radius).
    static let horizon = -0.833

    static func isUp(at date: Date, _ location: Location) -> Bool {
        altitude(at: date, location) > horizon
    }

    /// Next sunrise or sunset within two days, to about 30 seconds; nil during polar day/night.
    static func nextEvent(after date: Date, _ location: Location) -> Date? {
        let up = isUp(at: date, location)
        var lo = date
        for step in stride(from: 600.0, through: 2 * 86400, by: 600) {
            var hi = date + step
            guard isUp(at: hi, location) != up else { lo = hi; continue }
            while hi.timeIntervalSince(lo) > 30 {
                let mid = lo + hi.timeIntervalSince(lo) / 2
                if isUp(at: mid, location) == up { lo = mid } else { hi = mid }
            }
            return hi
        }
        return nil
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

    private static let cache = OSAllocatedUnfairLock<(zone: String, location: Location)?>(initialState: nil)

    /// Approximated by the time zone's reference city, so no location permission is needed.
    static func location(in zone: TimeZone = .current) -> Location {
        if let hit = cache.withLock({ $0 }), hit.zone == zone.identifier { return hit.location }
        let table = try? String(contentsOfFile: "/usr/share/zoneinfo/zone.tab", encoding: .utf8)
        let location = table.flatMap { zoneTabLocation(zone.identifier, in: $0) }
            // Unknown zone (e.g. "UTC"): longitude from the offset, a mid latitude.
            ?? Location(latitude: 45, longitude: Double(zone.secondsFromGMT()) / 240)
        cache.withLock { $0 = (zone.identifier, location) }
        return location
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
            return Location(latitude: lat, longitude: lon)
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
