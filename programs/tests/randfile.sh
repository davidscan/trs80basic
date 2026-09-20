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

# FIELD takes array elements: the Disk manual's own example is
# FIELD 1,16 AS CLIENT$(1).  It was ?SN (the 2026-09-19 audit, M-29).  GET
# refills them, LSET, RSET and MID$= store through them, and a simple
# variable of the same name is a different variable.
cat > "$dir/a.bas" <<'BAS'
10 DIM C$(3,2):N=2
20 OPEN "R",1,"ARR.DAT",12
30 FIELD 1,4 AS C$(1,0),4 AS C$(N,N),4 AS C$
40 LSET C$(1,0)="ONE":RSET C$(2,2)="TWO":LSET C$="SIMP":MID$(C$(1,0),4)="!"
50 PUT 1,1:LSET C$(1,0)="x":LSET C$(2,2)="y":PUT 1,2
60 GET 1,1:PRINT "[";C$(1,0);"|";C$(N,2);"|";C$;"]";LEN(C$(3,2))
70 CLOSE 1:OPEN "R",1,"ARR.DAT",12:FIELD 1,12 AS R$:GET 1,1:PRINT "[";R$;"]":CLOSE
BAS
out=$(cd "$dir" && TRS80_Z80= "$here/basic" a.bas 2>&1)
want='[ONE!| TWO|SIMP] 0 
[ONE! TWOSIMP]'
[ "$out" = "$want" ] || fail "FIELD on array elements" "$out"

# a variable FIELDed onto a second file, which is then closed, is an
# ordinary string again: a GET on the first file used to re-create its
# mapping as an empty one, and the next LSET was ?NO
cat > "$dir/s.bas" <<'BAS'
10 OPEN "R",1,"DATA.TXT",5:OPEN "R",2,"NEW.DAT",5
20 FIELD 1,5 AS A$:FIELD 2,5 AS A$:CLOSE 2
30 GET 1,1:LSET A$="ab":PRINT "[";A$;"]"
BAS
out=$(cd "$dir" && TRS80_Z80= "$here/basic" s.bas 2>&1)
[ "$out" = "[ab   ]" ] || fail "LSET after the variable's file was closed" "$out"

# GET past the last record is no error: the buffer comes back as zero
# bytes (Disk manual, GET and LOF).  It was ?IE, against the manual and
# against `man GET` (the 2026-09-19 audit, M-27).  The file is not grown by
# looking, the record after it is the next one, and record 0 is still ?RN.
cat > "$dir/g.bas" <<'BAS'
10 ON ERROR GOTO 90
20 OPEN "R",1,"NEW.DAT",6:FIELD 1,2 AS I$,4 AS A$
30 GET 1,5:PRINT LEN(A$);ASC(A$);ASC(RIGHT$(A$,1));CVI(I$);EOF(1);LOF(1)
40 LSET A$="SIX":PUT 1:PRINT LOF(1)
50 GET 1,1:PRINT "[";I$;A$;"]";EOF(1)
60 GET 1,0
70 PRINT "NOT REACHED"
80 CLOSE:END
90 PRINT "ERROR";ERR/2+1;"IN";STR$(ERL):RESUME 80
BAS
out=$(cd "$dir" && TRS80_Z80= "$here/basic" g.bas 2>&1)
want=' 4  0  0  0 -1  3 
 6 
[ONE   ] 0 
ERROR 30 IN 60'
[ "$out" = "$want" ] || fail "GET past the last record" "$out"

# An ordinary assignment takes a FIELD variable out of the buffer (Disk
# manual, "More on field names"; `man FIELD` always said so): GET no longer
# refills it, LSET works within its own length and leaves the record
# alone, and a new FIELD brings it back.
printf 'HELLO\nWORLD\n' > "$dir/LET.TXT"
cat > "$dir/l.bas" <<'BAS'
5 Q$="A STRING ASSIGNED BEFORE ANY FIELD"
10 OPEN "R",1,"LET.TXT",5:FIELD 1,5 AS A$,0 AS Z$
20 GET 1,1:PRINT "[";A$;"]"
30 A$="XY":GET 1,2:PRINT "[";A$;"]"
40 LSET A$="Q":PRINT "[";A$;"]":PUT 1,1
50 FIELD 1,5 AS A$:PRINT "[";A$;"]":GET 1,1:PRINT "[";A$;"]":CLOSE
BAS
out=$(cd "$dir" && TRS80_Z80= "$here/basic" l.bas 2>&1)
want='[HELLO]
[XY]
[Q ]
[WORLD]
[WORLD]'
[ "$out" = "$want" ] || fail "an assignment detaches a FIELD variable" "$out"
rm -rf "$dir"
echo "RANDFILE OK"
