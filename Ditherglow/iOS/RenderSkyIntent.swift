import AppIntents
import Foundation
import UniformTypeIdentifiers

/// The Shortcuts action behind a wallpaper that follows the sun: pipe it into Set Wallpaper Photo
/// and run that from time-of-day automations.
struct RenderSkyIntent: AppIntent {
    static let title: LocalizedStringResource = "Render Sky"
    static let description = IntentDescription(
        "Makes a wallpaper of the Ditherglow sky as it looks now at your location, or at a time you choose. Use it with Set Wallpaper Photo.",
        categoryName: "Wallpaper"
    )

    @Parameter(title: "Time", description: "Leave empty for now.")
    var date: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Render the sky at \(\.$date)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        guard let png = Wallpaper.png(at: date ?? .now) else { throw RenderError.failed }
        return .result(value: IntentFile(data: png, filename: "Ditherglow.png", type: .png))
    }

    enum RenderError: Error, CustomLocalizedStringResourceConvertible {
        case failed

        var localizedStringResource: LocalizedStringResource { "Couldn't render the sky." }
    }
}

nonisolated struct DitherglowShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RenderSkyIntent(),
            phrases: ["Render the sky in \(.applicationName)", "Make a \(.applicationName) wallpaper"],
            shortTitle: "Render Sky",
            systemImageName: "sun.horizon"
        )
    }
}
