10 REM SIN, COS and TAN are the ROM's routines (1541H-15BAH), step for step in single
20 REM precision: x/2pi, the turn's fraction, folded to [-.25,.25] against .25 (156DH-1584H),
30 REM the five-term series at 1594H (149AH), COS = SIN(x+pi/2), TAN = SIN/COS through the
40 REM divider at 08A2H whose zero test is ?/0.  A quarter turn within one unit of the ROM's
50 REM pi/2 (1.5707963, ATN(1)*2) reduces to exactly 0: COS is 0 and TAN is ?/0.  Until
60 REM 2026-09-27 the host's libm answered on the raw argument (the 2026-09-26 audit, M-12).
70 F=0:S=0:ON ERROR GOTO 900
100 IF COS(1.5707963)<>0 OR COS(ATN(1)*2)<>0 OR COS(1.5707962)<>0 THEN PRINT "FAIL: COS of the ROM's quarter turn is 0:";COS(1.5707963);COS(ATN(1)*2):F=1
110 S=1:X=TAN(1.5707963)
120 IF S<>2 THEN PRINT "FAIL: TAN(1.5707963) WAS NOT ?/0":F=1
130 S=3:X=TAN(ATN(1)*2)
140 IF S<>4 THEN PRINT "FAIL: TAN(ATN(1)*2) WAS NOT ?/0":F=1
150 IF ABS(TAN(1.5708))<100000 THEN PRINT "FAIL: TAN(1.5708) returns a value (Model III manual p.239):";TAN(1.5708):F=1
160 REM the manual's other example: TAN(90*.01745329) is ?/0 (Model III manual p.239).  The
170 REM reader makes .01745329 one unit above the nearest single (it divides 1745329 by 10 eight
175 REM times, each rounded: 0EC7H-0ED0H), so 90 times it is 1.570796370506287, COS of it 0 and
176 REM TAN ?/0.  With the nearest single (until 2026-10-05) COS was 1.87254E-07.
180 IF COS(90*.01745329)<>0 THEN PRINT "FAIL: COS(90*.01745329):";COS(90*.01745329):F=1
185 S=5:X=TAN(90*.01745329)
186 IF S<>6 THEN PRINT "FAIL: TAN(90*.01745329) WAS NOT ?/0":F=1
200 REM the series' values, printed to six digits
210 IF STR$(SIN(1))<>" .841471" OR STR$(COS(1))<>" .540302" OR STR$(TAN(.5))<>" .546302" THEN PRINT "FAIL: SIN(1) COS(1) TAN(.5):";SIN(1);COS(1);TAN(.5):F=1
220 IF SIN(0)<>0 OR COS(0)<>1 OR TAN(0)<>0 THEN PRINT "FAIL: at 0:";SIN(0);COS(0);TAN(0):F=1
230 IF STR$(SIN(3.14159/2))<>" 1" OR STR$(COS(3.14159))<>"-1" OR STR$(SIN(-1))<>"-.841471" THEN PRINT "FAIL: quadrants:";SIN(3.14159/2);COS(3.14159);SIN(-1):F=1
240 IF STR$(SIN(2.5))<>" .598472" OR STR$(SIN(4))<>"-.756802" OR STR$(SIN(5.5))<>"-.70554" THEN PRINT "FAIL: the four quarters:";SIN(2.5);SIN(4);SIN(5.5):F=1
250 IF STR$(SIN(100))<>"-.506368" OR SIN(1E20)<>0 THEN PRINT "FAIL: many turns:";SIN(100);SIN(1E20):F=1
260 REM an argument below the quarter's resolution is lost in .25-f (the adder), as on the machine
270 IF SIN(1E-9)<>0 THEN PRINT "FAIL: SIN(1E-9):";SIN(1E-9):F=1
300 REM a double argument is a single first (0AB1H), the result a single
310 IF STR$(SIN(1#))<>" .841471" OR STR$(COS(.5#)/3)<>" .292527" THEN PRINT "FAIL: a double argument:";SIN(1#);COS(.5#)/3:F=1
890 ON ERROR GOTO 0:IF F THEN PRINT "TRIG FIXTURE FAILED":ERROR 5
895 PRINT "TRIG FIXTURE OK":END
900 C=ERR/2+1
910 IF (S=1 OR S=3 OR S=5) AND C=11 THEN S=S+1:RESUME NEXT
930 PRINT "FAIL: UNEXPECTED ERROR";C;"IN";ERL;"S=";S:F=1:RESUME NEXT
