#!/bin/sh
# speed.sh -- the throttle (TRS80_MHZ, the `speed` metacommand) holds the
# wall clock to the clock rate it is given.  Every statement is charged
# CYCPERSTMT = 1000 cycles, so at 1.77 MHz a run of N statements takes
# N * 0.565 ms; the pacing is closed-loop against gawk's time extension
# (thr_wait, p10), which the launcher loads.  Until 2026-09-26 each slice
# forked `sleep` for its whole share on top of the time already spent, and
# the same loop ran 40% slow (the 2026-09-23 audit, L-13).  The loop here
# is 4003 statements: 2.26 s nominal, 3.2 s under the old code, so the
# bound below separates them with room for a slow runner.
# Without the extension (a gawk that prints a warning for it, which the
# launcher refuses) the pacing is open-loop and only "not faster" is
# asserted; the clock case then prints SKIPPED, which run_all counts.
# Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/speed.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
tmp=$(mktemp -d) || exit 2
fail() { echo "SPEED FAILED: $1"; printf '%s\n' "$2"; rm -rf "$tmp"; exit 1; }
cat > "$tmp/loop.bas" <<'EOF2'
10 FOR I=1 TO 2000
20 X=I
30 NEXT I
40 PRINT "DONE"
EOF2
nominal=2.262     # 4003 statements * 1000 cycles / 1.77 MHz

# the clock: the extension the launcher would load, probed as it probes
tm=
for ext in time timex; do
    if out=$(gawk -l "$ext" 'BEGIN { }' 2>&1) && [ -z "$out" ]; then tm="-l $ext"; break; fi
done
now() { gawk $tm 'BEGIN { printf "%.3f", gettimeofday() }'; }
# seconds between two readings, and a comparison, in awk (sh has no decimals)
elapsed() { gawk -v a="$1" -v b="$2" 'BEGIN { printf "%.3f", b - a }'; }
between() { gawk -v x="$1" -v lo="$2" -v hi="$3" 'BEGIN { exit !(x >= lo && x <= hi) }'; }

# 1. the open loop (no extension), which every gawk has: never faster than
# the nominal, and the run happened
t0=$(date +%s)
out=$(cd "$tmp" && TRS80_DUMB=1 TRS80_Z80= TRS80_MHZ=1.77 gawk -b -f "$here/trs80basic.awk" loop.bas 2>&1)
t1=$(date +%s)
[ "$out" = "DONE" ] || fail "the open-loop run" "$out"
[ $((t1 - t0)) -ge 2 ] || fail "the open loop ran faster than 1.77 MHz allows: $((t1 - t0)) s for $nominal s of statements" "$out"

if [ -z "$tm" ]; then
    echo "SKIPPED: the closed-loop pacing (this gawk has no time extension the launcher would load)"
    rm -rf "$tmp"; echo "SPEED OK"; exit 0
fi

# 2. the closed loop through the launcher: within 5% below and 15% (plus
# start-up) above the nominal.  The old code's 3.2 s fails this.
t0=$(now)
out=$(cd "$tmp" && TRS80_DUMB=1 TRS80_Z80= TRS80_MHZ=1.77 "$here/basic" loop.bas 2>&1)
t1=$(now)
e=$(elapsed "$t0" "$t1")
[ "$out" = "DONE" ] || fail "the throttled run" "$out"
between "$e" 2.15 2.90 || fail "1.77 MHz: $e s for a $nominal s run (the old open loop took 3.2 s)" "$out"

# 3. `speed` at READY sets the same pacing (speed 3.54: half the time), and
# speed 0 lifts it: the same loop at full speed is under half a second
prog='10 FOR I=1 TO 2000\n20 X=I\n30 NEXT I\n40 PRINT "DONE"\n'
t0=$(now)
out=$(cd "$tmp" && printf "\nspeed 3.54\n${prog}RUN\nBYE\n" | TRS80_DUMB=1 TRS80_Z80= "$here/basic" 2>&1 | grep -c '^DONE')
t1=$(now)
e=$(elapsed "$t0" "$t1")
[ "$out" = "1" ] || fail "the speed 3.54 run" "$out"
between "$e" 1.07 1.60 || fail "speed 3.54: $e s for a 1.13 s run" ""
t0=$(now)
out=$(cd "$tmp" && printf "\nspeed 0\n${prog}RUN\nBYE\n" | TRS80_DUMB=1 TRS80_Z80= TRS80_MHZ=1.77 "$here/basic" 2>&1 | grep -c '^DONE')
t1=$(now)
e=$(elapsed "$t0" "$t1")
[ "$out" = "1" ] || fail "the speed 0 run" "$out"
between "$e" 0 0.5 || fail "speed 0 after TRS80_MHZ=1.77 still paced: $e s" ""
rm -rf "$tmp"
echo "SPEED OK"
