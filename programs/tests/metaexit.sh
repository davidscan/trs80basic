#!/bin/sh
# metaexit.sh -- `exit` and `bye` are lower-case metacommands that leave the
# interpreter as BYE does (the user, 2026-10-21; the Q-5 ruling of 2026-10-03
# named both): nothing after them runs, exit status 0.  Like every
# metacommand they are lower case only and take no argument, so a listing's
# EXIT or `exit now` reaches BASIC (?SN) and a program is never ended by
# one.  Batch input is byte-exact, so the piped case below also pins that
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

out=$(printf '\nEXIT\nexit now\n10 EXIT\n20 PRINT "RAN"\nRUN\nPRINT "STILL"\nbye\n' | run | sed -n '/^>EXIT/,$p')
want='>EXIT
?SN ERROR
READY
>exit now
?SN ERROR
READY
>10 EXIT
>20 PRINT "RAN"
>RUN
?SN ERROR IN 10
READY
>PRINT "STILL"
STILL
READY
>bye'
[ "$out" = "$want" ] || fail "EXIT, exit with an argument and a program's EXIT reach BASIC" "$out"

# piped INKEY$ and INPUT are byte-exact: lower case stays lower case
out=$(printf '\n10 A$=INKEY$:INPUT B$:PRINT "["A$"]["B$"]"\nRUN\nq\nhello World\n' | run | sed -n '/^\[/p')
[ "$out" = "[q][hello World]" ] || fail "piped INKEY\$ and INPUT keep the bytes sent" "$out"

echo "METAEXIT OK"
