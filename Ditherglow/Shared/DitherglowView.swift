import SwiftUI

/// Full-bleed animated Daybreak sky. Platform-agnostic, reused by macOS and iOS.
struct DitherglowView: View {
    /// Fixed moment for previewing the sky; `nil` follows the clock.
    var dateOverride: Date? = nil
    /// Animation-time units per real second. The shader's frequencies are ~0.2 rad/unit,
    /// so 0.05 means a blob takes roughly ten minutes to complete one loop.
    var speed: Double = 0.05
    /// Offsets every blob's path, so neighbouring screens don't show the same pattern.
    var seed: Float = 0
    /// Size of one dither pixel, in points.
    var blockSize: Double = 4
    /// The sky moves slowly; a low frame rate is plenty and saves power.
    var framesPerSecond: Double = 12

    /// Start somewhere random so each launch looks different.
    private static let launchAnchor = Anchor(date: Date(), time: .random(in: 0..<1000))

    /// Animation time is `anchor.time` at `anchor.date`, then advances at `speed`.
    private struct Anchor {
        var date: Date
        var time: Double
    }

    @State private var anchor = Self.launchAnchor

    var body: some View {
        // Copy into locals: the visualEffect closure runs off the main actor.
        let seed = seed
        let blockSize = Float(blockSize)

        TimelineView(.animation(minimumInterval: 1 / framesPerSecond)) { context in
            let colors = Sky.colors(at: dateOverride ?? context.date).flatMap { [$0.x, $0.y, $0.z] }
            let time = Float(anchor.time + context.date.timeIntervalSince(anchor.date) * speed)

            Rectangle()
                .visualEffect { content, proxy in
                    content.colorEffect(ShaderLibrary.ditherglow(
                        .float2(proxy.size),
                        .float(time),
                        .float(seed),
                        .float(blockSize),
                        .floatArray(colors)
                    ))
                }
        }
        .ignoresSafeArea()
        .onChange(of: speed) { oldSpeed, _ in
            let now = Date()
            anchor = Anchor(date: now, time: anchor.time + now.timeIntervalSince(anchor.date) * oldSpeed)
        }
    }
}

#Preview {
    DitherglowView(speed: 0.5)
}
