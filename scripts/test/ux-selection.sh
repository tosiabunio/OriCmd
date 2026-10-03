#!/bin/zsh
# Runs on isolated test directories and the ru.themmag.OriCmd.tests settings suite.
set -euo pipefail
cd "$(dirname "$0")/../.."
run() { /opt/homebrew/bin/timeout 90 scripts/test/run.sh "$1" "$2"; }
scripts/test/mkdata.sh
run ux-selection-full 'home down insert down accessibilitydump'
rg -Fq 'alpha | selected: true' build/shots/ux-selection-full-accessibility.txt
! rg -Fq 'many | selected: true' build/shots/ux-selection-full-accessibility.txt
run ux-selection-brief 'home down insert down cmd+1 accessibilitydump'
rg -Fq 'alpha | selected: true' build/shots/ux-selection-brief-accessibility.txt
run ux-selection-thumbs 'home down insert down cmd+4 wait accessibilitydump'
rg -Fq 'alpha | selected: true' build/shots/ux-selection-thumbs-accessibility.txt
defaults write ru.themmag.OriCmd.tests SelectionMarkers -bool NO
run ux-selection-off 'home down insert down accessibilitydump'
rg -Fq 'alpha | selected: true' build/shots/ux-selection-off-accessibility.txt
print 'ok   marks and cursor remain distinct across views and with markers disabled'
