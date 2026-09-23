#!/bin/sh
# varnames.sh -- TRS80_VARNAMES=2, the ROM's two-character variable names.
# The machine's variable table holds two characters of a name, so SUM and
# SU are one variable; a period listing may rely on it (gprixmc1.bas sets
# ADDR and reads AD).  By default (the user's ruling, 2026-08-07) every
# character counts; the switch applies the ROM's rule in the tokenizer
# (vn_cut, src/p50_token.awk).  Reserved words, USRn, BYE and DEFUSR are
# never cut, FNABC is FNAB, `$` keeps a string apart, and LIST still shows
# the names as typed.
# Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/varnames.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
dir=$(mktemp -d) || exit 2
fail() { echo "VARNAMES FAILED: $1"; printf '%s\n' "$2"; rm -rf "$dir"; exit 1; }

cat > "$dir/a.bas" <<'BAS'
10 ABC=5:PRINT AB;ABC
BAS
out=$(TRS80_Z80= "$here/basic" "$dir/a.bas" 2>&1)
[ "$out" = ' 0  5 ' ] || fail "unset: every character of a name counts" "$out"
out=$(TRS80_Z80= TRS80_VARNAMES=1 "$here/basic" "$dir/a.bas" 2>&1)
[ "$out" = ' 0  5 ' ] || fail "only the value 2 turns the rule on" "$out"
out=$(TRS80_Z80= TRS80_VARNAMES=2 "$here/basic" "$dir/a.bas" 2>&1)
[ "$out" = ' 5  5 ' ] || fail "ABC is AB" "$out"

cat > "$dir/b.bas" <<'BAS'
10 SUM=1:SU=SU+1:PRINT SUM;
20 AB=7:ABC$="X":PRINT AB;AB$;
30 DEF FNABC(X)=X*2:PRINT FNAB(4);
40 DIM XYZ(3):XYW(2)=9:PRINT XY(2);
50 FOR IDX=1 TO 3:NEXT ID:PRINT ID;
60 PRINT VARPTR(SUM)=VARPTR(SU);
70 PRINT LEFT$("HELLO",2);STRING$(2,"*");MID$("ABCD",2,2);CHR$(65);
80 DEFUSR1=&H7000:PRINT USR1(3);
90 A1B=4:PRINT A1
BAS
out=$(TRS80_Z80= TRS80_VARNAMES=2 "$here/basic" "$dir/b.bas" 2>/dev/null)
want=' 2  7 X 8  9  4 -1 HE**BCA 3  4 '
[ "$out" = "$want" ] || fail "names, strings, FN, arrays, FOR/NEXT, VARPTR, keywords, USRn" "$out"

cat > "$dir/c.bas" <<'BAS'
10 DIM AB(2)
20 DIM ABC(3)
BAS
out=$(TRS80_Z80= TRS80_VARNAMES=2 "$here/basic" "$dir/c.bas" 2>&1)
[ "$out" = '?DD ERROR IN 20' ] || fail "DIM ABC after DIM AB is a second DIM of AB" "$out"
out=$(TRS80_Z80= "$here/basic" "$dir/c.bas" 2>&1)
[ "$out" = '' ] || fail "unset: AB and ABC are two arrays" "$out"

# LIST shows the program as typed: the rule is the variable table's
out=$(printf '\n10 TOTAL1=5:ADDR=1\nLIST\n' | TRS80_Z80= TRS80_DUMB=1 TRS80_VARNAMES=2 \
      gawk -b -f "$here/trs80basic.awk" 2>&1 | grep '^10 ')
[ "$out" = '10 TOTAL1=5:ADDR=1' ] || fail "LIST keeps the full names" "$out"

rm -rf "$dir"
echo "VARNAMES OK"
