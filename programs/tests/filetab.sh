#!/bin/sh
# filetab.sh -- PRINT#'s TAB takes its column as PRINT's TAB does, through
# the byte converter (2B1CH -> 0A7FH, CINT's own conversion): a double is
# a single first, so TAB(4.99999999#) is column 5, and a column outside
# 0-255 is ?FC.  Until 2026-11-04 PRINT#'s copy floored the raw value
# (column 4) and padded any width, TAB(300) included (a sibling of the
# byteconv fix, afeef5f).
# Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/filetab.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
dir=$(mktemp -d) || exit 2
fail() { echo "FILETAB FAILED: $1"; printf '%s\n' "$2"; rm -rf "$dir"; exit 1; }
run() { (cd "$dir" && TRS80_Z80= TRS80_DUMB=1 "$here/basic" t.bas 2>&1); }

cat > "$dir/t.bas" <<'BAS'
10 ON ERROR GOTO 100
20 OPEN "O",1,"T":PRINT#1,TAB(4.99999999#);"A":PRINT#1,TAB(3);"B"
30 PRINT#1,TAB(300);"C"
40 PRINT#1,TAB(-1);"D"
50 CLOSE:OPEN "I",1,"T"
60 IF EOF(1) THEN CLOSE:END
70 LINE INPUT#1,A$:PRINT LEN(A$);A$:GOTO 60
100 PRINT "ERR";ERR;"IN";ERL:RESUME NEXT
BAS
out=$(run)
want='ERR 8 IN 30 
ERR 8 IN 40 
 6      A
 4    B'
[ "$out" = "$want" ] || fail "TAB's column in PRINT#" "$out"
rm -rf "$dir"
echo "FILETAB OK"
