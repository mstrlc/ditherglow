import Foundation
import simd

/// The Daybreak palette: sky colours as a function of the sun's altitude, so the desktop
/// goes day → golden hour → orange and pink glows → blue hour → moonlight and back.
nonisolated enum Sky {
    /// Six colours per stop, same order in every stop: each slot morphs into its counterpart,
    /// so a blob that is orange at sunset becomes the deep blue of dusk, then moonlight.
    struct Stop {
        let altitude: Double
        let name: String
        let colors: [UInt32]
    }

    /// Sorted by altitude, lowest first. Below the first stop it stays night; above the last, midday.
    static let stops: [Stop] = [
        // Moonlight: near-black navy with a cold silver glow.
        Stop(altitude: -14, name: "Moonlight", colors: [0x03050D, 0x0B1530, 0x02030A, 0x14224A, 0x6F86B8, 0x070B1C]),
        // Late dusk: the last ember on the horizon under a deep blue sky.
        Stop(altitude: -9, name: "Dusk", colors: [0x060711, 0x192751, 0x04050A, 0x6F372B, 0x273E78, 0x0E1430]),
        // Blue hour: blue, a band of yellow and orange, and black.
        Stop(altitude: -4.5, name: "Blue Hour", colors: [0x0C0E18, 0x426096, 0x07070D, 0xC47B5C, 0x2B406F, 0xDFBB81]),
        // Sun on the horizon: orange and pink glows.
        Stop(altitude: -0.5, name: "Sunrise & Sunset", colors: [0x644D86, 0xDF7D90, 0xAA5C84, 0xE18F6D, 0xEAB989, 0xF0CEB7]),
        // Golden hour: warm light, the sky turning blue again.
        Stop(altitude: 5, name: "Golden Hour", colors: [0x98C4E0, 0xEDAEBA, 0xF19579, 0xF4B769, 0xF9DAAA, 0xFAE6BF]),
        // Day: soft blues with sunlit cream.
        Stop(altitude: 18, name: "Day", colors: [0x8EC9F0, 0xBFE3F7, 0xA9D6F5, 0x6FB1E6, 0xFFE9B0, 0xF9F3E3]),
        // High sun: clearer, deeper blue.
        Stop(altitude: 45, name: "Midday", colors: [0x5FA8E8, 0x9FD3F5, 0x7FC1EE, 0x3E8FDC, 0xFFF1C9, 0xE6F4FB]),
    ]

    static func altitude(at date: Date) -> Double { Sun.altitude(at: date, Sun.location()) }

    static func colors(at date: Date) -> [SIMD3<Float>] { colors(altitude: altitude(at: date)) }

    /// The sky's six colours at `altitude` (degrees; negative is below the horizon).
    static func colors(altitude: Double) -> [SIMD3<Float>] {
        let (lower, upper, t) = bracket(altitude)
        // Smoothstep: lingers near each named phase, moves quicker between them.
        let k = Float(t * t * (3 - 2 * t))
        return zip(lower.colors, upper.colors).map { simd_mix(rgb($0), rgb($1), SIMD3(repeating: k)) }
    }

    /// The stops either side of `altitude` and how far it sits between them (0...1).
    /// Below the first stop it stays night; above the last, midday.
    private static func bracket(_ altitude: Double) -> (Stop, Stop, Double) {
        guard let i = stops.firstIndex(where: { $0.altitude > altitude }) else { return (stops.last!, stops.last!, 0) }
        guard i > 0 else { return (stops[0], stops[0], 0) }
        let lower = stops[i - 1], upper = stops[i]
        return (lower, upper, (altitude - lower.altitude) / (upper.altitude - lower.altitude))
    }

    /// The name of the nearest stop, e.g. "Golden Hour".
    static func phase(altitude: Double) -> String {
        stops.min { abs($0.altitude - altitude) < abs($1.altitude - altitude) }!.name
    }

    static func rgb(_ hex: UInt32) -> SIMD3<Float> {
        SIMD3(Float((hex >> 16) & 0xFF) / 255, Float((hex >> 8) & 0xFF) / 255, Float(hex & 0xFF) / 255)
    }
}
