#!/bin/sh
# fileerr.sh -- the Disk BASIC file errors raised on a channel that is not
# open, a bad mode or name, a bad record number and a short CVI string,
# by the interpreter's Disk BASIC error table (p10 ERRC: 53 bad file
# number, 64 bad record number; 13 type mismatch, 21 missing operand,
# 5 illegal function call, 2 syntax error).  Each case traps its error and
# prints ERR/2+1.  (The 2026-11-18 coverage measurement found these
# raised only by the corpus.)
# Self-checking: exits 1 on a mismatch.  Run from the repo root:
#     sh programs/tests/fileerr.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
dir=$(mktemp -d) || exit 2
trap 'rm -rf "$dir"' EXIT
fail() { echo "FILEERR FAILED: $1"; printf '%s|\n' "$2"; exit 1; }
run() {
    printf '10 ON ERROR GOTO 90\n20 %s\n30 CLOSE:END\n90 PRINT ERR/2+1:RESUME 30\n' "$1" > "$dir/p.bas"
    (cd "$dir" && TRS80_Z80= "$here/basic" p.bas) 2>&1 </dev/null
}
check() { out=$(run "$2"); [ "$out" = " $3 " ] || fail "$1: want $3" "$out"; }

check 'GET on a closed channel'         'GET 1,1'               53
check 'PUT on a closed channel'         'PUT 1,1'               53
check 'FIELD on a closed channel'       'FIELD 1,10 AS A$'      53
check 'LINE INPUT# on a closed channel' 'LINE INPUT#1,A$'       53
check 'EOF of a closed channel'         'PRINT EOF(3)'          53
check 'LOF of a closed channel'         'PRINT LOF(3)'          53
check 'OPEN with a numeric mode'        'OPEN 5,1,"X"'          13
check 'KILL of an empty name'           'KILL ""'               21
check 'CVI of a one-byte string'        'PRINT CVI("A")'         5
check 'LSET of a number'                'LSET 5="A"'             2
check 'GET of record 0'                 'OPEN "R",1,"r.dat",8:FIELD 1,8 AS A$:GET 1,0' 64
check 'PUT of record 0'                 'OPEN "R",1,"r.dat",8:FIELD 1,8 AS A$:LSET A$="X":PUT 1,0' 64

echo "FILEERR OK"
