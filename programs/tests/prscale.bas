10 REM A SINGLE IS PRINTED FROM A VALUE SCALED IN ROUNDED STEPS: the output routine multiplies
20 REM or divides the value by 10, a rounded single operation each time, until it holds six
30 REM integer digits (1222H-1268H: below 999999.5, not below 99999.9453125), then adds .5 and
40 REM truncates (12ECH-12F0H).  So 4/9, stored as .44444445, prints .444445: six multiplications
50 REM carry it to 444444.5.  PRINT USING scales the same way (1135H, 11B6H): a single shows six
60 REM digits and zeros behind them, a value scaled up further than the picture has decimals is
70 REM divided back a rounded step at a time (1164H), and ^^^^ keeps the scaling's exponent when
80 REM the rounding carries into a new digit: 999999 in ##.##^^^^ is 10.00E+05.
90 REM Until 2026-10-05 the digits were those of the stored value, converted once.
100 CLEAR 2000:F=0:CLS
110 IF STR$(4/9)<>" .444445" THEN PRINT "FAIL: 4/9:";4/9:F=1
120 A=8740.1129893920E-9:IF STR$(A)<>" 8.74012E-06" THEN PRINT "FAIL: 8.740114935790189D-06 as a single:";A:F=1
130 IF STR$(903/130)<>" 6.94616" OR STR$(3/331)<>" 9.06345E-03" THEN PRINT "FAIL: 903/130, 3/331:";903/130;3/331:F=1
140 IF STR$(1/3)<>" .333333" OR STR$(2/3)<>" .666667" OR STR$(.1)<>" .1" THEN PRINT "FAIL: 1/3 2/3 .1:";1/3;2/3;.1:F=1
150 IF STR$(123456.7)<>" 123457" OR STR$(999999)<>" 999999" OR STR$(1E6)<>" 1E+06" THEN PRINT "FAIL: six digits:";123456.7;999999;1E6:F=1
160 D#=4/9:IF STR$(D#)<>" .4444444477558136" THEN PRINT "FAIL: the stored value of 4/9 moved:";D#:F=1
200 DATA "##.##"," 1.22"
210 DATA "#.########","1.21500000"
220 DATA "########.##","       1.22"
230 DATA "##.##[[[["," 1.22E+00"
300 READ U$,W$:IF U$="END" THEN 400
310 V=.0486*25:GOSUB 900:GOTO 300
320 DATA "END",""
400 V=4/9:U$="#.########":W$="0.44444500":GOSUB 900
410 U$="###.#######[[[[":W$=" 44.4445000E-02":GOSUB 900
420 V=123456.7:U$="######.#":W$="123457.0":GOSUB 900
430 V=1234567:U$="#,###,###.#":W$="1,234,570.0":GOSUB 900
440 U$="#######":W$="1234570":GOSUB 900
450 V=999999:U$="##.##[[[[":W$="10.00E+05":GOSUB 900
460 U$="#.#####[[[[":W$="1.00000E+06":GOSUB 900
470 V=-999999:U$="##.##[[[[":W$="%-10.00E+05":GOSUB 900
480 V=99.995:U$="##.##[[[[":W$="10.00E+01":GOSUB 900
490 V=.005:U$="##.##":W$=" 0.01":GOSUB 900
500 REM an integer and a double are not scaled this way
510 I%=32767:PRINT@0,STRING$(24,32);:PRINT@0,USING "#####.##";I%;:U$="#####.## of 32767%":W$="32767.00":GOSUB 910
520 D#=1234567.891#:PRINT@0,STRING$(24,32);:PRINT@0,USING "########.###";D#;:U$="########.### of a double":W$=" 1234567.891":GOSUB 910
600 PRINT@64,"";:IF F THEN PRINT "PRSCALE FIXTURE FAILED":ERROR 5
610 PRINT "PRSCALE FIXTURE OK":END
900 PRINT@0,STRING$(24,32);:PRINT@0,USING U$;V;
910 G$="":FOR I=0 TO LEN(W$)-1:G$=G$+CHR$(PEEK(15360+I)):NEXT
920 IF PEEK(15360+LEN(W$))<>32 THEN G$=G$+"..."
930 IF G$<>W$ THEN F=F+1:PRINT@64*F,"FAIL: "+U$+STR$(V)+" GAVE ["+G$+"] NOT ["+W$+"]";
940 RETURN
