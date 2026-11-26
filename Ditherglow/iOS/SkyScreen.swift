import SwiftUI
import UIKit

/// The ambient screen: the live sky full screen, with an optional clock. A tap shows the controls,
/// which hide again after a few seconds and take the sky back to live.
struct SkyScreen: View {
    @AppStorage(Preferences.blockSizeKey) private var blockSize = Preferences.defaultBlockSize
    @AppStorage(Preferences.speedKey) private var speed = Preferences.defaultSpeed
    @AppStorage(Preferences.showsClockKey) private var showsClock = Preferences.defaultShowsClock
    @Environment(\.scenePhase) private var scenePhase

    @State private var showsControls = false
    /// The scrubbed hour, or `nil` to follow the clock.
    @State private var previewHour: Double?
    @State private var isScrubbing = false
    @State private var showsSettings = false
    /// Bumped on every interaction, restarting the countdown that hides the controls.
    @State private var lastInteraction = Date()

    /// How long the controls stay up after the last touch.
    private static let controlsTimeout = Duration.seconds(5)

    var body: some View {
        let previewDate = previewHour.map { TimeOfDay.date(hour: $0) }

        DitherglowView(dateOverride: previewDate, speed: speed, blockSize: blockSize, isPaused: scenePhase != .active)
            .overlay(alignment: .top) {
                if showsClock {
                    ClockView(dateOverride: previewDate)
                        .padding(.top, 60)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottom) {
                if showsControls {
                    // Ticks each minute so the live summary and slider keep up with the clock.
                    TimelineView(.everyMinute) { context in
                        controls(previewDate: previewDate, now: context.date)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .contentShape(.rect)
            .onTapGesture {
                withAnimation(.snappy) { showsControls.toggle() }
                if !showsControls { previewHour = nil }
                touch()
            }
            .task(id: lastInteraction) {
                guard showsControls, !isScrubbing, !showsSettings else { return }
                try? await Task.sleep(for: Self.controlsTimeout)
                guard !Task.isCancelled else { return }
                withAnimation(.snappy) {
                    showsControls = false
                    previewHour = nil
                }
            }
            .sheet(isPresented: $showsSettings, onDismiss: touch) {
                SettingsSheet(skyDate: previewDate ?? .now)
            }
            .task {
                // So wallpapers rendered from Shortcuts, which may run with no screen to ask, fit this one.
                if let scene = UIApplication.shared.connectedScenes.lazy.compactMap({ $0 as? UIWindowScene }).first {
                    Wallpaper.remember(scene.screen)
                }
            }
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
            .keepsScreenAwake()
    }

    private func controls(previewDate: Date?, now: Date) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(TimeOfDay.summary(of: previewDate ?? now))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
                if previewHour != nil {
                    Button("Live", systemImage: "dot.radiowaves.left.and.right") {
                        withAnimation(.snappy) { previewHour = nil }
                        touch()
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
                Button("Settings", systemImage: "gearshape.fill") {
                    showsSettings = true
                    touch()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
            }
            .font(.subheadline)
            // Shows the current time while live; dragging it scrubs through today.
            Slider(value: Binding(
                get: { previewHour ?? TimeOfDay.hour(of: now) },
                set: {
                    previewHour = $0
                    touch()
                }
            ), in: 0...24) { editing in
                isScrubbing = editing
                touch()
            }
        }
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
        // Dark whatever the system setting, so the panel sits quietly on the sky, which is dark half the day.
        .environment(\.colorScheme, .dark)
        // A tap on the panel itself keeps it up rather than reaching the sky's tap, which hides it.
        .onTapGesture(perform: touch)
        .padding()
        .frame(maxWidth: 560)
    }

    private func touch() {
        lastInteraction = Date()
    }
}

/// The time, large and quiet, over the sky.
private struct ClockView: View {
    /// The scrubbed moment, shown instead of the clock while previewing.
    var dateOverride: Date?

    var body: some View {
        TimelineView(.everyMinute) { context in
            let date = dateOverride ?? context.date
            VStack(spacing: 0) {
                Text(date, format: .dateTime.weekday(.wide).month().day())
                    .font(.title3.weight(.medium))
                Text(date, format: .dateTime.hour().minute())
                    .font(.system(size: 88, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .foregroundStyle(.white.opacity(0.85))
            .shadow(color: .black.opacity(0.25), radius: 12)
        }
    }
}

#Preview {
    SkyScreen()
}
