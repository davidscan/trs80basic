#!/bin/sh
# inputcomma.sh -- the separator behind INPUT's prompt is ";" (ROM 21D3H,
# RST 08H against 3BH), and behind PRINT @'s position it is "," (208DH,
# RST 08H against 2CH); anything else is ?SN, as on the machine.
# EXT (needs ext on / TRS80_EXT=1): INPUT "prompt",var is accepted and drops
# the "? " -- the later Microsoft BASICs' form, never Level II's; no period
# listing uses it, so the gate costs nothing (AUDIT 2026-09-23, L-2, ruled
# 2026-09-24).  PRINT @ has no such extension.
# Self-checking: exits 1 on any mismatch.  Run from the repo root:
#     sh programs/tests/inputcomma.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
fail() { echo "INPUTCOMMA FAILED: $1"; printf '%s\n' "$2"; exit 1; }
run() { printf '%b' "$1" | TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" 2>&1 | sed -n '/^>RUN/,$p'; }

# without ext the comma is ?SN; with it the prompt shows and "? " does not
out=$(run '\n10 INPUT "X",A\n20 PRINT "A=";A\nRUN\next on\nRUN\n7\n')
want='>RUN
?SN ERROR IN 10
READY
>ext on
READY
>RUN
X7
A= 7 
READY
>'
[ "$out" = "$want" ] || fail "INPUT \"X\",A: ?SN without ext, the prompt alone under it" "$out"

# the ";" form is the ROM's, with the "? ", ext or not
out=$(run '\n10 INPUT "X";A\n20 PRINT "A=";A\nRUN\n7\n')
want='>RUN
X? 7
A= 7 
READY
>'
[ "$out" = "$want" ] || fail "INPUT \"X\";A keeps the ? " "$out"

# PRINT @ takes a comma and nothing else, ext or not.  The cursor has
# already moved to the position (2083H) when the comma is demanded, so the
# error message starts a fresh line (19E6H -> 20F9H): the blank line is
# the machine's.
out=$(run '\n10 PRINT @5;"X"\n20 PRINT @5 "X"\n30 PRINT @5,"X"\nRUN\next on\nRUN\nDELETE 10-20\nRUN\n')
want='>RUN

?SN ERROR IN 10
READY
>ext on
READY
>RUN

?SN ERROR IN 10
READY
>DELETE 10-20
READY
>RUN
X
READY
>'
[ "$out" = "$want" ] || fail "PRINT @ needs its comma" "$out"
echo "INPUTCOMMA OK"
