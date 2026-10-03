#!/bin/zsh
# Runs on isolated test directories and the ru.themmag.OriCmd.tests settings suite.
set -euo pipefail
cd "$(dirname "$0")/../.."
run() { /opt/homebrew/bin/timeout 90 scripts/test/run.sh "$1" "$2"; }
scripts/test/mkdata.sh
run ux-operations-completed 'alt+r wait text:eadme escape f5 wait enter wait wait cmd:cm_Operations wait'
rg -q 'Completed' build/shots/ux-operations-completed-win1.txt
cmp build/testdata/left/readme.txt build/testdata/right/readme.txt
run ux-operations-skip 'alt+r wait text:eadme escape f5 wait enter wait wait click:Skip wait wait cmd:cm_Operations wait'
rg -q 'Finished with skipped items' build/shots/ux-operations-skip-win1.txt
rg -q '1 skipped item' build/shots/ux-operations-skip-win1.txt
run ux-operations-cancel 'alt+r wait text:eadme escape f5 wait enter wait wait cmd:cm_Operations wait tablepick:0 click:Cancel_Operation wait wait'
rg -q 'Cancelled' build/shots/ux-operations-cancel-win1.txt
[[ ! -f build/shots/ux-operations-cancel-sheet.png ]]
cmp build/testdata/left/readme.txt build/testdata/right/readme.txt
run ux-operations-clear 'alt+n wait text:otes escape f5 wait f2 wait wait cmd:cm_Operations wait click:Clear_Finished wait'
rg -q 'No operations this session' build/shots/ux-operations-clear-win1.txt
printf 'block' > build/testdata/right/block
run ux-operations-failed "alt+r wait text:eadme escape f5 wait text:$PWD/build/testdata/right/block/ enter wait wait enter wait cmd:cm_Operations wait"
rg -q 'Failed' build/shots/ux-operations-failed-win1.txt
UI_LANGUAGE=ru run ux-operations-ru 'cmd:cm_Operations wait'
rg -q 'В этом сеансе ещё нет операций' build/shots/ux-operations-ru-win1.txt
print 'ok   completed, skipped, cancelled, queued and cleared results and Russian UI'
