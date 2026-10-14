#!/bin/sh
# dosname.sh -- a TRSDOS file name NAME/EXT is the host file NAME.EXT
# (ruled 2026-10-14; dos_name, p90).  A .PASSWORD and a :d drive are
# dropped.  Until then the slash was a directory: Dungeon Escape's
# OPEN "O",1,"BOB/DE" stopped ?FD.  A name with a lower-case letter, or
# whose NAME part is a directory here, stays the path as written.
# Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/dosname.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
d=$(mktemp -d) || exit 2
trap 'rm -rf "$d"' EXIT
cd "$d" || exit 2
mkdir DATA
fail=0
bad() { echo "DOSNAME FAILED: $*"; fail=1; }

cat > t.bas <<'BAS'
10 OPEN "O",1,"BOB/DE":PRINT#1,"SAVED":CLOSE
20 OPEN "I",1,"BOB/DE.SECRET:1":LINE INPUT#1,A$:CLOSE:PRINT "READ ";A$
30 OPEN "O",1,"DATA/X":PRINT#1,"IN DIR":CLOSE
40 OPEN "O",1,"lower/x":PRINT#1,"NO":CLOSE
BAS
out=$(TRS80_Z80= "$here/basic" t.bas 2>&1)
[ -f BOB.DE ] && [ "$(cat BOB.DE)" = "SAVED" ] || bad "OPEN O BOB/DE wrote $(ls)"
case $out in *"READ SAVED"*) ;; *) bad "OPEN I with a password and a drive: $out" ;; esac
[ -f DATA/X ] || bad "DATA is a directory here: DATA/X stays a path"
case $out in *"?FD ERROR IN 40"*) ;; *) bad "lower/x is a host path (no such directory): $out" ;; esac

printf '10 PRINT "LOADED"\n' > P.BAS
cat > u.bas <<'BAS'
10 SAVE "COPY/BAS"
20 KILL "BOB/DE"
30 RUN "P/BAS"
BAS
out=$(TRS80_Z80= "$here/basic" u.bas 2>&1)
[ -f COPY.BAS ] || bad "SAVE COPY/BAS: $(ls)"
[ -f BOB.DE ] && bad "KILL BOB/DE left BOB.DE"
case $out in *LOADED*) ;; *) bad "RUN P/BAS: $out" ;; esac

[ $fail = 0 ] || exit 1
echo "DOSNAME OK"
