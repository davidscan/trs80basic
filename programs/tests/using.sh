#!/bin/sh
# using.sh -- PRINT USING's statement, as the ROM parses and prints it
# (the 2026-09-26 audit, L-18):
#   the format is followed by ";" (2CC3H, RST 08H): PRINT USING F$,X is ?SN;
#   an item is followed by ";" or "," or the end of the statement (2DD5H-2DE2H):
#     PRINT USING "##";1 X is ?SN, PRINT USING "##";1,2 prints both;
#   more than 24 digit positions in one field is ?FC (2DC5H-2DC7H);
#   each item is printed as soon as it is formatted (2DD0H), so what stands
#     before a failing item is on the screen when the error comes.
# Self-checking: exits 1 on any mismatch.  Run from the repo root:
#   sh programs/tests/using.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
tmp=$(mktemp) || exit 2
fail() { echo "USING FAILED: $1"; printf '%s\n' "$2" | sed 's/$/|/'; rm -f "$tmp"; exit 1; }
run() { TRS80_Z80= "$here/basic" "$tmp" 2>&1 </dev/null; }

cat > "$tmp" <<'BAS'
10 ON ERROR GOTO 100
20 PRINT USING "##";1,2
30 PRINT USING "##",1
40 PRINT USING "#########################";1
50 PRINT USING "########################";1
60 PRINT USING "##";1,"A"
65 PRINT USING "##";1 X
70 PRINT USING "## AND ##";1,2;
75 PRINT "!"
80 PRINT "END"
90 END
100 PRINT "ERR";ERR/2+1;"IN";ERL:RESUME NEXT
BAS
out=$(run)
want=" 1 2
ERR 2 IN 30 
ERR 5 IN 40 
                       1
 1ERR 13 IN 60 
 1ERR 2 IN 65 
 1 AND  2!
END"
[ "$out" = "$want" ] || fail "PRINT USING" "$out"

rm -f "$tmp"
echo "USING OK"
