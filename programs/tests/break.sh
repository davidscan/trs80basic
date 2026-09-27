#!/bin/sh
# break.sh -- the BREAK vector at 16396 (p30 brk_take).  Batch mode has no
# keyboard, so a Ctrl-C BYTE fed on stdin stands in for the key: INKEY$
# consumes it, and the pending BREAK fires at the next poll inside the
# loop.  Self-checking: exits 1 on any mismatch.  Run from the repo root:
#     sh programs/tests/break.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
tmp=$(mktemp) || exit 2
c3=$(printf '\003')
run() { printf '%s' "$1" | "$here/basic" "$tmp" 2>&1; }
fail() { echo "BREAK FIXTURE FAILED: $1"; echo "--- got:"; printf '%s\n' "$2"; rm -f "$tmp"; exit 1; }
# enabled (the seeded 201): one Ctrl-C breaks
printf '10 A$=INKEY$:FOR I=1 TO 500:NEXT:PRINT "NOT REACHED"\n' > "$tmp"
out=$(run "$c3
"); [ "$out" = "BREAK IN 10" ] || fail "enabled by default" "$out"
for v in 23 175 165; do
    printf '10 POKE 16396,%s:A$=INKEY$:FOR I=1 TO 500:NEXT:PRINT "STILL RUNNING";PEEK(16396)\n' "$v" > "$tmp"
    out=$(run "$c3
"); [ "$out" = "STILL RUNNING $v " ] || fail "POKE 16396,$v should disable BREAK" "$out"
done
# disabled, three Ctrl-C in a row: the override breaks.  A fed line ends in
# an ENTER byte, which is itself "another key", so the presses go in ONE line.
printf '10 POKE 16396,23:A$=INKEY$:B$=INKEY$:C$=INKEY$:FOR I=1 TO 500:NEXT:PRINT "NOT REACHED"\n' > "$tmp"
out=$(run "$c3$c3$c3
"); [ "$out" = "BREAK IN 10" ] || fail "three Ctrl-C in a row should override" "$out"
# a key between two Ctrl-C resets the count
printf '10 POKE 16396,23:A$=INKEY$:B$=INKEY$:C$=INKEY$:D$=INKEY$:FOR I=1 TO 500:NEXT:PRINT "STILL RUNNING"\n' > "$tmp"
out=$(run "$c3${c3}A$c3
"); [ "$out" = "STILL RUNNING" ] || fail "another key must reset the override count" "$out"
# re-enabled with 201 (and the DOS restore value 195 counts as enabled)
for v in 201 195; do
    printf '10 POKE 16396,23:POKE 16396,%s:A$=INKEY$:FOR I=1 TO 500:NEXT:PRINT "NOT REACHED"\n' "$v" > "$tmp"
    out=$(run "$c3
"); [ "$out" = "BREAK IN 10" ] || fail "POKE 16396,$v should enable BREAK" "$out"
done
# the matrix still shows the key while BREAK is disabled (row 6 bit 2)
printf '10 POKE 16396,23:PRINT PEEK(14400)\n' > "$tmp"
out=$(run "$c3
"); [ "$out" = " 4 " ] || fail "matrix should still show BREAK" "$out"
# CONT after BREAK starts the statement in front of the break, never the
# one already done behind it: N=N+1 once, RETURN once (Farvour 1D1E, 1DB4H;
# the 2026-09-26 audit, H-2).  At the prompt, so CONT can be typed.
out=$(printf '\n10 A$=INKEY$\n20 FOR I=1 TO 1000:N=N+1:NEXT\n30 PRINT N;I\n40 GOSUB 100:K=K+1:IF K<300 THEN 40\n50 PRINT "DONE";K:END\n100 RETURN\nRUN\n%s\nCONT\n' "$c3" |
      TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" 2>&1 | grep -v -e READY -e '^>' -e BREAK | tail -2)
[ "$out" = " 1000  1001 
DONE 300 " ] || fail "CONT after BREAK ran a finished statement again" "$out"
# (INPUT's Ctrl-C cancel is the tty line editor's path and cannot be fed in
# batch -- a real-terminal check covers it.)
rm -f "$tmp"
echo "BREAK FIXTURE OK"
