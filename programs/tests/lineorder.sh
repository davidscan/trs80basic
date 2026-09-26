#!/bin/sh
# lineorder.sh -- the line index after lines are typed: a line past the
# last APPENDS to the index, a replaced line keeps its place, a line in
# between re-sorts it (index_add, p40; until 2026-09-26 every stored line
# re-sorted the whole index, and a pasted listing cost the square of its
# length: the 2026-09-23 audit, L-14).  What must not change: LIST and
# RUN order, a GOTO into a line typed later, the deletion of a line, "."
# as the last line entered, and the program image growing by the appended
# line (40F9H, the end-of-program pointer, before and after `50 REM`: a
# 6-byte line).
# Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/lineorder.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
fail() { echo "LINEORDER FAILED: $1"; printf '%s\n' "$2"; exit 1; }
out=$(TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" 2>&1 <<'EOF2' | grep -E '^([=?]|[0-9])'

30 PRINT "=THIRTY"
10 PRINT "=TEN"
20 PRINT "=TWENTY":GOTO 40
40 PRINT "=FORTY"
PRINT "=END BEFORE";PEEK(16633)+256*PEEK(16634)
50 REM
PRINT "=END AFTER";PEEK(16633)+256*PEEK(16634)
20 PRINT "=TWENTY AGAIN":GOTO 45
LIST
RUN
45 PRINT "=FORTY-FIVE"
RUN
10
RUN
LIST .
EOF2
)
before=$(printf '%s\n' "$out" | sed -n 's/^=END BEFORE *//p'); after=$(printf '%s\n' "$out" | sed -n 's/^=END AFTER *//p')
[ -n "$before" ] && [ "$((after - before))" = "6" ] || fail "the image grows by the appended 50 REM (6 bytes): $before -> $after" "$out"
rest=$(printf '%s\n' "$out" | grep -v '^=END')
want='10 PRINT "=TEN"
20 PRINT "=TWENTY AGAIN":GOTO 45
30 PRINT "=THIRTY"
40 PRINT "=FORTY"
50 REM
=TEN
=TWENTY AGAIN
?UL ERROR IN 20
=TEN
=TWENTY AGAIN
=FORTY-FIVE
=TWENTY AGAIN
=FORTY-FIVE
45 PRINT "=FORTY-FIVE"'
[ "$rest" = "$want" ] || fail "LIST, RUN and . after lines typed out of order, appended, replaced and deleted" "$rest"
echo "LINEORDER OK"
