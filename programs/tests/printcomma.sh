#!/bin/sh
# printcomma.sh -- PRINT#'s comma writes PRINT's zone blanks into the file
# (Disk manual, PRINT#: "Unquoted commas and semi-colons have the same
# effect as they do in regular PRINT to display statements"; its case,
# A=2300 and B=1.303: "The comma between A and B in the PRINT# list causes
# 10 extra spaces in the disk file").  The zone is measured in the FILE's
# line, not from the screen's cursor, and across a line held open by a
# trailing separator.  Numbers written that way still read back, since
# INPUT# ends a number at a blank.  Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/printcomma.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
dir=$(mktemp -d) || exit 2
fail() { echo "PRINTCOMMA FAILED: $1"; printf '%s\n' "$2"; rm -rf "$dir"; exit 1; }
cat > "$dir/t.bas" <<'BAS'
10 A=2300:B=1.303
20 OPEN "O",1,"SEQ.DAT"
30 PRINT "SCREEN AT 7";:PRINT#1,A,B
40 PRINT#1,A;B
50 PRINT#1,"AB",:PRINT#1,"CD","EF"
60 PRINT#1,"1234567890123456","X"
70 PRINT#1,,"Y"
80 PRINT#1,"P";CHR$(13);"Q","R"
90 CLOSE 1
100 OPEN "I",1,"SEQ.DAT"
110 INPUT#1,X,Y:PRINT X;Y;"."
120 CLOSE 1
BAS
out=$(cd "$dir" && TRS80_Z80= "$here/basic" t.bas 2>&1)
[ "$out" = "SCREEN AT 7 2300  1.303 ." ] || fail "numbers written with a comma read back" "$out"
got=$(tr '\r' '~' < "$dir/SEQ.DAT" | sed 's/$/|/')
want=" 2300            1.303 |
 2300  1.303 |
AB              CD              EF|
1234567890123456                X|
                Y|
P~Q               R|"
[ "$got" = "$want" ] || fail "the disk image" "$got"
rm -rf "$dir"
echo "PRINTCOMMA OK"
