import SwiftUI

/// Preview window: scrub through today to tune the sky.
struct ContentView: View {
    @State private var followsClock = true
    @State private var hour = 12.0
    @AppStorage(Preferences.blockSizeKey) private var blockSize = Preferences.defaultBlockSize

    var body: some View {
        DitherglowView(dateOverride: followsClock ? nil : previewDate, speed: 0.5, blockSize: blockSize)
            .overlay(alignment: .bottom) {
                HStack {
                    Toggle("Live", isOn: $followsClock)
                    Slider(value: $hour, in: 0...24)
                        .disabled(followsClock)
                    Text(label)
                        .monospacedDigit()
                        .frame(width: 210, alignment: .trailing)
                }
                .padding(10)
                .background(.regularMaterial, in: .rect(cornerRadius: 10))
                .padding()
            }
            .frame(minWidth: 560, minHeight: 360)
    }

    private var previewDate: Date {
        Calendar.current.startOfDay(for: .now).addingTimeInterval(hour * 3600)
    }

    private var label: String {
        let date = followsClock ? Date.now : previewDate
        let altitude = Sky.altitude(at: date)
        return "\(date.formatted(date: .omitted, time: .shortened)) · \(Sky.phase(altitude: altitude)) "
            + String(format: "%.0f°", altitude)
    }
}

#Preview {
    ContentView()
}
