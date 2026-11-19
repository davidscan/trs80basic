#!/bin/sh
# errpaths.sh -- the Level II error each statement and function raises on
# malformed or out-of-range input, where no other suite asked (the
# 2026-11-18 coverage measurement found these raised only by the corpus).
# Each case traps its error and prints the error number (ERR/2+1) and the
# line, so a wrong code, a missing error or an error from the wrong line
# all show; the numbers are the Level II manual's error table.
# Self-checking: exits 1 on a mismatch.  Run from the repo root:
#     sh programs/tests/errpaths.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
tmp=$(mktemp) || exit 2
trap 'rm -f "$tmp"' EXIT
fail() { echo "ERRPATHS FAILED: $1"; printf '%s|\n' "$2"; exit 1; }
# the case's line 20, trapped by line 900
run() {
    printf '10 ON ERROR GOTO 900\n20 %s\n30 PRINT "NO ERROR"\n40 END\n900 PRINT "E";ERR/2+1;ERL:RESUME 40\n' "$1" > "$tmp"
    (cd "${tmp%/*}" && TRS80_Z80= "$here/basic" "$tmp") 2>&1 </dev/null
}
check() { out=$(run "$2"); [ "$out" = "E $3  20 " ] || fail "$1: want ?$4 ($3)" "$out"; }

# functions
check 'ASC of an empty string'         'PRINT ASC("")'               5  FC
check 'STRING$ longer than 255'        'PRINT LEN(STRING$(256,"A"))' 5  FC
check 'POINT x past 127'               'PRINT POINT(128,0)'          5  FC
check 'LEN of a number'                'PRINT LEN(5)'                13 TM
check 'a function name without ('      'PRINT LEN "A"'               2  SN
# expressions
check 'a string compared with a number' 'A$="X":IF A$=1 THEN PRINT "Y"' 13 TM
check 'a ; between subscripts'         'DIM A(5):PRINT A(1;2)'        2  SN
check 'an error inside a subscript'    'DIM A(5):PRINT A(1/0)'        11 /0
# statements
check 'CLEAR of a string'              'CLEAR "A"'                   13 TM
check 'DIM of a number'                'DIM 5'                        2  SN
check 'ON ERROR without GOTO'          'ON ERROR 100'                 2  SN
check 'SET without ('                  'SET 1,2'                      2  SN
check 'POKE without its comma'         'POKE 32000'                   2  SN

# string space: CLEAR ends the trap too, so ?OS is reported, not trapped
printf '10 ON ERROR GOTO 900\n20 CLEAR 10:A$=STRING$(20,"A")\n30 END\n900 PRINT "TRAPPED":END\n' > "$tmp"
out=$( (cd "${tmp%/*}" && TRS80_Z80= "$here/basic" "$tmp") 2>/dev/null </dev/null; echo "rc=$?")
[ "$out" = "rc=1" ] || fail 'CLEAR 10 then a 20-byte string: ?OS, untrapped (CLEAR resets ON ERROR)' "$out"
err=$( (cd "${tmp%/*}" && TRS80_Z80= "$here/basic" "$tmp") 2>&1 >/dev/null </dev/null | head -1)
[ "$err" = "?OS ERROR IN 20" ] || fail 'the ?OS names line 20' "$err"

# an error inside a subscript stops the array access before the array is
# made: B(1/0) leaves no auto-DIMmed B behind, so DIM B(5) is not ?DD
printf '10 ON ERROR GOTO 900\n20 PRINT B(1/0)\n30 DIM B(5):PRINT "DIM OK"\n40 END\n900 PRINT "E";ERR/2+1;ERL:IF ERL=20 THEN RESUME 30 ELSE END\n' > "$tmp"
out=$( (cd "${tmp%/*}" && TRS80_Z80= "$here/basic" "$tmp") 2>&1 </dev/null | tr '\n' '|')
[ "$out" = "E 11  20 |DIM OK|" ] || fail 'B(1/0) is ?/0 and creates no array' "$out"

echo "ERRPATHS OK"
