import Observation
import Sparkle

/// Sparkle's standard updater, checking the appcast in `Info.plist`'s `SUFeedURL`.
/// Mirrors the updater's state into observable properties for the menu and Settings.
@Observable
final class Updater {
    /// False while a check is already running, so the menu item can't stack them.
    private(set) var canCheckForUpdates = false

    /// Sparkle persists this itself (`SUEnableAutomaticChecks`), so it isn't in `Preferences`.
    var automaticallyChecksForUpdates: Bool {
        didSet {
            // Writing records an explicit choice, which also skips Sparkle's second-launch prompt.
            guard automaticallyChecksForUpdates != oldValue else { return }
            controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            // Sparkle posts KVO changes on the main thread.
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
