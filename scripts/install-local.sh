#!/bin/zsh
# Builds this checkout as a Release app and installs it into /Applications as the next
# build of the fork: the counter in the repository's .git folder goes up by one on
# every install. About shows the calendar version and this local build number;
# the commit stays in bundle metadata for diagnostics.
set -euo pipefail
cd "$(dirname "$0")/.."

COUNTER="$(git rev-parse --git-common-dir)/oricmd-fork-build"
BUILD=$(( $(cat "$COUNTER" 2>/dev/null || echo 0) + 1 ))
COMMIT=$(git rev-parse --short HEAD)$(git diff --quiet HEAD || echo +)
LOG=build/install-local.log
mkdir -p build

echo "Building fork build $BUILD ($COMMIT)…"
if ! xcodebuild -project OriCmd.xcodeproj -scheme OriCmd -configuration Release \
  -derivedDataPath build/release/DerivedData ONLY_ACTIVE_ARCH=NO \
  ORICMD_FORK_BUILD=$BUILD ORICMD_FORK_COMMIT=$COMMIT build > $LOG 2>&1; then
  grep -E "error:" $LOG | sort -u
  echo "Build failed, see $LOG"
  exit 1
fi
APP=build/release/DerivedData/Build/Products/Release/OriCmd.app
codesign --verify --deep --strict "$APP"

# Only the installed copy quits: a test run's Debug app has the same name.
if pkill -f '^/Applications/OriCmd.app/Contents/MacOS/OriCmd'; then sleep 1; fi
ditto "$APP" /Applications/OriCmd.app
echo $BUILD > "$COUNTER"
open /Applications/OriCmd.app
echo "Installed OriCmd fork build $BUILD ($COMMIT)"
