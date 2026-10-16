#!/bin/bash
# Installs the pinned SwiftFormat and SwiftLint, ahead of any versions preinstalled on the runner.
set -euo pipefail

bin="$RUNNER_TEMP/linters"
mkdir -p "$bin"

curl -fsSL -o "$RUNNER_TEMP/swiftformat.zip" \
    "https://github.com/nicklockwood/SwiftFormat/releases/download/$SWIFTFORMAT_VERSION/swiftformat.zip"
unzip -oq "$RUNNER_TEMP/swiftformat.zip" -d "$bin"

curl -fsSL -o "$RUNNER_TEMP/swiftlint.zip" \
    "https://github.com/realm/SwiftLint/releases/download/$SWIFTLINT_VERSION/portable_swiftlint.zip"
unzip -oq "$RUNNER_TEMP/swiftlint.zip" -d "$bin"

chmod +x "$bin/swiftformat" "$bin/swiftlint"
echo "$bin" >> "$GITHUB_PATH"
"$bin/swiftformat" --version
"$bin/swiftlint" version
