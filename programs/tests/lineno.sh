#!/bin/sh
# lineno.sh -- the line number behind GOTO, GOSUB, RUN and THEN, as the
# ROM's line-number reader takes it (1E5AH, the one reader for all four:
# GOSUB and RUN n join the GOTO code at 1EC1H/1EC2H, IF's number jumps
# to 1EC2H from 2050H).  It starts at 0 and returns at the first byte that
# is not a digit, so a bare GOTO is GOTO 0; while it accumulates, a value
# past 6552 with a digit still to come is ?SN (1E62H-1E66H), so 65530 and
# up cannot be named -- ?SN, never ?UL.  A number that names no line is
# ?UL from the locate at 1ED9H, and RUN n reaches it the same way after
# clearing the variables (1EA9H), so RUN 0 with no line 0 and RUN 10 in
# an empty program are ?UL.  Until 2026-09-25 a bare GOTO was ?SN, GOTO
# 70000 was ?UL, RUN 0 ran from the first line and RUN 10 in an empty
# program was silent (the 2026-09-23 audit, L-5).
# Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/lineno.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
fail() { echo "LINENO FAILED: $1"; printf '%s\n' "$2"; exit 1; }
repl() { TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" 2>&1 | grep '^[A-Z?=0-9]' | grep -v '^READY\|^MEM SIZE\|^TRS-80\|^R/S L2\|^man \|^"help' ; }

out=$(repl <<'EOF'

10 PRINT "A":GOTO
20 PRINT "B"
RUN
0 PRINT "ZERO":END
RUN 10
NEW
10 GOTO 65529
RUN
NEW
10 GOTO 65530
RUN
NEW
10 GOTO 70000
RUN
NEW
10 GOSUB 70000
RUN
NEW
10 IF 1 THEN 70000
RUN
NEW
10 X=1:GOTO X
20 PRINT "C"
RUN
NEW
10 PRINT "D"
RUN 0
RUN 20
RUN 10
NEW
RUN 10
RUN
PRINT "END"
EOF
)
want='A
?UL ERROR IN 10
A
ZERO
?UL ERROR IN 10
?SN ERROR IN 10
?SN ERROR IN 10
?SN ERROR IN 10
?SN ERROR IN 10
?UL ERROR IN 10
?UL ERROR
?UL ERROR
D
?UL ERROR
END'
[ "$out" = "$want" ] || fail "GOTO, GOSUB, THEN and RUN line numbers" "$out"
echo "LINENO OK"
