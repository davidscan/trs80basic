#!/bin/sh
# passthru.sh -- the dir and cat metacommands, keyboard-only shell
# passthroughs (ruled 2026-08-12): what comes back is scrubbed to
# printable ASCII, every command of the typed line included, and an
# endless source is cut.  Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/passthru.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
dir=$(mktemp -d) || exit 2
fail() { echo "PASSTHRU FAILED: $1"; printf '%s\n' "$2"; rm -rf "$dir"; exit 1; }
cd "$dir" || exit 2
bound="$here/programs/tests/bound.pl"
run() { printf '%b' "$1" | TRS80_DUMB=1 TRS80_Z80= perl "$bound" 30 gawk -b -f "$here/trs80basic.awk" 2>"$dir/err" | sed -n '/^>/,$p'; }
esc=$(printf '\033')
printf 'A\033[31mB\n' > esc.txt
printf 'two words\n' > 'a b.txt'

# every command of the line goes through the scrub, and its errors too:
# `cat a; echo b` scrubbed only the echo, and cat's ESC and its "No such
# file" reached the terminal raw (the 2026-09-30 audit)
out=$(run '\ncat esc.txt; echo INJ\ncat nosuch.txt; echo DONE\n')
case $out in *"$esc"*) fail "an ESC byte reached the terminal" "$out" ;; esac
case $out in *"A.[31mB"*INJ*) ;; *) fail "the first command's output, scrubbed" "$out" ;; esac
case $out in *"nosuch.txt"*DONE*) ;; *) fail "the first command's error, in the output" "$out" ;; esac
[ -s "$dir/err" ] && fail "nothing on stderr" "$(cat "$dir/err")"

# the line is still the shell's: quoting and options work as typed
out=$(run "\ncat 'a b.txt'\ndir -d esc.txt\n")
case $out in *"two words"*"esc.txt"*) ;; *) fail "a quoted name and an option" "$out" ;; esac

# an endless source is cut, not read until memory runs out
out=$(run '\ncat /dev/zero\nPRINT "BACK"\n'); rc=$?
case $out in *"(output cut at 1048576 bytes)"*BACK*) ;; *) fail "cat /dev/zero is cut (rc=$rc)" "$(printf '%s' "$out" | tail -c 300)" ;; esac

rm -rf "$dir"
echo "OK -- dir and cat: scrubbed, every command, endless sources cut"
