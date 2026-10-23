#!/bin/sh
# fileopen.sh -- a file open on a channel is found by what its name names,
# not by its spelling: OPEN and KILL of `./DATA` (or `data` on a case-blind
# disk) while DATA is open are AO (ERR=138), as the same spelling always
# was (the 2026-09-30 audit, BL-27).
# Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/fileopen.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
dir=$(mktemp -d) || exit 2
fail() { echo "FILEOPEN FAILED: $1"; printf '%s\n' "$2"; rm -rf "$dir"; exit 1; }
run() { (cd "$dir" && TRS80_Z80= TRS80_DUMB=1 "$here/basic" t.bas 2>&1); }

# KILL by another spelling of the open file: AO, and the file stays
cat > "$dir/t.bas" <<'BAS'
10 ON ERROR GOTO 100
20 OPEN "O",1,"DATA":PRINT#1,"KEEP"
30 KILL "./DATA":PRINT "KILLED"
40 OPEN "O",2,"./DATA":PRINT "OPENED TWICE"
50 CLOSE:END
100 PRINT "ERR";ERR;"IN";ERL:RESUME NEXT
BAS
out=$(run)
want='ERR 138 IN 30 
KILLED
ERR 138 IN 40 
OPENED TWICE'
[ "$out" = "$want" ] || fail "KILL and OPEN of ./DATA while DATA is open" "$out"
[ "$(cat "$dir/DATA")" = "KEEP" ] || fail "the open file was damaged" "$(cat "$dir/DATA")"

# a case variant, where the disk is case-blind (macOS by default)
: > "$dir/CASEPROBE"
if [ -e "$dir/caseprobe" ]; then
    sed 's|"./DATA"|"data"|' "$dir/t.bas" > "$dir/t2.bas" && mv "$dir/t2.bas" "$dir/t.bas"
    out=$(run)
    [ "$out" = "$want" ] || fail "KILL and OPEN of data while DATA is open (case-blind disk)" "$out"
fi

# a different file is still free
cat > "$dir/t.bas" <<'BAS'
10 OPEN "O",1,"DATA":OPEN "O",2,"OTHER":PRINT#2,"X":CLOSE 2:KILL "OTHER":CLOSE:PRINT "OK"
BAS
out=$(run)
[ "$out" = "OK" ] || fail "another file opens and dies as before" "$out"

rm -rf "$dir"
echo "FILEOPEN OK"
