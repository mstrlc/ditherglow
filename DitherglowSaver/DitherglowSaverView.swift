import ScreenSaver
import SwiftUI

/// Hosts `DitherglowView` as a screen saver, with the app's pixel size, speed and location
/// (see `AppSettings`). `@objc` keeps the class name stable for `NSPrincipalClass`.
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

    /// The System Settings preview doesn't always get `startAnimation` (a reopened sheet makes a new
    /// instance that's only put in a window), so it would stay black: start it here too.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        startPreviewIfReady()
    }

    /// The preview's instance starts at zero size and is sized after it's in a window.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        startPreviewIfReady()
    }

    /// Waits for a real size: the preview's pixel size is scaled from its width.
    private func startPreviewIfReady() {
        guard isPreview, window != nil, bounds.width > 0, bounds.height > 0 else { return }
        addHost()
    }

    override func startAnimation() {
        super.startAnimation()
        addHost()
    }

    /// The TimelineView drives the frames, so animating means having the hosting view at all.
    private func addHost() {
        guard host == nil else { return }
        let settings = AppSettings.load()
        let host = NSHostingView(rootView: DitherglowView(
            location: settings.location,
            speed: settings.speed,
            // Random so each screen (its own saver instance) shows a different pattern.
            seed: .random(in: 0..<100),
            blockSize: blockSize(settings.blockSize)
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

    /// Size of one dither pixel. The System Settings preview is only a few hundred points wide,
    /// so it's scaled to keep the full screen's block count and read as a miniature of it.
    /// Floored at 1 pt so the dither stays visible rather than blurring into a smooth gradient.
    private func blockSize(_ size: Double) -> Double {
        guard isPreview, let screenWidth = NSScreen.main?.frame.width, screenWidth > 0 else { return size }
        return max(1, size * bounds.width / screenWidth)
    }
}
