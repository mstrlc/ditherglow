#!/bin/bash
# Everything CI checks, run by the git hooks before a push or merge. Skip once with --no-verify.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "› Lint"
scripts/lint.sh
echo "› Build"
scripts/build.sh
