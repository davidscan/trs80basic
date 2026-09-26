#!/bin/sh
# varnames.sh -- variable names are the ROM's two characters by default, and
# every character counts under `memory host` (EXT).  The machine's variable
# table holds two characters of a name, so SUM and SU are one variable, and a
# period listing may rely on it (gprixmc1.bas sets ADDR and reads AD; 14 of
# 4,339 corpus listings differ, measured 2026-09-26).  The rule is applied in
# the tokenizer (vn_cut, src/p50_token.awk): reserved words, USRn, BYE and
# DEFUSR are never cut, FNABC is FNAB, `$` keeps a string apart, and LIST
# still shows the names as typed.  Switching the mode at the prompt or from
# a REM META: mid-run re-reads every line's names when it is next reached.
# TRS80_VARNAMES=2, the opt-in of 2026-09-23, is retired and ignored.
# Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/varnames.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
dir=$(mktemp -d) || exit 2
fail() { echo "VARNAMES FAILED: $1"; printf '%s\n' "$2"; rm -rf "$dir"; exit 1; }
run() { TRS80_Z80= TRS80_MEMORY= "$here/basic" "$@" 2>&1; }

cat > "$dir/a.bas" <<'BAS'
10 ABC=5:PRINT AB;ABC
BAS
out=$(run "$dir/a.bas");                 [ "$out" = ' 5  5 ' ] || fail "default: ABC is AB" "$out"
out=$(run --memory host "$dir/a.bas");   [ "$out" = ' 0  5 ' ] || fail "memory host: every character counts" "$out"
out=$(TRS80_Z80= TRS80_MEMORY=host "$here/basic" "$dir/a.bas" 2>&1); [ "$out" = ' 0  5 ' ] || fail "TRS80_MEMORY=host" "$out"
out=$(TRS80_Z80= TRS80_VARNAMES=2 "$here/basic" --memory host "$dir/a.bas" 2>&1); [ "$out" = ' 0  5 ' ] || fail "TRS80_VARNAMES is retired" "$out"

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
out=$(TRS80_Z80= TRS80_MEMORY= "$here/basic" "$dir/b.bas" 2>/dev/null)
want=' 2  7 X 8  9  4 -1 HE**BCA 3  4 '
[ "$out" = "$want" ] || fail "names, strings, FN, arrays, FOR/NEXT, VARPTR, keywords, USRn" "$out"

cat > "$dir/c.bas" <<'BAS'
10 DIM AB(2)
20 DIM ABC(3)
BAS
out=$(run "$dir/c.bas");                 [ "$out" = '?DD ERROR IN 20' ] || fail "DIM ABC after DIM AB is a second DIM of AB" "$out"
out=$(run --memory host "$dir/c.bas");   [ "$out" = '' ] || fail "memory host: AB and ABC are two arrays" "$out"

# LIST shows the program as typed: the rule is the variable table's
out=$(printf '\n10 TOTAL1=5:ADDR=1\nLIST\n' | TRS80_Z80= TRS80_DUMB=1 gawk -b -f "$here/trs80basic.awk" 2>&1 | grep '^10 ')
[ "$out" = '10 TOTAL1=5:ADDR=1' ] || fail "LIST keeps the full names" "$out"

# the switch at the prompt re-reads a line already run
out=$(printf '\n10 ABC=5:PRINT AB;ABC\nRUN\nmemory host\nRUN\nmemory rom\nRUN\n' | TRS80_Z80= TRS80_DUMB=1 gawk -b -f "$here/trs80basic.awk" 2>&1 | grep '^ [0-9]')
[ "$out" = ' 5  5 
 0  5 
 5  5 ' ] || fail "memory host|rom at the prompt re-reads the names" "$out"

# REM META: memory host mid-run: the line already run is re-read when
# reached again, and the directive's own line goes on to its end
cat > "$dir/d.bas" <<'BAS'
10 ABC=5:AB=1:PRINT ABC;:IF N=1 THEN PRINT XYZ:END
20 N=1:REM META: memory host
30 XYZ=9:GOTO 10
BAS
out=$(TRS80_Z80= TRS80_EXT=1 "$here/basic" "$dir/d.bas" 2>&1); [ "$out" = ' 1  5  9 ' ] || fail "REM META: memory host mid-run" "$out"
out=$(run "$dir/d.bas");                                        [ "$out" = ' 1  1  9 ' ] || fail "the directive is a remark with the gate off" "$out"

rm -rf "$dir"
echo "VARNAMES OK"
