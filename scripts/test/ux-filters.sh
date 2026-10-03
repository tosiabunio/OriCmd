#!/bin/zsh
# Runs on isolated test directories and the ru.themmag.OriCmd.tests settings suite.
set -euo pipefail
cd "$(dirname "$0")/../.."
run() { /opt/homebrew/bin/timeout 90 scripts/test/run.sh "$1" "$2"; }
scripts/test/mkdata.sh
run ux-filter-both 'cmd:cm_SrcUserSpec wait cmd+a text:*.txt enter wait ctrl+s text:file enter wait filterdump'
rg -q 'Text: file · Mask: \*\.txt · 2 of 17' build/shots/ux-filter-both-filters.txt
run ux-filter-zero 'cmd:cm_SrcUserSpec wait cmd+a text:*.md enter wait ctrl+s text:file enter wait filterdump'
rg -q '0 of 17' build/shots/ux-filter-zero-filters.txt
run ux-filter-clear 'cmd:cm_SrcUserSpec wait cmd+a text:*.txt enter wait ctrl+s text:file enter wait clearfilters wait filterdump'
rg -q '^No filters$' build/shots/ux-filter-clear-filters.txt
run ux-filter-escape 'cmd:cm_SrcUserSpec wait cmd+a text:*.txt enter wait ctrl+s text:file escape wait filterdump'
rg -q '^Mask: \*\.txt · 7 of 17' build/shots/ux-filter-escape-filters.txt
defaults write ru.themmag.OriCmd.tests CompactPanelHeader -bool NO
run ux-filter-classic 'ctrl+s text:nomatch enter wait filterdump clearfilters wait'
rg -q 'Text: nomatch · 0 of 17' build/shots/ux-filter-classic-filters.txt
UI_LANGUAGE=ru run ux-filter-ru 'ctrl+s text:file enter wait filterdump'
rg -q 'Текст: file · 3 из 17' build/shots/ux-filter-ru-filters.txt
print 'ok   combined filters, zero results, clear button, Esc, both headers and Russian UI'
