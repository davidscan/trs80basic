#!/bin/sh
# errline.sh -- which line an error names, and what ERL reports.
#
# The ROM keeps ONE cell for the line it is executing, 40A2H, and marks the
# Input Phase by storing FFFFH there (1A36).  The error reporter copies that
# cell to 40EAH, which is what ERL reads (19A5), and prints the " IN nnn"
# suffix unless H AND L is FF -- unless the line is 65535 (1A11-1A14).
#
# So: an error in line 0 reports " IN 0", an error in a statement typed at
# the prompt reports no line at all, and ERL after a direct-mode error is
# 65535.  A plain 0 for "no line" could not tell those apart, and line 0
# lost its suffix (the 2026-09-19 audit, L-4).
# Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/errline.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
tmp=$(mktemp) || exit 2
trap 'rm -f "$tmp"' EXIT
fail() { echo "ERRLINE FAILED: $1"; printf '%s\n' "$2"; exit 1; }
repl() { TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" 2>&1 | grep -v '^>.' ; }

# line 0 is a real line and says so
printf '0 PRINT 1/0\n' > "$tmp"
out=$(TRS80_Z80= "$here/basic" "$tmp" 2>&1 </dev/null); rc=$?
[ "$out" = "?/0 ERROR IN 0" ] || fail "an error in line 0" "$out"
[ "$rc" = 1 ] || fail "exit status for an error in line 0" "$rc"

# ... and ERL names it, and so does "." (LASTLN)
printf '0 ON ERROR GOTO 10\n1 PRINT 1/0\n10 PRINT "ERL=";ERL\n' > "$tmp"
out=$(TRS80_Z80= "$here/basic" "$tmp" 2>&1 </dev/null)
[ "$out" = "ERL= 1 " ] || fail "ERL for a trapped error" "$out"
printf '0 ON ERROR GOTO 10\n1 PRINT 1/0\n10 PRINT "ERL=";ERL\n' > "$tmp"

# a statement typed at the prompt: no line in the message, and ERL is 65535
out=$(printf '\nPRINT 1/0\nPRINT ERL\n' | repl | tr '\n' ' ')
case $out in *"?/0 ERROR READY"*) ;; *) fail "a direct-mode error names no line" "$out" ;; esac
case $out in *" 65535 "*) ;; *) fail "ERL after a direct-mode error is 65535" "$out" ;; esac

# the same cell through the system variable window: 40A2/40A3H is 65535 at
# the prompt and the running line inside a program
out=$(printf '\nPRINT PEEK(16546)+256*PEEK(16547)\n' | repl | tr '\n' ' ')
case $out in *" 65535 "*) ;; *) fail "PEEK(16546/7) at the prompt" "$out" ;; esac
printf '0 PRINT PEEK(16546)+256*PEEK(16547)\n20 PRINT PEEK(16546)+256*PEEK(16547)\n' > "$tmp"
out=$(TRS80_Z80= "$here/basic" "$tmp" 2>&1 </dev/null | tr '\n' ' ')
[ "$out" = " 0   20  " ] || fail "PEEK(16546/7) inside a program, line 0 included" "$out"

# BREAK from a direct-mode statement names no line either (ROM 1A01-1A14 is
# the shared path); from a program it names the line
printf '0 STOP\n' > "$tmp"
out=$(TRS80_Z80= "$here/basic" "$tmp" 2>&1 </dev/null)
[ "$out" = "BREAK IN 0" ] || fail "STOP in line 0" "$out"

echo "ERRLINE OK"
