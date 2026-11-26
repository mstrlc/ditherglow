# AGENTS.md

Ditherglow is a macOS menu bar app that draws an animated, dithered sky behind the desktop icons, with an early iOS app (`Ditherglow iOS` target) that shows the same sky full screen. The palette follows the sun's altitude at the user's (time-zone-derived) location. See [README.md](README.md) for features and usage.

## Build

```bash
scripts/build.sh   # Debug, unsigned, into build/ci — what CI builds
scripts/lint.sh    # swiftformat --lint + swiftlint --strict; fix formatting with `swiftformat .`
scripts/check.sh   # both, as the git hooks run them
```

- macOS 14+ deployment target, Swift 6, Xcode 26+ (CI uses Xcode 26.6 on `macos-26`).
- CI (`.github/workflows/macos-github-ci.yml`) lints and builds every PR into `develop` or `main`. SwiftFormat and SwiftLint versions are pinned there; keep them in step with `--minversion` in `.swiftformat`.
- Run `scripts/install-hooks.sh` once per clone: `pre-push` and `pre-merge-commit` then run `scripts/check.sh`. Skip once with `--no-verify`.
- One package dependency, [Sparkle](https://sparkle-project.org) (updates); no test target.
- Releases are ad-hoc signed and hardened runtime is off: with it on, an ad-hoc app can't load the embedded Sparkle.framework (library validation needs a shared Team ID). Turn it back on together with Developer ID signing and notarization.
- The project uses file-system-synchronized groups, one per folder: the `Ditherglow macOS` target builds `Shared/` + `macOS/`, `Ditherglow iOS` builds `Shared/` + `iOS/`. New files are picked up automatically by the right target, so don't edit `project.pbxproj` to add them.
- Both targets produce `Ditherglow.app` (`PRODUCT_NAME` is set explicitly, not the target name). Build the iOS app with the `Ditherglow iOS` scheme (iOS 17+). CI and `scripts/build.sh` only build macOS so far.

## Architecture

| File | Role |
| --- | --- |
| `Ditherglow/macOS/DitherglowApp.swift` | `MenuBarExtra` (no Dock icon), the main `Window` (preview on top, settings below) and the About `Window` |
| `Ditherglow/macOS/DesktopWindowController.swift` | One borderless window per screen at desktop level, rebuilt on screen changes; pauses a covered screen, and all of them while displays sleep or the session is locked |
| `Ditherglow/macOS/DockPresence.swift` | Dock icon and app menu while a window is open; menu bar only otherwise |
| `Ditherglow/macOS/MenuBarIcon.swift` | 16×16 pixel-art orb template image for the menu bar (lit / outline) |
| `Ditherglow/macOS/Updater.swift` | Sparkle updater wrapper for the menu and Settings; feed URL in `macOS/Info.plist` |
| `Ditherglow/Shared/DitherglowView.swift` | `TimelineView` at 12 fps feeding the Metal shader via `colorEffect` |
| `Ditherglow/Shared/Ditherglow.metal` | Single stitchable pass: OKLab blob gradient evaluated once per dither block + 8×8 Bayer dither |
| `Ditherglow/Shared/Sky.swift` | Daybreak palette: named stops keyed by sun altitude, smoothstep-blended |
| `Ditherglow/Shared/Sun.swift` | Solar altitude and location from the bundled `Shared/zone.tab` (no location permission) |
| `Ditherglow/Shared/Preferences.swift` | `UserDefaults` keys, defaults and ranges |
| `Ditherglow/Shared/SkyImage.swift` | CPU port of the shader for still PNGs (wallpapers): one evaluation per dither block, scaled up with hard edges |
| `Ditherglow/Shared/TimeOfDay.swift` | Hour-of-day maths and the "time · phase · altitude" summary behind both apps' scrubbers |
| `Ditherglow/iOS/SkyScreen.swift` | iOS ambient screen: the live sky with a clock; a tap shows the scrubber and settings, which hide after 5 s and return to live |
| `Ditherglow/iOS/SettingsSheet.swift` | iOS settings: pixel size, speed, clock, keep screen on, time zone or city |
| `Ditherglow/iOS/LivePhoto.swift` | Live Photo for an animated lock screen, built on a real capture's metadata (`iOS/LivePhotoReference/`, from livewall, MIT) so iOS accepts it as a wallpaper |
| `Ditherglow/iOS/RenderSkyIntent.swift` | The Render Sky Shortcuts action (App Intent): a wallpaper PNG of the sky now or at a given time |
| `Ditherglow/iOS/Wallpaper.swift` | Wallpaper-sized stills from the screen size saved at launch; `WallpaperFile` for the share sheet |
| `Ditherglow/iOS/WallpaperGuide.swift` | Walkthrough for Render Sky → Set Wallpaper Photo plus sunrise/sunset automations, with today's times |
| `Ditherglow/iOS/KeepAwake.swift` | Turns off auto-lock while the sky is on screen: never, while charging (default) or always |

`Shared/` is built into both apps, so it stays platform-agnostic (no AppKit or UIKit); it also holds the app icon and asset catalog. Mac-only code goes in `macOS/`, iOS-only code in `iOS/`.

## Conventions

- **Concurrency:** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Pure value/logic types (`Sky`, `Sun`, `Preferences`) are marked `nonisolated`. Values used inside `visualEffect` closures must be copied into locals first, since those run off the main actor.
- **Palette stops:** every `Sky.Stop` has exactly six colours, and slot *i* in one stop morphs into slot *i* in the next. Keep the order meaningful when editing, and keep stops sorted by altitude.
- **Live Photo wallpapers:** iOS's checks are undocumented; see the comment on `LivePhoto`. If a new iOS rejects them ("motion not supported"), refresh the reference from a camera Live Photo that works as a wallpaper with `scripts/live-photo-reference.swift IMG.HEIC IMG.MOV`.
- **Two renderers:** `SkyImage.swift` mirrors `Ditherglow.metal` line for line, because Shortcuts runs the app in the background, where iOS refuses GPU work. Change both together, then compare a still with the live view.
- **Shader contract:** colours reach the shader as a flat `[Float]` of sRGB triples (`count / 3` colours). Blending happens in OKLab inside the shader, not in Swift.
- **Performance:** the wallpaper runs all day. Keep the frame rate low and the shader to one pass; avoid per-pixel work that could be per-block, and never draw frames nobody can see (`DitherglowView.isPaused`).
- **Settings:** add new tunables to `Preferences` (key, default, range) and read them with `@AppStorage`.
- Comments explain *why*, as doc comments (`///`) on types and properties. Match the existing terse style.

## Git

- `main` holds the stable, released version; `develop` collects work for the next release.
- One branch per feature or fix, cut from `develop`, with its PR into `develop`. A release merges `develop` into `main`.
- Branches: `feat/`, `fix/`, `chore/`, `housekeep/` prefixes.
- Commits: conventional commits, `type(scope): description` (e.g. `feat(settings): add pixel size and speed settings`).
