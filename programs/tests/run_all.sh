#!/bin/sh
# run_all.sh -- the whole regression suite in one exit status, as CI runs it.
#
#   sh programs/tests/run_all.sh          # from anywhere; exit 0 = everything passed
#
# Seven parts: (1) the committed
# trs80basic.awk is exactly `cat src/p*.awk`; (2) transcripts t1-t33 exit 0
# (t13/t29 through the OLLAMA stub, t32 through the Z80 stub); (3) the
# self-checking .bas fixtures; (4) the .sh suites; (5) the examples against
# their .out transcripts; (6) the Python tool tests; (7) the interactive
# keyboard through a pseudo-terminal (kbd_pty.py).
# Nothing here needs a terminal or the network. The companion core
# (../trs80_z80_core/core.py beside the checkout, or TRS80_Z80) is used when
# present: z80.sh runs against it with --fixture as well as against the stub,
# and z80core.sh, sound.sh and system.sh run their core parts; without it
# those print SKIPPED and pass. The summary counts the skips, and
# TRS80_REQUIRE_CORE=1 makes a skip a failure, so CI (which checks the core
# out beside this repo) cannot pass on skips silently. TRS80_Z80= pins the
# stub for the transcripts and fixtures, so a core beside the checkout does
# not change what they measure.
# (7) is the exception in spirit: kbd_pty.py makes its own pseudo-terminal, so
# the interactive keyboard reader is covered here and on CI's Linux.
# Failures are named as they happen; the summary line is the last one.

here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
cd "$here" || exit 2
fail=0
log=$(mktemp) || exit 2
trap 'rm -f "$log"' EXIT
skipped=0
bad() { echo "FAIL: $*"; fail=$((fail+1)); }
# a suite that printed SKIPPED passed without measuring what it is for
skip_check() {
    grep -q "SKIPPED" "$log" || return 0
    skipped=$((skipped+1))
    if [ -n "$TRS80_REQUIRE_CORE" ]; then bad "$1 (SKIPPED with TRS80_REQUIRE_CORE set)"; show "$1"
    else echo "skipped: $1 ($(grep -m1 "SKIPPED" "$log"))"; fi
}
# the companion core, found as the suites and the launcher find it
core=${TRS80_Z80:-"python3 $here/../trs80_z80_core/core.py"}
set -- $core
if [ -f "$2" ]; then have_core=1; else have_core=; fi
# a failing suite's own output, so a CI log says why and not only what
show() { echo "--- $1 output (last 40 lines) ---"; tail -40 "$log"; echo "--- end $1 ---"; }

# 1. the generated file
if ! cat src/p*.awk | cmp -s - trs80basic.awk; then
    bad "trs80basic.awk is not cat src/p*.awk (rebuild and commit it)"
fi

# 2. the transcripts
i=1
while [ $i -le 33 ]; do
    TRS80_DUMB=1 TRS80_Z80="python3 programs/tests/z80_stub.py" \
    TRS80_OLLAMA_CURL="sh programs/tests/ollama_stub.sh" \
        gawk -b -f trs80basic.awk < "programs/tests/t$i.txt" >/dev/null 2>&1 \
        || bad "t$i"
    i=$((i+1))
done

# 3. the batch fixtures (the stub: a core beside the checkout must not matter).
# A fixture fails by its exit status, AND by printing "FIXTURE FAILED": a
# failure path that stops raising an error must not pass silently (sysvar.bas
# did, from 70b0c22 on: its CLEAR 50 erased the DIM its failure path used).
fixture() {
    if ! "$@" >"$log" 2>&1; then bad "$b.bas"; show "$b.bas"
    elif grep -q "FIXTURE FAILED" "$log"; then
        bad "$b.bas (printed FIXTURE FAILED but exited 0)"; show "$b.bas"
    fi
}
for b in varptr rawbytes alias literal inp out255 ifcomma intconv defint forstack pokerange mbfpoke round errcode cursor dataitem power using apostrophe controlflow functions types sngl; do
    fixture env TRS80_Z80= ./basic "programs/tests/$b.bas"
done
lp=$(mktemp) || exit 2
b=sysvar
fixture env TRS80_Z80= TRS80_PRINTER="$lp" ./basic programs/tests/sysvar.bas
rm -f "$lp"

# 4. the shell suites (each pins its own core or stub; z80core, sound and
# system skip their core parts without one, and skip_check counts that)
for s in break devvec usr pmtrunc z80 z80core sound tokload system tips_probe hostwrite special linelen clear memsize clearopt hints print input ready inputnum printcomma onerror ollama randfile lof crunch auto notty corepath errline goto imgpoke lineedit numov numread inputitem freshline linecut dotline fname notfound inputcomma varptrsign varnames cont lineno name keyword tokens stmttail mem; do
    if sh "programs/tests/$s.sh" >"$log" 2>&1; then skip_check "$s.sh"; else bad "$s.sh"; show "$s.sh"; fi
done
# the protocol suite against the real core, as CLAUDE.md prescribes
if [ -n "$have_core" ]; then
    TRS80_Z80="$core --fixture" sh programs/tests/z80.sh >"$log" 2>&1 \
        || { bad "z80.sh against the core"; show "z80.sh (core)"; }
else
    echo "SKIPPED: z80.sh against the core (no core at $2)" >"$log"; skip_check "z80.sh (core)"
fi

# 5. the examples against their checked-in transcripts
sh programs/examples/run_examples.sh >"$log" 2>&1 \
    || { bad "programs/examples (run_examples.sh)"; show "run_examples.sh"; }

# 6. the tokenizer tools and the guide generator
if command -v python3 >/dev/null 2>&1; then
    (cd tools && python3 -m unittest -q test_tok test_detok test_userguide >"$log" 2>&1) \
        || { bad "tools/test_*.py"; show "tools/test_*.py"; }
    # 7. the interactive keyboard, through a pseudo-terminal
    python3 programs/tests/kbd_pty.py >"$log" 2>&1 || { bad "kbd_pty.py"; show "kbd_pty.py"; }
else
    # counted like a missing core, and a failure under TRS80_REQUIRE_CORE
    echo "SKIPPED: tools/test_*.py and kbd_pty.py (no python3)" >"$log"; skip_check "python3 suites"
fi

if [ $fail -eq 0 ]; then echo "run_all: all passed, $skipped skipped"; exit 0; fi
echo "run_all: $fail failed, $skipped skipped"; exit 1
