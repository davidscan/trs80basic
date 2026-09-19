#!/bin/sh
# hostwrite.sh -- a SAVE, CSAVE or OPEN whose target cannot be written is
# ?FD ERROR, never a gawk fatal.  A failed gawk output redirect is fatal, so
# host_writable (p90) probes first; until 2026-09-19 the probe was a bare
# touch, which passes a directory and a read-only file its owner holds, and
# the redirect then killed the interpreter with the unsaved program in
# memory (the 2026-09-19 audit, C-1).  The OLLAMA transcript file (<thread>.ollama, p87
# ai_open) is probed the same way.  Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/hostwrite.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
d=$(mktemp -d) || exit 2
trap 'rm -rf "$d"' EXIT
cd "$d" || exit 2
mkdir adir adir.ollama
printf 'old\n' > ro.bas
chmod 444 ro.bas
fail=0
bad() { echo "HOSTWRITE FAILED: $*"; fail=1; }

# the statement on line 20 must stop the run with ?FD there: exit 1, where
# a gawk fatal exits 2
check() {   # $1 = the statement, $2 = what it tests
    printf '10 PRINT "X"\n20 %s\n30 PRINT "NOT REACHED"\n' "$1" > t.bas
    out=$(TRS80_Z80= TRS80_OLLAMA_CURL="sh $here/programs/tests/ollama_stub.sh" \
          "$here/basic" t.bas 2>&1)
    rc=$?
    case "$out" in
      *"?FD ERROR IN 20"*) [ "$rc" = 1 ] || bad "$2: rc=$rc, want 1" ;;
      *) bad "$2: $out" ;;
    esac
}
check 'CSAVE "adir"'                'CSAVE onto a directory'
check 'SAVE "adir"'                 'SAVE onto a directory'
check 'OPEN "O",1,"adir"'           'OPEN "O" onto a directory'
check 'OPEN "E",1,"adir"'           'OPEN "E" onto a directory'
check 'OPEN "R",1,"adir"'           'OPEN "R" onto a directory'
check 'OPEN "O",1,"nodir/x.dat"'    'OPEN "O" into a missing directory'
check 'OPEN "O",1,"OLLAMA:m:adir"'  'an OLLAMA thread whose transcript is a directory'
# a read-only file: root may write it regardless, so only as an ordinary user
if [ "$(id -u)" != 0 ]; then
    check 'SAVE "ro.bas"'           'SAVE onto a read-only file'
    check 'OPEN "E",1,"ro.bas"'     'OPEN "E" onto a read-only file'
    check 'OPEN "R",1,"ro.bas"'     'OPEN "R" onto a read-only file'
    [ "$(cat ro.bas)" = old ] || bad "the read-only file was changed"
fi

# at the prompt, the session and its program survive the refusal
out=$(printf '\n10 PRINT "KEEP ME"\nCSAVE "adir"\nLIST\n' \
      | TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" 2>&1)
case "$out" in
  *"?FD ERROR"*'10 PRINT "KEEP ME"'*) ;;
  *) bad "the session did not survive: $out" ;;
esac

# and writable targets still work
printf '10 SAVE "ok.bas"\n20 OPEN "O",1,"new.dat":PRINT#1,"DATA":CLOSE\n30 PRINT "SAVED"\n' > t.bas
out=$(TRS80_Z80= "$here/basic" t.bas 2>&1)
if [ "$out" != SAVED ] || [ ! -s ok.bas ] || [ "$(cat new.dat)" != DATA ]; then
    bad "writable targets: $out"
fi

[ $fail = 0 ] && echo "HOSTWRITE OK"
exit $fail
