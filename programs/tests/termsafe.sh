#!/bin/sh
# termsafe.sh -- nothing a program prints, reads from a file or LISTs
# reaches the terminal as a raw control: no C0 byte but the newline, no
# DEL, no C1 (80H-9FH) as UTF-8 encodes it (C2 80-9F) or as a stray byte
# after ASCII.  CHR$ of every byte, a string literal and a REM holding ESC,
# BEL and C1, and a data file holding the same, in batch (plain) output.
# Screen mode is pinned in kbd_pty.py (scenario 13).  Confirmed 2026-10-03
# (the 2026-09-30 audit, BL-39).  Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/termsafe.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
d=$(mktemp -d) || exit 2
trap 'rm -rf "$d"' EXIT
cd "$d" || exit 2
fail=0
bad() { echo "TERMSAFE FAILED: $*"; fail=1; }

printf 'P\033[38;5;77mQ\233R\302\233S\007\n' > ctl.dat
printf '10 A$="X\033[38;5;123mY\007\302\233Z\233W\033]0;PWNED\007":PRINT A$\n20 REM \033]0;PWNREM\007 \302\2332J\n30 OPEN "I",1,"ctl.dat":LINE INPUT#1,B$:CLOSE:PRINT B$\n40 FOR I=0 TO 255:IF I<>13 AND I<>10 THEN PRINT CHR$(I);\n50 NEXT\n60 PRINT:LIST 10-20\n' > ctl.bas
TRS80_Z80= "$here/basic" ctl.bas > out.txt 2>&1 || bad "the run failed: $(cat out.txt)"
grep -q 'PWNED' out.txt || bad "the probe did not print its string"
c0=$(printf '[\001-\011\013-\037\177]')
c1=$(printf '\302[\200-\237]')
stray=$(printf '(^|[\001-\177])[\200-\237]')
LC_ALL=C grep -q "$c0" out.txt && bad "a C0 control or DEL reached the output"
LC_ALL=C grep -q "$c1" out.txt && bad "a UTF-8 C1 control reached the output"
LC_ALL=C grep -Eq "$stray" out.txt && bad "a raw C1 byte reached the output"

# the check itself can see each kind (a guard against a check that cannot fail)
printf 'a\033b\n' > t1; printf 'a\302\233b\n' > t2; printf 'a\233b\n' > t3
LC_ALL=C grep -q "$c0" t1 || bad "the C0 check cannot fail"
LC_ALL=C grep -q "$c1" t2 || bad "the C1 check cannot fail"
LC_ALL=C grep -Eq "$stray" t3 || bad "the raw-C1 check cannot fail"

# the C1 test in the TAB completion is a byte loop, not a regex over bytes
# above 127: that regex was a parse error to gawk in a UTF-8 locale without
# -b, so a bare `gawk -f trs80basic.awk` did not start (BL-40, 2026-10-05).
# The locale may not exist on the host; then the check measures nothing and
# says so.
if LC_ALL=en_US.UTF-8 locale charmap 2>/dev/null | grep -q UTF-8; then
    out=$(printf '\nPRINT 1+1\nBYE\n' | LC_ALL=en_US.UTF-8 TRS80_DUMB=1 TRS80_Z80= gawk -f "$here/trs80basic.awk" 2>&1)
    case "$out" in *" 2 "*) ;; *) bad "the script does not start without -b in a UTF-8 locale: $(printf '%s' "$out" | head -2)";; esac
else
    echo "termsafe: no UTF-8 locale on this host; the start-without--b check not measured"
fi

[ $fail = 0 ] && echo "TERMSAFE OK"
exit $fail
