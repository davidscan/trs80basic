#!/bin/sh
# kbmirror.sh -- the keyboard decodes 3800-3BFFH, and only the address's
# low byte selects rows, so 3900-3BFFH read as 3800-38FFH (The Alternate
# Source's and TAB's Level II memory maps: "3800H - 3BFFH keyboard").
# PEEK(15359), 3BFFH, reads every row: the period any-key test
# (IF PEEK(15359)<>0 THEN ...).  Until 2026-10-28 only 3800-38FFH was the
# matrix and 3900-3BFFH read 255, a key held on every row.
# Piped, each matrix PEEK takes one stdin byte and presses its key: "a" is
# the unshifted A key (row 0, bit 2); Ctrl-A has no key (all rows 0).
# Self-checking: exits 1 on a mismatch.  Run from the repo root:
#     sh programs/tests/kbmirror.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
tmp=$(mktemp) || exit 2
trap 'rm -f "$tmp"' EXIT
fail() { echo "KBMIRROR FAILED: $1"; printf '%s\n' "$2"; exit 1; }
run() { printf '%b' "$1" > "$tmp"; printf '%b' "$2" | (cd "${tmp%/*}" && TRS80_Z80= "$here/basic" "$tmp") 2>&1 | tr '\n' ' '; }
check() { [ "$2" = "$3" ] || fail "$1" "$2"; }

# A held: row 0 at 3801H and its mirrors 3901H, 3B01H; every row at 38FFH
# and 3BFFH; 3A00H selects no row
check 'A held, rows 0 and all, through 3BFFH' \
    "$(run '10 A=PEEK(14337):B=PEEK(14593):C=PEEK(15105):D=PEEK(15359):E=PEEK(14848):F=PEEK(14591)\n20 PRINT A;B;C;D;E;F\n' 'aaaaaa')" \
    ' 2  2  2  2  0  2  '

# no key: the mirror reads 0 like the matrix, not 255; 3800H selects no row
check 'no key, 3BFFH 3900H 3B00H' \
    "$(run '10 A=PEEK(15359):B=PEEK(14592):C=PEEK(15104):D=PEEK(14591):E=PEEK(14336)\n20 PRINT A;B;C;D;E\n' '\001\001\001\001\001')" \
    ' 0  0  0  0  0  '

# the any-key idiom: waits through no-key bytes, ends on a key
check 'IF PEEK(15359)=0 loop' \
    "$(run '10 N=N+1:IF PEEK(15359)=0 THEN 10\n20 PRINT N\n' '\001\001\001x')" \
    ' 4  '

# below and above the keyboard: 37FFH is not it, 3C00H is the screen
check '37FFH and 3C00H are not the keyboard' \
    "$(run '10 POKE 15360,65:A=PEEK(15360):PRINT PEEK(14335);A\n' '')" \
    ' 255  65  '

echo "KBMIRROR OK"
