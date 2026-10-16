# AGENTS.md

Ditherglow is a macOS menu bar app that draws an animated, dithered sky behind the desktop icons. The palette follows the sun's altitude at the user's (time-zone-derived) location. See [README.md](README.md) for features and usage.

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
- The project uses file-system-synchronized groups: new files under `Ditherglow/` are picked up automatically, so don't edit `project.pbxproj` to add them.

## Architecture

| File | Role |
| --- | --- |
| `Ditherglow/DitherglowApp.swift` | `MenuBarExtra` (no Dock icon), preview `Window`, `Settings` scene |
| `Ditherglow/macOS/DesktopWindowController.swift` | One borderless window per screen at desktop level, rebuilt on screen changes; pauses a covered screen, and all of them while displays sleep or the session is locked |
| `Ditherglow/macOS/MenuBarIcon.swift` | 16×16 pixel-art orb template image for the menu bar (lit / outline) |
| `Ditherglow/macOS/Updater.swift` | Sparkle updater wrapper for the menu and Settings; feed URL in `macOS/Info.plist` |
| `DitherglowSaver/DitherglowSaverView.swift` | `ScreenSaverView` hosting `DitherglowView` for the `Ditherglow.saver` target |
| `Ditherglow/Shared/DitherglowView.swift` | `TimelineView` at 12 fps feeding the Metal shader via `colorEffect` |
| `Ditherglow/Shared/Ditherglow.metal` | Single stitchable pass: OKLab blob gradient evaluated once per dither block + 8×8 Bayer dither |
| `Ditherglow/Shared/Sky.swift` | Daybreak palette: named stops keyed by sun altitude, smoothstep-blended |
| `Ditherglow/Shared/Sun.swift` | Solar altitude and location from the bundled `Shared/zone.tab` (no location permission) |
| `Ditherglow/Shared/Preferences.swift` | `UserDefaults` keys, defaults and ranges |

`Shared/` is meant to stay platform-agnostic (no AppKit); AppKit-specific code goes in `macOS/`.

The `DitherglowSaver` target also syncs the `Ditherglow/` folder, with everything outside `Shared/` listed as a membership exception. A new app-only file outside `Shared/` must be added to that exception list (or it gets compiled into the saver). Load resources via `Bundle.ditherglow`, never `Bundle.main`: in the saver, the main bundle is Apple's `legacyScreenSaver` host.

## Conventions

- **Concurrency:** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Pure value/logic types (`Sky`, `Sun`, `Preferences`) are marked `nonisolated`. Values used inside `visualEffect` closures must be copied into locals first, since those run off the main actor.
- **Palette stops:** every `Sky.Stop` has exactly six colours, and slot *i* in one stop morphs into slot *i* in the next. Keep the order meaningful when editing, and keep stops sorted by altitude.
- **Shader contract:** colours reach the shader as a flat `[Float]` of sRGB triples (`count / 3` colours). Blending happens in OKLab inside the shader, not in Swift.
- **Performance:** the wallpaper runs all day. Keep the frame rate low and the shader to one pass; avoid per-pixel work that could be per-block, and never draw frames nobody can see (`DitherglowView.isPaused`).
- **Settings:** add new tunables to `Preferences` (key, default, range) and read them with `@AppStorage`.
- Comments explain *why*, as doc comments (`///`) on types and properties. Match the existing terse style.

## Git

- `main` holds the stable, released version; `develop` collects work for the next release.
- One branch per feature or fix, cut from `develop`, with its PR into `develop`. A release merges `develop` into `main`.
- Branches: `feat/`, `fix/`, `chore/`, `housekeep/` prefixes.
- Commits: conventional commits, `type(scope): description` (e.g. `feat(settings): add pixel size and speed settings`).
