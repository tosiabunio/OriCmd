#!/bin/zsh
# Runs on isolated test directories and the ru.themmag.OriCmd.tests settings suite.
set -euo pipefail
cd "$(dirname "$0")/../.."
run() { /opt/homebrew/bin/timeout 90 scripts/test/run.sh "$1" "$2"; }
scripts/test/mkdata.sh
run ux-copy-marked 'home down space space f5 wait'
rg -q 'Marked selection · 2 folders' build/shots/ux-copy-marked-sheet.txt
rg -q 'alpha · beta' build/shots/ux-copy-marked-sheet.txt
rg -q 'Existing files: 1. Ask user' build/shots/ux-copy-marked-sheet.txt
run ux-copy-cursor 'alt+r wait text:eadme escape f6 wait'
rg -q '^Move$' build/shots/ux-copy-cursor-sheet.txt
rg -q 'Item under cursor · 1 file' build/shots/ux-copy-cursor-sheet.txt
run ux-copy-filter 'home down space space f5 wait tab text:*.txt wait'
rg -q 'Only: \*\.txt' build/shots/ux-copy-filter-sheet.txt
run ux-copy-filter-run 'home down space space f5 wait tab text:*.txt enter wait wait'
cmp build/testdata/left/alpha/inside.txt build/testdata/right/alpha/inside.txt
[[ ! -e build/testdata/right/beta ]]
scripts/test/mkdata.sh
run ux-copy-queue 'home down space space f5 wait f2 wait wait'
diff -rq build/testdata/left/alpha build/testdata/right/alpha
diff -rq build/testdata/left/beta build/testdata/right/beta
UI_LANGUAGE=ru run ux-copy-ru 'home down space space f5 wait'
rg -q 'Отмеченные элементы · 2 папки' build/shots/ux-copy-ru-sheet.txt
print 'ok   copy/move scope, names, rules, filtering, F2 queue and Russian UI'
