#!/bin/sh
# cont.sh -- CONT after a STOP in the middle of a line goes on with the
# statement behind the STOP (ROM 1DE4H: 40F7H holds the address of the
# statement to continue at), and a second CONT, with nothing left to
# continue, is ?CN (1DE9H-1DEBH).  A CONT that ran the STOP's line twice, or
# started the line over, passed the suite until 2026-09-24 (M-13).
# Self-checking: exits 1 on a mismatch.  Run from the repo root:
#     sh programs/tests/cont.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
fail() { echo "CONT FAILED: $1"; printf '%s\n' "$2"; exit 1; }
run() { printf '%b' "$1" | TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" 2>&1 | sed -n '/^>RUN/,$p'; }

out=$(run '\n10 PRINT "A";:STOP:PRINT "B";:PRINT "C"\nRUN\nCONT\nCONT\n')
want='>RUN
A
BREAK IN 10
READY
>CONT
BC
READY
>CONT
?CN ERROR
READY
>'
[ "$out" = "$want" ] || fail "CONT after a mid-line STOP, then ?CN" "$out"

# CONT after END goes on too: END and STOP share 1DB4H-1DD1H, which saves
# the line and the statement behind the END in 40F5H/40F7H; only the
# BREAK message differs (1DDEH)
out=$(run '\n10 PRINT "A":END:PRINT "B"\nRUN\nCONT\n')
want='>RUN
A
READY
>CONT
B
READY
>'
[ "$out" = "$want" ] || fail "CONT after END continues behind the END" "$out"
echo "CONT OK"
