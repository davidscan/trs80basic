10 REM SIN, COS and TAN are the ROM's routines (1541H-15BAH), step for step in single
20 REM precision: x/2pi, the turn's fraction, folded to [-.25,.25] against .25 (156DH-1584H),
30 REM the five-term series at 1594H (149AH), COS = SIN(x+pi/2), TAN = SIN/COS through the
40 REM divider at 08A2H whose zero test is ?/0.  A quarter turn within one unit of the ROM's
50 REM pi/2 (1.5707963) reduces to exactly 0: COS is 0 and TAN is ?/0.  Until
60 REM 2026-09-27 the host's libm answered on the raw argument (the 2026-09-26 audit, M-12).
62 REM ATN is the ROM's routine too (15BDH-15E2H, since 2026-10-05): the series at 15E3H, for an
64 REM argument of 1 or more on its reciprocal and taken from pi/2.  ATN(1) is .78539824, one
66 REM unit above the nearest single to pi/4, so ATN(1)*2 is NOT the quarter turn: COS of it is
68 REM -3.74507E-07 and TAN a value.  Every sum goes through the single adder (0716H).
70 F=0:S=0:ON ERROR GOTO 900
100 IF COS(1.5707963)<>0 OR COS(1.5707962)<>0 THEN PRINT "FAIL: COS of the ROM's quarter turn is 0:";COS(1.5707963);COS(1.5707962):F=1
110 S=1:X=TAN(1.5707963)
120 IF S<>2 THEN PRINT "FAIL: TAN(1.5707963) WAS NOT ?/0":F=1
130 S=3:X=TAN(ATN(1)*2)
140 IF S<>3 OR STR$(X)<>"-2.67018E+06" OR STR$(COS(ATN(1)*2))<>"-3.74507E-07" THEN PRINT "FAIL: ATN(1)*2 is one unit past the quarter turn:";X;COS(ATN(1)*2):F=1
142 D#=ATN(1):IF STR$(D#)<>" .7853982448577881" OR STR$(ATN(1)*4)<>" 3.14159" THEN PRINT "FAIL: ATN(1):";D#;ATN(1)*4:F=1
144 D#=ATN(10):E#=ATN(.5):IF STR$(D#)<>" 1.47112774848938" OR STR$(E#)<>" .4636476039886475" THEN PRINT "FAIL: ATN(10), ATN(.5):";D#;E#:F=1
146 D#=ATN(2):E#=ATN(-.3):IF STR$(D#)<>" 1.107148766517639" OR STR$(E#)<>"-.2914567887783051" THEN PRINT "FAIL: ATN(2), ATN(-.3):";D#;E#:F=1
148 IF ATN(0)<>0 OR STR$(ATN(1E20))<>" 1.5708" OR ATN(-1)+ATN(1)<>0 OR ATN(.000357708)<>.000357708 OR ATN(1E-20)<>1E-20 THEN PRINT "FAIL: ATN at 0, 1E20, -1, small:";ATN(0);ATN(1E20);ATN(-1);ATN(.000357708):F=1
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
240 IF STR$(SIN(2.5))<>" .598472" OR STR$(SIN(4))<>"-.756802" OR STR$(SIN(5.5))<>"-.705541" THEN PRINT "FAIL: the four quarters:";SIN(2.5);SIN(4);SIN(5.5):F=1
250 IF STR$(SIN(100))<>"-.506368" OR SIN(1E20)<>0 THEN PRINT "FAIL: many turns:";SIN(100);SIN(1E20):F=1
260 REM an argument below the quarter's resolution is lost in .25-f (the adder), as on the machine
270 IF SIN(1E-9)<>0 THEN PRINT "FAIL: SIN(1E-9):";SIN(1E-9):F=1
300 REM a double argument is a single first (0AB1H), the result a single
310 IF STR$(SIN(1#))<>" .841471" OR STR$(COS(.5#)/3)<>" .292528" THEN PRINT "FAIL: a double argument:";SIN(1#);COS(.5#)/3:F=1
890 ON ERROR GOTO 0:IF F THEN PRINT "TRIG FIXTURE FAILED":ERROR 5
895 PRINT "TRIG FIXTURE OK":END
900 C=ERR/2+1
910 IF (S=1 OR S=3 OR S=5) AND C=11 THEN S=S+1:RESUME NEXT
930 PRINT "FAIL: UNEXPECTED ERROR";C;"IN";ERL;"S=";S:F=1:RESUME NEXT
