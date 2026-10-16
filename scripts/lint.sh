#!/bin/bash
# Lints the way CI does. Fix formatting with `swiftformat .`.
set -euo pipefail
cd "$(dirname "$0")/.."

for tool in swiftformat swiftlint; do
    command -v "$tool" >/dev/null || { echo "$tool not found: brew install swiftformat swiftlint" >&2; exit 1; }
done

swiftformat --lint .
swiftlint lint --strict --quiet
