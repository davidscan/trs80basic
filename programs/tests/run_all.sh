#!/bin/sh
# run_all.sh -- the whole regression suite in one exit status, as CI runs it.
#
#   sh programs/tests/run_all.sh          # from anywhere; exit 0 = everything passed
#
# Five parts, in the order CLAUDE.md lists them: (1) the committed
# trs80basic.awk is exactly `cat src/p*.awk`; (2) transcripts t1-t33 exit 0
# (t13/t29 through the OLLAMA stub, t32 through the Z80 stub); (3) the
# self-checking .bas fixtures; (4) the .sh suites; (5) the Python tool tests.
# Nothing here needs a terminal, the network, or the companion core: the
# suites that want the core skip without it, and TRS80_Z80= pins the stub for
# the rest so a core beside the checkout does not change what is measured.
# Failures are named as they happen; the summary line is the last one.

here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
cd "$here" || exit 2
fail=0
bad() { echo "FAIL: $*"; fail=$((fail+1)); }

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
for b in varptr rawbytes alias inp out255; do
    TRS80_Z80= ./basic "programs/tests/$b.bas" >/dev/null 2>&1 || bad "$b.bas"
done
lp=$(mktemp) || exit 2
TRS80_Z80= TRS80_PRINTER="$lp" ./basic programs/tests/sysvar.bas >/dev/null 2>&1 \
    || bad "sysvar.bas"
rm -f "$lp"

# 4. the shell suites (each pins its own core or stub; z80core/sound skip without one)
for s in break devvec usr pmtrunc z80 z80core sound tokload tips_probe; do
    sh "programs/tests/$s.sh" >/dev/null 2>&1 || bad "$s.sh"
done

# 5. the tokenizer tools
if command -v python3 >/dev/null 2>&1; then
    (cd tools && python3 -m unittest -q test_tok test_detok >/dev/null 2>&1) \
        || bad "tools/test_*.py"
fi

if [ $fail -eq 0 ]; then echo "run_all: all passed"; exit 0; fi
echo "run_all: $fail failed"; exit 1
