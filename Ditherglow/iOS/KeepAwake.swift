import SwiftUI
import UIKit

extension View {
    /// Stops the phone auto-locking while this view is on screen, as `Preferences.KeepAwake` says.
    func keepsScreenAwake() -> some View {
        modifier(KeepAwakeModifier())
    }
}

private struct KeepAwakeModifier: ViewModifier {
    @AppStorage(Preferences.keepAwakeKey) private var mode = Preferences.defaultKeepAwake
    @Environment(\.scenePhase) private var scenePhase
    @State private var isCharging = false

    private var staysAwake: Bool {
        guard scenePhase == .active else { return false }
        switch mode {
        case .never: return false
        case .whileCharging: return isCharging
        case .always: return true
        }
    }

    func body(content: Content) -> some View {
        content
            .task {
                UIDevice.current.isBatteryMonitoringEnabled = true
                updateCharging()
                for await _ in NotificationCenter.default.notifications(named: UIDevice.batteryStateDidChangeNotification) {
                    updateCharging()
                }
            }
            .onChange(of: staysAwake, initial: true) { _, staysAwake in
                UIApplication.shared.isIdleTimerDisabled = staysAwake
            }
    }

    private func updateCharging() {
        // `.full` means plugged in at 100%; the simulator reports `.unknown`.
        isCharging = [.charging, .full].contains(UIDevice.current.batteryState)
    }
}
