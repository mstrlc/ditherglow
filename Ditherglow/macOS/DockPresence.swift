import AppKit
import SwiftUI

/// Ditherglow lives in the menu bar (`LSUIElement`), but while one of its windows is open it acts like a
/// regular app: a Dock icon, an app menu and a place in ⌘-Tab. It goes back to the menu bar when the last one closes.
private enum DockPresence {
    static var openWindows = 0 {
        didSet {
            NSApp.setActivationPolicy(openWindows > 0 ? .regular : .accessory)
            if openWindows > 0 { NSApp.activate() }
        }
    }
}

extension View {
    /// Shows the app in the Dock for as long as this window's content is on screen.
    func showsInDock() -> some View {
        onAppear { DockPresence.openWindows += 1 }
            .onDisappear { DockPresence.openWindows -= 1 }
    }
}
