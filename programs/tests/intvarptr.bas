10 REM A numeric's VARPTR bytes are the machine's for its type: an
20 REM integer 2 (LSB, MSB), a single 4, a double 8 (MBF, exponent last),
30 REM sized by the suffix, else the DEF table.  Until 2026-09-29 every
40 REM numeric was a single's 4 bytes (the 2026-09-26 audit, R-8, step 2).
50 F=0
100 REM --- an integer: LSB, MSB; a POKE into either changes the value
110 A%=513:V=VARPTR(A%):IF PEEK(V)<>1 OR PEEK(V+1)<>2 THEN PRINT "FAIL: 513 IS 01 02";PEEK(V);PEEK(V+1):F=1
120 POKE V,3:IF A%<>515 THEN PRINT "FAIL: POKE THE LSB";A%:F=1
130 A%=-2:IF PEEK(V)<>254 OR PEEK(V+1)<>255 THEN PRINT "FAIL: -2 IS FE FF";PEEK(V);PEEK(V+1):F=1
140 POKE V+1,128:POKE V,0:IF A%<>-32768 THEN PRINT "FAIL: 8000H IS -32768";A%:F=1
150 REM --- a DEFINT letter is an integer too
160 DEFINT E:E=258:V=VARPTR(E):IF PEEK(V)<>2 OR PEEK(V+1)<>1 THEN PRINT "FAIL: DEFINT E";PEEK(V);PEEK(V+1):F=1
200 REM --- a double: 8 bytes; a single's value stored in it has a zero low half
210 B#=1/3:V=VARPTR(B#):S=0:FOR I=0 TO 3:S=S+PEEK(V+I):NEXT
220 IF S<>0 OR PEEK(V+4)<>171 OR PEEK(V+5)<>170 OR PEEK(V+6)<>42 OR PEEK(V+7)<>127 THEN PRINT "FAIL: B#=1/3";S;PEEK(V+4);PEEK(V+5);PEEK(V+6);PEEK(V+7):F=1
230 REM --- eight bytes POKEd one at a time, exponent last, arrive whole
240 C#=0:V=VARPTR(C#):FOR I=0 TO 7:READ B:POKE V+I,B:NEXT
250 IF C#<>1/3# THEN PRINT "FAIL: DOUBLE BY BYTES";C#:F=1
260 DATA 171,170,170,170,170,170,42,127
270 C#=2:IF PEEK(V+6)<>0 OR PEEK(V+7)<>130 THEN PRINT "FAIL: PEEK AFTER ASSIGNMENT";PEEK(V+6);PEEK(V+7):F=1
280 D#=1:D#=D#/3:V=VARPTR(D#):IF PEEK(V+1)<>170 OR PEEK(V+6)<>42 OR PEEK(V+7)<>127 THEN PRINT "FAIL: 1/3#";PEEK(V+1);PEEK(V+6);PEEK(V+7):F=1
300 REM --- a single stays 4 bytes; the entries are packed by size
310 G!=.1:V=VARPTR(G!):IF PEEK(V)<>205 OR PEEK(V+3)<>125 THEN PRINT "FAIL: .1";PEEK(V);PEEK(V+3):F=1
320 H%=1:J#=1:K=1:X=VARPTR(H%):Y=VARPTR(J#):Z=VARPTR(K)
330 IF X-Y<>8 OR Y-Z<>4 THEN PRINT "FAIL: H% J# K SPACING";X-Y;Y-Z:F=1
340 REM --- VARPTR of a name not yet stored is sized by its own suffix
350 X=VARPTR(L%):Y=VARPTR(M#):IF X-Y<>8 THEN PRINT "FAIL: UNSTORED L% M#";X-Y:F=1
360 L%=772:V=VARPTR(L%):IF PEEK(V)<>4 OR PEEK(V+1)<>3 THEN PRINT "FAIL: L% LATER STORED";PEEK(V);PEEK(V+1):F=1
900 IF F THEN PRINT "INTVARPTR FIXTURE FAILED":ERROR 5
910 PRINT "INTVARPTR FIXTURE OK":END
