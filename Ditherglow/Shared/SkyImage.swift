import CoreGraphics
import Foundation
import ImageIO
import simd
import UniformTypeIdentifiers

/// Still images of the sky, for wallpapers. A CPU port of `Ditherglow.metal`: Shortcuts automations run the app
/// in the background, where iOS refuses GPU work. The shader gives each dither block one flat colour, so this
/// evaluates the gradient once per block and scales the result up without smoothing.
/// Keep it in step with the shader: same maths, same constants.
nonisolated enum SkyImage {
    /// The sky at `date` as a PNG of `size` points at `scale` pixels per point.
    static func png(at date: Date, size: CGSize, scale: Double, blockSize: Double) -> Data? {
        guard let image = render(at: date, size: size, scale: scale, blockSize: blockSize) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Animation time for a still. Tied to the clock, so wallpapers made minutes apart differ only a little,
    /// and wrapped so the shader's sines keep their precision.
    static func time(at date: Date) -> Double {
        (date.timeIntervalSinceReferenceDate * Preferences.defaultSpeed).truncatingRemainder(dividingBy: 10000)
    }

    /// The sky at `date` in a new image of `size` points at `scale` pixels per point.
    static func render(at date: Date, size: CGSize, scale: Double, blockSize: Double) -> CGImage? {
        let width = Int((size.width * scale).rounded()), height = Int((size.height * scale).rounded())
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        draw(at: date, time: time(at: date), size: size, blockSize: blockSize, in: context)
        return context.makeImage()
    }

    /// How block colours are stored before they're scaled up into the context.
    enum Encoding {
        /// 8-bit sRGB.
        case sRGB
        /// 16-bit BT.2100 HLG, with the sky's white at `white` nits. For the Live Photo, which has to be HDR.
        case hlg(white: Double)
    }

    /// Fills `context` with the sky's palette at `date` and its blobs at animation time `time`.
    /// `size` is the picture in points; the context's pixel width sets the scale.
    static func draw(at date: Date, time t: Double, size: CGSize, blockSize: Double, encoding: Encoding = .sRGB, in context: CGContext) {
        // The palette goes into OKLab once here, rather than per block as the shader does.
        let labColors = Sky.colors(at: date).map { oklab(fromLinear: linear(fromSRGB: SIMD3<Double>($0))) }
        let columns = Int((size.width / blockSize).rounded(.up)), rows = Int((size.height / blockSize).rounded(.up))
        guard columns > 0, rows > 0, !labColors.isEmpty else { return }

        // One RGB pixel per dither block.
        var blocks: [SIMD3<Double>] = []
        blocks.reserveCapacity(columns * rows)
        let aspect = size.width / max(size.height, 1)
        for row in 0..<rows {
            for column in 0..<columns {
                let uv = SIMD2((Double(column) + 0.5) * blockSize / size.width, (Double(row) + 0.5) * blockSize / size.height)
                // Seed 0, as `DitherglowView` uses on a single screen.
                var lab = gradient(uv: uv, aspect: aspect, t: t, seed: 0, colors: labColors)
                // Clamp to sRGB before dithering, as the shader does.
                lab = oklab(fromLinear: linear(fromSRGB: clamp(srgb(fromLinear: linear(fromOklab: lab)))))
                let step = 0.08
                lab.x = ((lab.x / step + bayer8(column, row)).rounded(.down) + 0.5) * step
                blocks.append(clamp(srgb(fromLinear: linear(fromOklab: lab))))
            }
        }
        guard let small = image(of: blocks, columns: columns, rows: rows, encoding: encoding) else { return }

        // Scale up with hard edges; the last row and column of blocks may run past the edge, as on screen.
        context.interpolationQuality = .none
        let blockPixels = blockSize * Double(context.width) / size.width
        let drawn = CGSize(width: Double(columns) * blockPixels, height: Double(rows) * blockPixels)
        // Core Graphics is y-up; the shader's rows run from the top, so pin the grid to the top edge.
        context.draw(small, in: CGRect(x: 0, y: Double(context.height) - drawn.height, width: drawn.width, height: drawn.height))
    }

    /// The blocks as a `columns` × `rows` image, one pixel each.
    private static func image(of blocks: [SIMD3<Double>], columns: Int, rows: Int, encoding: Encoding) -> CGImage? {
        let data: Data, bits: Int, space: CGColorSpace, byteOrder: CGBitmapInfo
        switch encoding {
        case .sRGB:
            data = Data(blocks.flatMap { rgb in [rgb.x, rgb.y, rgb.z, 1].map { UInt8(($0 * 255).rounded()) } })
            (bits, space, byteOrder) = (8, CGColorSpace(name: CGColorSpace.sRGB)!, [])
        case let .hlg(white):
            let values = blocks.flatMap { rgb in
                let hlg = hlg(fromSRGB: rgb, white: white)
                return [hlg.x, hlg.y, hlg.z, 1].map { UInt16(($0 * 65535).rounded()).littleEndian }
            }
            data = values.withUnsafeBufferPointer { Data(buffer: $0) }
            (bits, space, byteOrder) = (16, CGColorSpace(name: CGColorSpace.itur_2100_HLG)!, .byteOrder16Little)
        }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: columns, height: rows, bitsPerComponent: bits, bitsPerPixel: bits * 4, bytesPerRow: columns * bits / 2,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue).union(byteOrder),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// An sRGB colour as a BT.2100 HLG signal, with SDR white at `white` nits on a 1000-nit display.
    /// BT.2408's reference white is 203 nits (75% signal).
    static func hlg(fromSRGB c: SIMD3<Double>, white: Double) -> SIMD3<Double> {
        let rec709 = linear(fromSRGB: c)
        // BT.709 primaries to BT.2020.
        let rec2020 = SIMD3(
            0.6274 * rec709.x + 0.3293 * rec709.y + 0.0433 * rec709.z,
            0.0691 * rec709.x + 0.9195 * rec709.y + 0.0114 * rec709.z,
            0.0164 * rec709.x + 0.0880 * rec709.y + 0.8956 * rec709.z
        )
        // Light relative to a 1000-nit peak. HLG's system gamma is deliberately not undone: the lock screen doesn't
        // seem to apply it, and undoing it left the darks washed out.
        let light = rec2020 * (white / 1000)
        return clamp(light.map { e in
            e <= 1.0 / 12 ? (3 * e).squareRoot() : 0.17883277 * log(12 * e - 0.28466892) + 0.55991073
        })
    }

    // MARK: - Shader port

    /// The gradient in OKLab at `uv` (0...1, y down). See `gradientLab` in the shader.
    private static func gradient(uv: SIMD2<Double>, aspect: Double, t: Double, seed: Double, colors: [SIMD3<Double>]) -> SIMD3<Double> {
        var p = uv
        p.x *= aspect

        var w = p
        w += 0.18 * SIMD2<Double>(sin(p.y * 2.3 + t * 0.61 + seed), cos(p.x * 1.9 - t * 0.47 + seed * 1.7))
        w += 0.06 * SIMD2<Double>(sin(w.y * 2.7 - t * 0.83), cos(w.x * 2.4 + t * 0.71))

        var acc = SIMD3<Double>()
        var accChroma = 0.0
        var total = 0.0
        for (i, lab) in colors.enumerated() {
            let fi = Double(i) + seed
            let c = SIMD2(aspect * (0.5 + 0.48 * sin(t * (0.23 + 0.071 * fi) + fi * 2.399)),
                          0.5 + 0.48 * cos(t * (0.19 + 0.053 * fi) + fi * 1.618))
            let dv = w - c
            let d = (simd_dot(dv, dv) + 0.03).squareRoot()
            let radius = 0.5 + 0.15 * sin(t * 0.3 + fi * 3.1)
            let wt = pow(radius / d, 2.4)
            acc += wt * lab
            accChroma += wt * simd_length(SIMD2(lab.y, lab.z))
            total += wt
        }

        var lab = acc / total
        let chroma = simd_length(SIMD2(lab.y, lab.z))
        let targetChroma = accChroma / total
        let k = targetChroma / max(chroma, max(targetChroma * 0.55, 0.015))
        lab.y *= k
        lab.z *= k
        return lab
    }

    private static func bayer8(_ px: Int, _ py: Int) -> Double {
        let x = px & 7, xy = (px ^ py) & 7
        let v = ((xy & 1) << 5) | ((x & 1) << 4) | ((xy & 2) << 2) | ((x & 2) << 1) | ((xy & 4) >> 1) | ((x & 4) >> 2)
        return (Double(v) + 0.5) / 64
    }

    private static func clamp(_ c: SIMD3<Double>) -> SIMD3<Double> {
        simd_clamp(c, SIMD3(repeating: 0), SIMD3(repeating: 1))
    }

    private static func linear(fromSRGB c: SIMD3<Double>) -> SIMD3<Double> {
        c.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
    }

    private static func srgb(fromLinear c: SIMD3<Double>) -> SIMD3<Double> {
        c.map { max($0, 0) }.map { $0 <= 0.0031308 ? $0 * 12.92 : 1.055 * pow($0, 1 / 2.4) - 0.055 }
    }

    private static func oklab(fromLinear c: SIMD3<Double>) -> SIMD3<Double> {
        let l = cbrt(0.4122214708 * c.x + 0.5363325363 * c.y + 0.0514459929 * c.z)
        let m = cbrt(0.2119034982 * c.x + 0.6806995451 * c.y + 0.1073969566 * c.z)
        let s = cbrt(0.0883024619 * c.x + 0.2817188376 * c.y + 0.6299787005 * c.z)
        return SIMD3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                     1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                     0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    private static func linear(fromOklab c: SIMD3<Double>) -> SIMD3<Double> {
        var l = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z
        var m = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z
        var s = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z
        l = l * l * l
        m = m * m * m
        s = s * s * s
        return SIMD3(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                     -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                     -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }
}

private nonisolated extension SIMD3<Double> {
    func map(_ transform: (Double) -> Double) -> SIMD3<Double> {
        SIMD3(transform(x), transform(y), transform(z))
    }
}
