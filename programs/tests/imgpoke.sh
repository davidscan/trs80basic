#!/bin/sh
# imgpoke.sh -- what a byte POKEd into the program image belongs to.  Image
# RAM is writable (the Dancing Demon keeps a buffer inside its own bytes),
# and the stored byte is part of the LINE it landed in, as on the machine:
# it moves with the line when an earlier line is added or deleted, and it is
# gone when that line is re-entered, deleted, or replaced by NEW or a LOAD.
# Until the 2026-09-19 audit (M-8) the store was keyed by address alone and
# never dropped: a program loaded later was read -- by PEEK and by the USR
# frame -- through the last program's POKEs.
# Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/imgpoke.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
dir=$(mktemp -d) || exit 2
fail() { echo "IMGPOKE FAILED: $1"; printf '%s\n' "$2"; rm -rf "$dir"; exit 1; }
run() { (cd "$dir" && TRS80_DUMB=1 TRS80_Z80="python3 $here/programs/tests/z80_stub.py" \
         gawk -b -f "$here/trs80basic.awk" 2>&1) | grep '^=' ; }
printf '10 REM ABCDEF\n20 PRINT "LOADED"\n' > "$dir/P.BAS"

# 17129: link(2) line(2) REM(1) blank(1) then the text, so "A" is at 17135;
# the line "5 REM" put in front of it is 6 bytes long
out=$(run <<'EOF2'

10 REM ABCDEF
100 POKE 17135,33
RUN
PRINT "=POKED";PEEK(17135)
DELETE 100-100
PRINT "=LOADER LINE DELETED, REM KEEPS ITS BYTE";PEEK(17135)
5 REM
PRINT "=A LINE ADDED IN FRONT: THE BYTE MOVED WITH ITS LINE";PEEK(17135+6)
DEFUSR3=&H7005:PRINT "=THE CORE SEES IT THERE";USR3(17135+6)
5
10 REM ABCDEF
PRINT "=LINE RE-ENTERED: FRESH";PEEK(17135)
POKE 17135,33:NEW
10 REM XYZ
PRINT "=NEW, THEN ANOTHER PROGRAM";PEEK(17135)
PRINT "=AND THE CORE";USR3(17135)
LOAD "P.BAS"
POKE 17135,33:PRINT "=POKED AGAIN";PEEK(17135)
LOAD "P.BAS"
PRINT "=THE SAME PROGRAM LOADED AGAIN: FRESH";PEEK(17135)
POKE 20000,7:PRINT "=FREE RAM";PEEK(20000)
EOF2
)
want='=POKED 33 
=LOADER LINE DELETED, REM KEEPS ITS BYTE 33 
=A LINE ADDED IN FRONT: THE BYTE MOVED WITH ITS LINE 33 
=THE CORE SEES IT THERE 33 
=LINE RE-ENTERED: FRESH 65 
=NEW, THEN ANOTHER PROGRAM 88 
=AND THE CORE 88 
=POKED AGAIN 33 
=THE SAME PROGRAM LOADED AGAIN: FRESH 65 
=FREE RAM 7 '
[ "$out" = "$want" ] || fail "POKEs into the program image" "$out"
rm -rf "$dir"
echo "IMGPOKE OK"
