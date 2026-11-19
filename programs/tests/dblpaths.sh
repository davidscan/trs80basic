#!/bin/sh
# dblpaths.sh -- double-precision subtraction, its borrow and its swap of
# operands, zero results, and INT/FIX of doubles at every magnitude band
# (p91_dbl.awk: dadd, dint, d_norm, dmul, dneg).  The 2026-11-18 coverage
# measurement found these branches run only by the corpus: a subtraction
# whose right operand is the larger (the operands swap and the sign
# flips), a borrow out of the low 24 bits, INT of a value under 1 or past
# 2^32, and the rounding of a negative value's fraction away from zero.
# The figures are what Level II prints, digit for digit.
# Self-checking: exits 1 on a mismatch.  Run from the repo root:
#     sh programs/tests/dblpaths.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
tmp=$(mktemp) || exit 2
trap 'rm -f "$tmp"' EXIT
fail() { echo "DBLPATHS FAILED: $1"; printf '%s|\n' "$2"; exit 1; }
run() { printf '%b' "$1" > "$tmp"; (cd "${tmp%/*}" && TRS80_Z80= "$here/basic" "$tmp") 2>&1 </dev/null; }
check() { out=$(run "$2"); [ "$out" = "$3" ] || fail "$1" "$out"; }

check 'the larger right operand swaps; equal operands give 0; zero products and negations' \
    '10 PRINT 1.5#-2.25#;3#-10#;-2.5#+1.25#;1#-1#;0#*5#;-(0#)\n' \
    '-.75 -7 -1.25  0  0  0 '
check 'a tiny right operand, a cancelled sum, a decimal fraction' \
    '10 PRINT 1#-1D-16;2#-1D-15;1D10-1D10-1#;.1#-.3#\n' \
    ' .9999999999999999  1.999999999999999 -1 -.2 '
check 'a third, both ways round, and doubled' \
    '10 A#=1:B#=1/3#:PRINT A#-B#;B#-A#;A#-B#*2\n' \
    ' .6666666666666667 -.6666666666666667  .3333333333333334 '
check 'near-cancelling differences' \
    '10 PRINT 1#-.9999999999#\n20 PRINT 12345678.123#-12345679.125#\n' \
    "$(printf ' 9.999998051846149D-11 \n-1.001999999862164 ')"
check 'INT and FIX under 1, and at 11 and 12 digits' \
    '10 PRINT INT(.5#);INT(-.5#);FIX(-.5#);INT(-123456789012.5#);FIX(98765432109.9#)\n' \
    ' 0 -1  0 -123456789013  98765432109 '
check 'INT past 2^32 and at 16 digits' \
    '10 PRINT INT(4294967296.7#);INT(-4294967295.2#);INT(-1D15-.5#)\n' \
    ' 4294967296 -4294967296 -1000000000000001 '

# the borrow when the guard byte is taken away: the aligned right operand
# is a high bit with a lone low bit in its guard byte, so the low word goes
# negative (and, with an empty middle word, borrows from the top).  The
# result's eight bytes show it: the low byte is 1 where an exact
# difference would be 0 (the guard byte is not subtracted, dadd's note).
check 'the borrow, byte for byte' \
    '10 DEFINT I:K=35:Y#=3#-2^(-K):GOSUB 100\n20 H#=1#:FOR I=1 TO 8:H#=H#/2:NEXT:L#=H#:FOR I=1 TO 50:L#=L#/2:NEXT:Y#=1#-(H#+L#):GOSUB 100\n30 H#=1#:FOR I=1 TO 4:H#=H#/2:NEXT:L#=H#:FOR I=1 TO 52:L#=L#/2:NEXT:Y#=1#-(H#+L#):GOSUB 100\n40 END\n100 V=VARPTR(Y#):FOR I=0 TO 7:PRINT PEEK(V+I);:NEXT:PRINT:RETURN\n' \
    "$(printf ' 1  0  248  255  255  255  63  130 \n 0  0  0  0  0  0  127  128 \n 1  0  0  0  0  0  112  128 ')"

echo "DBLPATHS OK"
