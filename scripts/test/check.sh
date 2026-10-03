#!/bin/zsh
# Builds the app and runs the core tests without opening a file-manager window.
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 scripts/test/test_runner.py
mkdir -p build/logs
xcodebuild -project OriCmd.xcodeproj -scheme OriCmd -configuration Debug \
  -derivedDataPath build/DerivedData -destination 'platform=macOS' \
  -parallel-testing-enabled NO test > build/logs/core-tests.log 2>&1 || {
  tail -80 build/logs/core-tests.log
  exit 1
}
grep -E 'error:|warning:|TEST (SUCCEEDED|FAILED)|Test .*passed' build/logs/core-tests.log || true
missing=$(python3 scripts/test/loc.py)
[[ "$missing" == '[]' ]] || { print -u2 "$missing"; exit 1; }
