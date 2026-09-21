#!/bin/sh
# corepath.sh -- the launcher's auto-discovered core survives a checkout
# path with a space (or a quote) in it.
#
# TRS80_Z80 is a COMMAND, which gawk runs through `sh -c`, so the path in it
# has to be one shell word.  `TRS80_Z80="python3 $here/../trs80_z80_core/
# core.py"` was not: under "/My Code/" the shell split it in two, python3
# failed to open the first half, and the session fell back to the argument-
# returning stub (the 2026-09-19 audit, L-9).
#
# The check builds "<tmp>/sp ace/trs80basic" beside "<tmp>/sp ace/
# trs80_z80_core/core.py", which is the layout the launcher looks for, and
# uses the protocol stub as the core: the point is only whether the
# coprocess STARTS, so a notice on stderr is the failure.
# Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/corepath.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
command -v python3 >/dev/null 2>&1 || { echo "COREPATH SKIPPED: no python3"; exit 0; }
d=$(mktemp -d) || exit 2
trap 'rm -rf "$d"' EXIT
fail() { echo "COREPATH FAILED: $1"; printf '%s\n' "$2"; exit 1; }

for name in "sp ace" "quo'te"; do
    b="$d/$name/trs80basic"
    mkdir -p "$b/support" "$d/$name/trs80_z80_core" || exit 2
    cp "$here/basic" "$here/trs80basic.awk" "$b/" || exit 2
    cp "$here/support/manpages.txt" "$b/support/" || exit 2
    cp "$here/programs/tests/z80_stub.py" "$d/$name/trs80_z80_core/core.py" || exit 2
    printf '10 DEFUSR=32000:PRINT "R=";USR(7)\n' > "$b/p.bas"

    out=$(cd "$b" && env -u TRS80_Z80 ./basic p.bas 2>&1)
    case $out in
        *"cannot start"*) fail "the core did not start under '$name'" "$out" ;;
        *"can't open file"*) fail "the path was split under '$name'" "$out" ;;
    esac
    [ "$out" = "R= 7 " ] || fail "the run under '$name' printed something else" "$out"
done

echo "COREPATH OK"
