#!/bin/zsh
# Runs on isolated test directories and the ru.themmag.OriCmd.tests settings suite.
set -euo pipefail
cd "$(dirname "$0")/../.."
run() { /opt/homebrew/bin/timeout 90 scripts/test/run.sh "$1" "$2"; }
scripts/test/mkdata.sh
run ux-palette-search 'cmd+shift+p wait text:copy wait'
rg -q 'Copy…' build/shots/ux-palette-search-sheet.txt
rg -q '^F5$' build/shots/ux-palette-search-sheet.txt
run ux-palette-copyquery 'alt+r wait text:eadme escape cmd+shift+p wait text:copy enter wait'
rg -q 'Only files of this type:' build/shots/ux-palette-copyquery-sheet.txt
run ux-palette-execute 'cmd+shift+p wait text:cm_MkDir enter wait text:palette-made enter wait'
[[ -d build/testdata/left/palette-made ]]
run ux-palette-disabled 'cmd+shift+p wait text:cm_CloseCurrentTab enter wait'
[[ -f build/shots/ux-palette-disabled-sheet.png ]]
run ux-palette-initial 'cmd+shift+p wait enter wait'
[[ -f build/shots/ux-palette-initial-sheet.png ]]
run ux-palette-focus 'alt+r wait text:eadme escape cmd+shift+p wait escape down accessibilitydump'
[[ ! -f build/shots/ux-palette-focus-sheet.png ]]
rg -q 'cursor:' build/shots/ux-palette-focus-panels.txt
run ux-palette-empty 'cmd+shift+p wait text:no_such_command_928 wait'
! rg -q '^F5$|^Copy…$' build/shots/ux-palette-empty-sheet.txt
printf '[Shortcuts]\nM+J=cm_Copy\n' > build/palette-shortcuts.ini
run ux-palette-keys "importini:$PWD/build/palette-shortcuts.ini cmd+shift+p wait text:cm_Copy wait"
rg -q '⌘J' build/shots/ux-palette-keys-sheet.txt
UI_LANGUAGE=ru run ux-palette-ru 'cmd+shift+p wait text:cm_MkDir wait'
rg -q 'Создать' build/shots/ux-palette-ru-sheet.txt
print 'ok   search, execution, Esc, empty results, customized keys and Russian UI'
