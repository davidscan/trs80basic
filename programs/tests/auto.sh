#!/bin/sh
# auto.sh -- AUTO's arguments, by ROM 2008-2036, and its prompt loop, by
# ROM 1A39-1A73.
#  * a bare AUTO is 10,10, and one parameter takes the increment 10: the
#    default pushed at 200B is what 2012-2013 leaves in HL;
#  * the start is read by 1E4FH: "." is the current line, and a bare comma
#    is 0, so AUTO ,20 numbers from 0 (both went wrong here until
#    2026-09-27, the 2026-09-26 audit's M-7);
#  * only a comma may follow the start (2016H, RST 08H): AUTO 10 X and
#    AUTO X are ?SN;
#  * a TRAILING COMMA with nothing after it keeps the increment already in
#    40E4H -- whatever the last AUTO left there (2019-201D) -- where we
#    went back to 10.  Anything else after the comma is ?SN at 2022;
#  * an increment of zero is ?FC at 2028; it used to be quietly taken as 10;
#  * both numbers go through 1E5AH, which is ?SN as soon as the running
#    total passes 6552 (1E62-1E66).  That is where the 65529 line limit
#    comes from, and it makes AUTO 65530 an error, not the silent no-op it
#    was here (the 2026-09-19 audit, L-18);
#  * in the loop, ENTER alone is an entry with no body: it DELETES the
#    line if it is there (the "*" prompt) and is silent if not, and AUTO
#    goes on.  Only BREAK ends AUTO -- in a pipe, the end of input (ruled
#    R-6) -- and the ROM's own limit: the number is bumped before the
#    entry is stored (1A60-1A6C), and when the bumped number reaches
#    65529 the entry just typed is DISCARDED and AUTO ends.  An empty
#    line ended it here until 2026-09-27, and the 65529 entry was kept.
# The limit is how every case below ends its AUTO inside a pipe: an
# increment chosen so the SECOND bump crosses 65529.
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
# ... and 65529 itself is fine: it prompts there, but the bumped number
# is past the limit, so the entry is discarded and AUTO ends
out=$(printf '\nAUTO 65529\nREM X\nDELETE 65529\nPRINT "AFTER"\n' | repl | tr '\n' ' ')
case $out in *"65529 "*"?FC ERROR"*"AFTER"*) ;; *) fail "AUTO 65529 prompts, and discards the entry" "$out" ;; esac
case $out in *"?SN ERROR"*) fail "AUTO 65529 should not be ?SN" "$out" ;; esac

# an increment past the limit is ?SN for the same reason
out=$(printf '\nAUTO 10,65530\nPRINT "AFTER"\n' | repl | tr '\n' ' ')
case $out in *"?SN ERROR"*"AFTER"*) ;; *) fail "AUTO 10,65530 is ?SN" "$out" ;; esac

# a trailing comma KEEPS the last increment: 50 here, not 10.  65478+50
# is 65528 (kept), 65528+50 is past the limit (discarded, AUTO ends);
# then 65428, 65478* (replaced), and the same ending.
out=$(printf '\nAUTO 65478,50\nREM A\n\nAUTO 65428,\nREM C\nREM D\n\nLIST\n' | repl | tr '\n' ' ')
case $out in *"65478 REM A 65528  READY"*) ;; *) fail "AUTO 65478,50 numbering" "$out" ;; esac
case $out in *"65428 REM C 65478*REM D 65528  READY 65428 REM C 65478 REM D READY"*) ;; *) fail "AUTO 65428, keeps the increment 50" "$out" ;; esac

# one parameter takes 10, whatever the last increment was
out=$(printf '\nAUTO 65478,50\nREM A\n\nAUTO 65508\nREM C\nREM D\n\nLIST\n' | repl | tr '\n' ' ')
case $out in *"65528  READY 65478 REM A 65508 REM C 65518 REM D READY"*) ;; *) fail "AUTO 65508 takes the increment 10" "$out" ;; esac

# something other than a number after the comma is ?SN
out=$(printf '\nAUTO 100,"X"\nPRINT "AFTER"\n' | repl | tr '\n' ' ')
case $out in *"?SN ERROR"*"AFTER"*) ;; *) fail 'AUTO 100,"X" is ?SN' "$out" ;; esac

# only a comma may follow the start
out=$(printf '\nAUTO 10 X\nPRINT "AFTER"\nAUTO X\nPRINT "AGAIN"\n' | repl | tr '\n' ' ')
case $out in *"?SN ERROR"*"AFTER"*"?SN ERROR"*"AGAIN"*) ;; *) fail "AUTO 10 X and AUTO X are ?SN" "$out" ;; esac
case $out in *"10 "*) fail "AUTO 10 X started" "$out" ;; esac

# a bare comma starts at 0
out=$(printf '\nAUTO ,65508\nREM Z\n\nLIST\n' | repl | tr '\n' ' ')
case $out in *"0 REM Z 65508  READY 0 REM Z READY"*) ;; *) fail "AUTO ,65508 starts at 0" "$out" ;; esac

# "." is the current line (1E4FH): the one last entered
out=$(printf '\n50 REM X\nAUTO .,65478\nREM Y\n\nLIST\n' | repl | tr '\n' ' ')
case $out in *"50*REM Y 65528  READY 50 REM Y READY"*) ;; *) fail "AUTO .,65478 starts at the current line" "$out" ;; esac

# ENTER at a line that exists deletes it, and AUTO goes on
out=$(printf '\n10 REM A\n20 REM B\nAUTO 20,65508\n\n\nLIST\n' | repl | tr '\n' ' ')
case $out in *"20* 65528  READY 10 REM A READY"*) ;; *) fail "ENTER at 20* deletes line 20 and goes on" "$out" ;; esac

# ENTER at a line that is not there is silent, goes on, and still resets
# the variables (1AEFH -> 1B5DH)
out=$(printf '\nA=5\nAUTO 30,65498\n\n\nPRINT "AFTER";A\n' | repl | tr '\n' ' ')
case $out in *"30  65528  READY AFTER 0 "*) ;; *) fail "ENTER at a missing line goes on, and resets" "$out" ;; esac

echo "AUTO OK"
