#!/bin/sh
# cont.sh -- CONT after a STOP in the middle of a line goes on with the
# statement behind the STOP (ROM 1DE4H: 40F7H holds the address of the
# statement to continue at), and a second CONT, once the program has run
# off its end, ends again at READY: 197EH -> 1DC1H-1DD1H save the end as
# the CONT point (it was ?CN here until 2026-09-26, audit R-5).  A CONT
# that ran the STOP's line twice, or started the line over, passed the
# suite until 2026-09-24 (M-13).
# Self-checking: exits 1 on a mismatch.  Run from the repo root:
#     sh programs/tests/cont.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
fail() { echo "CONT FAILED: $1"; printf '%s\n' "$2"; exit 1; }
run() { printf '%b' "$1" | TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" 2>&1 | sed -n '/^>RUN/,$p'; }

out=$(run '\n10 PRINT "A";:STOP:PRINT "B";:PRINT "C"\nRUN\nCONT\nCONT\n')
want='>RUN
A
BREAK IN 10
READY
>CONT
BC
READY
>CONT
READY
>'
[ "$out" = "$want" ] || fail "CONT after a mid-line STOP, then CONT at the end" "$out"

# an error handler that runs off the end of the program is ?NR (197EH-
# 198CH: the 40F2H flag, code 22H), not a silent READY (audit M-2)
out=$(run '
10 ON ERROR GOTO 30
20 ERROR 5
30 PRINT "H"
RUN
')
want='>RUN
H
?NR ERROR IN 30
READY
>'
[ "$out" = "$want" ] || fail "a handler running off the end is ?NR" "$out"

# CONT after END goes on too: END and STOP share 1DB4H-1DD1H, which saves
# the line and the statement behind the END in 40F5H/40F7H; only the
# BREAK message differs (1DDEH)
out=$(run '\n10 PRINT "A":END:PRINT "B"\nRUN\nCONT\n')
want='>RUN
A
READY
>CONT
B
READY
>'
[ "$out" = "$want" ] || fail "CONT after END continues behind the END" "$out"
# CONT after an ERROR re-runs the statement that failed: the error routine
# saves the line and the statement in 40F5H/40F7H (19C9H-19CDH) before it
# looks for a handler, and its exit (19B1H -> 1B9AH, past the 1B77H clear)
# never drops them, so 1DE4H finds them.  Until 2026-09-24 every reported
# error was ?CN afterwards.
out=$(run '\n10 A=0\n20 PRINT "X";:PRINT 1/A;:PRINT "Y"\n30 PRINT "DONE"\nRUN\nA=2\nCONT\n')
want='>RUN
X
?/0 ERROR IN 20
READY
>A=2
READY
>CONT
 .5 Y
DONE
READY
>'
[ "$out" = "$want" ] || fail "CONT after an error re-runs the failing statement" "$out"

# an error in a statement TYPED at READY skips that save (19C7H: the line
# is FFFFH), so it leaves the CONT point of an earlier STOP alone
out=$(run '\n10 PRINT "A":STOP:PRINT "B"\nRUN\nPRINT 1/0\nCONT\n')
want='>RUN
A
BREAK IN 10
READY
>PRINT 1/0
?/0 ERROR
READY
>CONT
B
READY
>'
[ "$out" = "$want" ] || fail "an error typed at READY keeps the CONT point" "$out"

# LIST and LLIST keep the CONT point too: LIST never writes 40F7H
# (2B2E-2B73; its writers are 1B77H, 1DD1H and 19CDH), so BREAK, LIST,
# CONT works.  Until 2026-09-27 a typed LIST made CONT ?CN (the
# 2026-09-26 audit, M-5).  DELETE goes through 1B5DH, so it still clears it.
out=$(run '\n10 PRINT "A":STOP:PRINT "B"\n20 PRINT "C"\nRUN\nLIST 20\nLLIST\nCONT\nRUN\nDELETE 20\nCONT\n')
want='>RUN
A
BREAK IN 10
READY
>LIST 20
20 PRINT "C"
READY
>LLIST
READY
>CONT
B
C
READY
>RUN
A
BREAK IN 10
READY
>DELETE 20
READY
>CONT
?CN ERROR
READY
>'
[ "$out" = "$want" ] || fail "CONT after a typed LIST or LLIST" "$out"
echo "CONT OK"
