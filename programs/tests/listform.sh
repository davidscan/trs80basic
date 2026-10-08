#!/bin/sh
# listform.sh -- LIST shows a line as the ROM STORED it, not as it was
# typed (audit BM-5).  The cruncher upper-cases letters outside strings,
# DATA and REM, stores ? as PRINT and GO TO as GOTO (1BC0-1C8F); LIST
# (2B7E-2BC4) expands the stored bytes back with no blank added, ELSE
# takes back the ":" it is stored behind and ' the ":REM" before it, and
# the expansion stops at 255 characters.  LLIST, SAVE and CSAVE write the
# same text.  Until 2026-10-08 all four printed the line as typed.
# Self-checking: exits 1 on a mismatch.  Run from the repo root:
#     sh programs/tests/listform.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
dir=$(mktemp -d) || exit 2
trap 'rm -rf "$dir"' EXIT
fail() { echo "LISTFORM FAILED: $1"; printf '%s\n' "$2"; exit 1; }
# an interactive transcript (the blank line answers MEM SIZE?)
run() { printf '\n%s\n' "$1" | (cd "$dir" && TRS80_DUMB=1 TRS80_Z80= TRS80_PRINTER="$dir/lp" gawk -b -f "$here/trs80basic.awk" 2>&1); }

prog='10 print a:? "x";b
20 go to 10
30 if a then 10 else print "q"
40 data aB,c:rem lower
50 a=1 '"'"' hi There
60 print"x":'"'"'c
70 go  to 10
80 gosub10:return
90 x = 1 : y=2
100 a=b or c and not d'
want='10 PRINT A:PRINT "x";B
20 GOTO 10
30 IF A THEN 10 ELSE PRINT "q"
40 DATA aB,c:REM lower
50 A=1 '"'"' hi There
60 PRINT"x":'"'"'c
70 GOTO 10
80 GOSUB10:RETURN
90 X = 1 : Y=2
100 A=B OR C AND NOT D'

# 1. LIST
got=$(run "$prog
LIST" | sed -n '/^>LIST/,/^READY/p' | sed '1d;$d')
[ "$got" = "$want" ] || fail "LIST shows the stored form" "$got"

# 2. LLIST and SAVE write the same text
run "$prog
LLIST
SAVE \"s.bas\"" >/dev/null
got=$(cat "$dir/lp")
[ "$got" = "$want" ] || fail "LLIST shows the stored form" "$got"
got=$(cat "$dir/s.bas")
[ "$got" = "$want" ] || fail "SAVE writes the stored form" "$got"

# 3. the expansion stops at 255 characters: 110 crunched PRINTs behind QQ:
long="10 QQ:$(printf '?:%.0s' $(seq 1 110))?"
got=$(run "$long
LIST" | sed -n '/^>LIST/{n;p;}')
exp="10 QQ:$(printf 'PRINT:%.0s' $(seq 1 42))"
[ "$got" = "$exp" ] || fail "LIST cuts the expansion at 255 characters" "$got"
[ ${#got} -eq 258 ] || fail "the listed line is 3 + 255 characters" "${#got}"

echo "listform: ok"
