#!/bin/sh
# lineedit.sh -- entering, replacing or deleting a program line resets the
# run state, as the ROM does: line entry ends with a call to 1B5DH, RUN's
# initializer without the jump, and DELETE leaves the same way.  Variables
# and DEF FNs go, DEFINT and friends are forgotten, the GOSUB/FOR stacks,
# ON ERROR and CONT are reset, DATA is RESTOREd, files are closed.  Before
# the 2026-09-19 audit's M-9 all of it survived an edit, and the saved
# indexes pointed into a program that had changed: RETURN resumed at the
# wrong line, FNA(3) evaluated tokens of whatever line now sat there.
# (An FN that is not defined reads as 0 here -- what Disk BASIC does with
# one is not in the references -- so the 0 below only shows the DEF is gone.)
# Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/lineedit.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
dir=$(mktemp -d) || exit 2
fail() { echo "LINEEDIT FAILED: $1"; printf '%s\n' "$2"; rm -rf "$dir"; exit 1; }
out=$(cd "$dir" && TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" 2>&1 <<'EOF2' | grep '^[=?]'

10 DEF FNA(X)=X*2:DATA 11,22
20 GOSUB 100
30 END
100 READ Q:STOP
110 RETURN
RUN
PRINT "=BEFORE";Q;FNA(3)
A=5:B$="X":DIM C(20):C(20)=9
15 REM A LINE IS ENTERED
PRINT "=AFTER A NEW LINE";A;"[";B$;"]";Q
DIM C(30):PRINT "=THE ARRAY WENT TOO";C(30)
PRINT "=FN IS NO LONGER DEFINED";FNA(3)
PRINT "=RETURN"
RETURN
PRINT "=CONT"
CONT
READ Q:PRINT "=DATA IS RESTORED";Q
A=6
15
PRINT "=AFTER A LINE IS DELETED";A
A=7
DELETE 110-110
PRINT "=AFTER DELETE";A
DEFSTR S:S="X":PRINT "=DEFSTR ";S
15 REM
PRINT "=THE TYPE TABLE IS SINGLE AGAIN"
S="X"
OPEN "O",1,"F.DAT"
15 REM AGAIN
PRINT "=THE FILE IS CLOSED"
PRINT#1,"X"
EOF2
)
want='=BEFORE 11  6 
=AFTER A NEW LINE 0 [] 0 
=THE ARRAY WENT TOO 0 
=FN IS NO LONGER DEFINED 0 
=RETURN
?RG ERROR
=CONT
?CN ERROR
=DATA IS RESTORED 11 
=AFTER A LINE IS DELETED 0 
=AFTER DELETE 0 
=DEFSTR X
=THE TYPE TABLE IS SINGLE AGAIN
?TM ERROR
=THE FILE IS CLOSED
?NO ERROR'
[ "$out" = "$want" ] || fail "the run state after a program line changes" "$out"

# A line number followed only by BLANKS is a deletion too (ROM 1AAD-1AAE,
# 1ABF: the scan for the first token skips blanks, and meeting the end of
# the line there means "delete").  It used to store a line of blanks (the
# 2026-09-19 audit, L-17).  printf, not a heredoc: the blanks ARE the test.
out=$(cd "$dir" && printf '\n30\n10 PRINT "=TEN"\n20 PRINT "=TWENTY":ERROR 5\n10    \nRUN\nLIST\n30   \n65530 X\n' \
    | TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" 2>&1 | grep -E '^([=?]|[0-9])')
# The ?UL and ?SN of the Input Phase name no line: not an empty one (the
# first, before anything has failed) and not the last error's (the others).
want='?UL ERROR
=TWENTY
?FC ERROR IN 20
20 PRINT "=TWENTY":ERROR 5
?UL ERROR
?SN ERROR'
[ "$out" = "$want" ] || fail "a line number followed only by blanks" "$out"
rm -rf "$dir"
echo "LINEEDIT OK"
