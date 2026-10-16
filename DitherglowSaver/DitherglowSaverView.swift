import ScreenSaver
import SwiftUI

/// Hosts `DitherglowView` as a screen saver. Runs inside Apple's sandboxed `legacyScreenSaver`
/// host with its own defaults, so it uses the default look rather than the app's settings.
/// `@objc` keeps the class name stable for `NSPrincipalClass`.
@objc(DitherglowSaverView)
final class DitherglowSaverView: ScreenSaverView {
    private var host: NSHostingView<DitherglowView>?
    private var stopObserver: (any NSObjectProtocol)?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        guard !isPreview else { return }
        // Since Sonoma, legacyScreenSaver keeps saver instances alive after dismissal and never
        // calls `stopAnimation`, so the shader would keep running. Exiting is the known workaround;
        // the system relaunches the host next time.
        stopObserver = DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.screensaver.willstop"),
            object: nil,
            queue: .main
        ) { _ in exit(0) }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// The TimelineView drives the frames, so animating means having the hosting view at all.
    override func startAnimation() {
        super.startAnimation()
        guard host == nil else { return }
        let host = NSHostingView(rootView: DitherglowView(
            // Random so each screen (its own saver instance) shows a different pattern.
            seed: .random(in: 0..<100),
            blockSize: blockSize
        ))
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
        self.host = host
    }

    override func stopAnimation() {
        super.stopAnimation()
        host?.removeFromSuperview()
        host = nil
    }

    /// Size of one dither pixel. The System Settings thumbnail is only a few hundred points wide,
    /// so it's scaled to keep the full screen's block count and read as a miniature of it.
    /// Floored at 1 pt so the dither stays visible rather than blurring into a smooth gradient.
    private var blockSize: Double {
        guard isPreview, let screenWidth = NSScreen.main?.frame.width, screenWidth > 0 else {
            return Preferences.defaultBlockSize
        }
        return max(1, Preferences.defaultBlockSize * bounds.width / screenWidth)
    }
}
