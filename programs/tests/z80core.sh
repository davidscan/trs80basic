#!/bin/sh
# z80core.sh -- USR routines a BASIC program itself puts into memory, run by
# the real companion core (../trs80_z80_core/core.py) with NO fixture: the
# bytes reach the core only through the frame, exactly as a period listing's
# do.  Self-checking: exits 1 on any mismatch, 0 if the core is not present.
# Run from the repo root:  sh programs/tests/z80core.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
core=${TRS80_Z80:-"python3 $here/../trs80_z80_core/core.py"}
set -- $core
[ -f "$2" ] || { echo "Z80 CORE FIXTURE SKIPPED: no core at $2"; exit 0; }
tmp=$(mktemp) || exit 2
fail() { echo "Z80 CORE FIXTURE FAILED: $1"; [ -n "$2" ] && printf '%s\n' "$2"; rm -f "$tmp" "$tmp.err"; exit 1; }

cat > "$tmp" <<'EOF2'
10 F=0
20 REM --- a DATA/POKE loader: CALL 0A7FH / ADD HL,HL / JP 0A9AH at 32000
30 FOR I=0 TO 6:READ B:POKE 32000+I,B:NEXT
40 DATA 205,127,10,41,195,154,10
50 DEFUSR=32000:IF USR(21)<>42 THEN PRINT "FAIL poked routine";USR(21):F=1
60 IF USR(-300)<>-600 THEN PRINT "FAIL signed";USR(-300):F=1
70 REM --- the same routine packed into a string (the VARPTR idiom)
80 A$="1234567":V=VARPTR(A$):D=PEEK(V+1)+256*PEEK(V+2)
90 FOR I=0 TO 6:READ B:POKE D+I,B:NEXT
100 DATA 205,127,10,41,195,154,10
110 DEFUSR1=D:IF USR1(100)<>200 THEN PRINT "FAIL string-packed routine";USR1(100):F=1
120 REM --- a screen writer: fill the top line with 42 ('*') via a DJNZ loop
130 FOR I=0 TO 9:READ B:POKE 32100+I,B:NEXT
140 DATA 33,0,60,6,64,54,42,35,16,251
150 POKE 32110,201
160 DEFUSR2=32100:X=USR2(0)
170 FOR I=0 TO 63:IF PEEK(15360+I)<>42 THEN PRINT "FAIL screen byte";I;PEEK(15360+I):F=1:I=63
180 NEXT
190 REM --- CLS through the ROM entry point, then a byte the routine leaves in RAM
200 FOR I=0 TO 6:READ B:POKE 32200+I,B:NEXT
210 DATA 205,201,1,62,7,50,72
220 POKE 32207,125:POKE 32208,201
230 DEFUSR3=32200:X=USR3(0)
240 IF PEEK(15360)<>32 OR PEEK(16383)<>32 THEN PRINT "FAIL CLS trap":F=1
250 IF PEEK(32072)<>7 THEN PRINT "FAIL write-set byte";PEEK(32072):F=1
260 REM --- a routine that changes HIMEM by storing to 40B1H comes back through poke_byte
270 IF F THEN PRINT "Z80 CORE FIXTURE FAILED":END
280 PRINT "Z80 CORE FIXTURE OK"
EOF2
out=$(TRS80_Z80="$core" "$here/basic" "$tmp" 2>"$tmp.err" </dev/null); rc=$?
err=$(cat "$tmp.err")
[ "$rc" = "0" ] || fail "rc=$rc" "$out
$err"
[ "$out" = "Z80 CORE FIXTURE OK" ] || fail "output" "$out"
[ -z "$err" ] || fail "stderr" "$err"
rm -f "$tmp" "$tmp.err"
echo "Z80 CORE FIXTURE OK"
