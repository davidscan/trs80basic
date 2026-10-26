#!/bin/sh
# suffixdisk.sh -- a variable is its name AND its type (suffixid.bas) at the
# entry points suffixid.bas cannot reach: DEF FN parameters and the Disk
# BASIC statements (MID$=, LINE INPUT, LINE INPUT#, FIELD, LSET/RSET), a
# USR string argument, LET's literal source, and CLEAR resetting the type
# of a bare name.  Each keys its name by vkey (p70): under DEFSTR L a bare L
# is L$, and FNR#(A1#) binds A1#, not A1 (the Level II manual, section 1:
# "A$, A%, A!, A# are distinct variable names").  suffixid.bas keeps the
# cassette ROM's statements; this one needs files, so it runs in a temp dir.
# Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/suffixdisk.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
dir=$(mktemp -d) || exit 2
fail() { echo "SUFFIXDISK FAILED: $1"; printf '%s\n' "$2"; rm -rf "$dir"; exit 1; }

cat > "$dir/s.bas" <<'BAS'
10 REM CLEAR resets the DEF table, so a bare name read before it is a new key after it
20 DEFINT M:M=1.5:DEFSTR N:N="A":CLEAR 100:M=1.5:N=2.5:F=0
30 IF M<>1.5 OR M!<>1.5 OR N<>2.5 THEN PRINT "FAIL: CLEAR KEPT DEFINT M OR DEFSTR N";M;N:F=1
100 REM DEF FN: a parameter keeps its suffix
110 DEF FNR#(A1#)=A1#*2:A1=5:A1#=7:R=FNR#(3)
120 IF R<>6 OR A1<>5 OR A1#<>7 THEN PRINT "FAIL: FNR#(A1#) BOUND";R;A1;A1#:F=1
130 DEF FNQ(B%)=B%*10+B:B=.5:B%=9:R=FNQ(3)
140 IF R<>30.5 OR B%<>9 OR B<>.5 THEN PRINT "FAIL: FNQ(B%) BOUND";R;B%;B:F=1
150 DEFSTR T:DEF FNT$(T)=T+"?":IF FNT$("X")<>"X?" THEN PRINT "FAIL: FNT$(T) UNDER DEFSTR T":F=1
160 ON ERROR GOTO 900:S=1
170 DEFSTR U:DEF FNP(U%)=U%*2:IF FNP(4)<>8 THEN PRINT "FAIL: FNP(U%) UNDER DEFSTR U":F=1
175 R=FNP("X"):PRINT "FAIL: FNP(U%) TOOK A STRING UNDER DEFSTR U":F=1
180 ON ERROR GOTO 0
200 REM the DEFSTR siblings: a bare name under DEFSTR is its $ form at each statement
210 DEFSTR D:D="ABCD":MID$(D,2,1)="X":IF D$<>"AXCD" THEN PRINT "FAIL: MID$(D) UNDER DEFSTR D";D$:F=1
220 DEFSTR E:E="HELLO":POKE 16526,0:POKE 16527,0:X$=USR(E):IF X$<>"HELLO" THEN PRINT "FAIL: USR(E) UNDER DEFSTR E [";X$;"]":F=1
230 DEFSTR G:G="WORD":A$=G:X=VARPTR(A$):Y=VARPTR(G$)
240 IF PEEK(X+1)+256*PEEK(X+2)<>PEEK(Y+1)+256*PEEK(Y+2) THEN PRINT "FAIL: A$=G LEFT G'S LITERAL":F=1
300 OPEN "O",1,"SUFD.TXT":PRINT#1,"ONE,TWO":PRINT#1,"THREE":CLOSE
310 DEFSTR L:OPEN "I",1,"SUFD.TXT":LINE INPUT#1,L:CLOSE:IF L$<>"ONE,TWO" THEN PRINT "FAIL: LINE INPUT#1,L UNDER DEFSTR L";L$:F=1
320 DEFSTR K:LINE INPUT K:IF K$<>"TYPED,LINE" THEN PRINT "FAIL: LINE INPUT K UNDER DEFSTR K";K$:F=1
330 DEFSTR H-J:OPEN "R",1,"SUFR.DAT",10:FIELD 1,5 AS H,5 AS J:LSET H="AB":RSET J="CD"
340 IF H$<>"AB   " OR J$<>"   CD" THEN PRINT "FAIL: FIELD/LSET/RSET UNDER DEFSTR H-J [";H$;"][";J$;"]":F=1
350 PUT 1,1:LSET H="":GET 1,1:CLOSE:IF H$+J$<>"AB      CD" THEN PRINT "FAIL: GET INTO H UNDER DEFSTR H [";H$;J$;"]":F=1
800 IF F THEN PRINT "SUFFIXDISK FIXTURE FAILED":ERROR 5
810 PRINT "SUFFIXDISK FIXTURE OK":END
900 IF S=1 AND ERR/2+1=13 AND ERL=175 THEN S=2:RESUME 180
910 PRINT "FAIL: UNEXPECTED ERROR";ERR/2+1;"IN";ERL:F=1:RESUME 180
BAS
out=$(cd "$dir" && printf 'TYPED,LINE\n' | TRS80_Z80= "$here/basic" s.bas 2>&1)
st=$?
case $out in
*"SUFFIXDISK FIXTURE OK"*) [ $st -eq 0 ] || fail "printed OK but exited $st" "$out" ;;
*) fail "the fixture" "$out" ;;
esac
case $out in *FAIL*) fail "a FAIL line beside OK" "$out" ;; esac
rm -rf "$dir"
echo "suffixdisk: OK"
