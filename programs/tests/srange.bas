10 REM THE ENDS OF THE SINGLE RANGE IN A PRODUCT AND A QUOTIENT.  Multiply and divide settle the
20 REM exponent first (0914H-0930H): they add or subtract the two exponent bytes, test that for
30 REM range, and only then work the mantissas, which can still move the result one place.
40 REM   A product whose exponents add to 128 or more is ?OV even when the mantissas would
50 REM   bring it under the limit: 1E19*1E19, 8E37*2 and 1.6E38*1 are ?OV; 1.6E38*.9 is a value.
60 REM   A quotient: the divide adds 2 to its exponent byte with no test (08ADH), so the byte
70 REM   wraps at the top: 1.6E38/.9 is 0 and 1.6E38/.25 is 5.52715E-39; and at the bottom a
80 REM   quotient is 0 two places above a product's floor: 1E-38/2 is 0, 1E-38*.5 is 5E-39.
90 REM Until 2026-10-05 only the finished value was tested against the range.
100 CLEAR 300:F=0:S=0:ON ERROR GOTO 900
110 IF STR$(1.6E38*.9)<>" 1.44E+38" OR STR$(8E37*1.9)<>" 1.52E+38" OR STR$(4E37*3)<>" 1.2E+38" THEN PRINT "FAIL: products under the limit:";1.6E38*.9;8E37*1.9;4E37*3:F=1
120 IF STR$(9.2E18*1.84E19)<>" 1.6928E+38" OR STR$(9.2E18*9.2E18)<>" 8.464E+37" OR STR$(1.70141E38*.5)<>" 8.50705E+37" THEN PRINT "FAIL: more products under the limit":F=1
130 Y=1.6E38:IF Y/.9<>0 OR Y/.5<>0 OR Y/.6<>0 OR 1E38/.5<>0 OR 8.6E37/.5<>0 THEN PRINT "FAIL: a quotient whose exponent byte wraps to 0 is 0:";Y/.9;Y/.5:F=1
140 IF STR$(Y/.95)<>" 1.68421E+38" OR STR$(1E38/.7)<>" 1.42857E+38" OR STR$(8E37/.5)<>" 1.6E+38" THEN PRINT "FAIL: quotients under the limit:";Y/.95;1E38/.7;8E37/.5:F=1
150 IF STR$(Y/.25)<>" 5.52715E-39" OR STR$(Y/.3)<>" 4.60596E-39" OR STR$(1E38/.25)<>" 3.45447E-39" THEN PRINT "FAIL: a quotient 2^256 too small:";Y/.25;Y/.3;1E38/.25:F=1
160 X=1:FOR I=1 TO 124:X=X/2:NEXT:IF STR$(X)<>" 4.70198E-38" OR STR$(X/4)<>" 1.17549E-38" OR X/8<>0 OR X/9<>0 THEN PRINT "FAIL: 2^-124 over 4, 8, 9:";X;X/4;X/8;X/9:F=1
170 IF STR$(X/7)<>" 6.71711E-39" OR STR$(X/7.9)<>" 5.95187E-39" OR (X*1.5)/8<>0 OR STR$((X*1.9)/4)<>" 2.23344E-38" THEN PRINT "FAIL: quotients at the floor:";X/7;X/7.9;(X*1.5)/8:F=1
180 IF 1E-38/2<>0 OR 1E-38/3<>0 OR STR$(1E-38*.5)<>" 5E-39" OR STR$(1E-38*.3)<>" 3E-39" OR 1E-38*.1<>0 THEN PRINT "FAIL: 1E-38 halved by / and by *:";1E-38/2;1E-38*.5:F=1
190 IF STR$(1/1.7E38)<>" 5.88235E-39" OR STR$(1E-30/1E8)<>" 1E-38" OR 1E-30/2E8<>0 OR 1E-30/1.7E8<>0 THEN PRINT "FAIL: reciprocals at the floor:";1/1.7E38;1E-30/1E8:F=1
200 IF STR$(1E-19*1E-19)<>" 1E-38" OR 1E-20*1E-19<>0 OR STR$(1E-19*5E-20)<>" 5E-39" THEN PRINT "FAIL: products at the floor":F=1
300 REM each of these must be ?OV
310 S=1:X=1E19*1E19
315 IF S<>-1 THEN PRINT "FAIL: STEP 1 RAISED NOTHING":F=1
320 S=2:X=8E37*2
325 IF S<>-2 THEN PRINT "FAIL: STEP 2 RAISED NOTHING":F=1
330 S=3:X=1.6E38*1
335 IF S<>-3 THEN PRINT "FAIL: STEP 3 RAISED NOTHING":F=1
340 S=4:X=4E37*4
345 IF S<>-4 THEN PRINT "FAIL: STEP 4 RAISED NOTHING":F=1
350 S=5:X=1E38*1.5
355 IF S<>-5 THEN PRINT "FAIL: STEP 5 RAISED NOTHING":F=1
360 S=6:X=9.3E18*1.8E19
365 IF S<>-6 THEN PRINT "FAIL: STEP 6 RAISED NOTHING":F=1
370 S=7:X=-8E37*2
375 IF S<>-7 THEN PRINT "FAIL: STEP 7 RAISED NOTHING":F=1
380 S=8:X=Y/.49
385 IF S<>-8 THEN PRINT "FAIL: STEP 8 RAISED NOTHING":F=1
390 S=9:X=Y/.24
395 IF S<>-9 THEN PRINT "FAIL: STEP 9 RAISED NOTHING":F=1
400 S=10:X=1E38/.3
405 IF S<>-10 THEN PRINT "FAIL: STEP 10 RAISED NOTHING":F=1
410 S=11:X=1E38/.2
415 IF S<>-11 THEN PRINT "FAIL: STEP 11 RAISED NOTHING":F=1
420 S=12:X=1.70141E38*1
425 IF S<>-12 THEN PRINT "FAIL: STEP 12 RAISED NOTHING":F=1
430 S=0
890 ON ERROR GOTO 0:IF F THEN PRINT "SRANGE FIXTURE FAILED":ERROR 5
895 PRINT "SRANGE FIXTURE OK":END
900 G=ERR/2+1:IF S=0 THEN PRINT "FAIL: UNEXPECTED ERROR";G;"IN";ERL:F=1:RESUME NEXT
910 IF G<>6 THEN PRINT "FAIL: STEP";S;"RAISED";G;"NOT 6":F=1
920 S=-S:RESUME NEXT
