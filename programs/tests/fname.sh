#!/bin/sh
# fname.sh -- the file name of LOAD, SAVE, RUN, MERGE, CLOAD and CSAVE is a
# string EXPRESSION, as in Disk BASIC (the ROM evaluates it: 2BF8H, 2C32H):
# SAVE F$, RUN "PART"+N$+".BAS".  Only a lone quoted literal used to be:
# SAVE F$ wrote a file named F$, and RUN F$ re-ran the program in memory.
# The raw unquoted name (EXT: LOAD mygame.bas) still works for anything
# that does not start with a quote or a $-name.
# Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/fname.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
dir=$(mktemp -d) || exit 2
fail() { echo "FNAME FAILED: $1"; printf '%s\n' "$2"; rm -rf "$dir"; exit 1; }
cd "$dir" || exit 2
printf '10 PRINT "PART TWO RAN"\n' > PART2.BAS
cat > one.bas <<'BAS'
10 N$="2":A$="OUT"
20 SAVE A$+N$:PRINT "SAVED"
30 RUN "PART"+N$+".BAS"
BAS
out=$(TRS80_Z80= "$here/basic" one.bas 2>&1 </dev/null)
want="SAVED
PART TWO RAN"
[ "$out" = "$want" ] || fail "SAVE and RUN with a string expression" "$out"
[ -f OUT2 ] && [ ! -e 'A$+N$' ] || fail "SAVE A\$+N\$ wrote the wrong file" "$(ls)"
grep -q '^30 RUN "PART"+N\$+".BAS"$' OUT2 || fail "the saved listing" "$(cat OUT2)"

# RUN F$ runs the named file, not the program in memory; a number is ?TM
printf '10 F$="PART2.BAS":RUN F$\n' > two.bas
out=$(TRS80_Z80= "$here/basic" two.bas 2>&1 </dev/null)
[ "$out" = "PART TWO RAN" ] || fail "RUN F\$" "$out"
printf '10 F$="PART2.BAS":LOAD F$+1\n' > three.bas
out=$(TRS80_Z80= "$here/basic" three.bas 2>&1 </dev/null)
[ "$out" = "?TM ERROR IN 10" ] || fail "a type mismatch inside the name is ?TM" "$out"

# the raw name (EXT), the quoted name with ,R, and MERGE by variable
out=$(TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" 2>&1 <<'EOF2' | grep '^[0-9=P]'

LOAD PART2.BAS
LIST
M$="one.bas":MERGE M$
LIST 20
LOAD "PART2.BAS",R
EOF2
)
want='10 PRINT "PART TWO RAN"
20 SAVE A$+N$:PRINT "SAVED"
PART TWO RAN'
[ "$out" = "$want" ] || fail "raw name, MERGE by variable, quoted name with ,R" "$out"
cd / ; rm -rf "$dir"
echo "FNAME OK"
