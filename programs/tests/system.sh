#!/bin/sh
# system.sh -- the SYSTEM command: a SYSTEM tape and a /CMD load module
# loaded from host files, run through the USR frame, the manual's prompt
# protocol, and its error paths.  Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/system.sh
#
# Two parts.  With the stub (TRS80_Z80=) the LOADS are checked: every byte
# lands where the tape says (PEEK sees it), the entry is taken, the DOS
# form is ?FC, a missing name is ?FD, a bad checksum prints C and prompts
# again, and `/` is tallied as an unexecuted USR call.  With the real core
# beside the checkout the RUNS are checked too: the tape writes HI on the
# screen and RETurns, the load module ends with JP 1A19H (READY), `/32000`
# runs what is in memory.  Inside a PROGRAM the two endings differ: after a
# RET the next statement runs, and JP 1A19H ends the program at READY, as
# the machine does (the 2026-09-19 audit, L-44 -- until then this suite
# pinned the next statement running after it, too).
#
# The fixtures were assembled by the core's `python3 -m z80.asm`:
#   syshi.cas   ORG 7D00H: LD HL,3C00H / LD (HL),'H' / INC HL / LD (HL),'I'
#               / LD A,7 / LD (7D40H),A / RET            (SYSTEM tape, name SYSHI)
#   sysrdy.cmd  ORG 7E00H: LD A,9 / LD (7E40H),A / JP 1A19H   (/CMD, name SYSRDY)
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
cd "$here" || exit 2
tmp=$(mktemp) || exit 2
bad=$(mktemp) || exit 2
a5=$(mktemp) || exit 2
ne=$(mktemp) || exit 2
trap 'rm -f "$tmp" "$tmp.err" "$bad" "$bad.cas" "$a5" "$a5.cmd" "$ne" "$ne.cas" "$ne.cmd"' EXIT
fail() { echo "SYSTEM FAILED: $1"; [ -n "$2" ] && printf '%s\n' "$2"; exit 1; }
# $1 is the core command ("" = the stub).  It is set on gawk itself, not on
# the function: under POSIX sh an assignment in front of a function call
# outlives it, and `TRS80_Z80= run` left part 2 blind to a core named in
# the environment (the 2026-09-23 audit's NIT)
run() { TRS80_DUMB=1 TRS80_Z80="$1" gawk -b -f trs80basic.awk >"$tmp" 2>"$tmp.err"; }

# a copy of the tape with one data byte flipped: a checksum error
mv "$bad" "$bad.cas"
python3 -c "
b = bytearray(open('programs/tests/syshi.cas', 'rb').read()); b[270] ^= 1
open('$bad.cas', 'wb').write(b)" 2>/dev/null || cp programs/tests/syshi.cas "$bad.cas"

# ---- part 1: the loads, with the stub ----------------------------------------
esc=$(printf '\033')
run "" <<EOF

SYSTEM
programs/tests/syshi
/
PRINT "A";PEEK(32000);PEEK(32001);PEEK(32002);PEEK(32013)
SYSTEM
programs/tests/sysrdy.cmd
/
PRINT "B";PEEK(32256);PEEK(32257);PEEK(32263)
SYSTEM "I"
PRINT "PASSFC"
SYSTEM "I${esc}[2KZ"
PRINT "PASSESC"
SYSTEM
nosuchfile
PRINT "PASSFD"
SYSTEM
$bad
/
PRINT "PASSC"
EOF
grep -q "A 33  0  60  201" "$tmp" || fail "the tape's bytes did not land at 7D00H" "$(cat "$tmp")"
grep -q "B 62  9  26" "$tmp" || fail "the load module's bytes did not land at 7E00H" "$(cat "$tmp")"
grep -q "?FC ERROR" "$tmp" || fail "SYSTEM \"I\" (a DOS command) must be ?FC" "$(cat "$tmp")"
grep -q "^PASSFC" "$tmp" || fail "?FC did not let the next line run" "$(cat "$tmp")"
# the ?FC message quotes the program's own bytes: a control byte in them is
# shown as a full stop, never sent raw to the terminal (the 2026-09-23 audit, L-8)
grep -q "^PASSESC" "$tmp" || fail "SYSTEM with an ESC byte in the string did not let the next line run" "$(cat "$tmp")"
LC_ALL=C grep -q "$esc" "$tmp.err" && fail "a raw ESC byte from SYSTEM's string reached stderr" "$(LC_ALL=C od -c "$tmp.err" | head -20)"
grep -q 'SYSTEM "I.\[2KZ"' "$tmp.err" || fail "the control byte in SYSTEM's string must show as a full stop" "$(cat "$tmp.err")"
grep -q "?FD ERROR" "$tmp" || fail "a name that is not a file must be ?FD" "$(cat "$tmp")"
grep -q "^PASSFD" "$tmp" || fail "?FD did not let the next line run" "$(cat "$tmp")"
grep -q "^C$" "$tmp" || fail "a bad checksum must print C at the prompt" "$(cat "$tmp")"
grep -q "^PASSC" "$tmp" || fail "the program did not go on after the bad tape" "$(cat "$tmp")"
# the tally is printed as each immediate command finishes: one line per /
[ "$(grep -c "USR STUB: 1 CALL NOT EXECUTED" "$tmp.err")" -eq 3 ] \
    || fail "the stub must tally the three / runs, one line each" "$(cat "$tmp.err")"
grep -q "(7D00H x1)" "$tmp.err" && grep -q "(7E00H x1)" "$tmp.err" \
    || fail "the tally must name the entry addresses" "$(cat "$tmp.err")"

# A load module whose CODE holds A5H 55H is still a load module (the
# 2026-09-19 audit, M-6): LD HL,55A5H / LD A,5 / LD (7F40H),A / RET at
# 7F00H.  Looking for the tape's sync pair anywhere in the file took it for
# a tape, printed C and loaded nothing.  Once by extension, once by its
# first byte (no extension).
printf '\005\006SYSA5 \001\013\000\177\041\245\125\076\005\062\100\177\311\002\002\000\177' > "$a5.cmd"
cp "$a5.cmd" "$a5"
run "" <<EOF

SYSTEM
$a5.cmd
/
PRINT "E";PEEK(32512);PEEK(32513);PEEK(32514);PEEK(32520)
POKE 32513,0
SYSTEM
$a5
/
PRINT "F";PEEK(32512);PEEK(32513);PEEK(32514);PEEK(32520)
EOF
grep -q "E 33  165  85  201" "$tmp" || fail "a .cmd holding A5H 55H in its code is a load module" "$(cat "$tmp")"
grep -q "F 33  165  85  201" "$tmp" || fail "a load module with no extension is known by its first byte" "$(cat "$tmp")"
grep -q "^C$" "$tmp" && fail "a load module holding A5H 55H was read as a tape" "$(cat "$tmp")"
[ "$(grep -c "(7F00H x1)" "$tmp.err")" -eq 2 ] || fail "the load module's entry was not taken" "$(cat "$tmp.err")"

# With TRS80_USR_TRACE the trace must name the address that will RUN.
# sys_exec resolved the USR vector first and only then assigned the entry,
# so the line printed the 408EH vector's entry -- "undefined" here, since
# no DEFUSR has run -- for a call going somewhere else (the 2026-09-19
# audit, L-50).
TRS80_Z80= TRS80_USR_TRACE=1 gawk -b -f trs80basic.awk >"$tmp" 2>"$tmp.err" <<EOF

SYSTEM
programs/tests/syshi
/32000
EOF
grep -q "USR slot=0 entry=32000 arg=0" "$tmp.err" \
    || fail "the USR trace must name the address SYSTEM runs" "$(cat "$tmp.err")"
grep -q "entry=undefined" "$tmp.err" \
    && fail "the USR trace still names the vector" "$(cat "$tmp.err")"
# ... and the tape's own entry, taken by a bare `/`, is traced too
TRS80_Z80= TRS80_USR_TRACE=1 gawk -b -f trs80basic.awk >"$tmp" 2>"$tmp.err" <<EOF

SYSTEM
programs/tests/syshi
/
EOF
grep -q "USR slot=0 entry=32000 arg=0" "$tmp.err" \
    || fail "the USR trace for a bare /" "$(cat "$tmp.err")"

# A load module may OPEN with a 10H or 1AH record -- a comment or a DOS-only
# record.  sys_load_cmd has always accepted both mid-file, and so does the
# core (z80/load.py load_cmd), but the format sniff in sys_load did not have
# them in its first-byte set, so such a file with no .cmd extension was
# taken for a tape and failed (the 2026-09-19 audit, L-42).
# Each file: <type> 02 "AA", then 01 08 00 7F + LD A,7 / LD (7F40H),A / RET,
# then 02 02 00 7F -- eight body bytes in the load record, entry 7F00H.
r10=$(mktemp) || exit 2
r1a=$(mktemp) || exit 2
printf '\020\002AA\001\010\000\177\076\007\062\100\177\311\002\002\000\177' > "$r10"
printf '\032\002AA\001\010\000\177\076\007\062\100\177\311\002\002\000\177' > "$r1a"
for f in "$r10" "$r1a"; do
    run "" <<EOF

SYSTEM
$f
/
PRINT "R";PEEK(32512);PEEK(32517)
EOF
    grep -q "R 62  201" "$tmp" \
        || fail "a load module opening with a 10H or 1AH record ($f)" "$(cat "$tmp"; cat "$tmp.err")"
    grep -q "^C\$" "$tmp" && fail "that record type was read as a tape" "$(cat "$tmp")"
    grep -q "(7F00H x1)" "$tmp.err" \
        || fail "the transfer record's entry was not taken ($f)" "$(cat "$tmp.err")"
done
rm -f "$r10" "$r1a"

# A file that ends with no entry record (the 2026-09-19 audit, M-7): `/`
# runs at its first block's load address, the core loader's rule -- not at
# the entry of whatever was loaded before it.  The tape is syshi.cas less
# its 78H record, loaded after sysrdy (entry 7E00H); the load module is
# the one above less its 02H record, loaded after that tape (7D00H).
size=$(wc -c < programs/tests/syshi.cas)
head -c $((size - 3)) programs/tests/syshi.cas > "$ne.cas"
head -c 21 "$a5.cmd" > "$ne.cmd"
run "" <<EOF

SYSTEM
programs/tests/sysrdy
$ne.cas
/
SYSTEM
$ne.cmd
/
EOF
grep -q "^C$" "$tmp" && fail "a file with no entry record still loads" "$(cat "$tmp")"
grep -q "?F[CD] ERROR" "$tmp" && fail "a file with no entry record still loads" "$(cat "$tmp")"
[ "$(grep -c "USR STUB: 1 CALL" "$tmp.err")" -eq 2 ] || fail "two / runs" "$(cat "$tmp.err")"
grep -q "(7E00H x1)" "$tmp.err" && fail "/ ran the PREVIOUS file's entry" "$(cat "$tmp.err")"
grep -q "(7D00H x1)" "$tmp.err" || fail "a tape with no 78H record runs at its first block" "$(cat "$tmp.err")"
grep -q "(7F00H x1)" "$tmp.err" || fail "a load module with no 02H record runs at its first block" "$(cat "$tmp.err")"

# ---- part 2: the runs, with the real core ----------------------------------
core=${TRS80_Z80:-"python3 $here/../trs80_z80_core/core.py"}
set -- $core
if [ ! -f "$2" ]; then echo "SYSTEM: loads OK; runs SKIPPED (no core at $2)"; exit 0; fi
run "$core" <<EOF

SYSTEM
programs/tests/syshi
/
PRINT "A";PEEK(15360);PEEK(15361);PEEK(32064)
POKE 15360,32:POKE 15361,32:POKE 32064,0
SYSTEM
programs/tests/sysrdy
/
PRINT "B";PEEK(32320)
SYSTEM
/32000
PRINT "C";PEEK(32064)
10 SYSTEM
20 PRINT "RANON";PEEK(32320)
POKE 32320,0
RUN
programs/tests/sysrdy
/
PRINT "D";PEEK(32320)
NEW
10 SYSTEM
20 PRINT "E";PEEK(32064)
POKE 32064,0
RUN
programs/tests/syshi
/
EOF
grep -q "A 72  73  7" "$tmp" || fail "the tape did not run (HI on the screen, 7 in RAM)" "$(cat "$tmp"; cat "$tmp.err")"
grep -q "B 9" "$tmp" || fail "the load module did not run to JP 1A19H" "$(cat "$tmp"; cat "$tmp.err")"
# (RAM, not the screen: by now the READY prompts have scrolled the top line)
grep -q "C 7" "$tmp" || fail "/32000 did not run what was in memory" "$(cat "$tmp"; cat "$tmp.err")"
grep -q "D 9" "$tmp" || fail "a program's SYSTEM did not run the load module" "$(cat "$tmp"; cat "$tmp.err")"
if grep -q "^RANON" "$tmp"; then fail "JP 1A19H inside a program did not end it at READY" "$(cat "$tmp"; cat "$tmp.err")"; fi
grep -q "E 7" "$tmp" || fail "after a RET, a program's SYSTEM did not go on to its next statement" "$(cat "$tmp"; cat "$tmp.err")"
grep -q "USR STUB" "$tmp.err" && fail "the core was not used" "$(cat "$tmp.err")"
run "$core" <<EOF

SYSTEM
$a5.cmd
/
PRINT "G";PEEK(32576)
EOF
grep -q "G 5" "$tmp" || fail "the load module holding A5H 55H did not run" "$(cat "$tmp"; cat "$tmp.err")"
echo "SYSTEM: loads and runs OK"
exit 0
