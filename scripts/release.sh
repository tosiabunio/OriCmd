#!/bin/zsh
# Publishes a signed OriCmd <version> to the fork's GitHub Releases:
# sets the version, builds and signs the DMG, commits, tags, pushes and uploads
# the disk image, signed manifest and signature.
# Usage: scripts/release.sh 0.2 [notes.md]   (without notes GitHub lists the commits)
# A letter suffix marks a pre-release version: 0.2b, 0.3rc1.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?usage: scripts/release.sh <version> [notes.md]}
NOTES=${2:-}
REPOSITORY=tosiabunio/OriCmd
SIGNING_KEY=${ORICMD_UPDATE_SIGNING_KEY:-$PWD/build/update-signing/private.key}
[ -f "$SIGNING_KEY" ] || { echo "Set ORICMD_UPDATE_SIGNING_KEY to the fork's private signing key"; exit 1; }
[[ $VERSION =~ '^[0-9]+(\.[0-9]+)*([a-z]+[0-9]*)?$' ]] || { echo "Version must look like 0.2, 1.0.1 or 0.2b"; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Commit or stash the changes first"; exit 1; }
[ "$(git branch --show-current)" = main ] || { echo "Releases are made from main"; exit 1; }
! git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null || { echo "Tag v$VERSION already exists"; exit 1; }
gh auth status >/dev/null

PROJECT=OriCmd.xcodeproj/project.pbxproj
BUILD=$(( $(awk '/CURRENT_PROJECT_VERSION/ { gsub(";", "", $3); print $3; exit }' $PROJECT) + 1 ))
sed -i '' -e "s/MARKETING_VERSION = [0-9A-Za-z.]*;/MARKETING_VERSION = $VERSION;/" \
  -e "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = $BUILD;/" $PROJECT

scripts/make-dmg.sh
DMG=build/OriCmd-$VERSION.dmg
[ -f $DMG ] || { echo "$DMG was not built"; exit 1; }

scripts/build-update-signer.sh
build/update-signer sign "$SIGNING_KEY" OriCmd/UpdateSigningPublicKey.txt "$DMG" "$REPOSITORY" "$VERSION"
MANIFEST=build/OriCmd-$VERSION.manifest.json
SIGNATURE=build/OriCmd-$VERSION.manifest.sig

git commit -q -am "Release $VERSION"
git tag "v$VERSION"
git push fork main "v$VERSION"

if [ -n "$NOTES" ]; then
  gh release create --repo "$REPOSITORY" "v$VERSION" "$DMG" "$MANIFEST" "$SIGNATURE" --title "OriCmd $VERSION" --notes-file "$NOTES"
else
  gh release create --repo "$REPOSITORY" "v$VERSION" "$DMG" "$MANIFEST" "$SIGNATURE" --title "OriCmd $VERSION" --generate-notes
fi

echo "Signed OriCmd $VERSION published to $REPOSITORY"
