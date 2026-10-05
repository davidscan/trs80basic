10 REM A DOUBLE IS THE MACHINE'S: a 56-bit mantissa, and add, subtract, multiply, divide and the
20 REM reader worked as the ROM works them (0C70H-0E4CH, 0E65H-0F28H), their faults with them:
30 REM   the subtract leaves the guard byte unsubtracted (0CB3H): 1D16-.2# is ABOVE 1D16
40 REM   the divide does not notice a zero dividend: 0#/.2# is 7.3D-39 (0 from .25 up); and a
50 REM   divisor of 2^126 or more reads as zero: 1#/1.7D38 is 0
60 REM   INT of a whole negative double from 32768 up, its six low bytes zero, is one unit of
70 REM   the top byte too far down (0D69H): INT(-44800#) is -45056
80 REM Until 2026-10-05 a double was the host's 53 bits: 89438606.6 printed 89438606.59999999,
90 REM .7#+.1# was .7999999999999999 and 2#/3# ended in 6.
100 CLEAR 500:F=0:S=0:ON ERROR GOTO 900
110 IF STR$(89438606.6)<>" 89438606.6" OR STR$(.7#+.1#)<>" .8" OR STR$(2#/3#)<>" .6666666666666667" THEN PRINT "FAIL: 89438606.6, .7#+.1#, 2#/3#:";89438606.6;.7#+.1#;2#/3#:F=1
120 IF STR$(1#/3#)<>" .3333333333333333" OR STR$(1#-.9#)<>" .1" OR STR$(100#*1.1#)<>" 110" OR STR$(19.99#*3#)<>" 59.97" THEN PRINT "FAIL: 1#/3#, 1#-.9#, 100#*1.1#, 19.99#*3#":F=1
130 A#=1D16-.2#:IF STR$(A#)<>" 1D+16" OR A#<=1D16 OR A#-1D16<>.25 THEN PRINT "FAIL: 1D16-.2# is a quarter above 1D16:";A#;A#-1D16:F=1
140 A#=0:FOR I=1 TO 10:A#=A#+.1#:NEXT:IF STR$(A#)<>" 1" OR A#=1# OR STR$(A#-1#)<>" 2.775557561562891D-17" THEN PRINT "FAIL: ten times .1#:";A#;A#-1#:F=1
150 A#=0#:B#=A#/.2#:C#=A#/.25#:IF STR$(B#)<>" 7.346839692639297D-39" OR C#<>0 OR STR$(0#/-.1#)<>"-1.469367938527859D-38" THEN PRINT "FAIL: a zero dividend:";B#;C#;0#/-.1#:F=1
160 IF 1#/1.7D38<>0 OR 2#/1D38<>0 OR STR$(1#/8D37)<>" 1.25D-38" OR 1.6D38/.9#<>0 OR STR$(1.6D38/.25#)<>" 5.527147875260445D-39" THEN PRINT "FAIL: quotients at the ends:";1#/1.7D38;1#/8D37;1.6D38/.25#:F=1
170 IF INT(-44800#)<>-45056 OR INT(-65536#)<>-66048 OR INT(-44800.5#)<>-44801 OR FIX(-44800#)<>-44800 OR INT(44800#)<>44800 OR INT(-40000#)<>-40000 THEN PRINT "FAIL: INT of a negative double:";INT(-44800#);INT(-65536#);INT(-44800.5#):F=1
180 IF STR$(VAL("89438606.6"))<>" 89438606.6" OR VAL(".1")<>.1# OR VAL("1D16")-.2#<=1D16 OR STR$(1234567.891#*100#)<>" 123456789.1" THEN PRINT "FAIL: VAL reads as a literal does":F=1
190 A#=123456789012345678#:B#=.1234567890123456789#:IF STR$(A#)<>" 1.234567890123457D+17" OR STR$(B#)<>" .1234567890123457" OR STR$(A#*B#)<>" 1.524157875323884D+16" OR STR$(A#/3#)<>" 4.115226300411523D+16" THEN PRINT "FAIL: long literals:";A#;B#;A#*B#;A#/3#:F=1
200 A#=1#/3#:B=A#:C#=B:IF STR$(B)<>" .333333" OR STR$(C#)<>" .3333333432674408" OR A#=C# OR STR$(CSNG(2#/3#))<>" .666667" OR CINT(2.5#)<>2 OR CINT(-2.5#)<>-3 THEN PRINT "FAIL: a double to a single and back":F=1
210 IF 2D-39<>0 OR 3D-39<>0 OR STR$(1.2D-38/1.5#)<>" 8D-39" OR STR$(1D-38*.3#)<>" 3D-39" OR 1D-38*.29#<>0 THEN PRINT "FAIL: the bottom of the range:";1.2D-38/1.5#;1D-38*.3#:F=1
212 REM a value a hair under a power of ten prints a colon for its first digit (the digit loop
214 REM counts past "9", 12C2H): the ROM bug list's entry
216 A#=9.999999999999999D-37:IF STR$(A#)<>" :D-37" OR STR$(9.999999999999999D-7)<>" 9.999999999999999D-07" OR STR$(1D-36)<>" 1D-36" THEN PRINT "FAIL: the colon:";A#:F=1
218 Y#=1#:FOR I=1 TO 128:Y#=Y#*.5#:NEXT:IF STR$(Y#)<>" 2.938735877055719D-39" OR Y#/1#<>0 OR 1#/Y#<>Y# OR Y#*.5#<>0 OR Y#/.5#<>0 OR STR$(Y#*2#)<>" 5.877471754111438D-39" THEN PRINT "FAIL: the smallest double:";Y#;Y#/1#;1#/Y#:F=1
220 REM the stored bytes: 1#/3# is AB AA AA AA AA AA 2A 7F, the last mantissa bit rounded up
230 A#=1#/3#:V=VARPTR(A#):IF PEEK(V)<>171 OR PEEK(V+1)<>170 OR PEEK(V+6)<>42 OR PEEK(V+7)<>127 THEN PRINT "FAIL: the bytes of 1#/3#:";PEEK(V);PEEK(V+1);PEEK(V+6);PEEK(V+7):F=1
240 A#=1D16-.2#:V=VARPTR(A#):IF PEEK(V)<>1 OR PEEK(V+2)<>4 OR PEEK(V+7)<>182 THEN PRINT "FAIL: the bytes of 1D16-.2#:";PEEK(V);PEEK(V+2);PEEK(V+7):F=1
250 A#=0:V=VARPTR(A#):POKE V,205:FOR I=1 TO 5:POKE V+I,204:NEXT:POKE V+6,76:POKE V+7,126:IF A#<>.2# OR STR$(A#)<>" .2" THEN PRINT "FAIL: .2# POKEd in by bytes:";A#:F=1
300 REM each of these must be ?OV
310 S=1:A#=1D19*1D19
315 IF S<>-1 THEN PRINT "FAIL: STEP 1 RAISED NOTHING":F=1
320 S=2:A#=8D37*2#
325 IF S<>-2 THEN PRINT "FAIL: STEP 2 RAISED NOTHING":F=1
330 S=3:A#=1.6D38/.49#
335 IF S<>-3 THEN PRINT "FAIL: STEP 3 RAISED NOTHING":F=1
340 S=4:A#=1.7D38+1.7D38
345 IF S<>-4 THEN PRINT "FAIL: STEP 4 RAISED NOTHING":F=1
350 S=0
890 ON ERROR GOTO 0:IF F THEN PRINT "DBL56 FIXTURE FAILED":ERROR 5
895 PRINT "DBL56 FIXTURE OK":END
900 G=ERR/2+1:IF S=0 THEN PRINT "FAIL: UNEXPECTED ERROR";G;"IN";ERL:F=1:RESUME NEXT
910 IF G<>6 THEN PRINT "FAIL: STEP";S;"RAISED";G;"NOT 6":F=1
920 S=-S:RESUME NEXT
