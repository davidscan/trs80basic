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
# Nothing here needs a terminal, the network, or the companion core: the
# suites that want the core skip without it, and TRS80_Z80= pins the stub for
# the rest so a core beside the checkout does not change what is measured.
# (7) is the exception in spirit: kbd_pty.py makes its own pseudo-terminal, so
# the interactive keyboard reader is covered here and on CI's Linux.
# Failures are named as they happen; the summary line is the last one.

here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
cd "$here" || exit 2
fail=0
log=$(mktemp) || exit 2
trap 'rm -f "$log"' EXIT
bad() { echo "FAIL: $*"; fail=$((fail+1)); }
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

# 3. the batch fixtures (the stub: a core beside the checkout must not matter)
for b in varptr rawbytes alias inp out255 ifcomma; do
    TRS80_Z80= ./basic "programs/tests/$b.bas" >"$log" 2>&1 || { bad "$b.bas"; show "$b.bas"; }
done
lp=$(mktemp) || exit 2
TRS80_Z80= TRS80_PRINTER="$lp" ./basic programs/tests/sysvar.bas >"$log" 2>&1 \
    || { bad "sysvar.bas"; show "sysvar.bas"; }
rm -f "$lp"

# 4. the shell suites (each pins its own core or stub; z80core/sound skip without one)
for s in break devvec usr pmtrunc z80 z80core sound tokload system tips_probe hostwrite linelen; do
    sh "programs/tests/$s.sh" >"$log" 2>&1 || { bad "$s.sh"; show "$s.sh"; }
done

# 5. the examples against their checked-in transcripts
sh programs/examples/run_examples.sh >"$log" 2>&1 \
    || { bad "programs/examples (run_examples.sh)"; show "run_examples.sh"; }

# 6. the tokenizer tools
if command -v python3 >/dev/null 2>&1; then
    (cd tools && python3 -m unittest -q test_tok test_detok >"$log" 2>&1) \
        || { bad "tools/test_*.py"; show "tools/test_*.py"; }
    # 7. the interactive keyboard, through a pseudo-terminal
    python3 programs/tests/kbd_pty.py >"$log" 2>&1 || { bad "kbd_pty.py"; show "kbd_pty.py"; }
fi

if [ $fail -eq 0 ]; then echo "run_all: all passed"; exit 0; fi
echo "run_all: $fail failed"; exit 1
