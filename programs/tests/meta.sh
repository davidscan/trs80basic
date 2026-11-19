#!/bin/sh
# meta.sh -- what the metacommands show (man, history, help).  Self-checking:
# exits 1 on any mismatch.  Run from the repo root:  sh programs/tests/meta.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
fail() { echo "META FAILED: $1"; printf '%s\n' "$2"; exit 1; }
run() { printf '%b' "$1" | TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" 2>&1; }

# a statement of more than one word is on its first word's page
out=$(run '\nman line input\nman ON ERROR GOTO\nman nosuch thing\n')
case $out in *">man line input
LINE INPUT"*) ;; *) fail "man line input is the LINE page" "$out" ;; esac
case $out in *">man ON ERROR GOTO
ON "*) ;; *) fail "man ON ERROR GOTO is the ON page" "$out" ;; esac
case $out in *"NO MANUAL ENTRY FOR NOSUCH THING"*) ;; *) fail "an unknown phrase is still no entry" "$out" ;; esac

# history lists the whole session, not its last 28 lines
lines=; i=1; while [ $i -le 40 ]; do lines="${lines}PRINT $i\\n"; i=$((i + 1)); done
out=$(run "\n${lines}history\n")
case $out in *"   1  PRINT 1
"*"  40  PRINT 40
  41  history"*) ;; *) fail "history from the first line" "$(printf '%s' "$out" | tail -5)" ;; esac

# help: its index, the metacommand list, the key list, and a search of the
# BASIC pages (the 2026-11-18 coverage measurement found help never run)
out=$(run '\nhelp\nhelp meta\nhelp keys\nhelp string\nhelp zzqqx\n')
case $out in *">help
HELP:
  help meta        list the metacommands"*) ;; *) fail "help shows its index" "$out" ;; esac
case $out in *">help meta
METACOMMANDS (lowercase only):"*"  history | h           list this session's typed commands"*) ;; *) fail "help meta lists the metacommands" "$out" ;; esac
case $out in *">help keys
KEYS (control keys work shifted or unshifted):"*"  up / down       recall command history at the > prompt"*) ;; *) fail "help keys lists the key bindings" "$out" ;; esac
case $out in *'MATCHES FOR "string":'*"  ASC(a\$)   the character code of the first character of a\$"*) ;; *) fail "help <text> searches the BASIC pages" "$out" ;; esac
case $out in *">help zzqqx
NO COMMANDS MATCH zzqqx"*) ;; *) fail "help with no match says so" "$out" ;; esac

echo "OK -- the metacommands' output"
