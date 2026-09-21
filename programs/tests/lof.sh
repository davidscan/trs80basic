#!/bin/sh
# lof.sh -- LOF on a SEQUENTIAL file.  The Disk manual's LOF entry says the
# function "tells you the number of the last, i.e., highest numbered, record
# in a file.  It is useful for both sequential and random access."  A
# sequential file has no logical record length of its own, so its records are
# the 256-byte physical ones and LOF is its length rounded up.  Anything but
# "R" used to be ?BM (the 2026-09-19 audit, L-34).
# The measurement must not disturb the channel's own read: gawk keys a file
# redirection by name, so LOF asks a COMMAND pipe, not `getline < f`.
# Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/lof.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
dir=$(mktemp -d) || exit 2
fail() { echo "LOF FAILED: $1"; printf '%s\n' "$2"; rm -rf "$dir"; exit 1; }

# 1 byte -> 1 record; exactly 256 -> 1; one past -> 2; empty -> 0
: > "$dir/E.TXT"
printf 'A' > "$dir/ONE.TXT"
awk 'BEGIN{for(i=0;i<256;i++)printf "x"}' > "$dir/FULL.TXT"
awk 'BEGIN{for(i=0;i<257;i++)printf "x"}' > "$dir/OVER.TXT"
cat > "$dir/a.bas" <<'BAS'
10 OPEN "I",1,"ONE.TXT":PRINT LOF(1);:CLOSE
20 OPEN "I",1,"FULL.TXT":PRINT LOF(1);:CLOSE
30 OPEN "I",1,"OVER.TXT":PRINT LOF(1);:CLOSE
40 OPEN "I",1,"E.TXT":PRINT LOF(1):CLOSE
BAS
out=$(cd "$dir" && TRS80_Z80= "$here/basic" a.bas 2>&1)
want=' 1  1  2  0 '
[ "$out" = "$want" ] || fail "a sequential file's length in 256-byte records" "$out"

# LOF part way through a read does NOT restart the read
printf 'ONE\nTWO\nTHREE\n' > "$dir/L.TXT"
cat > "$dir/b.bas" <<'BAS'
10 OPEN "I",1,"L.TXT"
20 LINE INPUT#1,A$:PRINT A$
30 N=LOF(1)
40 LINE INPUT#1,A$:PRINT A$
50 LINE INPUT#1,A$:PRINT A$:PRINT "LOF=";N:CLOSE
BAS
out=$(cd "$dir" && TRS80_Z80= "$here/basic" b.bas 2>&1)
want='ONE
TWO
THREE
LOF= 1 '
[ "$out" = "$want" ] || fail "LOF mid-read leaves the read where it was" "$out"

# an output file: what has been written counts, buffering and all
cat > "$dir/c.bas" <<'BAS'
10 OPEN "O",1,"W.TXT":PRINT LOF(1);
20 FOR I=1 TO 40:PRINT#1,"0123456789":NEXT
30 PRINT LOF(1):CLOSE
BAS
out=$(cd "$dir" && TRS80_Z80= "$here/basic" c.bas 2>&1)
want=' 0  2 '
[ "$out" = "$want" ] || fail "an output file's records grow as it is written" "$out"

# "R" is unchanged: the record count, by the file's own record length
printf 'AAAAA\nBBBBB\nCCCCC\n' > "$dir/R.TXT"
cat > "$dir/d.bas" <<'BAS'
10 OPEN "R",1,"R.TXT",5:PRINT LOF(1):CLOSE
BAS
out=$(cd "$dir" && TRS80_Z80= "$here/basic" d.bas 2>&1)
[ "$out" = " 3 " ] || fail "a random file still counts its own records" "$out"

rm -rf "$dir"
echo "LOF OK"
