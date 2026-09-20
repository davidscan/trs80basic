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
# each target is resolved when its value is stored, after the assignments
# before it: INPUT I,A(I) answered 3,77 stores into A(3), as READ I,A(I)
# does.  INPUT# takes its targets the same way.
dir=$(mktemp -d) || exit 2
cat > "$tmp" <<'BAS'
10 DIM A(5),B(5)
20 INPUT I,A(I):PRINT "INPUT";I;A(0);A(3)
30 INPUT X$,A(LEN(X$)):PRINT "BY A STRING";A(2)
40 OPEN "O",1,"T.DAT":PRINT#1,2;88:CLOSE
50 OPEN "I",1,"T.DAT":INPUT#1,J,B(J):CLOSE
60 PRINT "INPUT#";J;B(0);B(2)
BAS
out=$(cd "$dir" && printf '3,77\nHI,9\n' | TRS80_Z80= "$here/basic" "$tmp" 2>&1)
rm -rf "$dir"
want="? 3,77
INPUT 3  0  77 
? HI,9
BY A STRING 9 
INPUT# 2  0  88 "
[ "$out" = "$want" ] || fail "a subscript uses the value just read" "$out"
rm -f "$tmp"
echo "INPUT OK"
