# CLAUDE.md

Ditherglow is a macOS menu bar app that draws an animated, dithered sky behind the desktop icons. The palette follows the sun's altitude at the user's (time-zone-derived) location. See [README.md](README.md) for features and usage.

## Build

```bash
xcodebuild -project Ditherglow.xcodeproj -scheme Ditherglow -configuration Debug build
```

- macOS 14+ deployment target, Swift 6, Xcode 16+.
- No package dependencies and no test target.
- The project uses file-system-synchronized groups: new files under `Ditherglow/` are picked up automatically, so don't edit `project.pbxproj` to add them.

## Architecture

| File | Role |
| --- | --- |
| `Ditherglow/DitherglowApp.swift` | `MenuBarExtra` (no Dock icon), preview `Window`, `Settings` scene |
| `Ditherglow/macOS/DesktopWindowController.swift` | One borderless window per screen at desktop level, rebuilt on screen changes |
| `Ditherglow/Shared/DitherglowView.swift` | `TimelineView` at 12 fps feeding the Metal shader via `colorEffect` |
| `Ditherglow/Shared/Ditherglow.metal` | Single stitchable pass: OKLab blob gradient evaluated once per dither block + 8×8 Bayer dither |
| `Ditherglow/Shared/Sky.swift` | Daybreak palette: named stops keyed by sun altitude, smoothstep-blended |
| `Ditherglow/Shared/Sun.swift` | Solar altitude and location from the bundled `Shared/zone.tab` (no location permission) |
| `Ditherglow/Shared/Preferences.swift` | `UserDefaults` keys, defaults and ranges |

`Shared/` is meant to stay platform-agnostic (no AppKit); AppKit-specific code goes in `macOS/`.

## Conventions

- **Concurrency:** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Pure value/logic types (`Sky`, `Sun`, `Preferences`) are marked `nonisolated`. Values used inside `visualEffect` closures must be copied into locals first, since those run off the main actor.
- **Palette stops:** every `Sky.Stop` has exactly six colours, and slot *i* in one stop morphs into slot *i* in the next. Keep the order meaningful when editing, and keep stops sorted by altitude.
- **Shader contract:** colours reach the shader as a flat `[Float]` of sRGB triples (`count / 3` colours). Blending happens in OKLab inside the shader, not in Swift.
- **Performance:** the wallpaper runs all day. Keep the frame rate low and the shader to one pass; avoid per-pixel work that could be per-block.
- **Settings:** add new tunables to `Preferences` (key, default, range) and read them with `@AppStorage`.
- Comments explain *why*, as doc comments (`///`) on types and properties. Match the existing terse style.

## Git

- Branches: `feat/`, `fix/`, `chore/`, `housekeep/` prefixes.
- Commits: conventional commits, `type(scope): description` (e.g. `feat(settings): add pixel size and speed settings`).
