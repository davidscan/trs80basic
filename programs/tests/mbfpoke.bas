10 REM A numeric variable written one MBF byte at a time keeps its bytes:
20 REM while the exponent byte (V+3) is still 0 the VALUE is 0, but the
30 REM mantissa bytes already stored must survive until it arrives.
35 REM (compared as printed: a value that has been through four bytes is single precision)
40 F=0:DIM R(3)
50 A=123.456:GOSUB 500:X=0:W=VARPTR(X):GOSUB 600
60 IF STR$(X)<>STR$(A) THEN PRINT "FAIL: ASCENDING COPY INTO A ZERO VARIABLE";X:F=1
70 A=-.0078125:GOSUB 500:Y=0:W=VARPTR(Y):GOSUB 700
80 IF STR$(Y)<>STR$(A) THEN PRINT "FAIL: DESCENDING COPY";Y:F=1
90 A=1E+20:GOSUB 500:R(2)=0:W=VARPTR(R(2)):GOSUB 600
100 IF STR$(R(2))<>STR$(A) THEN PRINT "FAIL: COPY INTO AN ARRAY ELEMENT";R(2):F=1
110 REM --- the bytes read back as stored while the value is still 0
120 Z=0:W=VARPTR(Z):POKE W,1:POKE W+1,2:POKE W+2,3
130 IF Z<>0 OR PEEK(W)<>1 OR PEEK(W+1)<>2 OR PEEK(W+2)<>3 THEN PRINT "FAIL: MANTISSA BYTES UNDER A ZERO EXPONENT";PEEK(W);PEEK(W+1);PEEK(W+2):F=1
140 REM --- an assignment outdates them: the next PEEK encodes the new value
150 Z=1:IF PEEK(W)<>0 OR PEEK(W+2)<>0 OR PEEK(W+3)<>129 THEN PRINT "FAIL: PEEK AFTER ASSIGNMENT";PEEK(W);PEEK(W+2);PEEK(W+3):F=1
160 REM --- one byte changed in a live number still works (the old path)
170 Z=1:POKE W+3,130:IF Z<>2 THEN PRINT "FAIL: EXPONENT POKE";Z:F=1
180 POKE W+2,128:IF Z<>-2 THEN PRINT "FAIL: SIGN BIT POKE";Z:F=1
190 IF F THEN PRINT "MBFPOKE FIXTURE FAILED":ERROR 5
200 PRINT "MBFPOKE FIXTURE OK":END
500 V=VARPTR(A):S$="":FOR I=0 TO 3:S$=S$+CHR$(PEEK(V+I)):NEXT:RETURN
600 FOR I=0 TO 3:POKE W+I,ASC(MID$(S$,I+1,1)):NEXT:RETURN
700 FOR I=3 TO 0 STEP -1:POKE W+I,ASC(MID$(S$,I+1,1)):NEXT:RETURN
