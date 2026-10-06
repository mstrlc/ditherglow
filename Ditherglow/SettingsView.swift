import SwiftUI

/// Settings window: how big the dither pixels are and how fast the blobs drift.
struct SettingsView: View {
    @AppStorage(Preferences.blockSizeKey) private var blockSize = Preferences.defaultBlockSize
    @AppStorage(Preferences.speedKey) private var speed = Preferences.defaultSpeed

    var body: some View {
        Form {
            LabeledContent("Pixel size") {
                Slider(value: $blockSize, in: Preferences.blockSizeRange, step: 1)
                Text("\(Int(blockSize)) pt")
                    .monospacedDigit()
                    .frame(width: 70, alignment: .trailing)
            }
            LabeledContent("Speed") {
                Slider(value: $speed, in: Preferences.speedRange)
                Text(Preferences.loopDuration(speed: speed), format: .units(allowed: [.minutes, .seconds], width: .narrow, maximumUnitCount: 1))
                    .monospacedDigit()
                    .frame(width: 70, alignment: .trailing)
            }
            .help("Roughly how long one blob takes to loop around")
            Button("Restore Defaults") {
                blockSize = Preferences.defaultBlockSize
                speed = Preferences.defaultSpeed
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

#Preview {
    SettingsView()
}
