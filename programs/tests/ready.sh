#!/bin/sh
# ready.sh -- two things about the commands that manage the program:
#  * LIST, LLIST, DELETE, AUTO, CLOAD and LOAD (without ,R) END AT READY,
#    typed or met inside a program, as on the machine (ROM: LIST 2B2E-2B54,
#    DELETE 2BD9, AUTO 2036, CLOAD 2C7A).  A program that ran one used to
#    carry on at a stale index into a line table rebuilt under it (the
#    2026-09-19 audit, H-8): lines were skipped silently.
#  * DELETE refuses, with ?FC and deleting NOTHING, unless the upper line
#    exists (manual; ROM 2BC6-2BD6) -- so DELETE - cannot erase the program
#    -- and parses its whole statement before it touches a line (H-9).
# Self-checking: exits 1 on any mismatch.  Run from the repo root:
#   sh programs/tests/ready.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
d=$(mktemp -d) || exit 2
cd "$d" || exit 2
fail() { echo "READY FAILED: $1"; printf '%s\n' "$2"; cd /; rm -rf "$d"; exit 1; }
batch() { TRS80_Z80= "$here/basic" "$1" 2>&1 </dev/null; }
# a transcript at the prompt, the echo of the typed lines removed
repl() { TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" 2>&1 | grep -v '^>.' ; }

# --- DELETE inside a program: READY, and nothing skipped afterwards
printf '10 PRINT "A"\n20 DELETE 10\n30 PRINT "B"\n40 PRINT "C"\n' > del.bas
out=$(batch del.bas); [ "$out" = "A" ] || fail "DELETE in a program did not end it" "$out"
out=$(printf '\nLOAD "del.bas"\nRUN\nLIST\n' | repl | tr '\n' ' ')
case $out in *'A READY 20 DELETE 10 30 PRINT "B" 40 PRINT "C" READY'*) ;; *) fail "after DELETE in a program, LIST" "$out" ;; esac

# --- CLOAD and LOAD inside a program: the new program is there, not running
printf '10 PRINT "NEW10"\n20 PRINT "NEW20"\n' > part2.bas
printf '10 PRINT "OLD10":CLOAD "part2.bas"\n20 PRINT "OLD20"\n' > chain.bas
out=$(batch chain.bas); [ "$out" = "OLD10" ] || fail "CLOAD in a program" "$out"
out=$(printf '\nLOAD "chain.bas"\nRUN\nRUN\n' | repl | tr '\n' ' ')
case $out in *"OLD10 READY"*"NEW10 NEW20 READY"*) ;; *) fail "RUN after a CLOAD from a program" "$out" ;; esac
printf '10 PRINT "OLD10":LOAD "part2.bas"\n20 PRINT "OLD20"\n' > chain.bas
out=$(batch chain.bas); [ "$out" = "OLD10" ] || fail "LOAD in a program" "$out"
# ... while LOAD ,R runs the new program from its FIRST line
printf '10 PRINT "OLD10":LOAD "part2.bas",R\n20 PRINT "OLD20"\n' > chain.bas
out=$(batch chain.bas | tr '\n' ' '); [ "$out" = "OLD10 NEW10 NEW20 " ] || fail "LOAD ,R from a program" "$out"

# --- LIST, LLIST and AUTO end the program too
printf '10 PRINT "X":LIST 20:PRINT "NOT REACHED"\n20 REM TWENTY\n30 PRINT "NOR THIS"\n' > list.bas
out=$(batch list.bas | tr '\n' ' '); [ "$out" = "X 20 REM TWENTY " ] || fail "LIST in a program" "$out"
printf '10 PRINT "X":LLIST:PRINT "NOT REACHED"\n' > list.bas
out=$(batch list.bas); [ "$out" = "X" ] || fail "LLIST in a program" "$out"
out=$(printf '\n10 PRINT "X":AUTO 100:PRINT "NOT REACHED"\nRUN\n\nPRINT "AT THE PROMPT"\n' | repl | tr '\n' ' ')
case $out in *"NOT REACHED"*) fail "AUTO in a program carried on" "$out" ;; esac
case $out in *"X 100 "*"READY"*"AT THE PROMPT"*) ;; *) fail "AUTO in a program" "$out" ;; esac

# --- DELETE's range rules: every refusal leaves all four lines
out=$(printf '\n10 REM\n20 REM\n30 REM\n40 REM\nDELETE 10-25\nDELETE -\nDELETE 10-\nDELETE\nDELETE 50\nDELETE 40-10\nDELETE 10,20\nLIST\n' | repl | tr '\n' ' ')
n=$(printf '%s' "$out" | grep -o '?FC ERROR' | wc -l | tr -d ' ')
[ "$n" -eq 6 ] || fail "DELETE refusals: $n of 6 were ?FC" "$out"
case $out in *"?SN ERROR"*"10 REM 20 REM 30 REM 40 REM READY"*) ;; *) fail "a refused DELETE removed a line (or DELETE 10,20 was not ?SN)" "$out" ;; esac
# ... and the legal forms: a lower bound that does not exist is fine, and
# . is the line last entered (50)
out=$(printf '\n10 REM\n20 REM\n30 REM\n40 REM\n50 REM\nDELETE 15-30\nLIST\nDELETE -10\nLIST\nDELETE .\nLIST\n' | repl | tr '\n' ' ')
case $out in *"READY 10 REM 40 REM 50 REM READY READY 40 REM 50 REM READY READY 40 REM READY"*) ;; *) fail "legal DELETE forms" "$out" ;; esac

cd /; rm -rf "$d"
echo "READY OK"
