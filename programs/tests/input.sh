#!/bin/sh
# input.sh -- INPUT answered with ENTER alone assigns nothing: the ROM tests
# the first byte of the line and skips to the end of the statement (21E8H,
# and 2229H at a ?? prompt), so "the variables will have the value they
# were previously assigned" (Level II manual p.3-9).  That is the
# press-ENTER-to-keep-the-current-value prompt.  Self-checking: exits 1 on
# any mismatch.  Run from the repo root:  sh programs/tests/input.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
tmp=$(mktemp) || exit 2
fail() { echo "INPUT FAILED: $1"; printf '%s\n' "$2"; rm -f "$tmp"; exit 1; }
cat > "$tmp" <<'BAS'
10 A=5:B$="OLD":C=9
20 INPUT A:PRINT "A=";A
30 INPUT B$:PRINT "B$=[";B$;"]"
40 INPUT A,C:PRINT "BOTH KEPT";A;C
50 INPUT A,C:PRINT "FIRST TAKEN";A;C
60 INPUT A:PRINT "BLANKS ARE A VALUE";A
70 INPUT "SPEED";A:PRINT "TYPED";A
BAS
# answers: ENTER, ENTER, ENTER, "7" then ENTER at the ??, a line of blanks, 3
out=$(printf '\n\n\n7\n\n   \n3\n' | TRS80_Z80= "$here/basic" "$tmp" 2>&1)
want="? 
A= 5 
? 
B\$=[OLD]
? 
BOTH KEPT 5  9 
? 7
?? 
FIRST TAKEN 7  9 
?    
BLANKS ARE A VALUE 0 
SPEED? 3
TYPED 3 "
[ "$out" = "$want" ] || fail "empty INPUT lines" "$out"
rm -f "$tmp"
echo "INPUT OK"
