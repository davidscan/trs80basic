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
255 REM --- a routine parked across the clock cells 4041-4046H (Space Chase, 80 Micro 5/1982): the POKEd bytes reach the frame
256 FOR I=0 TO 9:READ B:POKE 16446+I,B:NEXT
257 DATA 205,127,10,41,41,41,41,195,154,10
258 DEFUSR4=16446:IF USR4(3)<>48 THEN PRINT "FAIL routine across the clock cells";USR4(3):F=1
260 REM --- a routine that changes HIMEM by storing to 40B1H comes back through poke_byte
261 REM --- a float stored through VARPTR while the target holds 0: LD HL,src / LD DE,dst / LD BC,4 / LDIR / RET.
262 REM     the write-set arrives ascending, exponent LAST; the mantissa bytes must not be lost on the way
263 Q=-123.456:Z=0:S=VARPTR(Q):S=S-65536*(S<0):T=VARPTR(Z):T=T-65536*(T<0):REM VARPTR is the ROM's integer, negative up here (L-43)
264 FOR I=0 TO 11:READ B:POKE 32300+I,B:NEXT
265 DATA 33,0,0,17,0,0,1,4,0,237,176,201
266 POKE 32301,S-256*INT(S/256):POKE 32302,INT(S/256):POKE 32304,T-256*INT(T/256):POKE 32305,INT(T/256)
267 DEFUSR5=32300:X=USR5(0)
268 IF STR$(Z)<>STR$(Q) THEN PRINT "FAIL float through VARPTR";Z:F=1
269 REM --- CALL 0A9AH returns to the routine (the ROM's ends in RET): LD HL,5 / CALL 0A9AH / LD A,42 / LD (7D00H),A / LD HL,9 / RET
271 FOR I=0 TO 14:READ B:POKE 32400+I,B:NEXT
272 DATA 33,5,0,205,154,10,62,42,50,0,125,33,9,0,201
273 POKE 32000,0:DEFUSR6=32400:X=USR6(77)
274 IF X<>5 OR PEEK(32000)<>42 THEN PRINT "FAIL CALL 0A9AH";X;PEEK(32000):F=1
275 REM --- and makes the ROM's stores on the way: HL to 4121H, the integer type flag 2 to 40AFH
276 IF PEEK(16673)<>5 OR PEEK(16674)<>0 OR PEEK(16559)<>2 THEN PRINT "FAIL 0A9AH stores";PEEK(16673);PEEK(16674);PEEK(16559):F=1
277 REM --- an integer through VARPTR is 2 bytes, LSB first: LD HL,(N%) / INC HL / LD (N%),HL / JP 0A9AH
278 N%=1000:P=VARPTR(N%):P=P-65536*(P<0):FOR I=0 TO 9:READ B:POKE 32500+I,B:NEXT
279 DATA 42,0,0,35,34,0,0,195,154,10
280 POKE 32501,P-256*INT(P/256):POKE 32502,INT(P/256):POKE 32505,P-256*INT(P/256):POKE 32506,INT(P/256)
281 DEFUSR7=32500:X=USR7(0):IF X<>1001 OR N%<>1001 THEN PRINT "FAIL integer through VARPTR";X;N%:F=1
282 REM --- the last screen cell, 3FFFH, reaches the screen: LD A,88 / LD (3FFFH),A / RET
283 FOR I=0 TO 5:READ B:POKE 32600+I,B:NEXT
284 DATA 62,88,50,255,63,201
285 DEFUSR8=32600:X=USR8(0):IF PEEK(16383)<>88 OR PEEK(16382)<>32 THEN PRINT "FAIL last screen cell";PEEK(16383);PEEK(16382):F=1
286 REM --- a returned HL of 8000H is the signed integer -32768: CALL 0A7FH / ADD HL,HL / JP 0A9AH
287 FOR I=0 TO 6:READ B:POKE 32700+I,B:NEXT
288 DATA 205,127,10,41,195,154,10
289 DEFUSR9=32700:IF USR9(16384)<>-32768 OR USR9(16383)<>32766 THEN PRINT "FAIL HL 8000H";USR9(16384);USR9(16383):F=1
290 REM --- the argument's type code at 40AFH (2 integer, 4 single, 8 double, 3 string): LD A,(40AFH) / LD L,A / LD H,0 / JP 0A9AH
291 FOR I=0 TO 8:READ B:POKE 31500+I,B:NEXT
292 DATA 58,175,64,111,38,0,195,154,10
293 A%=7:A#=7:A$="X":DEFUSR9=31500:IF USR9(A%)<>2 OR USR9(A)<>4 OR USR9(A#)<>8 OR USR9(A$)<>3 THEN PRINT "FAIL argument type codes";USR9(A%);USR9(A);USR9(A#);USR9(A$):F=1
298 IF F THEN PRINT "Z80 CORE FIXTURE FAILED":END
299 PRINT "Z80 CORE FIXTURE OK"
EOF2
out=$(TRS80_Z80="$core" "$here/basic" "$tmp" 2>"$tmp.err" </dev/null); rc=$?
err=$(cat "$tmp.err")
[ "$rc" = "0" ] || fail "rc=$rc" "$out
$err"
[ "$out" = "Z80 CORE FIXTURE OK" ] || fail "output" "$out"
[ -z "$err" ] || fail "stderr" "$err"

# A routine that ends with JP 1A19H hands the machine to READY: the program
# is over, and the statement after the call does not run (the 2026-09-19
# audit, L-44).  The byte it stored first still arrives.  Line 40 only runs
# through the prompt, after the program has ended.
cat > "$tmp" <<'EOF2'
10 FOR I=0 TO 7:READ B:POKE 32000+I,B:NEXT
20 DATA 62,9,50,64,125,195,25,26
30 DEFUSR=32000:X=USR(0):PRINT "RAN ON"
EOF2
out=$(printf '\nLOAD "%s"\nRUN\nPRINT "B=";PEEK(32064)\n' "$tmp" | TRS80_DUMB=1 TRS80_Z80="$core" "$here/basic" 2>&1)
case $out in *"RAN ON"*) fail "JP 1A19H: the program ran on past the call" "$out" ;; esac
case $out in *"B= 9"*) ;; *) fail "JP 1A19H: the store before it was lost" "$out" ;; esac
rm -f "$tmp" "$tmp.err"
echo "Z80 CORE FIXTURE OK"
