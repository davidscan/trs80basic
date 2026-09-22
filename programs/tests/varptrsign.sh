#!/bin/sh
# varptrsign.sh -- VARPTR is the ROM's 16-bit integer, and it works at READY.
#
# The ROM's VARPTR (24E7-24FEH) hands the address to 0A9AH as an INTEGER,
# so above 32767 it is negative: 65533 is -3.  This interpreter returned the
# positive address (the 2026-09-19 audit, L-43; ruled 2026-09-21: follow the
# ROM).  PEEK and POKE take the negative form, the period idiom
# IF V<0 THEN V=V+65536 gives the positive one back, and a USR argument of
# it passes the core's 0A7FH trap (z80.sh pins that leg).
#
# And a VARPTR typed at the READY prompt before any RUN must not be a gawk
# fatal: the string-space tables were typed by their first use, which on
# that path was `length(VPDATA)` -- a scalar context -- so the next
# subscript killed the session (found 2026-09-21, fixing L-43).
here=$(cd "$(dirname "$0")/../.." && pwd)
fail() { echo "varptrsign.sh: FAIL: $1"; echo "$2"; exit 1; }
run() { printf "$1" | TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" 2>&1; }

# direct mode, before any RUN: no fatal, and the machine's negative
out=$(run '\nA$="HI":PRINT VARPTR(A$);PEEK(VARPTR(A$))\n')
case "$out" in *fatal*) fail "direct-mode VARPTR is a gawk fatal" "$out";; esac
echo "$out" | grep -q -- '^-[0-9]*  2 $' || fail "direct-mode VARPTR(A\$) is not negative, or PEEK of it is not the length" "$out"

# in a program: the sign, the idiom, PEEK and POKE through the negative form,
# a numeric's 4 cells, and an array element -- all at the top of memory
out=$(run '\n10 A$="HELLO":V=VARPTR(A$)\n20 IF V>=0 THEN PRINT "FAIL not negative";V\n30 P=V:IF P<0 THEN P=P+65536\n40 IF P<32768 OR P>65535 THEN PRINT "FAIL idiom";P\n50 IF PEEK(V)<>5 OR PEEK(P)<>5 THEN PRINT "FAIL PEEK both forms";PEEK(V);PEEK(P)\n60 D=PEEK(V+1)+256*PEEK(V+2):POKE D,74:IF A$<>"JELLO" THEN PRINT "FAIL POKE via the composed address ";A$\n70 N=1:W=VARPTR(N):IF W>=0 THEN PRINT "FAIL numeric not negative";W\n80 IF PEEK(W+3)<>129 THEN PRINT "FAIL numeric cells through the negative address";PEEK(W+3)\n90 DIM S$(2):S$(1)="X":IF VARPTR(S$(1))>=0 THEN PRINT "FAIL element not negative"\n100 PRINT "SIGN OK"\nRUN\n')
echo "$out" | grep -q 'SIGN OK' || fail "the program" "$out"
echo "$out" | grep -q '^FAIL' && fail "a check in the program" "$out"

# the stub USR returns its argument: a negative VARPTR passes through it
out=$(run '\n10 A$="HI":V=VARPTR(A$):DEFUSR=&H7000:PRINT USR(V)=V\nRUN\n')
echo "$out" | grep -q -- '^-1 $' || fail "the stub USR does not return a negative VARPTR unchanged" "$out"
echo "varptrsign.sh: ok"
