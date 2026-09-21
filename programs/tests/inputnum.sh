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

# The Disk manual's terminator sets: every one of the three -- numeric,
# quoted string, unquoted string -- lists "255th data character
# encountered" beside the comma and the end of file, and LINE INPUT# reads
# "up to ... the 255th data character (this 255 character is included in the
# string)".  Neither stopped here, so a long line came back as a string
# longer than one can hold (the 2026-09-19 audit, L-41).  The 255th
# character IS the terminator, so what is left waits for the next read.
python3 - "$dir" <<'PYEOF'
import sys, os
d = sys.argv[1]
open(os.path.join(d, "LONG.TXT"), "w").write("A" * 300 + "\n" + "B" * 10 + "\n")
open(os.path.join(d, "ITEM.TXT"), "w").write("X" * 300 + ",TAIL\n")
open(os.path.join(d, "QUOT.TXT"), "w").write('"' + "Q" * 300 + '",Z\n')
PYEOF
cat > "$dir/len.bas" <<'BAS'
10 OPEN "I",1,"LONG.TXT"
20 LINE INPUT#1,A$:PRINT LEN(A$);LEFT$(A$,1);"."
30 LINE INPUT#1,A$:PRINT LEN(A$);LEFT$(A$,1);"."
40 LINE INPUT#1,A$:PRINT LEN(A$);LEFT$(A$,1);".":CLOSE
50 OPEN "I",1,"ITEM.TXT"
60 INPUT#1,B$:PRINT LEN(B$);"."
70 INPUT#1,B$:PRINT LEN(B$);"."
80 INPUT#1,B$:PRINT "[";B$;"]."
90 CLOSE:OPEN "I",1,"QUOT.TXT"
100 INPUT#1,C$:PRINT LEN(C$);LEFT$(C$,1);"."
110 INPUT#1,C$:PRINT LEN(C$);RIGHT$(C$,1);".":CLOSE
BAS
out=$(cd "$dir" && TRS80_Z80= "$here/basic" len.bas 2>&1)
# The quoted item reads back 46 the second time, not 45: after the cut the
# remainder starts inside the string, so the next read takes it as an
# UNQUOTED item, and the manual says a double quote met there "will be
# included in the string" (p.127) -- the closing quote is its 46th character.
want=' 255 A.
 45 A.
 10 B.
 255 .
 45 .
[TAIL].
 255 Q.
 46 ".'
[ "$out" = "$want" ] || fail "an item and a line stop at 255 characters" "$out"

rm -rf "$dir"
echo "INPUTNUM OK"
