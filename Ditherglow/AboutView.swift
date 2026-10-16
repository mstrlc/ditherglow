import SwiftUI

/// About window, laid out like the standard macOS About panel: icon, name, version, links and credits.
struct AboutView: View {
    @Environment(Updater.self) private var updater

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .padding(.bottom, 12)
            Text("Ditherglow")
                .font(.title2.bold())
            Text("Version \(Self.version)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 2)
            Text("An animated, dithered sky behind your desktop icons, following the sun.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            // Stacked at one width: each label stretches, and `fixedSize` caps them at the widest.
            VStack(spacing: 8) {
                Button {
                    updater.checkForUpdates()
                } label: {
                    Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!updater.canCheckForUpdates)
                Link(destination: URL(string: "https://ditherglow.app")!) {
                    Label("ditherglow.app", systemImage: "globe")
                        .frame(maxWidth: .infinity)
                }
                Link(destination: URL(string: "https://github.com/mstrlc/ditherglow")!) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                        .frame(maxWidth: .infinity)
                }
            }
            .fixedSize()
            .padding(.top, 16)
            Text("© 2026 Matyáš Strelec · GNU GPL v3\nUpdates by Sparkle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .frame(width: 300)
    }

    /// "1.1 (42)", from the bundle so it always matches the build.
    private static let version: String = {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }()
}

#Preview {
    AboutView()
        .environment(Updater())
}
