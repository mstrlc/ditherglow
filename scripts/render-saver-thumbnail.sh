#!/bin/bash
# Renders the screen saver's System Settings thumbnail (see render-saver-thumbnail.swift).
# Compiled rather than run as a script, so it can use the app's own palette from Sky.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
xcrun swiftc -parse-as-library -O -o "$out/render" \
    scripts/render-saver-thumbnail.swift \
    Ditherglow/Shared/Sky.swift Ditherglow/Shared/Sun.swift \
    Ditherglow/Shared/Preferences.swift Ditherglow/Shared/Bundle+Ditherglow.swift
"$out/render"
