#!/bin/sh
# memexpr.sh -- MEM inside an expression counts the evaluator's own stack
# (audit OC-12; p60 e_or, EVSTK).  MEM is the stack pointer less the end of
# the arrays (27D4H), and while an expression is being read the stack holds
# the statement's push (2; LET 4, FOR and PRINT USING 6), each operator
# still waiting for its right operand (+ - * / 8 and the left operand's
# bytes, 2385H-23D1H; a string + 2, 298FH; AND and OR 8, 23E1H; ^ 10,
# 23D4H; a relation 10 and the bytes, 23F0H), 6 for each parenthesis or
# unary minus or NOT (252CH, 2532H), and 10 for each function whose
# arguments are being read (8 for LEFT$, RIGHT$ and MID$: 254EH-2559H).
# Until 2026-10-08 MEM said the same number everywhere.
# Self-checking: exits 1 on a mismatch.  Run from the repo root:
#     sh programs/tests/memexpr.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
fail() { echo "MEMEXPR FAILED: $1"; printf '%s\n' "$2"; exit 1; }
run() { printf '\n%s\n' "$1" | TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" 2>&1 \
    | grep -v '^>\|^READY\|^MEM SIZE\|^R/S\|^---\|^TRS-80\|^ Codeveloped\|^man pages\|^"help\|^$' | sed 's/ *$//'; }

# 1. the 48K map, one context per line
got=$(run 'X=0:Y=1:Z#=0:A$="":I=0:DIM B(3)
PRINT MEM
X=MEM:PRINT X
PRINT MEM+0
PRINT 0+MEM
PRINT (MEM)
PRINT -MEM
PRINT 1+(2+(MEM))
PRINT ABS(MEM)
PRINT MEM;MEM
PRINT 1;MEM
IF MEM>0 THEN PRINT MEM
X=MEM+0:PRINT X
X=0+MEM:PRINT X
X=(MEM):PRINT X
PRINT 1*MEM
PRINT INT(MEM)
PRINT 1+1*MEM
PRINT 1*(1+MEM)
PRINT Y+MEM
PRINT 1.5+MEM
PRINT Z#+MEM
PRINT 1+1+MEM
PRINT MEM+1+1
PRINT VAL(STR$(MEM))
PRINT FRE(0)
PRINT FRE(A$)
PRINT 0+FRE(0)
PRINT 1-(1-MEM)
PRINT 1+ABS(MEM)
PRINT ABS(0+MEM)
PRINT 1+(1+(1+(1+MEM)))
PRINT 1+2*3-6+MEM
PRINT (0<1)+1+MEM
PRINT 1=1;MEM
PRINT MEM
FOR I=MEM TO 0:NEXT:PRINT I-1
PRINT USING"########";MEM
PRINT TAB(1)MEM
PRINT "A";MEM
A$=STR$(MEM):PRINT A$
Z#=MEM:PRINT Z#
PRINT VAL(A$+STR$(MEM))
A$="":PRINT VAL(A$+STR$(MEM))
PRINT VAL(STR$(MEM))
PRINT VAL(LEFT$(STR$(MEM),9))
PRINT B(0)+MEM
PRINT -(0+MEM)
PRINT --MEM
PRINT +MEM
PRINT 1+-MEM
PRINT 0/1+MEM
PRINT SGN(1)*MEM
X=MEM:Y=MEM:PRINT X;Y
LET X=MEM:PRINT X
POKE 16000,0:PRINT MEM')
want=' 48276
 48274
 48276
 48266
 48270
-48270
 48247
 48266
 48276  48276
 1  48276
 48276
 48274
 48264
 48268
 48266
 48266
 48257
 48251
 48265
 48265.5
 48260
 48268
 48278
 48256
 48276
 50
 48266
 48250
 48257
 48256
 48222
 48267
 48266
-1  48276
 48276
 48272
   48272
  48276
A 48276
 48264
 48274
 4826448254
 48254
 48256
 48248
 48264
-48254
 48264
 48276
-48259
 48264
 48266
 48274  48274
 48274
 48276'
[ "$got" = "$want" ] || fail "MEM in each context" "$(printf '%s\n' "$want" > "${TMPDIR:-/tmp}/memexpr.$$"; printf '%s\n' "$got" | diff "${TMPDIR:-/tmp}/memexpr.$$" -; rm -f "${TMPDIR:-/tmp}/memexpr.$$")"

# 2. AND, OR and NOT, under CLEAR 20000 so MEM is an integer
got=$(run 'CLEAR 20000:X=0:Y=1:Z#=0:A$=""
PRINT MEM
PRINT 0 OR MEM
PRINT -1 AND MEM
PRINT Y OR MEM
PRINT 0 OR 0+MEM
PRINT (0=0)*0+MEM
PRINT NOT -MEM-1
PRINT NOT NOT MEM
PRINT 1+NOT -MEM')
want=' 28357
 28349
 28349
 28349
 28339
 28347
 28345
 28345
 28335'
[ "$got" = "$want" ] || fail "MEM under AND, OR and NOT" "$got"

echo "MEMEXPR OK"
