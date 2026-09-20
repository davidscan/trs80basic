#!/bin/sh
# sound.sh -- machine-code sound through the real companion core (its
# z80/sound.py) and the interpreter's `sound` metacommand.  Self-checking:
# exits 1 on any mismatch, 0 with SKIPPED when the core is not present.
# Run from the repo root:  sh programs/tests/sound.sh
#
# The routine is the Dancing Demon's shape, self-written (no listing's
# bytes): OUT (C),H / LD B,D / DJNZ / OUT (C),L / LD B,D / DJNZ around
# D = 100, so one cycle costs 26*100 + 38 = 2,638 T-states and the pitch is
# 1,774,080 / 2,638 = 672.5 Hz at the Model I clock, 568.6 Hz at 1.5 MHz.
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
core=${TRS80_Z80:-"python3 $here/../trs80_z80_core/core.py"}
set -- $core
[ -f "$2" ] || { echo "SOUND FIXTURE SKIPPED: no core at $2"; exit 0; }
tmp=$(mktemp) || exit 2
fail() { echo "SOUND FIXTURE FAILED: $1"; [ -n "$2" ] && printf '%s\n' "$2"; rm -f "$tmp" "$tmp".*; exit 1; }
pitch() {   # Hz from the zero crossings of a 16-bit mono WAV; $2 $3: from/to sample
python3 - "$@" <<'PY'
import sys, wave, array
w = wave.open(sys.argv[1], 'rb'); rate = w.getframerate()
a = array.array('h', w.readframes(w.getnframes()))
if sys.byteorder == 'big': a.byteswap()
if len(sys.argv) > 2: a = a[int(sys.argv[2]):len(a) if sys.argv[3] == 'end' else int(sys.argv[3])]
ups = [i for i in range(1, len(a)) if a[i - 1] < 0 <= a[i]]
print('%.1f' % ((len(ups) - 1) / ((ups[-1] - ups[0]) / rate)) if len(ups) > 2 else '0')
PY
}
frames() { python3 -c 'import sys, wave; print(wave.open(sys.argv[1], "rb").getnframes())' "$1"; }
near() { python3 -c 'import sys; sys.exit(0 if abs(float(sys.argv[1]) / float(sys.argv[2]) - 1) <= 0.005 else 1)' "$1" "$2"; }
count() { grep -c "$1" "$2"; }
TONE='22,100,14,255,33,1,2,62,1,30,0,237,97,66,16,254,237,105,66,16,254,29,32,243,61,32,240,201'

# --- 1. batch: TRS80_SOUND_WAV alone, pitch from the file
cat > "$tmp" <<EOF
10 FOR I=0 TO 27:READ B:POKE 32000+I,B:NEXT
20 DATA $TONE
30 DEFUSR=32000:X=USR(0):PRINT "TONE DONE"
EOF
out=$(TRS80_SOUND_WAV="$tmp.1.wav" TRS80_Z80="$core" "$here/basic" "$tmp" 2>"$tmp.err" </dev/null); rc=$?
[ "$rc" = "0" ] && [ "$out" = "TONE DONE" ] && [ ! -s "$tmp.err" ] || fail "batch WAV run rc=$rc" "$out
$(cat "$tmp.err")"
p=$(pitch "$tmp.1.wav")
near "$p" 672.5 || fail "batch WAV pitch: got $p Hz, want 672.5"

# --- 2. the metacommand's switches, through the REPL.  The player command
# logs each start, so `sound off` and the WAV-only core are seen not to start
# one; the restart's full frame carries a byte an earlier core wrote.
cat > "$tmp.t" <<EOF

sound
sound on
10 FOR I=0 TO 27:READ B:POKE 32000+I,B:NEXT
20 DATA $TONE
30 FOR I=0 TO 5:READ B:POKE 32200+I,B:NEXT
40 DATA 62,7,50,100,125,201
50 FOR I=0 TO 8:READ B:POKE 32300+I,B:NEXT
60 DATA 205,127,10,110,38,0,195,154,10
70 DEFUSR=32000:X=USR(0):DEFUSR1=32200:X=USR1(0):PRINT "TONE DONE"
75 DEFUSR2=32300:PRINT "BYTE";USR2(32100)
RUN
sound off
RUN
sound wav $tmp.2.wav
RUN 75
sound wav $tmp.3.wav
RUN
sound wav off
sound
BYE
EOF
TRS80_SOUND="echo start >> $tmp.log; cat >> $tmp.pcm" TRS80_DUMB=1 TRS80_Z80="$core" "$here/basic" < "$tmp.t" > "$tmp.out" 2>"$tmp.err"; rc=$?
[ "$rc" = "0" ] || fail "metacommand transcript rc=$rc" "$(cat "$tmp.out" "$tmp.err")"
[ ! -s "$tmp.err" ] || fail "metacommand transcript wrote to stderr" "$(cat "$tmp.err")"
[ "$(count 'SOUND ON (player from TRS80_SOUND), WAV OFF' "$tmp.out")" = "2" ] || fail "state after start / sound on" "$(cat "$tmp.out")"
[ "$(count 'SOUND OFF, WAV OFF' "$tmp.out")" = "3" ] || fail "state after sound off / wav off" "$(cat "$tmp.out")"
[ "$(count "SOUND OFF, WAV $tmp.2.wav" "$tmp.out")" = "1" ] || fail "state after sound wav" "$(cat "$tmp.out")"
[ "$(count '^TONE DONE' "$tmp.out")" = "3" ] || fail "three full runs" "$(cat "$tmp.out")"
[ "$(count '^BYTE 7 ' "$tmp.out")" = "4" ] || fail "the byte a core wrote survives every restart (RUN 75 reads it from a fresh core)" "$(cat "$tmp.out")"
[ "$(cat "$tmp.log" 2>/dev/null | wc -l | tr -d ' ')" = "1" ] || fail "the player started $(cat "$tmp.log" 2>/dev/null | wc -l) times, want 1 (sound on once; off and wav-only cores start none)" "$(cat "$tmp.out")"
[ "$(wc -c < "$tmp.pcm" | tr -d ' ')" -ge 16000 ] || fail "the player received $(wc -c < "$tmp.pcm") bytes, want the tone (16,788) plus the lead"
[ "$(wc -c < "$tmp.2.wav" | tr -d ' ')" = "44" ] || fail "RUN 75 makes no sound: its WAV should be a bare header" "$(wc -c < "$tmp.2.wav")"
p=$(pitch "$tmp.3.wav")
near "$p" 672.5 || fail "sound wav through the metacommand: got $p Hz, want 672.5"

# --- 3. `speed` typed after the first call reaches the core, and the restart
# does not start the capture over: the WAV holds the first run's tone at the
# Model I clock (as long as case 1's file) and then the second's at 1.5 MHz
cat > "$tmp.t" <<EOF

sound wav $tmp.4.wav
10 FOR I=0 TO 27:READ B:POKE 32000+I,B:NEXT
20 DATA $TONE
30 DEFUSR=32000:X=USR(0):PRINT "TONE DONE"
RUN
speed 1.5
RUN
BYE
EOF
TRS80_DUMB=1 TRS80_Z80="$core" "$here/basic" < "$tmp.t" > "$tmp.out" 2>"$tmp.err"; rc=$?
[ "$rc" = "0" ] && [ ! -s "$tmp.err" ] || fail "speed transcript rc=$rc" "$(cat "$tmp.out" "$tmp.err")"
[ "$(count '^TONE DONE' "$tmp.out")" = "2" ] || fail "two runs" "$(cat "$tmp.out")"
n1=$(frames "$tmp.1.wav"); n4=$(frames "$tmp.4.wav")
[ "$n4" -gt "$((n1 * 2))" ] || fail "the restart for speed started the WAV over: $n4 frames, the first run alone made $n1"
p=$(pitch "$tmp.4.wav" 0 "$n1")
near "$p" 672.5 || fail "the first run's tone is gone from the WAV: got $p Hz, want 672.5"
p=$(pitch "$tmp.4.wav" "$n1" end)
near "$p" 568.6 || fail "speed 1.5 after the first call: got $p Hz, want 568.6 (the core was not restarted?)"
# ... and naming the file again begins a new capture in it
cat > "$tmp.t" <<EOF

sound wav $tmp.5.wav
10 FOR I=0 TO 27:READ B:POKE 32000+I,B:NEXT
20 DATA $TONE
30 DEFUSR=32000:X=USR(0):PRINT "TONE DONE"
RUN
sound wav $tmp.5.wav
RUN
BYE
EOF
TRS80_DUMB=1 TRS80_Z80="$core" "$here/basic" < "$tmp.t" > "$tmp.out" 2>"$tmp.err"; rc=$?
[ "$rc" = "0" ] && [ ! -s "$tmp.err" ] || fail "sound wav twice rc=$rc" "$(cat "$tmp.out" "$tmp.err")"
[ "$(frames "$tmp.5.wav")" = "$n1" ] || fail "sound wav <the same path> should begin a new capture: $(frames "$tmp.5.wav") frames, want $n1"

# --- 4. no core: the state report says so
printf '\nsound\nBYE\n' | TRS80_DUMB=1 TRS80_Z80= "$here/basic" > "$tmp.out" 2>&1
grep -q 'NO CORE' "$tmp.out" || fail "no-core notice" "$(cat "$tmp.out")"

rm -f "$tmp" "$tmp".*
echo "SOUND FIXTURE OK"
