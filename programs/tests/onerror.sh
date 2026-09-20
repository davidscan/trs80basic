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
rm -f "$tmp"
echo "ONERROR OK"
