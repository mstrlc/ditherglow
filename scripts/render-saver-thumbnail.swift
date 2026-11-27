// Renders the screen saver's System Settings thumbnail with the real shader and palette, so it
// matches what the saver draws: the "Sunrise & Sunset" sky, as in the app icon.
//
//   scripts/render-saver-thumbnail.sh
//
// Writes DitherglowSaver/thumbnail.png and thumbnail@2x.png at the sizes Apple's own savers use.
// Not a plain `swift` script: it compiles together with Sky.swift and its dependencies.

import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

@main
enum RenderSaverThumbnail {
    /// Size in points, as in /System/Library/Screen Savers/Random.saver.
    static let size = (width: 90, height: 58)
    /// Size of one dither block at @2x, in pixels: small enough to read as a miniature of the
    /// full screen, big enough that the dither still shows. Halved for @1x.
    static let blockPixels2x = 3.0
    /// The sky's phase and a moment in its drift that spreads the colours nicely.
    static let altitude = -0.5
    static let time: Float = 41
    static let seed: Float = 0

    static func main() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let device = try MTLCreateSystemDefaultDevice().orThrow("No Metal device")
        let pipeline = try device.makeComputePipelineState(function: kernel(device: device, root: root))
        let colors = Sky.colors(altitude: altitude).flatMap { [$0.x, $0.y, $0.z] }

        for scale in [1, 2] {
            let image = try render(device: device, pipeline: pipeline, colors: colors, scale: scale)
            let name = scale == 1 ? "thumbnail.png" : "thumbnail@\(scale)x.png"
            try write(image, to: root.appending(path: "DitherglowSaver/\(name)"))
            print("Wrote DitherglowSaver/\(name)")
        }
    }

    /// The stitchable SwiftUI shader, compiled as plain Metal with a kernel that calls it per pixel.
    static func kernel(device: MTLDevice, root: URL) throws -> MTLFunction {
        var source = try String(contentsOf: root.appending(path: "Ditherglow/Shared/Ditherglow.metal"), encoding: .utf8)
        source = source
            .replacingOccurrences(of: "#include <SwiftUI/SwiftUI_Metal.h>", with: "")
            .replacingOccurrences(of: "[[ stitchable ]]", with: "")
        source += """

        struct Params { float2 size; float time; float seed; float blockSize; int count; };

        kernel void renderThumbnail(texture2d<float, access::write> out [[texture(0)]],
                                    device const float *colors [[buffer(0)]],
                                    constant Params &p [[buffer(1)]],
                                    uint2 gid [[thread_position_in_grid]]) {
            if (gid.x >= out.get_width() || gid.y >= out.get_height()) return;
            half4 c = ditherglow(float2(gid) + 0.5, half4(0), p.size, p.time, p.seed, p.blockSize, colors, p.count);
            out.write(float4(c), gid);
        }
        """
        let library = try device.makeLibrary(source: source, options: nil)
        return try library.makeFunction(name: "renderThumbnail").orThrow("No kernel")
    }

    struct Params {
        var size: SIMD2<Float>
        var time: Float
        var seed: Float
        var blockSize: Float
        var count: Int32
    }

    static func render(device: MTLDevice, pipeline: MTLComputePipelineState, colors: [Float], scale: Int) throws -> CGImage {
        let width = size.width * scale, height = size.height * scale
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderWrite]
        descriptor.storageMode = .shared
        let texture = try device.makeTexture(descriptor: descriptor).orThrow("No texture")
        var params = Params(
            size: SIMD2(Float(width), Float(height)),
            time: time,
            seed: seed,
            blockSize: Float(blockPixels2x * Double(scale) / 2),
            count: Int32(colors.count)
        )

        let queue = try device.makeCommandQueue().orThrow("No queue")
        let buffer = try queue.makeCommandBuffer().orThrow("No command buffer")
        let encoder = try buffer.makeComputeCommandEncoder().orThrow("No encoder")
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(texture, index: 0)
        encoder.setBytes(colors, length: colors.count * MemoryLayout<Float>.stride, index: 0)
        encoder.setBytes(&params, length: MemoryLayout<Params>.stride, index: 1)
        encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1), threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        encoder.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let provider = try CGDataProvider(data: Data(pixels) as CFData).orThrow("No data provider")
        return try CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ).orThrow("No image")
    }

    static func write(_ image: CGImage, to url: URL) throws {
        let destination = try CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil).orThrow("Can't write \(url.path)")
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ScriptError("Can't write \(url.path)") }
    }
}

struct ScriptError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

extension Optional {
    func orThrow(_ message: String) throws -> Wrapped {
        guard let self else { throw ScriptError(message) }
        return self
    }
}
