#!/bin/sh
# clear.sh -- CLEAR is RUN's initializer without the jump (ROM 1E7A/1EA0 ->
# 1B61): it resets the DEF-type table, the DATA pointer, the stacks, CONT
# and the ON ERROR target.  clear.bas asserts what a running program can
# see; the disarmed handler needs a FATAL error to show, so it is here.
# Self-checking: exits 1 on any mismatch.  Run from the repo root:
#   sh programs/tests/clear.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
tmp=$(mktemp) || exit 2
fail() { echo "CLEAR FAILED: $1"; printf '%s\n' "$2"; rm -f "$tmp"; exit 1; }
out=$(TRS80_Z80= "$here/basic" "$here/programs/tests/clear.bas" 2>&1 </dev/null) \
    || fail "clear.bas" "$out"
# ON ERROR GOTO does not survive CLEAR: the error after it is fatal
printf '10 ON ERROR GOTO 100:CLEAR 50:PRINT 1/0\n20 END\n100 PRINT "TRAPPED":RESUME NEXT\n' > "$tmp"
out=$(TRS80_Z80= "$here/basic" "$tmp" 2>&1 </dev/null); rc=$?
[ $rc -eq 1 ] && [ "$out" = "?/0 ERROR IN 10" ] || fail "ON ERROR survived CLEAR (rc=$rc)" "$out"
# DEFSTR before CLEAR is undone, and says so as ?TM
printf '10 DEFSTR A:CLEAR 50:A="X"\n' > "$tmp"
out=$(TRS80_Z80= "$here/basic" "$tmp" 2>&1 </dev/null); rc=$?
[ $rc -eq 1 ] && [ "$out" = "?TM ERROR IN 10" ] || fail "DEFSTR survived CLEAR (rc=$rc)" "$out"
rm -f "$tmp"
echo "CLEAR OK"
