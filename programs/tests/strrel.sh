#!/bin/sh
# strrel.sh -- ROM bug 21: a string relation whose right side concatenates.
# trs-80.com's "Known ROM bugs" list: IF "hm"="h"+"m" is ?TM on the
# machine, and the reverse order ("h"+"m"="hm") works.  The mechanism: the
# evaluator saves the text pointer after every operand its operator loop
# reads (2343H) and a finished operator reads on from that saved pointer
# (2346H), but the concatenation reads its right operand without saving
# it (298FH-2995H).  So the compare is made on the whole concatenated
# string, then the reading resumes from the stale pointer:
#   past the first operand, where "+" meets the compare's number: ?TM;
#   inside the last function's parentheses (CHR$(13), LEFT$(..)), where
#     the expression ends at that ")" and the statement meets it: the
#     compare's value is printed, then ?SN; under IF a true condition is
#     ?SN and a false one runs ELSE;
#   an array element saves its ")" (2703H), so "A"+A$(1) reads on as it
#     should.
# Until 2026-10-22 every case here concatenated and compared normally.
# Self-checking: exits 1 on a mismatch.  Run from the repo root:
#     sh programs/tests/strrel.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
tmp=$(mktemp) || exit 2
trap 'rm -f "$tmp"' EXIT
fail() { echo "STRREL FAILED: $1"; printf '%s\n' "$2"; exit 1; }
run() { printf '%b' "$1" > "$tmp"; (cd "${tmp%/*}" && TRS80_Z80= "$here/basic" "$tmp") 2>&1 </dev/null | tr '\n' ' '; }
check() { [ "$2" = "$3" ] || fail "$1" "$2"; }

# 1. the page's own case, and its reverse
check 'IF "HM"="H"+"M" is ?TM' \
    "$(run '10 IF "HM"="H"+"M" THEN PRINT "Y" ELSE PRINT "N"\n')" \
    '?TM ERROR IN 10 '
check 'the reverse order works' \
    "$(run '10 IF "H"+"M"="HM" THEN PRINT "Y" ELSE PRINT "N"\n')" \
    'Y '
check 'a parenthesised right side works' \
    "$(run '10 PRINT "QR"=("Q"+"R")\n')" \
    '-1  '
# 2. a variable or literal after + : ?TM, whatever the compare says
check 'X<>""+B$ is ?TM' \
    "$(run '10 B$="Y":PRINT "X"<>""+B$\n')" \
    '?TM ERROR IN 10 '
check 'a relation then AND: still ?TM' \
    "$(run '10 PRINT "AZ"="A"+"Z" AND 1\n')" \
    '?TM ERROR IN 10 '
# 3. a function last: the compare is right, then ?SN at its ")"
check 'A$<>""+CHR$(13), A$ a CR: 0 then ?SN' \
    "$(run '10 A$=CHR$(13):PRINT A$<>""+CHR$(13)\n')" \
    ' 0 ?SN ERROR IN 10 '
check 'LEFT$ last: -1 then ?SN' \
    "$(run '10 PRINT "X"<>""+LEFT$("AB",1)\n')" \
    '-1 ?SN ERROR IN 10 '
check 'inside parentheses the function'"'"'s ")" closes them' \
    "$(run '10 PRINT ("X"<>""+CHR$(65))\n')" \
    '-1 ?SN ERROR IN 10 '
check 'and what follows meets the number' \
    "$(run '10 PRINT ("X"<>""+CHR$(65)+"")\n')" \
    '?TM ERROR IN 10 '
# 4. under IF: true is ?SN, false runs ELSE (the corpus form)
check 'IF true: ?SN' \
    "$(run '10 A$="X":IF A$<>""+CHR$(13)+"" THEN PRINT "Y" ELSE PRINT "N"\n')" \
    '?SN ERROR IN 10 '
check 'IF false: ELSE' \
    "$(run '10 A$=CHR$(13):IF A$<>""+CHR$(13)+"" THEN PRINT "Y" ELSE PRINT "N"\n')" \
    'N '
# 5. an array element last reads on correctly
check 'A$(1) last: true' \
    "$(run '10 DIM A$(3):A$(1)="B":IF "AB"="A"+A$(1) THEN PRINT "Y" ELSE PRINT "N"\n')" \
    'Y '
check 'A$(1) last: false' \
    "$(run '10 DIM A$(3):A$(1)="B":IF "XB"="A"+A$(1) THEN PRINT "Y" ELSE PRINT "N"\n')" \
    'N '
check 'a period form: C$=V$(1)+"OW "+N$(2)' \
    "$(run '10 DIM V$(2),N$(2):V$(1)="B":N$(2)="X":C$="BOW X"\n20 IF C$=V$(1)+"OW "+N$(2) THEN PRINT "Y" ELSE PRINT "N"\n')" \
    'Y '
# 6. numbers are untouched
check '2=1+1' "$(run '10 PRINT 2=1+1;1=1+1\n')" '-1  0  '
echo "strrel: all checks passed"
