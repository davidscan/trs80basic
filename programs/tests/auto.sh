#!/bin/sh
# auto.sh -- AUTO's arguments, by ROM 2008-2036.
#  * a bare AUTO is 10,10, and one parameter takes the increment 10: the
#    default pushed at 200B is what 2012-2013 leaves in HL;
#  * a TRAILING COMMA with nothing after it keeps the increment already in
#    40E4H -- whatever the last AUTO left there (2019-201D) -- where we
#    went back to 10.  Anything else after the comma is ?SN at 2022;
#  * an increment of zero is ?FC at 2028; it used to be quietly taken as 10;
#  * both numbers go through 1E5AH, which is ?SN as soon as the running
#    total passes 6552 (1E62-1E66).  That is where the 65529 line limit
#    comes from, and it makes AUTO 65530 an error, not the silent no-op it
#    was here (the 2026-09-19 audit, L-18).
# Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/auto.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
fail() { echo "AUTO FAILED: $1"; printf '%s\n' "$2"; exit 1; }
# a transcript at the prompt, the echo of the typed lines removed
repl() { TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" 2>&1 | grep -v '^>.' ; }

# an increment of zero is ?FC, and nothing is started
out=$(printf '\nAUTO 100,0\nPRINT "AFTER"\n' | repl | tr '\n' ' ')
case $out in *"?FC ERROR"*"AFTER"*) ;; *) fail "AUTO 100,0 is ?FC" "$out" ;; esac

# a starting line past 65529 is ?SN where the number is converted
out=$(printf '\nAUTO 65530\nPRINT "AFTER"\n' | repl | tr '\n' ' ')
case $out in *"?SN ERROR"*"AFTER"*) ;; *) fail "AUTO 65530 is ?SN" "$out" ;; esac
# ... and 65529 itself is fine: it prompts there, and an empty line ends it
out=$(printf '\nAUTO 65529\n\nPRINT "AFTER"\n' | repl | tr '\n' ' ')
case $out in *"65529"*"AFTER"*) ;; *) fail "AUTO 65529 still prompts" "$out" ;; esac
case $out in *"?SN ERROR"*) fail "AUTO 65529 should not be ?SN" "$out" ;; esac

# an increment past the limit is ?SN for the same reason
out=$(printf '\nAUTO 10,65530\nPRINT "AFTER"\n' | repl | tr '\n' ' ')
case $out in *"?SN ERROR"*"AFTER"*) ;; *) fail "AUTO 10,65530 is ?SN" "$out" ;; esac

# a trailing comma KEEPS the last increment: 50 here, not 10
out=$(printf '\nAUTO 100,50\nREM A\nREM B\n\nAUTO 500,\nREM C\nREM D\n\nLIST\n' | repl | tr '\n' ' ')
case $out in *"100 REM A"*"150 REM B"*) ;; *) fail "AUTO 100,50 numbering" "$out" ;; esac
case $out in *"500 REM C"*"550 REM D"*) ;; *) fail "AUTO 500, keeps the increment 50" "$out" ;; esac

# one parameter takes 10, whatever the last increment was
out=$(printf '\nAUTO 100,50\nREM A\n\nAUTO 800\nREM C\nREM D\n\nLIST\n' | repl | tr '\n' ' ')
case $out in *"800 REM C"*"810 REM D"*) ;; *) fail "AUTO 800 takes the increment 10" "$out" ;; esac

# something other than a number after the comma is ?SN
out=$(printf '\nAUTO 100,"X"\nPRINT "AFTER"\n' | repl | tr '\n' ' ')
case $out in *"?SN ERROR"*"AFTER"*) ;; *) fail 'AUTO 100,"X" is ?SN' "$out" ;; esac

echo "AUTO OK"
