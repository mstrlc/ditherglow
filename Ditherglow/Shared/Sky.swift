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

    /// `location` defaults to the one chosen in Settings; the screen saver passes the app's, as it can't read them itself.
    static func altitude(at date: Date, location: Sun.Location? = nil) -> Double {
        Sun.altitude(at: date, location ?? Sun.location())
    }

    static func colors(at date: Date, location: Sun.Location? = nil) -> [SIMD3<Float>] {
        colors(altitude: altitude(at: date, location: location))
    }

    /// The sky's six colours at `altitude` (degrees; negative is below the horizon).
    static func colors(altitude: Double) -> [SIMD3<Float>] {
        let (lower, upper, t) = bracket(altitude)
        // Smoothstep: lingers near each named phase, moves quicker between them.
        let k = Float(t * t * (3 - 2 * t))
        return zip(lower.colors, upper.colors).map { mix(rgb($0), rgb($1), k) }
    }

    /// Morphs one colour into another in OKLCh: lightness and chroma move linearly and the hue turns the short way
    /// round, unless that's through green. Mixing in sRGB (or OKLab) sends opposite hues, like sunset orange into blue-hour blue, through grey.
    private static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ k: Float) -> SIMD3<Float> {
        guard k > 0 else { return a }
        guard k < 1 else { return b }
        let la = oklab(fromSRGB: a), lb = oklab(fromSRGB: b)
        let ca = simd_length(SIMD2(la.y, la.z)), cb = simd_length(SIMD2(lb.y, lb.z))
        // A near-grey end has no meaningful hue; take the other end's, so it fades in or out without a hue sweep.
        let greyChroma: Float = 0.02
        var ha = atan2(la.z, la.y), hb = atan2(lb.z, lb.y)
        if ca < greyChroma { ha = hb }
        if cb < greyChroma { hb = ha }
        var dh = wrapped(hb - ha)
        // Skies aren't green: if the short way passes through green (OKLab hue ~145°), go round via pink and violet.
        let toGreen = wrapped(145 * .pi / 180 - ha)
        if dh > 0 ? (toGreen > 0 && toGreen < dh) : (toGreen < 0 && toGreen > dh) {
            dh -= (dh > 0 ? 2 : -2) * .pi
        }
        let hue = ha + dh * k, chroma = ca + (cb - ca) * k
        let lab = SIMD3(la.x + (lb.x - la.x) * k, chroma * cos(hue), chroma * sin(hue))
        return srgb(fromOklab: lab)
    }

    /// An angle in -π...π.
    private static func wrapped(_ angle: Float) -> Float {
        var a = angle
        while a > .pi {
            a -= 2 * .pi
        }
        while a < -.pi {
            a += 2 * .pi
        }
        return a
    }

    private static func oklab(fromSRGB c: SIMD3<Float>) -> SIMD3<Float> {
        let rgb = SIMD3(linear(c.x), linear(c.y), linear(c.z))
        let l = cbrt(simd_dot(SIMD3(0.4122214708, 0.5363325363, 0.0514459929), rgb))
        let m = cbrt(simd_dot(SIMD3(0.2119034982, 0.6806995451, 0.1073969566), rgb))
        let s = cbrt(simd_dot(SIMD3(0.0883024619, 0.2817188376, 0.6299787005), rgb))
        return SIMD3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                     1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                     0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    /// Back to sRGB, clamped: a hue swept round at full chroma can leave the gamut.
    private static func srgb(fromOklab c: SIMD3<Float>) -> SIMD3<Float> {
        var l = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z
        var m = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z
        var s = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z
        l = l * l * l
        m = m * m * m
        s = s * s * s
        let rgb = SIMD3(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
        return simd_clamp(SIMD3(encode(rgb.x), encode(rgb.y), encode(rgb.z)), SIMD3(repeating: 0), SIMD3(repeating: 1))
    }

    private static func linear(_ x: Float) -> Float { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }

    private static func encode(_ x: Float) -> Float {
        let x = max(x, 0)
        return x <= 0.0031308 ? x * 12.92 : 1.055 * pow(x, 1 / 2.4) - 0.055
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
