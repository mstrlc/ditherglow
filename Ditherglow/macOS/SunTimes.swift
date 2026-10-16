import AppKit
import Observation

/// Today's sunrise and sunset for the menu, at the same place the sky's palette uses.
/// Recomputed when the day or the time zone changes, so the menu never shows yesterday's times.
@Observable
final class SunTimes {
    private(set) var sunrise: Date?
    private(set) var sunset: Date?

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        update()
        let center = NotificationCenter.default
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemTimeZoneDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            })
        }
        // A Mac asleep over midnight doesn't always get the day-change notification.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        })
    }

    private func update() {
        let times = Sun.riseAndSet(on: .now, Sun.location())
        sunrise = times.rise
        sunset = times.set
    }
}
