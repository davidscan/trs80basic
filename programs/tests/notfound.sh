#!/bin/sh
# notfound.sh -- a file that is not there is Disk BASIC's 54, "File not
# found" (ERR=106), for LOAD, LOAD ,R, RUN "file" and MERGE, the same code
# OPEN "I" and KILL give: all of them open the file through the same DOS
# open (Model III Disk System manual, the Disk BASIC error table, where 54
# is the only not-found code).  CLOAD stays ?FD: a tape has no "not found",
# and Level II's cassette read reports bad file data.  A name that is not a
# file at all (a socket, a descriptor) stays ?FD too (special.sh).  Until
# 2026-09-24 LOAD, RUN and MERGE said ?FD, so a listing's ERR=106 handler
# never saw them (AUDIT 2026-09-23, M-8).
# Self-checking: exits 1 on any mismatch.  Run from the repo root:
#     sh programs/tests/notfound.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
dir=$(mktemp -d) || exit 2
fail() { echo "NOTFOUND FAILED: $1"; printf '%s\n' "$2"; rm -rf "$dir"; exit 1; }
cd "$dir" || exit 2
run() { printf '%b' "$1" | TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" 2>&1 | sed -n '/^>/,$p'; }

# typed at READY: each names the code
out=$(run '\nLOAD "NOFILE.BAS"\nLOAD "NOFILE.BAS",R\nRUN "NOFILE.BAS"\nMERGE "NOFILE.BAS"\nCLOAD "NOFILE"\n')
want='>LOAD "NOFILE.BAS"
?FF ERROR
READY
>LOAD "NOFILE.BAS",R
?FF ERROR
READY
>RUN "NOFILE.BAS"
?FF ERROR
READY
>MERGE "NOFILE.BAS"
?FF ERROR
READY
>CLOAD "NOFILE"
?FD ERROR
READY
>'
[ "$out" = "$want" ] || fail "the codes typed at READY" "$out"

# trapped: ERR is 106, as a listing written for Disk BASIC compares it
cat > t.bas <<'BAS'
10 ON ERROR GOTO 100
20 LOAD "NOFILE.BAS"
30 PRINT "NOT REACHED"
100 PRINT "ERR";ERR;"ERL";ERL:N=N+1:IF N=1 THEN RESUME 110 ELSE END
110 MERGE "NOFILE.BAS":PRINT "NOT REACHED EITHER"
BAS
out=$(TRS80_Z80= "$here/basic" t.bas 2>&1 </dev/null)
want="ERR 106 ERL 20 
ERR 106 ERL 110 "
[ "$out" = "$want" ] || fail "ERR=106 through a handler, for LOAD and MERGE" "$out"

# the file being there is what the test is about: a present file loads
printf '10 PRINT "FOUND"\n' > HERE.BAS
out=$(run '\nRUN "HERE.BAS"\n')
want='>RUN "HERE.BAS"
FOUND
READY
>'
[ "$out" = "$want" ] || fail "a file that is there still loads" "$out"

rm -rf "$dir"
echo "NOTFOUND OK"
