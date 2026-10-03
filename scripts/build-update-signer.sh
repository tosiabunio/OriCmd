#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun swiftc -swift-version 6 scripts/update-signing.swift OriCmd/App/UpdateVerification.swift -o build/update-signer
