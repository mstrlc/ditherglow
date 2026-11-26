import SwiftUI

/// The app's one window: the sky preview on top, settings below, so changes show as they're made.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            PreviewView()
                .frame(height: 240)
            Divider()
            SettingsView()
        }
        .frame(width: 480)
    }
}

/// Scrub through today to tune the sky.
private struct PreviewView: View {
    @State private var followsClock = true
    @State private var hour = 12.0
    @AppStorage(Preferences.blockSizeKey) private var blockSize = Preferences.defaultBlockSize

    var body: some View {
        DitherglowView(dateOverride: followsClock ? nil : previewDate, speed: 0.5, blockSize: blockSize)
            .overlay(alignment: .bottom) {
                HStack {
                    Toggle("Live", isOn: $followsClock)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    // Shows the current time while live; grabbing it leaves live mode to scrub.
                    Slider(value: Binding(
                        get: { followsClock ? TimeOfDay.hour(of: .now) : hour },
                        set: {
                            hour = $0
                            followsClock = false
                        }
                    ), in: 0...24)
                    Text(TimeOfDay.summary(of: followsClock ? .now : previewDate))
                        .monospacedDigit()
                        .frame(width: 180, alignment: .trailing)
                }
                .padding(10)
                .background(.regularMaterial, in: .rect(cornerRadius: 10))
                .padding()
            }
    }

    private var previewDate: Date {
        TimeOfDay.date(hour: hour)
    }
}

#Preview {
    ContentView()
        .environment(Updater())
        .environment(CurrentLocation())
}
