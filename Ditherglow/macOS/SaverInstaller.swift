import AppKit
import Observation

/// Installs the screen saver the app carries (`Contents/Resources/Ditherglow.saver`) for the current user,
/// so it ships and updates with the app instead of as a separate download.
@Observable
final class SaverInstaller {
    enum State: Equatable {
        case notInstalled
        /// Installed, but not the copy this app carries: an older (or newer) build.
        case outdated
        case installed
        /// The app carries no saver, e.g. a build without the embed phase.
        case unavailable
    }

    private(set) var state = State.unavailable
    private(set) var error: String?

    private static let name = "Ditherglow.saver"

    private var bundled: URL? {
        Bundle.main.url(forResource: "Ditherglow", withExtension: "saver")
    }

    /// The per-user folder, which needs no admin rights. `~/Library/Screen Savers` may not exist yet.
    private var destination: URL {
        URL.libraryDirectory.appending(path: "Screen Savers/\(Self.name)", directoryHint: .isDirectory)
    }

    init() {
        refresh()
    }

    func refresh() {
        guard let bundled else {
            state = .unavailable
            return
        }
        guard FileManager.default.fileExists(atPath: destination.path) else {
            state = .notInstalled
            return
        }
        // Compare the executables rather than version numbers: every build differs, and versions can lag.
        state = Self.executable(of: bundled) == Self.executable(of: destination) ? .installed : .outdated
    }

    /// Copies the saver into place, replacing an older copy. The system picks the new one up the next
    /// time it loads the saver; a running `legacyScreenSaver` keeps the old one until then.
    func install() {
        guard let bundled else { return }
        error = nil
        do {
            let folder = destination.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // Copy beside it first, so a failed copy never leaves the user without a saver.
            let staging = folder.appending(path: ".\(Self.name).new", directoryHint: .isDirectory)
            try? FileManager.default.removeItem(at: staging)
            try FileManager.default.copyItem(at: bundled, to: staging)
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
            } else {
                try FileManager.default.moveItem(at: staging, to: destination)
            }
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
    }

    /// The screen saver picker is a sheet inside Wallpaper, which can't be opened directly.
    func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension")!)
    }

    private static func executable(of saver: URL) -> Data? {
        guard let url = Bundle(url: saver)?.executableURL else { return nil }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }
}
