#!/bin/sh
# screencell.sh -- what a display cell's byte means to POINT and to the SET
# color.  (The 2026-11-19 coverage run of a downstream program's test
# suite reached these; no suite here did.)
#   1. POINT on a cell holding a text byte is 0 for each of its six pixels
#      (Level II manual: POINT tests a graphics block): 65 has bit 0 set,
#      which a graphics reading would take as the cell's top-left pixel.
#   2. EXT: POKE of a non-graphics byte onto a cell retires its SET(x,y,c)
#      color, as printing a character there does; a graphics byte (128-191)
#      keeps it.  Seen only on the grid, so this case runs with --screen
#      and reads the last draw of each cell from the ANSI stream.
# Self-checking: exits 1 on a mismatch.  Run from the repo root:
#     sh programs/tests/screencell.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
dir=$(mktemp -d) || exit 2
trap 'rm -rf "$dir"' EXIT
fail() { echo "SCREENCELL FAILED: $1"; printf '%s|\n' "$2"; exit 1; }

# 1. POINT on a text cell
printf '10 CLS:POKE 15360,65:PRINT POINT(0,0);POINT(1,2);POINT(2,0)\n' > "$dir/p.bas"
out=$(cd "$dir" && TRS80_Z80= TRS80_DUMB=1 "$here/basic" p.bas 2>&1 </dev/null)
[ "$out" = " 0  0  0 " ] || fail 'POINT on a text byte is 0' "$out"

# 2. the SET color under POKE (EXT): cell 0 gets a text byte, cell 1 a
# graphics byte; each cell's last draw starts with the color escape or not
printf '10 CLS:SET(0,0,2):SET(2,0,3)\n20 POKE 15360,65:POKE 15361,191\n' > "$dir/c.bas"
(cd "$dir" && TRS80_Z80= "$here/basic" --screen c.bas >"$dir/c.out" 2>&1 </dev/null)
last() { LC_ALL=C gawk -b -v RS="\033\\\\[1;$1H" 'END { printf "%s", substr($0, 1, 3) }' "$dir/c.out"; }
c0=$(last 1); c1=$(last 2)
[ "$c0" = "A$(printf '\033')[" ] || fail 'POKE 65 onto a colored cell draws it uncolored' "$(printf '%s' "$c0" | od -c | head -1)"
[ "$c1" = "$(printf '\033')[3" ] || fail 'POKE 191 onto a colored cell keeps the color' "$(printf '%s' "$c1" | od -c | head -1)"

echo "SCREENCELL OK"
