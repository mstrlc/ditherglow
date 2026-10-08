#!/usr/bin/env swift
// Renders the app icon: a sunlit orb on the night sky, shaded only with large pixels, each colour
// change drawn with a 4×4 Bayer dither. Light appearance: the sun in the "Sunrise & Sunset" palette.
// Dark appearance: the same shape as a moon in the night blues.
//
//   swift scripts/render-icon.swift [blocks]   # blocks across the icon, default 32
//
// Writes Ditherglow/AppIcon.icon for Icon Composer: one stacked SVG layer per colour, glass off,
// with light, dark and tinted fills. Xcode builds the legacy .icns for older macOS from it.

import Foundation

// Darkest → lightest. The first three are the night sky around the orb (and the orb's unlit edge);
// the rest light the orb: the Sunrise & Sunset stop from Sky.swift, shadow → highlight.
let palette: [UInt32] = [0x070B1C, 0x0B1530, 0x14224A, 0x644D86, 0xAA5C84, 0xDF7D90, 0xE18F6D, 0xEAB989, 0xF0CEB7]
// Dark appearance: a moon. Night blues from Sky.swift (Moonlight, Blue Hour, Dusk) up to a silver highlight.
let darkPalette: [UInt32] = [0x03050D, 0x070B1C, 0x0B1530, 0x14224A, 0x192751, 0x273E78, 0x426096, 0x6F86B8, 0xA9B6D8]
let skyCount = 3
let blocks = CommandLine.arguments.dropFirst().compactMap { Int($0) }.first ?? 32

// MARK: Colour (as in Ditherglow.metal)

typealias V3 = SIMD3<Double>

func rgb(_ hex: UInt32) -> V3 {
    V3(Double((hex >> 16) & 0xFF), Double((hex >> 8) & 0xFF), Double(hex & 0xFF)) / 255
}

func srgbToLinear(_ c: V3) -> V3 {
    V3(c.x, c.y, c.z).map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
}

func linearToOklab(_ c: V3) -> V3 {
    let l = cbrt(0.4122214708 * c.x + 0.5363325363 * c.y + 0.0514459929 * c.z)
    let m = cbrt(0.2119034982 * c.x + 0.6806995451 * c.y + 0.1073969566 * c.z)
    let s = cbrt(0.0883024619 * c.x + 0.2817188376 * c.y + 0.6299787005 * c.z)
    return V3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
              1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
              0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
}

extension SIMD3 where Scalar == Double {
    func map(_ f: (Double) -> Double) -> V3 { V3(f(x), f(y), f(z)) }
}

/// 4×4 Bayer: 16 levels, so a transition walks through dots → crosses → XOXO checker →
/// crosses → dots instead of jumping straight to a checkerboard.
func bayer4(_ x: Int, _ y: Int) -> Double {
    let m = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
    return (Double(m[(y & 3) * 4 + (x & 3)]) + 0.5) / 16
}

/// Ordered dither over the palette index: every block is exactly one palette colour, and each
/// transition between neighbours becomes a Bayer pattern.
func paletteIndex(bx: Int, by: Int) -> Int {
    // Block centre relative to the orb, in orb radii (y up).
    // 0.35 keeps the top, bottom and side rows several blocks wide; just past a row leaves a 2-block nub.
    let radius = 0.35 * Double(blocks)
    let dx = (Double(bx) + 0.5 - Double(blocks) / 2) / radius
    let dy = (Double(blocks) / 2 - Double(by) - 0.5) / radius
    let r2 = dx * dx + dy * dy
    let f: Double
    if r2 < 1 {
        // Lambert-ish shading from the upper right. The orb only uses its own colours, so even the
        // unlit side keeps a clean silhouette against the sky.
        let z = (1 - r2).squareRoot()
        let lit = min(max(0.55 * dx + 0.55 * dy + 0.62 * z, 0), 1)
        f = Double(skyCount) + lit * Double(palette.count - skyCount - 1)
    } else {
        // Night sky, with a faint glow hugging the orb. Kept to the two darkest blues so it never
        // touches the orb's colours and blurs the edge.
        let glow = 1 - min(r2.squareRoot() - 1, 1)
        f = 0.15 + 0.85 * glow * glow
        return min(Int(floor(f + bayer4(bx, by))), 1)
    }
    return min(Int(floor(f + bayer4(bx, by))), palette.count - 1)
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

// MARK: Icon Composer

// One layer per palette colour, stacked: layer i covers every block whose colour is i or later,
// so the bottom layer is full bleed and each layer sits on solid colour (no seams between
// layers). The SVGs are plain shapes; the colour is the layer's fill, editable in Icon Composer.
func layerSVG(covering index: Int) -> String {
    var rects: [String] = []
    for by in 0..<blocks {
        var bx = 0
        while bx < blocks {
            guard paletteIndex(bx: bx, by: by) >= index else { bx += 1; continue }
            var run = 1
            while bx + run < blocks, paletteIndex(bx: bx + run, by: by) >= index { run += 1 }
            // Bleed 0.05 into the next block: abutting rects get antialiased separately and leave hairlines.
            rects.append("  <rect x=\"\(bx)\" y=\"\(by)\" width=\"\(Double(run) + 0.05)\" height=\"1.05\"/>")
            bx += run
        }
    }
    return """
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 \(blocks) \(blocks)" shape-rendering="crispEdges">
    \(rects.joined(separator: "\n"))
    </svg>

    """
}

func srgbString(_ hex: UInt32) -> String {
    let c = rgb(hex)
    return String(format: "srgb:%.5f,%.5f,%.5f,1.00000", c.x, c.y, c.z)
}

/// Tinted and clear appearances: grey following the colour's OKLab lightness, stretched to
/// 0.2...1 so the system tint keeps the light → dark steps (and the dither) at full contrast.
let paletteLightness = palette.map { linearToOklab(srgbToLinear(rgb($0))).x }

func tintedString(_ hex: UInt32) -> String {
    let l = linearToOklab(srgbToLinear(rgb(hex))).x
    let lo = paletteLightness.min()!, hi = paletteLightness.max()!
    let grey = 0.2 + 0.8 * (l - lo) / (hi - lo)
    return String(format: "srgb:%.5f,%.5f,%.5f,1.00000", grey, grey, grey)
}

let iconDocument = root.appendingPathComponent("Ditherglow/AppIcon.icon")
let assets = iconDocument.appendingPathComponent("Assets")
try? FileManager.default.removeItem(at: assets)
try! FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

let layerNames = ["Night", "Moonlight", "Dusk", "Purple", "Rose", "Pink", "Orange", "Gold", "Cream"]
var layers: [[String: Any]] = []
for (i, hex) in palette.enumerated() {
    let name = layerNames[i]
    try! layerSVG(covering: i).write(to: assets.appendingPathComponent("\(name).svg"), atomically: true, encoding: .utf8)
    layers.append([
        "fill-specializations": [
            ["value": ["solid": srgbString(hex)]],
            ["appearance": "dark", "value": ["solid": srgbString(darkPalette[i])]],
            ["appearance": "tinted", "value": ["solid": tintedString(hex)]],
        ],
        "glass": false,
        "image-name": "\(name).svg",
        "name": name,
    ])
}

let iconJSON: [String: Any] = [
    "groups": [[
        // Icon Composer lists the top layer first.
        "layers": Array(layers.reversed()),
        "shadow": ["kind": "none", "opacity": 0.5],
        "translucency": ["enabled": false, "value": 0.5],
    ]],
    "supported-platforms": ["squares": "shared"],
]
try! JSONSerialization.data(withJSONObject: iconJSON, options: [.prettyPrinted, .sortedKeys])
    .write(to: iconDocument.appendingPathComponent("icon.json"))

print("Rendered \(blocks)×\(blocks) blocks → \(iconDocument.path)")
