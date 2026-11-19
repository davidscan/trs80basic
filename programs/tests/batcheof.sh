#!/bin/sh
# batcheof.sh -- batch mode when the program asks for more input than stdin
# holds: INPUT and LINE INPUT, into a variable or an array element, stop
# the program with "?BATCH: END OF INPUT AT LINE n" on stderr and exit
# status 1, after everything the program printed before; and a program
# that waits on the keyboard matrix (PEEK 3800H-3BFFH) once stdin is
# exhausted stops as a BREAK would, silently, with status 0.  (The
# 2026-11-18 coverage measurement found these paths run only by the
# corpus, where some 1,800 listings end this way.)
# Self-checking: exits 1 on a mismatch.  Run from the repo root:
#     sh programs/tests/batcheof.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
tmp=$(mktemp) || exit 2
trap 'rm -f "$tmp"' EXIT
fail() { echo "BATCHEOF FAILED: $1"; printf '%s|\n' "$2"; exit 1; }
# the program's stdout, then its stderr and exit status (two runs: the
# program is deterministic, and no second temporary file is needed)
run() {
    printf '%b' "$1" > "$tmp"
    o=$( (cd "${tmp%/*}" && printf '%b' "$2" | TRS80_Z80= "$here/basic" "$tmp" 2>/dev/null) )
    e=$( (cd "${tmp%/*}" && printf '%b' "$2" | TRS80_Z80= "$here/basic" "$tmp" 2>&1 >/dev/null; echo "rc=$?") )
    printf '%s\n%s' "$o" "$e"
}
check() { out=$(run "$2" "$3"); [ "$out" = "$4" ] || fail "$1" "$out"; }

check 'INPUT: the first is answered, the second meets the end' \
    '10 INPUT A\n20 PRINT "GOT";A\n30 INPUT B\n40 PRINT "NEVER"\n' '7\n' \
    "$(printf '? 7\nGOT 7 \n? \n?BATCH: END OF INPUT AT LINE 30\nrc=1')"
check 'INPUT of two answered with one: "??" then the end' \
    '10 INPUT A,B\n20 PRINT "NEVER"\n' '1\n' \
    "$(printf '? 1\n?? \n?BATCH: END OF INPUT AT LINE 10\nrc=1')"
check 'LINE INPUT likewise' \
    '10 LINE INPUT A$\n20 PRINT A$\n30 LINE INPUT B$\n40 PRINT "NEVER"\n' 'HI THERE\n' \
    "$(printf 'HI THERE\nHI THERE\n?BATCH: END OF INPUT AT LINE 30\nrc=1')"
check 'INPUT into an array element' \
    '10 DIM A(3)\n20 INPUT A(1)\n30 PRINT "NEVER"\n' '' \
    "$(printf '? \n?BATCH: END OF INPUT AT LINE 20\nrc=1')"
check 'LINE INPUT into an array element' \
    '10 DIM A$(3)\n20 LINE INPUT A$(2)\n30 PRINT "NEVER"\n' '' \
    "$(printf '\n?BATCH: END OF INPUT AT LINE 20\nrc=1')"
check 'LINE INPUT into an array element, answered: commas and all' \
    '10 DIM A$(3)\n20 LINE INPUT A$(2)\n30 PRINT A$(2)\n' 'X, Y\n' \
    "$(printf 'X, Y\nX, Y\nrc=0')"
check 'a keyboard-matrix wait after stdin: a silent stop, status 0' \
    '10 PRINT "A"\n20 IF PEEK(14400)=0 THEN 20\n30 PRINT "NEVER"\n' '' \
    "$(printf 'A\nrc=0')"

echo "BATCHEOF OK"
