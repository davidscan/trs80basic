#!/bin/sh
# crunch.sh -- the program image is crunched as the ROM crunches (1BC0-1C8F),
# and tools/tok.py agrees with it byte for byte.  The 2026-09-19 audit's
# L-13: a letter outside a string, a REM and DATA is matched and stored in
# upper case (1C00-1C0B, 1C2D-1C31), "?" is the PRINT token (1BE4-1BE8), and
# ELSE is stored behind a ":" (1C42-1C49) -- the one thing the ROM's IF looks
# for when it skips to the ELSE.  The image is what a program PEEKs and what
# the Z80 core executes, so two crunchers that disagree give two machines.
# Self-checking: exits 1 on any mismatch.  Skips the tok.py half without python3.
# Run from the repo root:  sh programs/tests/crunch.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
dir=$(mktemp -d) || exit 2
fail() { echo "CRUNCH FAILED: $1"; printf '%s\n' "$2"; rm -rf "$dir"; exit 1; }

cat > "$dir/l.bas" <<'EOF2'
10 if a=1 then print "lower" else ? "q?";a
20 IF A THEN 30:ELSE go to 40
30 data abc, ?x:rem Stays ? as typed
40 ' and So does this ?
50 FOR I=17129 TO PEEK(16633)+256*PEEK(16634)-1:PRINT PEEK(I);:NEXT
EOF2

# 1. the bytes themselves, line 10: IF A D5 1 THEN PRINT "lower" : ELSE PRINT "q?" ; A
got=$(cd "$dir" && TRS80_Z80= "$here/basic" l.bas 2>&1 | tr -s ' \n' ' ' | sed 's/^ //; s/ $//; s/^q? 0 //')   # line 10 runs first and prints
l10='10 0 143 32 65 213 49 32 202 32 178 32 34 108 111 119 101 114 34 32 58 149 32 178 32 34 113 63 34 59 65 0'
case "$got" in
    "11 67 $l10 "*) ;;
    *) fail "line 10: upper case, ? as PRINT, ELSE behind a colon" "$got" ;;
esac
# line 20: the colon that is already there is not doubled; go to is GOTO
case "$got" in
    *" 20 0 143 32 65 32 202 32 51 48 58 149 32 141 32 52 48 0 "*) ;;
    *) fail "line 20: :ELSE keeps one colon, GO TO is 8DH" "$got" ;;
esac
# line 30: DATA and REM keep their case and their question marks
case "$got" in
    *" 30 0 136 32 97 98 99 44 32 63 120 58 147 32 83 116 97 121 115 32 63 "*) ;;
    *) fail "line 30: DATA and REM are literal" "$got" ;;
esac

# 2. tok.py makes the same image
if command -v python3 >/dev/null 2>&1; then
    python3 "$here/tools/tok.py" -o "$dir/out" "$dir/l.bas" >/dev/null 2>&1 \
        || fail "tok.py refused the listing" ""
    # drop the FFH header, print the bytes as the BASIC loop does
    want=$(python3 -c 'import sys; d=open(sys.argv[1],"rb").read()[1:]; print(" ".join(str(b) for b in d))' "$dir/out/l.bas")
    [ "$got" = "$want" ] || fail "tok.py and the interpreter's image differ" "interp: $got
tok.py: $want"
fi
rm -rf "$dir"
echo "CRUNCH OK"
