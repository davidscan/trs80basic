#!/bin/sh
# numov.sh -- a number too large, read from TEXT, is ?OV and nothing is
# stored.  The ROM has one ASCII-to-binary routine (0E6CH) behind VAL,
# INPUT, READ and INPUT#, and it leaves through 07B2H (?OV) when the
# exponent overflows -- at INPUT too, where a merely malformed number is
# ?REDO.  Until 2026-09-20 "1E39" came through as 1E+39 and "1E400" as an
# infinity, and PEEK(VARPTR(X)) of that infinity never returned.
# Self-checking: exits 1 on any mismatch.  Run from the repo root:
#     sh programs/tests/numov.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
tmp=$(mktemp -d) || exit 2
fail() { echo "NUMOV FAILED: $1"; printf '%s\n' "$2"; rm -rf "$tmp"; exit 1; }
run() { ( cd "$tmp" && TRS80_Z80= perl -e 'alarm 20; exec @ARGV' "$here/basic" "$@" 2>&1 ); }

# VAL: the limit itself passes, D exponents count, the sign does not matter
cat > "$tmp/val.bas" <<'BAS'
10 ON ERROR GOTO 100
20 PRINT VAL("1E38");VAL("-1.5D38")
30 X=7:X=VAL("1E39")
40 X=VAL("-1D39")
50 X=VAL("1E400")
60 PRINT "X KEPT";X:END
100 PRINT "ERR";ERR/2+1;"IN";ERL:RESUME NEXT
BAS
out=$(run "$tmp/val.bas")
want=" 1E+38 -1.5E+38 
ERR 6 IN 30 
ERR 6 IN 40 
ERR 6 IN 50 
X KEPT 7 "
[ "$out" = "$want" ] || fail "VAL" "$out"

# INPUT: ?OV ends the statement (no ?REDO), the variable keeps its value
cat > "$tmp/inp.bas" <<'BAS'
10 ON ERROR GOTO 100
20 A=5:INPUT A
30 PRINT "A KEPT";A:END
100 PRINT "ERR";ERR/2+1;"IN";ERL:RESUME NEXT
BAS
out=$(printf '1E400\n' | run "$tmp/inp.bas")
want="? 1E400
ERR 6 IN 20 
A KEPT 5 "
[ "$out" = "$want" ] || fail "INPUT" "$out"

# READ: the item before it is stored, the overflowing one is not
cat > "$tmp/read.bas" <<'BAS'
10 ON ERROR GOTO 100
20 B=9:READ A,B
30 PRINT "A, B KEPT";A;B:END
40 DATA 3,1E39
100 PRINT "ERR";ERR/2+1;"IN";ERL:RESUME NEXT
BAS
out=$(run "$tmp/read.bas")
want="ERR 6 IN 20 
A, B KEPT 3  9 "
[ "$out" = "$want" ] || fail "READ" "$out"

# INPUT#: the same reader
cat > "$tmp/file.bas" <<'BAS'
10 ON ERROR GOTO 100
20 OPEN "O",1,"OV.DAT":PRINT#1,"4 1E39":CLOSE
30 OPEN "I",1,"OV.DAT":B=9:INPUT#1,A,B
40 CLOSE:PRINT "A, B KEPT";A;B:END
100 PRINT "ERR";ERR/2+1;"IN";ERL:RESUME NEXT
BAS
out=$(run "$tmp/file.bas")
want="ERR 6 IN 30 
A, B KEPT 4  9 "
[ "$out" = "$want" ] || fail "INPUT#" "$out"

# an INTEGER target: a number that reads fine but does not fit -32768..32767
# is ?OV at the store (224AH -> 1F33H -> 0A7FH), at INPUT too, never ?REDO
cat > "$tmp/int.bas" <<'BAS'
10 ON ERROR GOTO 100
20 A%=5:INPUT A%
30 PRINT "A% KEPT";A%
40 OPEN "O",1,"IV.DAT":PRINT#1,"40000":CLOSE
50 OPEN "I",1,"IV.DAT":B%=9:INPUT#1,B%
60 CLOSE:PRINT "B% KEPT";B%:END
100 PRINT "ERR";ERR/2+1;"IN";ERL:RESUME NEXT
BAS
out=$(printf '40000\n' | run "$tmp/int.bas")
want="? 40000
ERR 6 IN 20 
A% KEPT 5 
ERR 6 IN 50 
B% KEPT 9 "
[ "$out" = "$want" ] || fail "INPUT and INPUT# into an integer" "$out"

# a store that fails ENDS the statement.  INPUT: the items behind the
# failed one are not assigned.  READ: the DATA pointer (40FFH) is committed
# only when the statement ends (1D96H from 2274H), so after the error it is
# where the statement began -- the handler's READ gets the FIRST item again
# -- while the items stored before the error keep their values.  (Until
# 2026-09-24 INPUT went on to B$, and READ's pointer moved past 40000.)
cat > "$tmp/int2.bas" <<'BAS'
10 ON ERROR GOTO 100
20 B$="OLD":INPUT A%,B$
30 PRINT "A%, B$ KEPT";A%;B$:END
100 PRINT "ERR";ERR/2+1;"IN";ERL:RESUME NEXT
BAS
out=$(printf '40000,NEW\n' | run "$tmp/int2.bas")
want="? 40000,NEW
ERR 6 IN 20 
A%, B$ KEPT 0 OLD"
[ "$out" = "$want" ] || fail "INPUT stops at the failed store" "$out"

cat > "$tmp/read2.bas" <<'BAS'
10 ON ERROR GOTO 100
20 C$="OLD":READ A,B%,C$
30 PRINT "A, B%, C$";A;B%;C$:END
40 DATA 5,40000,NEW
100 PRINT "ERR";ERR/2+1;"IN";ERL:READ R$:PRINT "NEXT ITEM ";R$:RESUME NEXT
BAS
out=$(run "$tmp/read2.bas")
want="ERR 6 IN 20 
NEXT ITEM 5
A, B%, C$ 5  0 OLD"
[ "$out" = "$want" ] || fail "READ's pointer after a failed store" "$out"

rm -rf "$tmp"
echo "NUMOV OK"
