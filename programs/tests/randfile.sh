#!/bin/sh
# randfile.sh -- a random file that was only read is not rewritten.  CLOSE
# used to write every "R" file back, PUT or no PUT: records re-padded (or
# CUT) to this OPEN's record length, backslashes doubled, \xNN text
# decoded.  Opening a file with the wrong length just to look at it
# destroyed it.  Now only a PUT marks the file for writing.
# Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/randfile.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
dir=$(mktemp -d) || exit 2
fail() { echo "RANDFILE FAILED: $1"; printf '%s\n' "$2"; rm -rf "$dir"; exit 1; }
printf 'A LONG FIRST RECORD\nback\\slash \\x41\nshort\n' > "$dir/DATA.TXT"
cp "$dir/DATA.TXT" "$dir/keep"
cat > "$dir/t.bas" <<'BAS'
10 OPEN "R",1,"DATA.TXT",8
20 FIELD 1,8 AS A$
30 GET 1,1:PRINT "[";A$;"]";LOF(1)
40 LSET A$="CHANGED"
50 CLOSE 1
BAS
out=$(cd "$dir" && TRS80_Z80= "$here/basic" t.bas 2>&1)
[ "$out" = "[A LONG F] 3 " ] || fail "GET from a text file" "$out"
cmp -s "$dir/DATA.TXT" "$dir/keep" || fail "a file that was only read was rewritten" "$(cat "$dir/DATA.TXT")"

# a PUT still reaches the disk at CLOSE, every record at the record length
cat > "$dir/p.bas" <<'BAS'
10 OPEN "R",1,"NEW.DAT",6
20 FIELD 1,6 AS A$
30 LSET A$="ONE":PUT 1,1:LSET A$="THREE":PUT 1,3
40 CLOSE 1
50 OPEN "R",1,"NEW.DAT",6:FIELD 1,6 AS A$
60 GET 1,3:PRINT "[";A$;"]";LOF(1):CLOSE 1
BAS
out=$(cd "$dir" && TRS80_Z80= "$here/basic" p.bas 2>&1)
[ "$out" = "[THREE ] 3 " ] || fail "PUT then CLOSE then GET" "$out"
want='ONE   |
      |
THREE |'
got=$(sed 's/$/|/' "$dir/NEW.DAT")
[ "$got" = "$want" ] || fail "the file a PUT wrote" "$got"

# MID$= on a FIELD variable stores into the record buffer, as LSET does:
# the variable's characters ARE the buffer's.  It used to change the
# variable alone, so PUT wrote the old record (the 2026-09-19 audit, M-25).
cat > "$dir/m.bas" <<'BAS'
10 OPEN "R",1,"MID.DAT",10
20 FIELD 1,4 AS A$,6 AS B$
30 LSET A$="ABCD":LSET B$="UVWXYZ"
40 MID$(B$,2,3)="123456":MID$(A$,4)="*"
50 PRINT "[";A$;"|";B$;"]":PUT 1,1:CLOSE 1
60 OPEN "R",1,"MID.DAT",10:FIELD 1,10 AS R$
70 GET 1,1:PRINT "[";R$;"]":CLOSE 1
BAS
out=$(cd "$dir" && TRS80_Z80= "$here/basic" m.bas 2>&1)
want='[ABC*|U123YZ]
[ABC*U123YZ]'
[ "$out" = "$want" ] || fail "MID\$= on a FIELD variable reaches the record" "$out"
rm -rf "$dir"
echo "RANDFILE OK"
