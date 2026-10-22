#!/bin/sh
# metaexit.sh -- `exit` and `bye` are lower-case metacommands that leave the
# interpreter as BYE does (the user, 2026-10-21; the Q-5 ruling of 2026-10-03
# named both): nothing after them runs, exit status 0.  Like every
# metacommand they are lower case only and take no argument, so `exit now`
# reaches BASIC (?SN).  Upper-case EXIT is BYE's synonym, the statement
# (the user, 2026-10-22): it leaves at READY and from inside a program.  Batch input is byte-exact, so the piped case below also pins that
# the terminal case swap (p30 kb_case) stays out of piped INKEY$ and INPUT.
# Self-checking: exits 1 on any mismatch.  Run from the repo root:
#     sh programs/tests/metaexit.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
fail() { echo "METAEXIT FAILED: $1"; printf '%s\n' "$2" | head -30; exit 1; }
run() { TRS80_DUMB=1 TRS80_Z80= perl -e 'alarm 20; exec @ARGV' gawk -b -f "$here/trs80basic.awk" 2>&1; }

out=$(printf '\nPRINT "ONE"\nexit\nPRINT "AFTER"\n' | run | sed -n '/^>PRINT/,$p'); rc=$?
want='>PRINT "ONE"
ONE
READY
>exit'
[ "$out" = "$want" ] || fail "exit leaves at once" "$out"

out=$(printf '\nbye\nPRINT "AFTER"\n' | run | tail -1)
[ "$out" = ">bye" ] || fail "bye leaves at once" "$out"

out=$(printf '\nexit now\nPRINT "STILL"\nEXIT\nPRINT "AFTER"\n' | run | sed -n '/^>exit now/,$p')
want='>exit now
?SN ERROR
READY
>PRINT "STILL"
STILL
READY
>EXIT'
[ "$out" = "$want" ] || fail "exit with an argument reaches BASIC; EXIT leaves at READY" "$out"

out=$(printf '\n10 PRINT "RAN"\n20 EXIT\n30 PRINT "PAST"\nRUN\nPRINT "AFTER"\n' | run | sed -n '/^>RUN/,$p')
want='>RUN
RAN'
[ "$out" = "$want" ] || fail "a program's EXIT leaves as BYE does" "$out"

# EXIT is kept whole, as BYE is: it is not the variable EX
out=$(printf '\nEX=5:PRINT EX\nbye\n' | run | sed -n '/^>EX=/,$p')
want='>EX=5:PRINT EX
 5 
READY
>bye'
[ "$out" = "$want" ] || fail "EX stays a variable" "$out"

# piped INKEY$ and INPUT are byte-exact: lower case stays lower case
out=$(printf '\n10 A$=INKEY$:INPUT B$:PRINT "["A$"]["B$"]"\nRUN\nq\nhello World\n' | run | sed -n '/^\[/p')
[ "$out" = "[q][hello World]" ] || fail "piped INKEY\$ and INPUT keep the bytes sent" "$out"

echo "METAEXIT OK"
