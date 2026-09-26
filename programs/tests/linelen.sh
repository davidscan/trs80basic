#!/bin/sh
# linelen.sh -- the keyboard line limit is the ROM's 240 characters (0361H:
# LD B,0F0H at 036FH), not the 255 of a string.  Piped input has no cursor
# to stop, so a longer line is cut at 240 and ONE stderr line says so; a
# line of exactly 240 is whole and silent; LOAD of a file has no such cap.
# Self-checking: exits 1 on any mismatch.  Run from the repo root:
#   sh programs/tests/linelen.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
cd "$here" || exit 2
err=$(mktemp) || exit 2; bas=$(mktemp) || exit 2
fail() { echo "LINELEN FAILED: $1"; printf '%s\n' "$2"; rm -f "$err" "$bas"; exit 1; }
rep() { awk -v n="$1" -v c="$2" 'BEGIN { while (n-- > 0) printf "%s", c }'; }
run() { TRS80_DUMB=1 TRS80_Z80= gawk -b -f trs80basic.awk 2>"$err"; }

# `10 A$="` is 7 characters and `":PRINT LEN(A$)` would be the tail: a 240
# line holds 7 + 232 X + the closing quote; the statement after it proves
# nothing was lost
l240="10 A\$=\"$(rep 232 X)\""
[ ${#l240} -eq 240 ] || fail "the fixture line is ${#l240}, not 240" ""
out=$(printf '\n%s\n20 PRINT LEN(A$)\nRUN\n' "$l240" | run)
case $out in *" 232 "*) ;; *) fail "a 240-character line lost something" "$out" ;; esac
[ -s "$err" ] && fail "a 240-character line drew a diagnostic" "$(cat "$err")"

# 241 and up: cut at 240, said once however many lines are cut
l250="10 A\$=\"$(rep 243 X)"
out=$(printf '\n%s\n20 PRINT LEN(A$)\n%s\nRUN\n' "$l250" "$l250" | run)
case $out in *" 233 "*) ;; *) fail "a 250-character line was not cut at 240" "$out" ;; esac
n=$(grep -c 'INPUT LINE CUT AT 240' "$err")
[ "$n" -eq 1 ] || fail "the cut was reported $n times, not once" "$(cat "$err")"

# an answer to INPUT is a keyboard line too
out=$(printf '\n10 CLEAR 500:INPUT A$:PRINT LEN(A$)\nRUN\n%s\n' "$(rep 250 Y)" | run)
case $out in *" 240 "*) ;; *) fail "an INPUT answer was not cut at 240" "$out" ;; esac

# a listing loaded from a file is not typed: a 250-character line loads whole
printf '10 A$="%s"\n20 PRINT LEN(A$)\n' "$(rep 243 X)" > "$bas"
out=$(TRS80_Z80= ./basic "$bas" 2>"$err")
case $out in *" 243 "*) ;; *) fail "LOAD cut a long line" "$out" ;; esac
[ -s "$err" ] && fail "LOAD of a long line drew a diagnostic" "$(cat "$err")"

rm -f "$err" "$bas"
echo "LINELEN OK"
