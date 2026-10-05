10 REM SINGLE PRECISION IS 24 BITS (ROM 0796H-07A9H: half up on the guard byte), INTEGER
20 REM ARITHMETIC IS 16 BITS AND OVERFLOWS INTO A SINGLE (0BD0H-0BDDH), AND A RESULT
30 REM BELOW 2^-128 IS ZERO (0793H -> 0778H).  The 2026-09-23 audit, M-15 and M-10.
40 CLEAR 500:F=0
100 N=0:FOR X=0 TO 1 STEP .1:N=N+1:NEXT
110 IF N<>10 THEN PRINT "FAIL: FOR X=0 TO 1 STEP .1 makes";N;"passes, the machine 10":F=1
120 X=0:FOR I=1 TO 10:X=X+.1:NEXT
130 IF X<=1 THEN PRINT "FAIL: ten additions of .1 overshoot 1 on the machine:";X:F=1
140 IF STR$(X)<>" 1" THEN PRINT "FAIL: and print as 1:";STR$(X):F=1
150 A#=1/3:IF STR$(A#)<>" .3333333432674408" THEN PRINT "FAIL: A#=1/3 keeps the single's 24 bits:";STR$(A#):F=1
160 DEFDBL C:C=2/3:IF STR$(C)<>" .6666666865348816" THEN PRINT "FAIL: 2/3 into a double:";STR$(C):F=1
170 C=1#/3:IF STR$(C)<>" .3333333333333333" THEN PRINT "FAIL: 1#/3 is double division:";STR$(C):F=1
180 IF STR$(.1)<>" .1" OR .1+.2<>.3 THEN PRINT "FAIL: .1+.2=.3 in 24 bits":F=1
190 B=.1:IF STR$(B*10)<>" 1" THEN PRINT "FAIL: .1*10":F=1
200 REM integers: 16 bits, an overflow is silently a single, never ?OV (0BD0H)
210 I%=30000:IF STR$(I%+I%)<>" 60000" OR STR$(I%*3)<>" 90000" OR STR$(I%-I%)<>" 0" THEN PRINT "FAIL: integer overflow to single":F=1
220 IF STR$(32767+1)<>" 32768" OR STR$(-32768-1)<>"-32769" THEN PRINT "FAIL: 32767+1, -32768-1":F=1
230 J%=-32768:IF STR$(-J%)<>" 32768" THEN PRINT "FAIL: -(-32768)":F=1
240 IF STR$(I%*2/4)<>" 15000" THEN PRINT "FAIL: (I%*2)/4":F=1
250 K%=7:IF STR$(K%/2)<>" 3.5" THEN PRINT "FAIL: 7%/2 is 3.5":F=1
300 REM underflow is zero, silently
310 IF 1E-20*1E-20<>0 OR 1.5E-39<>0 THEN PRINT "FAIL: 1E-40 and 1.5E-39 are 0":F=1
320 IF 1E-38*.1<>0 THEN PRINT "FAIL: 1E-39 is 0":F=1
330 REM a product reaches down to 2^-128; a quotient stops two places higher, because the divide
332 REM settles its exponent before the mantissas (0914H-0930H, 08ADH): X/2 is 0 one halving after
334 REM 2^-126.  The reader divides by ten, so a literal below about 1.18E-38 is 0.  (srange.bas)
336 X=1:FOR I=1 TO 128:X=X*.5:NEXT:IF STR$(X)<>" 2.93874E-39" OR X*.5<>0 THEN PRINT "FAIL: a product's floor is 2^-128:";X;X*.5:F=1
338 IF 2.94E-39<>0 OR 5.9E-39<>0 OR 1.18E-38=0 OR 1E-38=0 THEN PRINT "FAIL: a literal below the divide's floor is 0":F=1
340 X=1:C=0:FOR I=1 TO 2000:X=X/2:IF X=0 THEN 360
350 NEXT
360 IF I<>127 THEN PRINT "FAIL: X=X/2 reaches 0 at step 127, not";I:F=1
370 IF 1D-20*1D-20<>0 THEN PRINT "FAIL: a double underflows too":F=1
400 REM a single result of a function is 24 bits
410 IF STR$(SQR(2))<>" 1.41421" OR SQR(2)*SQR(2)=2 THEN PRINT "FAIL: SQR(2)^2 is not exactly 2 in 24 bits":F=1
420 IF VAL(".1E0")<>.1 OR VAL(".1")=.1 THEN PRINT "FAIL: VAL rounds a single (an E exponent); VAL(\".1\") is a double (0E65H)":F=1
430 IF CSNG(1#/3)<>1/3 THEN PRINT "FAIL: CSNG rounds":F=1
500 REM the single adder (0716H-07A9H): the operand with the smaller exponent is lined up and
510 REM keeps one guard byte; 25 or more places apart, the larger operand is the result (072FH)
520 IF 1-4.265E-8<>1 OR 1-5.9E-8<>1 OR 1-6E-8=1 THEN PRINT "FAIL: 1 minus less than 2^-24 is 1:";1-4.265E-8=1;1-5.9E-8=1;1-6E-8=1:F=1
530 D#=1-6E-8:E#=100-99.99999:IF STR$(D#)<>" .9999999403953552" OR STR$(E#)<>" 1.52587890625D-05" THEN PRINT "FAIL: 1-6E-8, 100-99.99999:";D#;E#:F=1
540 D#=.1+.2:IF STR$(D#)<>" .300000011920929" THEN PRINT "FAIL: .1+.2:";D#:F=1
550 N=0:FOR X=1 TO 1.00001 STEP 6E-8:N=N+1:NEXT:IF N<>84 THEN PRINT "FAIL: NEXT steps through the adder: 84 passes, not";N:F=1
900 IF F THEN PRINT "SNGL FIXTURE FAILED":ERROR 5
910 PRINT "SNGL FIXTURE OK":END
