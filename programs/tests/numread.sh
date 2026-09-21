#!/bin/sh
# numread.sh -- what the ROM's ASCII-to-binary routine (0E65H/0E6CH) takes
# as a number, for VAL, READ, INPUT and INPUT# alike.  Every character
# after the first is fetched through RST 10H, which skips blanks, so
# VAL("1 2") is 12; a bare "1E" is 1 and a lone "." is 0; "!" and "#" end
# the number; "%" ends an INTEGER and is ?SN behind anything else (0EEEH:
# a ".", an exponent, a value past 32767, or the double-precision entry
# VAL uses).  A sign counts only as the FIRST character, and
# VAL does not skip leading blanks before it: VAL(" -5") is 0.  Until
# 2026-09-21 a regular expression stood in for the routine: VAL("1 2") was
# 1, and DATA 1 2 / DATA 1E / DATA . / DATA 7% were ?SN.
# Self-checking: exits 1 on any mismatch.  Run from the repo root:
#     sh programs/tests/numread.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
tmp=$(mktemp -d) || exit 2
fail() { echo "NUMREAD FAILED: $1"; printf '%s\n' "$2" | head -20; rm -rf "$tmp"; exit 1; }
run() { ( cd "$tmp" && TRS80_Z80= perl -e 'alarm 20; exec @ARGV' "$here/basic" "$@" 2>&1 ); }

cat > "$tmp/val.bas" <<'BAS'
10 ON ERROR GOTO 100
20 PRINT VAL("1 2");VAL("1E");VAL(".");VAL("1.5!");VAL("2#");VAL("1 E 3")
30 PRINT VAL(" -5");VAL("-5");VAL("- 5");VAL("1.2.3");VAL("12AB");VAL("1E-2");VAL("1E+");VAL("")
40 X=7:X=VAL("12%")
50 PRINT "X KEPT";X:END
100 PRINT "ERR";ERR/2+1;"IN";ERL:RESUME NEXT
BAS
out=$(run "$tmp/val.bas")
want=" 12  1  0  1.5  2  1000 
 0 -5 -5  1.2  12  .01  1  0 
ERR 2 IN 40 
X KEPT 7 "
[ "$out" = "$want" ] || fail "VAL" "$out"

# READ: the same forms; what is left over after the number is ?SN in the
# DATA line, a bad % is ?SN in the READ's line and the pointer stays
cat > "$tmp/read.bas" <<'BAS'
10 ON ERROR GOTO 100
20 READ A,B,C,D%,E,F#:PRINT A;B;C;D%;E;F#
30 DATA 1 2, 1E, ., 7%, - 4 , 2.5#
40 READ G:PRINT "G";G
50 READ X$:READ H:PRINT "H";H
60 READ X$:READ J:PRINT "J";J
70 READ K:PRINT "K";K
80 END
90 DATA 1.5%, 40000%, 3%
95 DATA 12X
100 PRINT "ERR";ERR/2+1;"IN";ERL:RESUME NEXT
BAS
out=$(run "$tmp/read.bas" | head -20)
want=" 12  1  0  7 -4  2.5 
ERR 2 IN 40 
G 0 
ERR 2 IN 50 
H 0 
J 3 
ERR 2 IN 95 
K 0 "
[ "$out" = "$want" ] || fail "READ" "$out"

# INPUT: the same reader; left-over text is ?REDO, a bad % is ?SN
cat > "$tmp/inp.bas" <<'BAS'
10 ON ERROR GOTO 100
20 INPUT A,B,C%:PRINT A;B;C%
30 INPUT D:PRINT "D";D
40 INPUT E:PRINT "E KEPT";E:END
100 PRINT "ERR";ERR/2+1;"IN";ERL:RESUME NEXT
BAS
out=$(printf '1 2 3, 1E, 9%%\n5X\n5 .\n1.5%%\n' | run "$tmp/inp.bas")
want="? 1 2 3, 1E, 9%
 123  1  9 
? 5X
?REDO
? 5 .
D 5 
? 1.5%
ERR 2 IN 40 
E KEPT 0 "
[ "$out" = "$want" ] || fail "INPUT" "$out"

# INPUT#: a number in a file is read by the same routine
cat > "$tmp/file.bas" <<'BAS'
10 OPEN "O",1,"N.DAT":PRINT#1,"1E":PRINT#1,"7%":PRINT#1,".":CLOSE
20 OPEN "I",1,"N.DAT":INPUT#1,A,B%,C:CLOSE:PRINT A;B%;C
BAS
out=$(run "$tmp/file.bas")
[ "$out" = " 1  7  0 " ] || fail "INPUT#" "$out"

rm -rf "$tmp"
echo "NUMREAD OK"
