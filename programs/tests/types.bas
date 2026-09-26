10 REM VALUE TYPES (the 2026-09-23 audit, L-16 with M-15): a number carries the ROM's type
20 REM and PRINT/STR$ format by it -- an integer in full, a single to 6 digits (12EAH),
30 REM a double to 16 with D for its exponent.  A literal is typed as 0E6CH reads it:
40 REM integer with no point or exponent up to 32767 (0F4BH), single up to 7 significant
50 REM digits, double from the eighth (0F65H-0F74H) or with a D exponent (0EA1H) or #.
60 CLEAR 500:F=0
100 IF STR$(1000000)<>" 1E+06" THEN PRINT "FAIL: a single 1000000 is 1E+06:";STR$(1000000):F=1
110 IF STR$(-1000000)<>"-1E+06" THEN PRINT "FAIL: -1000000":F=1
120 IF STR$(999999)<>" 999999" THEN PRINT "FAIL: 999999 in full":F=1
130 IF STR$(32767)<>" 32767" OR STR$(32768)<>" 32768" THEN PRINT "FAIL: 32767/32768":F=1
140 IF STR$(12345678)<>" 12345678" THEN PRINT "FAIL: 8 digits is a double, printed in full:";STR$(12345678):F=1
150 IF STR$(1234567)<>" 1.23457E+06" THEN PRINT "FAIL: 7 digits is a single:";STR$(1234567):F=1
160 IF STR$(1D20)<>" 1D+20" THEN PRINT "FAIL: 1D20:";STR$(1D20):F=1
170 IF STR$(1D15)<>" 1000000000000000" OR STR$(1D16)<>" 1D+16" THEN PRINT "FAIL: 16 digits in full, 17 as D:";STR$(1D15);STR$(1D16):F=1
180 IF STR$(1E6)<>" 1E+06" OR STR$(1000000#)<>" 1000000" OR STR$(1000000!)<>" 1E+06" THEN PRINT "FAIL: E, #, ! markers":F=1
190 IF STR$(1/3)<>" .333333" THEN PRINT "FAIL: 1/3 is a single:";STR$(1/3):F=1
200 IF STR$(1D0/3)<>" .3333333333333333" THEN PRINT "FAIL: 1D0/3 is a double:";STR$(1D0/3):F=1
210 IF STR$(2.9999999)<>" 2.9999999" THEN PRINT "FAIL: 2.9999999 is a double:";STR$(2.9999999):F=1
220 IF STR$(.00000012345678)<>" 1.2345678D-07" THEN PRINT "FAIL: leading zeros do not count:";STR$(.00000012345678):F=1
230 IF STR$(100000.5)<>" 100001" THEN PRINT "FAIL: half up at the sixth:";STR$(100000.5):F=1
300 REM a variable is typed by its name at the reference: the suffix, else the DEF table, else single
310 A=1000000:IF STR$(A)<>" 1E+06" THEN PRINT "FAIL: A is a single":F=1
320 B#=1000000:IF STR$(B#)<>" 1000000" THEN PRINT "FAIL: B# is a double":F=1
330 C%=1000:IF STR$(C%)<>" 1000" THEN PRINT "FAIL: C% is an integer":F=1
340 DEFDBL D:D=1000000:IF STR$(D)<>" 1000000" THEN PRINT "FAIL: DEFDBL D":F=1
350 DEFINT E:E=1000:IF STR$(E)<>" 1000" THEN PRINT "FAIL: DEFINT E":F=1
360 DIM Q#(3):Q#(2)=1000000:IF STR$(Q#(2))<>" 1000000" THEN PRINT "FAIL: a double array element":F=1
370 DIM R(3):R(1)=1000000:IF STR$(R(1))<>" 1E+06" THEN PRINT "FAIL: a single array element":F=1
400 REM an operation takes the wider type; / is never integer; ^ is single
410 IF STR$(C%*1000!)<>" 1E+06" THEN PRINT "FAIL: integer * single:";STR$(C%*1000!):F=1
420 IF STR$(C%*1000#)<>" 1000000" THEN PRINT "FAIL: integer * double":F=1
430 IF STR$(C%/2)<>" 500" OR STR$(7/2)<>" 3.5" THEN PRINT "FAIL: / of integers is a single":F=1
440 IF STR$(2^.5)<>" 1.41421" THEN PRINT "FAIL: 2^.5":F=1
450 IF STR$(-B#)<>"-1000000" OR STR$(ABS(-B#))<>" 1000000" OR STR$(INT(B#/3))<>" 333333" THEN PRINT "FAIL: unary minus, ABS, INT keep the type":F=1
460 IF STR$(LEN("ABC")*1000000)<>" 3E+06" THEN PRINT "FAIL: LEN is an integer, 1000000 a single: 3E+06":F=1
470 IF STR$(LEN("ABC")*1000000#)<>" 3000000" THEN PRINT "FAIL: LEN * double":F=1
500 REM VAL types by the reader's rule
510 IF STR$(VAL("1234567"))<>" 1.23457E+06" OR STR$(VAL("12345678"))<>" 12345678" OR STR$(VAL("1D2")+0)<>" 100" THEN PRINT "FAIL: VAL's type":F=1
520 IF STR$(VAL("7")/2)<>" 3.5" THEN PRINT "FAIL: VAL(7) is an integer":F=1
900 IF F THEN PRINT "TYPES FIXTURE FAILED":ERROR 5
910 PRINT "TYPES FIXTURE OK":END
