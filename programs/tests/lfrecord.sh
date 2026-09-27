#!/bin/sh
# lfrecord.sh -- a line feed in front of a carriage return does not end a
# file record.  The Disk manual's special note on INPUT# (Model III Disk
# System Owner's Manual p.126): "When <ENTER> (a carriage return) is
# preceded by <LF> (a line feed), the <ENTER> is not taken as a terminator.
# Instead, it becomes a part of the data item (string variable)", and it
# applies "to all cases where <ENTER> is said to be a terminator"; the
# down arrow is how a program types the LF.  LINE INPUT# reads to "an
# <ENTER> character" (p.130-131) under the same rule.  On the host the
# reader works from gawk's LF-cut lines, so it must join a line to the
# next when the next begins with a CR, and must not cut at a CR that an
# LF precedes.  Until 2026-09-27 the pair split the record in two (the
# 2026-09-26 audit, M-9).  A lone LF stays the host's own line end, and a
# CR with anything else before it still ends the record.
# Self-checking: exits 1 on any mismatch.  Run from the repo root:
#     sh programs/tests/lfrecord.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
dir=$(mktemp -d) || exit 2
fail() { echo "LFRECORD FAILED: $1"; printf '%s\n' "$2"; rm -rf "$dir"; exit 1; }
run() { (cd "$dir" && TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" -- t.bas 2>&1); }
cat > "$dir/t.bas" <<'BAS'
10 OPEN "I",1,"F.DAT"
20 N=0
30 IF EOF(1) THEN 100
40 LINE INPUT#1,A$:N=N+1:PRINT N;LEN(A$);
50 IF LEN(A$)>0 THEN FOR I=1 TO LEN(A$):PRINT ASC(MID$(A$,I,1));:NEXT
55 PRINT
60 GOTO 30
100 CLOSE 1:OPEN "I",1,"F.DAT":INPUT#1,B$:IF NOT EOF(1) THEN INPUT#1,C$
110 PRINT "INPUT#";LEN(B$);LEN(C$):CLOSE 1
BAS

# the machine's own image: LF CR inside a record, CR LF at its end
printf 'AB\n\rCD\r\nEF\r\n' > "$dir/F.DAT"
out=$(run)
want=' 1  6  65  66  10  13  67  68 
 2  2  69  70 
INPUT# 6  2 '
[ "$out" = "$want" ] || fail "LF CR inside a CR LF record" "$out"

# a CR-only file (the TRS-80's ASCII save), the same pair inside
printf 'AB\n\rCD\rEF\r' > "$dir/F.DAT"
out=$(run)
[ "$out" = "$want" ] || fail "LF CR inside a CR-only record" "$out"

# the pair straddling the host's line cut, then a lone LF ending the record:
# the record runs to the LF that no CR follows
printf 'AB\n\rCD\nEF\n' > "$dir/F.DAT"
out=$(run)
[ "$out" = "$want" ] || fail "LF CR then a lone LF" "$out"

# a lone LF is still the host's line end, and a CR after anything but an LF
# still cuts the record: three records, none joined
printf 'AB\nCD\rEF\n' > "$dir/F.DAT"
out=$(run)
want=' 1  2  65  66 
 2  2  67  68 
 3  2  69  70 
INPUT# 2  2 '
[ "$out" = "$want" ] || fail "a lone LF and a bare CR still end records" "$out"

# the pair at the very end of the file: the record holds it, then EOF
printf 'AB\n\r' > "$dir/F.DAT"
out=$(run)
want=' 1  4  65  66  10  13 
INPUT# 4  0 '
[ "$out" = "$want" ] || fail "LF CR at the end of the file" "$out"

rm -rf "$dir"
echo "LFRECORD OK"
