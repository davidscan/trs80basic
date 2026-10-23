#!/bin/sh
# transcripts.sh -- run the READY-prompt transcripts t1..tN and compare each
# one's output with its checked-in tN.out.  --update rewrites the .out files.
#
#   sh programs/tests/transcripts.sh            # check
#   sh programs/tests/transcripts.sh --update   # regenerate (read the diff!)
#
# Until 2026-10-23 a transcript passed when gawk exited 0, whatever it
# printed: t6's CSAVE/CLOAD and t16's PRINT # USING file had been ?FD for
# months, and t4/t7's @DUMP was ?SN, all with exit 0 (the 2026-09-30
# audit, BM-13).  Each runs from the repo root as before, with --seed 1
# (t7 prints RND), the OLLAMA stub (t13, t29) and the Z80 stub (t32), and
# its exit status is the last line of its .out.  Every tN.txt from 1 up
# must exist with its tN.out, so a new transcript cannot be left out.
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
cd "$here" || exit 2
update=0; [ "$1" = "--update" ] && update=1
got=$(mktemp) || exit 2
trap 'rm -f "$got" "$got.n"' EXIT
n=$(ls programs/tests | grep -c '^t[0-9][0-9]*\.txt$')
fail=0
i=1
while [ $i -le "$n" ]; do
    t=programs/tests/t$i
    if [ ! -f "$t.txt" ]; then
        echo "FAIL t$i: missing ($n transcripts, so t1..t$n must all exist)"; fail=1
        i=$((i+1)); continue
    fi
    env TRS80_DUMB=1 TRS80_Z80="python3 programs/tests/z80_stub.py" \
        TRS80_OLLAMA_CURL="sh programs/tests/ollama_stub.sh" \
        gawk -b -f trs80basic.awk -- --seed 1 < "$t.txt" >"$got" 2>&1
    echo "exit=$?" >>"$got"
    # `dir` prints the host's ls -l line (owner, group, date): keep its name
    sed -E 's/^[-dl][-rwxsStT]{9}[@+.]? .* ([^ ]+)$/[ls -l] \1/' "$got" >"$got.n" && mv "$got.n" "$got"
    if [ $update = 1 ]; then
        cp "$got" "$t.out"; echo "updated t$i.out"
    elif [ ! -f "$t.out" ]; then
        echo "FAIL t$i: no t$i.out (run with --update and read it)"; fail=1
    elif cmp -s "$got" "$t.out"; then
        echo "ok   t$i"
    else
        echo "FAIL t$i"; diff "$t.out" "$got" | head -20; fail=1
    fi
    i=$((i+1))
done
exit $fail
