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
?BN ERROR'
[ "$out" = "$want" ] || fail "the run state after a program line changes" "$out"

# A line number followed only by BLANKS is a deletion too (ROM 1AAD-1AAE,
# 1ABF: the scan for the first token skips blanks, and meeting the end of
# the line there means "delete").  It used to store a line of blanks (the
# 2026-09-19 audit, L-17).  printf, not a heredoc: the blanks ARE the test.
# The number of a line that is NOT there is silent, and still ends at
# 1B5DH (1AB5H finds nothing, 1ABFH skips the insert, 1AEFH resets): A is
# 0 afterwards.  It was ?UL until 2026-09-27 (the 2026-09-26 audit, M-6,
# ruled R-11).  The ?SN of the Input Phase names no line (the line cell
# holds FFFFH there, 1A36H).
out=$(cd "$dir" && printf '\nA=5\n30\nPRINT "=A"+STR$(A)\n10 PRINT "=TEN"\n20 PRINT "=TWENTY":ERROR 5\n10    \nRUN\nLIST\n30   \nPRINT "=B"+STR$(ERL)\n65530 X\n' \
    | TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" 2>&1 | grep -E '^([=?]|[0-9])')
want='=A 0
=TWENTY
?FC ERROR IN 20
20 PRINT "=TWENTY":ERROR 5
=B 20
?SN ERROR'
[ "$out" = "$want" ] || fail "a line number followed only by blanks" "$out"

# A line number with blanks inside: 1E5AH reads the digits through RST
# 10H, which skips blanks, so 1 5 PRINT is line 15 -- typed, and loaded
# from a text file (the same entry).  It stored line 1 with the body
# "5 PRINT" until 2026-09-27 (the 2026-09-26 audit, L-14).
printf '1 5 PRINT "=LOADED FIFTEEN"\n 2 0 PRINT "=LOADED TWENTY"\n' > "$dir/blank.bas"
out=$(cd "$dir" && printf '\n1 5 PRINT "=FIFTEEN"\n10  PRINT "=TEN"\nLIST\nRUN\nLOAD "blank.bas"\nLIST\n' \
    | TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" 2>&1 | grep -E '^([=?]|[0-9])')
want='10  PRINT "=TEN"
15 PRINT "=FIFTEEN"
=TEN
=FIFTEEN
15 PRINT "=LOADED FIFTEEN"
20 PRINT "=LOADED TWENTY"'
[ "$out" = "$want" ] || fail "a line number with blanks inside" "$out"
rm -rf "$dir"
echo "LINEEDIT OK"
