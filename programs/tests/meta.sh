#!/bin/sh
# meta.sh -- what the metacommands show (man, history).  Self-checking:
# exits 1 on any mismatch.  Run from the repo root:  sh programs/tests/meta.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
fail() { echo "META FAILED: $1"; printf '%s\n' "$2"; exit 1; }
run() { printf '%b' "$1" | TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" 2>&1; }

# a statement of more than one word is on its first word's page (N-4)
out=$(run '\nman line input\nman ON ERROR GOTO\nman nosuch thing\n')
case $out in *">man line input
LINE INPUT"*) ;; *) fail "man line input is the LINE page" "$out" ;; esac
case $out in *">man ON ERROR GOTO
ON "*) ;; *) fail "man ON ERROR GOTO is the ON page" "$out" ;; esac
case $out in *"NO MANUAL ENTRY FOR NOSUCH THING"*) ;; *) fail "an unknown phrase is still no entry" "$out" ;; esac

# history lists the whole session, not its last 28 lines (N-4)
lines=; i=1; while [ $i -le 40 ]; do lines="${lines}PRINT $i\\n"; i=$((i + 1)); done
out=$(run "\n${lines}history\n")
case $out in *"   1  PRINT 1
"*"  40  PRINT 40
  41  history"*) ;; *) fail "history from the first line" "$(printf '%s' "$out" | tail -5)" ;; esac

echo "OK -- the metacommands' output"
