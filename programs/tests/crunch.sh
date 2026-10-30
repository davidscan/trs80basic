#!/bin/sh
# crunch.sh -- the program image is crunched as the ROM crunches (1BC0-1C8F),
# and tools/tok.py agrees with it byte for byte.  The 2026-09-19 audit's
# a letter outside a string, a REM and DATA is matched and stored in
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
# lines 60-90: a TAB after the line number (the 2026-09-30 audit).  The digit read
# stops past blanks, TABs and LFs (1D78H-1D88H); 1A8BH backs up over
# blanks only and one blank is dropped (1A93H), so a TAB goes with all
# before it, and of blanks alone one goes
printf '60\tREM T\n70\t  REM U\n80 \tREM V\n90  REM W\n' >> "$dir/l.bas"

# 1. the bytes themselves, line 10: IF A D5 1 THEN PRINT "lower" : ELSE PRINT "q?" ; A
got=$(cd "$dir" && TRS80_Z80= "$here/basic" l.bas 2>&1 | tr -s ' \n' ' ' | sed 's/^ //; s/ $//; s/^q? 0 //')   # line 10 runs first and prints
l10='10 0 143 32 65 213 49 32 202 32 178 32 34 108 111 119 101 114 34 32 58 149 32 178 32 34 113 63 34 59 65 0'
case "$got" in
    "11 67 $l10 "*) ;;
    *) fail "line 10: upper case, ? as PRINT, ELSE behind a colon" "$got" ;;
esac
# line 20: a typed ":ELSE" is stored "::ELSE", the cruncher's colon
# always added (Farvour 1C42-1C49); go to is GOTO
case "$got" in
    *" 20 0 143 32 65 32 202 32 51 48 58 58 149 32 141 32 52 48 0 "*) ;;
    *) fail "line 20: :ELSE is stored with two colons, GO TO is 8DH" "$got" ;;
esac
# line 30: DATA and REM keep their case and their question marks
case "$got" in
    *" 30 0 136 32 97 98 99 44 32 63 120 58 147 32 83 116 97 121 115 32 63 "*) ;;
    *) fail "line 30: DATA and REM are literal" "$got" ;;
esac

case "$got" in
    *" 60 0 147 32 84 0 "*" 70 0 32 147 32 85 0 "*" 80 0 147 32 86 0 "*" 90 0 32 147 32 87 0 0 0") ;;
    *) fail "lines 60-90: a TAB after the number is dropped with what precedes it" "$got" ;;
esac

# 2. tok.py makes the same image
if command -v python3 >/dev/null 2>&1; then
    python3 "$here/tools/tok.py" -o "$dir/out" "$dir/l.bas" >/dev/null 2>&1 \
        || fail "tok.py refused the listing" ""
    # drop the FFH header, print the bytes as the BASIC loop does
    want=$(python3 -c 'import sys; d=open(sys.argv[1],"rb").read()[1:]; print(" ".join(str(b) for b in d))' "$dir/out/l.bas")
    [ "$got" = "$want" ] || fail "tok.py and the interpreter's image differ" "interp: $got
tok.py: $want"
else
    echo "CRUNCH: the tok.py half SKIPPED (no python3)"
fi
# 3. &H digits end where a keyword begins: the cruncher has made ELSE a
# token before &H is read (1BC0-1C8F), so "&HFFELSE" -- how LIST shows
# "&HFF:ELSE" -- is FF then ELSE when run, as in the image
printf '10 A=1:IF A THEN Y=&HFFELSE Y=3\n20 PRINT Y;\n30 IF 0 THEN Y=&HFFELSE Y=3\n40 PRINT Y;\n50 PRINT &H3C\n' > "$dir/h.bas"
got=$(cd "$dir" && TRS80_Z80= "$here/basic" h.bas 2>&1 | tr -s ' \n' ' ' | sed 's/^ //; s/ $//')
[ "$got" = "255 3 60" ] || fail "&HFFELSE is FF then ELSE" "$got"
rm -rf "$dir"
echo "CRUNCH OK"
