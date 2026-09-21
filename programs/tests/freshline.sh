#!/bin/sh
# freshline.sh -- BREAK and READY start on a line of their own.  The ROM
# calls 20F9H -- a new line unless the cursor already stands at the start of
# one -- before the BREAK message (1DD7H) and before READY (1A22H).  So a
# program that ends behind PRINT "HI"; shows HI, then READY under it, and
# BREAK from column 0 leaves no blank line above itself.  A STOP typed at
# the prompt prints a bare BREAK (line 65535 has no " IN", 1A11-1A14).
# Until 2026-09-21: HIREADY, HIBREAK IN 20, and nothing for the typed STOP.
# Self-checking: exits 1 on any mismatch.  Run from the repo root:
#     sh programs/tests/freshline.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
fail() { echo "FRESHLINE FAILED: $1"; printf '%s\n' "$2" | head -30; exit 1; }

out=$(printf '\n10 PRINT "HI";\n20 STOP\n30 PRINT "X";:END\n40 PRINT "Y":STOP\nRUN\nCONT\nRUN 40\nSTOP\nPRINT 1;\n' |
      TRS80_DUMB=1 TRS80_Z80= perl -e 'alarm 20; exec @ARGV' gawk -b -f "$here/trs80basic.awk" 2>&1 |
      sed -n '/^>RUN$/,$p')
want='>RUN
HI
BREAK IN 20
READY
>CONT
X
READY
>RUN 40
Y
BREAK IN 40
READY
>STOP
BREAK
READY
>PRINT 1;
 1 
READY
>'
[ "$out" = "$want" ] || fail "transcript" "$out"
echo "FRESHLINE OK"
