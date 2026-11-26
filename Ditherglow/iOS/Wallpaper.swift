import CoreTransferable
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Wallpaper-sized stills of the sky, for Shortcuts and the share sheet.
nonisolated enum Wallpaper {
    /// What a wallpaper for this phone looks like: its portrait screen and the user's pixel size.
    struct Spec {
        var size: CGSize
        var scale: Double
        var blockSize: Double

        init(defaults: UserDefaults = .standard) {
            let width = defaults.double(forKey: Preferences.screenWidthKey)
            let height = defaults.double(forKey: Preferences.screenHeightKey)
            let scale = defaults.double(forKey: Preferences.screenScaleKey)
            // Before the app has ever run on this phone: a common iPhone size.
            size = width > 0 && height > 0 ? CGSize(width: width, height: height) : CGSize(width: 393, height: 852)
            self.scale = scale > 0 ? scale : 3
            blockSize = defaults.object(forKey: Preferences.blockSizeKey) as? Double ?? Preferences.defaultBlockSize
        }
    }

    /// The sky at `date` as a PNG that fills this phone's screen in portrait.
    static func png(at date: Date, defaults: UserDefaults = .standard) -> Data? {
        let spec = Spec(defaults: defaults)
        return SkyImage.png(at: date, size: spec.size, scale: spec.scale, blockSize: spec.blockSize)
    }

    /// Remembers the screen's portrait size, so wallpapers fit it even when rendered without one.
    @MainActor static func remember(_ screen: UIScreen, defaults: UserDefaults = .standard) {
        let pixels = screen.nativeBounds.size
        defaults.set(pixels.width / screen.nativeScale, forKey: Preferences.screenWidthKey)
        defaults.set(pixels.height / screen.nativeScale, forKey: Preferences.screenHeightKey)
        defaults.set(screen.nativeScale, forKey: Preferences.screenScaleKey)
    }
}

/// A wallpaper of the sky at `date`, rendered only when it's shared.
struct WallpaperFile: Transferable {
    var date: Date

    nonisolated static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { file in
            guard let png = Wallpaper.png(at: file.date) else { throw CocoaError(.fileWriteUnknown) }
            return png
        }
        .suggestedFileName("Ditherglow.png")
    }
}
