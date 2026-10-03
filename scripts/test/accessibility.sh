#!/bin/zsh
# Exercise accessible file rows using the background Debug harness and disposable folders.
set -euo pipefail
cd "$(dirname "$0")/../.."
scripts/test/mkdata.sh
scripts/test/run.sh accessibility "accessibilitycheck"
report=build/shots/accessibility-accessibility.txt
[ -s "$report" ] && ! grep -q '^FAIL' "$report"
[ "$(grep -c '^ok' "$report")" -eq 9 ]
cat "$report"
scripts/test/run.sh accessibility-pick "axpick:readme.txt accessibilitydump"
grep -q '^readme.txt | selected: true' build/shots/accessibility-pick-accessibility.txt
print 'ok   accessible Pick selects the named file'
scripts/test/run.sh accessibility-open "axpress:alpha wait accessibilitydump"
[ -s build/shots/accessibility-open-accessibility.txt ]
grep -q '^inside.txt |' build/shots/accessibility-open-accessibility.txt
print 'ok   accessible Press opens a folder through the panel delegate'
