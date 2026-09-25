#!/bin/sh
# dotline.sh -- "." is the current line: the last one entered, LISTed, or
# in which an error occurred.  The ROM stores 40ECH in four places: line
# entry (1AB1H), EDIT (2E66H), each line LIST shows (2B5BH) and the error
# routine (19A8H, with ERL, before it looks for an ON ERROR handler -- so
# a trapped error moves it too).  Only line entry moved it here, so after
# ?/0 ERROR IN 20, LIST . showed another line and DELETE . deleted one.
# Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/dotline.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
fail() { echo "DOTLINE FAILED: $1"; printf '%s\n' "$2"; exit 1; }
out=$(TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" 2>&1 <<'EOF2' | grep '^[0-9=?]'

10 PRINT "=A"
20 X=1/0
30 PRINT "=C"
40 ON ERROR GOTO 60:Y=1/0
50 END
60 RESUME NEXT
RUN
LIST .
LIST 10
LIST .
LIST 10-30
LIST .
RUN 40
LIST .
DELETE .
LIST
EOF2
)
want='=A
?/0 ERROR IN 20
20 X=1/0
10 PRINT "=A"
10 PRINT "=A"
10 PRINT "=A"
20 X=1/0
30 PRINT "=C"
30 PRINT "=C"
40 ON ERROR GOTO 60:Y=1/0
10 PRINT "=A"
20 X=1/0
30 PRINT "=C"
50 END
60 RESUME NEXT'
[ "$out" = "$want" ] || fail "the current line after an error and after LIST" "$out"

# a ?SN in a DATA item names the DATA line: the ROM makes it the current
# line before the error routine (1991H-1994H -> 19A2H), so the message,
# ERL and "." agree.  Until 2026-09-25 "." stayed on the READ line (the
# 2026-09-23 audit, L-7).
out=$(TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" 2>&1 <<'EOF2' | grep '^[0-9=?]'

10 READ A
20 PRINT "=B"
30 DATA "12"
RUN
LIST .
PRINT "="ERL
NEW
10 READ B$,A
20 PRINT "=B"
30 DATA "AB"CD,5
RUN
LIST .
EOF2
)
want='?SN ERROR IN 30
30 DATA "12"
= 30 
?SN ERROR IN 30
30 DATA "AB"CD,5'
[ "$out" = "$want" ] || fail "the current line after ?SN in a DATA item" "$out"
echo "DOTLINE OK"
