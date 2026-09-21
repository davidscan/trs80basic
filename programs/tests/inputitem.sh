#!/bin/sh
# inputitem.sh -- where INPUT's items end.  The ROM reads a typed line with
# READ's own item reader (21EBH puts a comma in front of the buffer "to
# make READ think" it is in a DATA statement), so the line ends where a
# DATA statement would:
#   * an unquoted ":" ends the item and the data (2869H; RST 10H calls ":"
#     an end of statement, 225B).  What is behind it is never read:
#     ?EXTRA IGNORED, or ?? when variables are still waiting
#   * "AB"CD -- text between the closing quote and the comma -- is ?REDO
#   * a quoted "12" typed for a number is ?REDO
#   * a tab behind the closing quote is skipped like a blank (RST 10H)
# Until 2026-09-21 AB:CD came through whole, "AB"CD was AB with the rest of
# the line dropped, and "12" was the number 12.
# Self-checking: exits 1 on any mismatch.  Run from the repo root:
#     sh programs/tests/inputitem.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
tmp=$(mktemp -d) || exit 2
fail() { echo "INPUTITEM FAILED: $1"; printf '%s\n' "$2" | head -30; rm -rf "$tmp"; exit 1; }
run() { ( cd "$tmp" && TRS80_Z80= perl -e 'alarm 20; exec @ARGV' "$here/basic" "$@" 2>&1 ); }

cat > "$tmp/in.bas" <<'BAS'
10 INPUT A$:PRINT "[";A$;"]"
20 INPUT B$,C$:PRINT "[";B$;"][";C$;"]"
30 INPUT D$:PRINT "[";D$;"]"
40 INPUT N:PRINT N
50 INPUT M:PRINT M
60 INPUT E$,F$:PRINT "[";E$;"][";F$;"]"
BAS
out=$(printf 'AB:CD,EF\nX:Y\nZ\n"AB"CD\n"OK"\t\n"12"\n12\n5:6\n"A:B","C" ,D\n' | run "$tmp/in.bas")
want='? AB:CD,EF
?EXTRA IGNORED
[AB]
? X:Y
?? Z
[X][Z]
? "AB"CD
?REDO
? "OK"
[OK]
? "12"
?REDO
? 12
 12 
? 5:6
?EXTRA IGNORED
 5 
? "A:B","C" ,D
?EXTRA IGNORED
[A:B][C]'
[ "$out" = "$want" ] || fail "INPUT" "$out"

rm -rf "$tmp"
echo "INPUTITEM OK"
