#!/bin/sh
# devvec.sh -- the ROM device vectors 16414/5 (video) and 16422/3 (printer),
# p80 dv_update.  Self-checking: exits 1 on any mismatch.  Run from the
# repo root:  sh programs/tests/devvec.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
tmp=$(mktemp) || exit 2
lp="$tmp.lp"
run() { rm -f "$lp"; TRS80_PRINTER="$lp" "$here/basic" "$tmp" 2>&1 </dev/null; }
lpget() { [ -f "$lp" ] && cat "$lp"; }
fail() { echo "DEVVEC FIXTURE FAILED: $1"; echo "--- screen:"; printf '%s\n' "$2"; echo "--- printer:"; printf '%s\n' "$3"; rm -f "$tmp" "$lp"; exit 1; }
# the ROM defaults read back
printf '10 PRINT PEEK(16414);PEEK(16415);PEEK(16422);PEEK(16423)\n' > "$tmp"
out=$(run); [ "$out" = " 88  4  141  5 " ] || fail "defaults" "$out" "$(lpget)"
# LPRINT to the screen, then restored; the printer column does not advance while routed
printf '10 POKE 16422,88:POKE 16423,4:LPRINT "TO SCREEN":LPRINT "L2";:LPRINT:PRINT PEEK(16539);\n20 POKE 16422,141:POKE 16423,5:LPRINT "TO PRINTER"\n' > "$tmp"
out=$(run); p=$(lpget)
[ "$out" = "TO SCREEN
L2
 0 " ] && [ "$p" = "TO PRINTER" ] || fail "LPRINT to screen" "$out" "$p"
# PRINT to the printer, then restored
printf '10 PRINT "ON SCREEN":POKE 16414,141:POKE 16415,5:PRINT "TO PRINTER":PRINT "MORE";:PRINT:POKE 16414,88:POKE 16415,4:PRINT "BACK"\n' > "$tmp"
out=$(run); p=$(lpget)
[ "$out" = "ON SCREEN
BACK" ] && [ "$p" = "TO PRINTER
MORE" ] || fail "PRINT to printer" "$out" "$p"
# the printer silenced (tip 74), then restored
printf '10 POKE 16422,103:POKE 16423,0:LLIST:LPRINT "X":POKE 16422,141:POKE 16423,5:LPRINT "Y"\n' > "$tmp"
out=$(run); p=$(lpget)
[ "$out" = "" ] && [ "$p" = "Y" ] || fail "printer silenced" "$out" "$p"
# a custom machine-language driver address leaves the default route
printf '10 POKE 16422,23:POKE 16423,32:LPRINT "STILL PRINTER":POKE 16414,187:POKE 16415,64:PRINT "STILL SCREEN"\n' > "$tmp"
out=$(run); p=$(lpget)
[ "$out" = "STILL SCREEN" ] && [ "$p" = "STILL PRINTER" ] || fail "custom driver address" "$out" "$p"
# both swapped at once: no loop, the printer-to-screen route wins
printf '10 POKE 16422,88:POKE 16423,4:POKE 16414,141:POKE 16415,5:PRINT "A":LPRINT "B"\n' > "$tmp"
out=$(run); p=$(lpget)
[ "$out" = "A
B" ] && [ -z "$p" ] || fail "both swapped" "$out" "$p"
# video to a printer nobody configured: one stderr note, output discarded
printf '10 POKE 16414,141:POKE 16415,5:PRINT "GONE":PRINT "GONE TOO"\n' > "$tmp"
out=$("$here/basic" "$tmp" 2>&1 </dev/null)
[ "$out" = "VIDEO ROUTED TO THE PRINTER (POKE 16414/16415); set TRS80_PRINTER to see it, or POKE 16414,88:POKE 16415,4" ] || fail "unconfigured printer note" "$out" ""
rm -f "$tmp" "$lp"
echo "DEVVEC FIXTURE OK"
