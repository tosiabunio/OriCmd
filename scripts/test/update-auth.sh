#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build
xcrun swiftc -swift-version 6 -parse-as-library OriCmd/App/UpdateVerification.swift \
  scripts/test/UpdateVerificationTests.swift -o build/update-verification-tests
build/update-verification-tests

# Verify the publishing CLI with a disposable key, never the real fork key.
scripts/build-update-signer.sh
fixture=$(mktemp -d "$PWD/build/update-signer-tests.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
build/update-signer keygen "$fixture/private.key" "$fixture/public.txt"
[ "$(stat -f %Lp "$fixture/private.key")" = 600 ]
if build/update-signer keygen "$fixture/private.key" "$fixture/public.txt" 2>/dev/null; then
  print -u2 'The signer overwrote an existing publishing key'; exit 1
fi
print 'ok   key generation protects the private key and refuses replacement'
print -n 'disposable disk image' > "$fixture/OriCmd-2026.10.0.dmg"
build/update-signer sign "$fixture/private.key" "$fixture/public.txt" "$fixture/OriCmd-2026.10.0.dmg" tosiabunio/OriCmd 2026.10.0
[ -s "$fixture/OriCmd-2026.10.0.manifest.json" ] && [ "$(stat -f %z "$fixture/OriCmd-2026.10.0.manifest.sig")" = 64 ]
print 'ok   the publishing tool produces a verified manifest and 64-byte signature'
build/update-signer keygen "$fixture/wrong.key" "$fixture/wrong-public.txt"
if build/update-signer sign "$fixture/wrong.key" "$fixture/public.txt" "$fixture/OriCmd-2026.10.0.dmg" tosiabunio/OriCmd 2026.10.0 2>/dev/null; then
  print -u2 'The signer accepted the wrong publishing key'; exit 1
fi
print 'ok   the publishing tool refuses a key the app does not trust'
