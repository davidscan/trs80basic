#!/bin/sh
# inputnum.sh -- INPUT# ends a NUMERIC item at a blank, not only at a comma
# or the end of the line (Disk manual, INPUT#: "blanks and <ENTER> serve as
# terminators for input to numeric variables"; its image " 1.234 -33 27"
# read by INPUT#1,A,B,C gives 1.234, -33 and 27).  That is what makes the
# manual's own advice for numbers work -- "just remember to separate the
# items with semi-colons" -- since PRINT#1,A;B;C writes blanks and nothing
# else between them.  A string item still runs to the comma, blanks and all.
# And the item is evaluated like VAL, so text where a number was wanted
# is 0, not ?TM.  Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/inputnum.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
dir=$(mktemp -d) || exit 2
fail() { echo "INPUTNUM FAILED: $1"; printf '%s\n' "$2"; rm -rf "$dir"; exit 1; }
cat > "$dir/t.bas" <<'BAS'
10 OPEN "O",1,"SEQ.DAT"
20 PRINT#1,1;-2.5;3
30 PRINT#1,5;"HELLO"
40 PRINT#1,7;8;:PRINT#1,9
50 PRINT#1,"PECOS, TEXAS";",";10;",";11
60 CLOSE 1
70 OPEN "I",1,"SEQ.DAT"
80 INPUT#1,X,Y,Z:PRINT "SEMICOLONS";X;Y;Z;"."
90 INPUT#1,P,Q$:PRINT "NUMBER THEN STRING";P;"[";Q$;"]"
100 INPUT#1,A:INPUT#1,B:INPUT#1,C:PRINT "ONE AT A TIME";A;B;C;"."
110 INPUT#1,A$,B$,M,N:PRINT "[";A$;"][";B$;"]";M;N;"."
120 PRINT "EOF";EOF(1);".":CLOSE 1
BAS
# the manual's own image, and blanks around a comma: one terminator, not two
printf ' 1.234 -33  27\n4 , 5 ,6\n12 ,,13\n' > "$dir/MAN.DAT"
cat >> "$dir/t.bas" <<'BAS'
200 OPEN "I",1,"MAN.DAT"
210 INPUT#1,A,B,C:PRINT "MANUAL";A;B;C;"."
220 INPUT#1,A,B,C:PRINT "BLANKS AND COMMAS";A;B;C;"."
230 INPUT#1,A,B,C:PRINT "EMPTY ITEM IS 0";A;B;C;"."
240 PRINT "EOF";EOF(1);".":CLOSE 1
BAS
# a numeric item is evaluated like VAL: text that is no number is 0, and a
# number followed by text is the number (the manual's A12 example)
printf '34 A12,5X\nNONE\n' > "$dir/VAL.DAT"
cat >> "$dir/t.bas" <<'BAS'
300 OPEN "I",1,"VAL.DAT"
310 INPUT#1,A,B,C,D:PRINT "LIKE VAL";A;B;C;D;"."
320 CLOSE 1
BAS
out=$(cd "$dir" && TRS80_Z80= "$here/basic" t.bas 2>&1)
want="SEMICOLONS 1 -2.5  3 .
NUMBER THEN STRING 5 [HELLO]
ONE AT A TIME 7  8  9 .
[PECOS][TEXAS] 10  11 .
EOF-1 .
MANUAL 1.234 -33  27 .
BLANKS AND COMMAS 4  5  6 .
EMPTY ITEM IS 0 12  0  13 .
EOF-1 .
LIKE VAL 34  0  5  0 ."
[ "$out" = "$want" ] || fail "numeric items ended by blanks" "$out"
rm -rf "$dir"
echo "INPUTNUM OK"
