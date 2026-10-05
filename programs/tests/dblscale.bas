10 REM A DOUBLE IS PRINTED FROM A VALUE SCALED IN ROUNDED STEPS OF 56 BITS: the output routine
20 REM multiplies a value below 65536 by 1E10, then multiplies or divides by 10 until the value
30 REM holds sixteen integer digits (1201H-1268H), adds .5 and truncates (12AEH-12B8H); each step
40 REM leaves the exact result rounded to the machine's 56-bit mantissa.  The sixteenth digit is
50 REM that of the value the steps left: the single .7 shown as a double is .6999999880790711,
60 REM where its exact expansion goes on ...071044.  PRINT USING shows sixteen digits, then
70 REM zeros.  Since the double itself became the machine's 56 bits (dbl56.bas) every double is
80 REM printed this way.  Until 2026-10-05 every double was converted once, and USING ran past
90 REM sixteen digits.
100 CLEAR 2000:F=0:CLS
110 A=.7:D#=A:IF STR$(D#)<>" .6999999880790711" THEN PRINT "FAIL: the single .7 as a double:";D#:F=1
120 A=3.29:D#=A:IF STR$(D#)<>" 3.290000200271607" THEN PRINT "FAIL: the single 3.29 as a double:";D#:F=1
130 A=38.31/811:D#=A:IF STR$(D#)<>" .04723798111081124" THEN PRINT "FAIL: 38.31/811 as a double:";D#:F=1
140 A=1E-20:D#=A:IF STR$(D#)<>" 9.999999682655226D-21" THEN PRINT "FAIL: the single 1E-20 as a double:";D#:F=1
150 D#=CDBL(1/3):IF STR$(D#)<>" .3333333432674408" THEN PRINT "FAIL: CDBL(1/3):";D#:F=1
160 IF STR$(123456789012345#)<>" 123456789012345" OR STR$(1D15)<>" 1000000000000000" OR STR$(1D16)<>" 1D+16" THEN PRINT "FAIL: whole numbers:";123456789012345#;1D15;1D16:F=1
170 IF STR$(.5#)<>" .5" OR STR$(65535#/65536#)<>" .9999847412109375" OR STR$(1D-30)<>" 1D-30" THEN PRINT "FAIL: .5# 65535#/65536# 1D-30:";.5#;65535#/65536#;1D-30:F=1
180 REM a computed double
190 IF STR$(1#/3#)<>" .3333333333333333" OR STR$(.1#)<>" .1" THEN PRINT "FAIL: 1#/3# .1#:";1#/3#;.1#:F=1
400 A=.7:D#=A:U$="#.##################":W$="0.699999988079071100":GOSUB 900
410 A=123456.7:D#=A:W$="%123456.703125000000000000":GOSUB 900
420 A=.0486*25:D#=A:U$="##.##":W$=" 1.21":GOSUB 900
430 U$="#.###############[[[[":W$="0.121499991416931D+01":GOSUB 900
440 D#=999999#:U$="##.##[[[[":W$="10.00D+05":GOSUB 900
450 D#=12345678901234#:U$="####################.#":W$="      12345678901234.0":GOSUB 900
460 D#=1D15/1024#:U$="###,###,###,###.######":W$="976,562,500,000.000000":GOSUB 900
470 REM a long fraction: sixteen digits, then zeros; ^^^^ keeps the exponent here too
480 D#=1#/3#:U$="#.##################":W$="0.333333333333333300":GOSUB 900
490 D#=999999.9#:U$="##.##[[[[":W$="10.00D+05":GOSUB 900
500 D#=1234567.891#:U$="########.##":W$=" 1234567.89":GOSUB 900
600 PRINT@64,"";:IF F THEN PRINT "DBLSCALE FIXTURE FAILED":ERROR 5
610 PRINT "DBLSCALE FIXTURE OK":END
900 PRINT@0,STRING$(30,32);:PRINT@0,USING U$;D#;
910 G$="":FOR I=0 TO LEN(W$)-1:G$=G$+CHR$(PEEK(15360+I)):NEXT
920 IF PEEK(15360+LEN(W$))<>32 THEN G$=G$+"..."
930 IF G$<>W$ THEN F=F+1:PRINT@64*F,"FAIL: "+U$+STR$(D#)+" GAVE ["+G$+"] NOT ["+W$+"]";
940 RETURN
