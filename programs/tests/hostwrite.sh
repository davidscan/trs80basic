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

# KILL onto a file the host will not let go of: ?FD, the file stays, and
# rm's own complaint never reaches the program's error channel.  It used to
# be ignored outright -- the program carried on as though the file had gone
# (the 2026-09-19 audit, L-5).  Only as an ordinary user: root deletes anyway.
if [ "$(id -u)" != 0 ]; then
    mkdir -p kdir && : > kdir/victim.txt && chmod 500 kdir
    printf '10 ON ERROR GOTO 100\n20 KILL "kdir/victim.txt"\n30 PRINT "NO ERROR":END\n100 PRINT "ERR=";ERR/2+1\n' > k.bas
    out=$(TRS80_Z80= "$here/basic" k.bas 2>&1)
    [ "$out" = "ERR= 22 " ] || bad "KILL on a refused delete: $out"
    [ -f kdir/victim.txt ] || bad "KILL removed the file it reported it could not"
    chmod 700 kdir
    # ... and a delete the host allows is still silent and still deletes
    : > gone.txt
    printf '10 KILL "gone.txt":PRINT "KILLED"\n' > k2.bas
    out=$(TRS80_Z80= "$here/basic" k2.bas 2>&1)
    [ "$out" = KILLED ] || bad "an ordinary KILL: $out"
    [ -f gone.txt ] && bad "an ordinary KILL left the file"
fi

# `sound wav <path>` names a file the core opens at its next start: one
# that cannot be written is refused at once and the capture stays as it
# was, and nothing is created by asking; `~` is the home directory.  An
# unwritable path used to be shown as the active capture while the core
# dropped it in silence (the 2026-09-19 audit, L-49).  No core needed.
mkdir -p home
out=$(printf '\nsound wav %s\nsound wav ~/cap.wav\nsound wav nodir/x.wav\nsound wav home\nBYE\n' "$d/home/a.wav" |
      HOME="$d/home" TRS80_Z80= TRS80_DUMB=1 "$here/basic" 2>&1 | grep -E '^(\?CANNOT|SOUND)')
want="SOUND OFF, WAV $d/home/a.wav
SOUND OFF, WAV $d/home/cap.wav
?CANNOT WRITE nodir/x.wav
SOUND OFF, WAV $d/home/cap.wav
?CANNOT WRITE home
SOUND OFF, WAV $d/home/cap.wav"
[ "$out" = "$want" ] || bad "sound wav refusals: $out"
[ -e home/a.wav ] || [ -e home/cap.wav ] && bad "sound wav created a file by naming it"

[ $fail = 0 ] && echo "HOSTWRITE OK"
exit $fail
