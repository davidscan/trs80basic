#!/bin/sh
# notty.sh -- started without a terminal, the interpreter says nothing on
# stderr of its own accord.  It probes the terminal in a few places, and a
# probe that fails must fail quietly: `./basic --screen` off a terminal
# printed the SHELL's own "sh: /dev/tty: Device not configured", because
# `stty size < /dev/tty 2>/dev/null` applies its redirections left to
# right and the failed open is reported before 2>/dev/null takes effect
# (the 2026-09-19 audit, L-12).  A stray line like that lands in the
# middle of a captured transcript and in every CI log.
# Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/notty.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
d=$(mktemp -d) || exit 2
trap 'rm -rf "$d"' EXIT
fail() { echo "NOTTY FAILED: $1"; printf '%s\n' "$2"; exit 1; }

# stderr only; stdout kept in $d/o so the run is also seen to have happened
err() { TRS80_Z80= "$here/basic" "$@" </dev/null 2>"$d/e" >"$d/o"; cat "$d/e"; }

out=$(err --screen)
[ -z "$out" ] || fail "--screen off a terminal wrote to stderr" "$out"

printf '10 PRINT "HI"\n' > "$d/p.bas"
out=$(err --screen "$d/p.bas")
[ -z "$out" ] || fail "--screen with a program wrote to stderr" "$out"

out=$(err "$d/p.bas")
[ -z "$out" ] || fail "a batch run wrote to stderr" "$out"
[ "$(cat "$d/o")" = "HI" ] || fail "the batch run did not print HI" "$(cat "$d/o")"

# a piped transcript: the same, and the terminal size probe is reached by
# anything that draws the below-grid window
out=$(printf '\nPRINT "HI"\nman PRINT\n' | TRS80_DUMB=1 TRS80_Z80= \
        gawk -b -f "$here/trs80basic.awk" 2>"$d/e" >"$d/o"; cat "$d/e")
[ -z "$out" ] || fail "a piped transcript wrote to stderr" "$out"
grep -q '^HI$' "$d/o" && grep -q 'PRINT \[items\]' "$d/o" || fail "the piped transcript did not run" "$(cat "$d/o")"

echo "NOTTY OK"
