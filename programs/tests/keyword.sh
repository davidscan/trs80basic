#!/bin/sh
# keyword.sh -- the tokenizer reads a line as the ROM's cruncher and readers
# do (the 2026-09-23 audit, M-2, and the keyword-crunching rule).
#
# The cruncher (1BC0-1C8F) tries the keyword table at EVERY letter outside a
# string, a REM and DATA, and stores what does not match as it stands; only
# digits, ":" and ";" (30H-3BH, 1BEC-1BF2) go by without a try.  A variable
# name is what is left between the tokens, so TOTAL is TO TAL, SCORE is
# SC OR E, IFA=1THEN30 and FORI=1TO3 work, and TAB (5) with a blank is the
# array TAB (trs-80.com's bug 7c).  While the cruncher matches GOTO, and
# only GOTO, every letter is fetched through RST 10H (1C24-1C2A), so G O T O
# is GOTO and GO TOTAL is GOTO TAL.
# A number in a line is read by 0E6CH through RST 10H (24A5H: JP C,0E6CH),
# which skips blanks: 1 2 is 12, 12 34 is 1234, 1E is 1, 1 E 3 is 1000; a
# line number the same way (1E5AH): GOTO 3 0 runs line 30.  "%" is taken
# only behind an integer up to 32767, ?SN otherwise (0EEE-0EEF).
# Until 2026-09-25 the tokenizer read a whole identifier and a number by a
# regex: TOTAL was a variable, IFA=1THEN30 was ?SN, PRINT 1E printed 1 and 0.
# Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/keyword.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
tmp=$(mktemp) || exit 2
trap 'rm -f "$tmp"' EXIT
fail() { echo "KEYWORD FAILED: $1"; printf '%s\n' "$2"; exit 1; }
run() { printf '%s\n' "$1" > "$tmp"; TRS80_Z80= "$here/basic" "$tmp" 2>&1 </dev/null | tr '\n' '|'; }
want() { out=$(run "$1"); [ "$out" = "$2" ] || fail "$3" "got:  $out
want: $2"; }

# the keyword rule: a name is what lies between the tokens
want '10 TOTAL=5:PRINT TOTAL' '?SN ERROR IN 10|' 'TOTAL is TO TAL: TO as a statement is ?SN'
want '10 total=5' '?SN ERROR IN 10|' 'lower case crunches the same'
want '10 SCORE=5:PRINT SCORE' '?SN ERROR IN 10|' 'SCORE is SC OR E'
want '10 ANDY=3' '?SN ERROR IN 10|' 'ANDY is AND Y'
want '10 A=1:IFA=1THEN30
20 PRINT "NO":END
30 PRINT "YES"' 'YES|' 'IFA=1THEN30'
want '10 FORI=1TO3:PRINTI;:NEXTI' ' 1  2  3 ' 'FORI=1TO3:PRINTI;:NEXTI'
want '10 fori=1to2:printi;:nexti' ' 1  2 ' 'the same in lower case'
want '10 COUNT=2:SUM=3:GOAL=4:PRINT COUNT;SUM;GOAL' ' 2  3  4 |' 'names holding no keyword are whole'
want '10 POINTS=1' '?SN ERROR IN 10|' 'POINTS is POINT S'
want '10 G O T O 30
20 PRINT "NO":END
30 PRINT "YES"' 'YES|' 'G O T O is GOTO (RST 10H while matching 8DH)'
want '10 GO TOTAL' '?UL ERROR IN 10|' 'GO TOTAL is GOTO TAL, and GOTO TAL is GOTO 0'
want '10 GO SUB 30
20 END
30 RETURN' '?SN ERROR IN 10|' 'GO SUB is not GOSUB'
want '10 PRINT TAB (5);"X"' ' 0 X|' 'TAB (5) with a blank is the array TAB (bug 7c)'
want '10 PRINT TAB(5);"X"' '     X|' 'TAB( is the token'
want '10 DEF FNA(X)=X*2:DEFFNB(X)=X+1:PRINT FNA(3);FN A(4);FNB(1)' ' 6  8  2 |' 'FN, FNA and DEFFNB'
want '10 A$="Q":AB$="R":PRINT A$;AB$' 'QR|' 'string names'
want '10 CLOSE#1:PRINT "C"' 'C|' '# behind a keyword is the channel marker'
want '10 XLEFT$="A"' '?SN ERROR IN 10|' 'a keyword ending in $ inside a name'
want '10 PRINT "TOTAL";:REM TOTAL
20 DATA TOTAL:READ A$:PRINT A$' 'TOTALTOTAL|' 'a string, a REM and DATA are not crunched'
want '10 X=1:X=X TO' '?SN ERROR IN 10|' 'a bare TO after a name'

# M-2: a number is read through RST 10H
want '10 A=1 2:PRINT A' ' 12 |' 'A=1 2 is 12'
want '10 PRINT 12 34' ' 1234 |' 'PRINT 12 34 is 1234'
want '10 PRINT 1E' ' 1 |' 'a bare E is an exponent of 0'
want '10 PRINT 1 E 3' ' 1000 |' '1 E 3 is 1000'
want '10 PRINT 1D3;.5;1.;1E+1;2E-1' ' 1000  .5  1  10  .2 |' 'D, a leading and a trailing point, a signed exponent'
want '10 GOTO 3 0
20 PRINT "NO":END
30 PRINT "YES"' 'YES|' 'GOTO 3 0 runs line 30'
want '10 IF 1 THEN 30 ELSE 20
20 PRINT "NO":END
30 PRINT "YES"' 'YES|' 'a number stops at the ELSE token'
out=$(run '10 PRINT 1END')     # the 1 is printed, then the END token is an operand: ?SN (2337H)
case "$out" in *"?SN ERROR IN 10|") ;; *) fail "1END is 1 then the END token, ?SN as an operand" "$out" ;; esac
want '10 X=END' '?SN ERROR IN 10|' 'a statement keyword as an operand is ?SN, never a variable'
want '10 PRINT 5%;32767%' ' 5  32767 |' '% behind an integer'
want '10 PRINT 1.5%' '?SN ERROR IN 10|' '% behind a fraction is ?SN'
want '10 PRINT 32768%' '?SN ERROR IN 10|' '% past 32767 is ?SN'
want '10 PRINT 2!;3#' ' 2  3 |' '! and # are taken'

# the image agrees: TOTAL=5 is BDH "TAL" D5H "5" there too (pm_crunch)
out=$(run '10 GOTO 30
20 TOTAL=5
30 FOR I=17129 TO 17160:PRINT PEEK(I);:NEXT' | tr '|' ' ' | tr -s ' ')
case "$out" in
    *" 20 0 189 84 65 76 213 53 0 "*) ;;
    *) fail "the image of TOTAL=5" "$out" ;;
esac
echo "KEYWORD OK"
