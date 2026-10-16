#!/bin/bash
# Builds the app the way CI does: Debug and unsigned, into build/ci so it doesn't clash with Xcode's own build.
set -euo pipefail
cd "$(dirname "$0")/.."

# Since Xcode 26 the Metal compiler is a separate download, and the shader can't build without it.
xcrun metal -v >/dev/null 2>&1 || xcodebuild -downloadComponent MetalToolchain

xcodebuild -project Ditherglow.xcodeproj -scheme Ditherglow -configuration Debug \
    -destination 'generic/platform=macOS' -derivedDataPath build/ci CODE_SIGNING_ALLOWED=NO -quiet build
