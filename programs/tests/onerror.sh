#!/bin/sh
# onerror.sh -- ON ERROR GOTO 0 inside an error handler hands the error
# back: "BASIC will handle the current error normally" (Level II manual,
# ON ERROR GOTO).  The ROM reloads the error's code and joins the error
# routine past the point where it notes the line (1F89-1F92 -> 19ABH), so
# the message names the line that FAILED, not the handler's, and the
# program stops.  It is how a handler passes on the errors it does not
# expect.  Outside a handler the statement only disarms the trap.
# Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/onerror.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
tmp=$(mktemp) || exit 2
fail() { echo "ONERROR FAILED: $1"; printf '%s\n' "$2"; rm -f "$tmp"; exit 1; }

cat > "$tmp" <<'BAS'
10 ON ERROR GOTO 100
20 X=1/0
30 PRINT "EXPECTED ERROR RESUMED"
40 DIM A(2):A(5)=1
50 PRINT "NOT REACHED":END
100 IF ERR/2+1=11 THEN RESUME NEXT
110 ON ERROR GOTO 0
120 PRINT "FELL THROUGH THE HANDLER"
BAS
out=$(TRS80_Z80= "$here/basic" "$tmp" 2>&1 </dev/null); rc=$?
want="EXPECTED ERROR RESUMED
?BS ERROR IN 40"
[ "$out" = "$want" ] || fail "the unexpected error is reported, at its own line" "$out"
[ "$rc" = 1 ] || fail "exit status" "$rc"

# outside a handler it only disarms: the program carries on to its next error
cat > "$tmp" <<'BAS'
10 ON ERROR GOTO 100
20 ON ERROR GOTO 0:PRINT "DISARMED"
30 X=1/0
40 END
100 PRINT "TRAPPED":END
BAS
out=$(TRS80_Z80= "$here/basic" "$tmp" 2>&1 </dev/null)
want="DISARMED
?/0 ERROR IN 30"
[ "$out" = "$want" ] || fail "outside a handler it only disarms" "$out"

# ROM 1F7A-1F80: the target is looked up at 1B2AH when the STATEMENT runs,
# so a handler line that is not there is ?UL there and then -- not later,
# when an error finally fires.  ON ERROR GOTO 0 needs no line 0.
cat > "$tmp" <<'BAS'
10 PRINT "BEFORE"
20 ON ERROR GOTO 999
30 PRINT "NOT REACHED"
BAS
out=$(TRS80_Z80= "$here/basic" "$tmp" 2>&1 </dev/null); rc=$?
want="BEFORE
?UL ERROR IN 20"
[ "$out" = "$want" ] || fail "a handler line that is not there is ?UL at the statement" "$out"
[ "$rc" = 1 ] || fail "exit status for the missing handler line" "$rc"

# a forward reference is fine -- the whole program is stored before RUN
cat > "$tmp" <<'BAS'
10 ON ERROR GOTO 100
20 ON ERROR GOTO 0
30 PRINT "ARMED FORWARD, THEN DISARMED":END
100 PRINT "NOT REACHED":END
BAS
out=$(TRS80_Z80= "$here/basic" "$tmp" 2>&1 </dev/null)
[ "$out" = "ARMED FORWARD, THEN DISARMED" ] || fail "a forward handler line, and GOTO 0" "$out"

# The three below need READY between the steps, so they run a transcript.
run() { printf '%b' "$1" | TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" 2>&1 | sed -n '/^>RUN/,$p'; }

# ROM 19C7H skips only the CONT save for a statement typed at READY (line
# FFFFH) and falls into the ON ERROR test at 19D0H, and 40F0H is cleared
# by RUN's initializer (1B74H), not by END: so a handler left armed by a
# program that ended traps an error in a typed statement, with ERL 65535,
# and RESUME NEXT goes on behind the typed statement.
out=$(run '\n10 ON ERROR GOTO 100\n20 END\n100 PRINT "TRAPPED";ERR/2+1;ERL:RESUME NEXT\nRUN\nPRINT 1/0:PRINT "AFTER"\n')
want='>RUN
READY
>PRINT 1/0:PRINT "AFTER"
TRAPPED 11  65535 
AFTER
READY
>'
[ "$out" = "$want" ] || fail "an armed handler traps an error in a typed statement" "$out"

# An error the handler itself raises is printed (nested traps: 19DBH-19DCH),
# and 19E3H-19E4H clear the handler flag 40F2H with EVERY printed error.
# So afterwards the trap is armed again (40F0H untouched): a typed RESUME
# NEXT is ?RW, and that ?RW is trapped like any error typed at READY; a
# GOTO into the failing line is trapped too.  Until 2026-09-24 the flag
# stayed set: the RESUME silently resumed the dead handler, and the GOTO's
# error was printed untrapped.
out=$(run '\n10 ON ERROR GOTO 100\n20 X=1/0\n30 END\n100 PRINT "HANDLER";ERR/2+1;ERL:Y=1/0\nRUN\nRESUME NEXT\nGOTO 20\n')
want='>RUN
HANDLER 11  20 
?/0 ERROR IN 100
READY
>RESUME NEXT
HANDLER 19  65535 
?/0 ERROR IN 100
READY
>GOTO 20
HANDLER 11  20 
?/0 ERROR IN 100
READY
>'
[ "$out" = "$want" ] || fail "an untrapped error inside the handler clears the flag; the trap stays armed" "$out"

# with the trap disarmed (ON ERROR GOTO 0 hands the error back, see the
# top of this file), the stray RESUME is a plain ?RW at READY
out=$(run '\n10 ON ERROR GOTO 100\n20 X=1/0\n100 ON ERROR GOTO 0:Y=1/0\nRUN\nRESUME NEXT\n')
want='>RUN
?/0 ERROR IN 20
READY
>RESUME NEXT
?RW ERROR
READY
>'
[ "$out" = "$want" ] || fail "RESUME at READY after the handler died is ?RW" "$out"

rm -f "$tmp"
echo "ONERROR OK"
