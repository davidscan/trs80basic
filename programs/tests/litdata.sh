#!/bin/sh
# litdata.sh -- the address of a string assigned from a literal, when a DATA
# statement stands earlier in the same line.  A string assigned from a
# literal keeps its bytes in the program line (p75_mem.awk lit_addr), and
# finding them walks the line's literals in order: a DATA statement's items
# are skipped to the next ":" outside quotes, so a quoted ":" inside DATA
# must not end the skip, and a second DATA later in the line is skipped the
# same way.  The address is the program image's own (42E9H on): the byte
# PEEKed there is the literal's first character.
# Self-checking: exits 1 on a mismatch.  Run from the repo root:
#     sh programs/tests/litdata.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
tmp=$(mktemp) || exit 2
trap 'rm -f "$tmp"' EXIT
fail() { echo "LITDATA FAILED: $1"; printf '%s|\n' "$2"; exit 1; }
run() { printf '%b' "$1" > "$tmp"; (cd "${tmp%/*}" && TRS80_Z80= "$here/basic" "$tmp") 2>&1 </dev/null; }
check() { out=$(run "$2"); [ "$out" = "$3" ] || fail "$1" "$out"; }

check 'a quoted ":" inside DATA does not end the skip' \
    '10 DATA "Q:R",5:A$="HELLO":V=VARPTR(A$):A=PEEK(V+1)+256*PEEK(V+2):PRINT PEEK(V);A;CHR$(PEEK(A))\n' \
    ' 5  17147 H'
check 'two DATA statements and a literal between them' \
    '10 DATA 1,2:B$="AB":DATA 3:A$="XYZ":V=VARPTR(A$):A=PEEK(V+1)+256*PEEK(V+2):PRINT PEEK(V);A;CHR$(PEEK(A))\n' \
    ' 3  17155 X'

echo "LITDATA OK"
