#!/bin/bash
# Points git at the versioned hooks in .githooks, so pushes and merges run scripts/check.sh first.
set -euo pipefail
cd "$(dirname "$0")/.."
git config core.hooksPath .githooks
echo "Git hooks installed from .githooks"
