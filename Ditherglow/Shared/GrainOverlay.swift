import CoreGraphics
import SwiftUI

/// Static film grain at native pixel resolution, tiled over the sky. A layer of its own rather than part of the
/// shader, so it stays crisp and fine whatever the pixel size, and costs nothing per frame.
/// Its strength is its opacity (`Preferences.grainKey`).
struct GrainOverlay: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Image(decorative: Self.tile, scale: displayScale)
            .resizable(resizingMode: .tile)
            .interpolation(.none)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private static let tilePixels = 512

    /// Black and white specks with symmetric alpha, so on average the grain neither lightens nor greys the sky.
    private static let tile: CGImage = {
        let n = tilePixels
        var bytes = [UInt8](repeating: 0, count: n * n * 4)
        for i in 0..<(n * n) {
            // Roughly gaussian, from a sum of uniforms.
            let g = (Float.random(in: -1...1) + Float.random(in: -1...1) + Float.random(in: -1...1)) / 3
            let alpha = UInt8(min(abs(g) * 2, 1) * 255)
            // Premultiplied: white is (a, a, a, a), black is (0, 0, 0, a).
            let value: UInt8 = g > 0 ? alpha : 0
            bytes[i * 4] = value
            bytes[i * 4 + 1] = value
            bytes[i * 4 + 2] = value
            bytes[i * 4 + 3] = alpha
        }
        let data = Data(bytes) as CFData
        return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }()
}
