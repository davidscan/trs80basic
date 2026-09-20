#!/bin/sh
# print.sh -- what the ROM's PRINT does to the screen that a cursor move
# does not (the 2026-09-19 audit, H-4):
#   a comma PRINTS blanks to the next 16-column zone (2123-2135 -> 215A):
#     they are in the text stream, they overwrite what was on the screen,
#     and they reach the printer when video is routed to it; from column
#     48 on, a carriage return.
# Self-checking: exits 1 on any mismatch.  Run from the repo root:
#   sh programs/tests/print.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
tmp=$(mktemp) || exit 2
lp="$tmp.lp"
fail() { echo "PRINT FAILED: $1"; printf '%s\n' "$2" | sed 's/$/|/'; rm -f "$tmp" "$lp"; exit 1; }
run() { rm -f "$lp"; TRS80_Z80= TRS80_PRINTER="$lp" "$here/basic" "$tmp" 2>&1 </dev/null; }

# the text stream
printf '10 PRINT "NAME","SCORE","LEVEL"\n20 PRINT 1,2,3,4,5\n30 PRINT "A",\n40 PRINT "B"\n' > "$tmp"
out=$(run)
want="NAME            SCORE           LEVEL
 1               2               3               4 
 5 
A               B"
[ "$out" = "$want" ] || fail "commas in the text stream" "$out"

# the blanks overwrite what was on the screen
printf '10 CLS:PRINT@0,STRING$(40,"X");:PRINT@0,"A","B";\n20 S$="":FOR I=15360 TO 15360+39:S$=S$+CHR$(PEEK(I)):NEXT\n30 PRINT@128,"[";S$;"]"\n' > "$tmp"
out=$(run | tail -1 | sed "s/.*\[/[/")
[ "$out" = "[A               BXXXXXXXXXXXXXXXXXXXXXXX]" ] || fail "a comma did not blank the stale cells" "$out"

# video routed to the printer: the gap is printed there too.  It is 16
# blanks, not 15: the zone is measured from the video cursor (40A6H), which
# only the video driver moves, and the video driver is not being called
printf '10 POKE 16414,141:POKE 16415,5:PRINT "A","B":POKE 16414,88:POKE 16415,4\n' > "$tmp"
out=$(run); p=$(cat "$lp" 2>/dev/null)
[ "$p" = "A                B" ] || fail "commas routed to the printer" "$p"

rm -f "$tmp" "$lp"
echo "PRINT OK"
