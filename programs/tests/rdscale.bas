10 REM THE READER SCALES BY TEN ONE ROUNDED STEP AT A TIME: it takes the digits as a number,
20 REM then multiplies or divides by 10 once for each digit behind the point, less the exponent,
30 REM each a rounded single operation (0EC7H-0ED0H, 0F0AH, 0F18H).  So the literal .29 is
40 REM 29/10/10, 0.29000002, one unit above the nearest single, and .000001 is 1/10 six times.
50 REM READ and INPUT into a single scale the same way; into a double, and VAL, enter as a double
60 REM (0E65H): .29 is exact there, 12% is ?SN.  An E or ! converts to single, then scales.
70 REM Until 2026-10-05 a single was the nearest single to the text.
80 CLEAR 200:F=0:S=0:ON ERROR GOTO 900:DEFDBL D
100 D=.29:IF STR$(D)<>" .2900000214576721" THEN PRINT "FAIL: .29 is 29/10/10:";D:F=1
110 IF .29<>29/10/10 OR .29=29/100 THEN PRINT "FAIL: .29 against 29/10/10 and 29/100":F=1
120 D=.000001:IF STR$(D)<>" 9.99999883788405D-07" THEN PRINT "FAIL: .000001:";D:F=1
130 D=1.5E10:IF STR$(D)<>" 15000000512" THEN PRINT "FAIL: 1.5E10:";D:F=1
140 D=29E-2:E=2.9E-1:IF D<>.29 OR E<>.29 THEN PRINT "FAIL: 29E-2, 2.9E-1:";D;E:F=1
150 D=.29#:IF STR$(D)<>" .29" THEN PRINT "FAIL: .29# is exact:";D:F=1
160 D=8740.1129893920E-9:IF STR$(D)<>" 8.740114935790189D-06" THEN PRINT "FAIL: an E literal of 14 digits is single, then scaled:";D:F=1
200 READ X,D:IF X<>.29 OR STR$(D)<>" .29" THEN PRINT "FAIL: READ into a single, a double:";X;D:F=1
210 READ D:IF STR$(D)<>" .2900000214576721" THEN PRINT "FAIL: READ of an E item into a double:";D:F=1
220 D=VAL(".29"):IF STR$(D)<>" .29" THEN PRINT "FAIL: VAL is a double:";D:F=1
230 D=VAL(".29E0"):IF STR$(D)<>" .2900000214576721" THEN PRINT "FAIL: VAL of an E item:";D:F=1
240 READ X:IF X<>12 THEN PRINT "FAIL: 12% into a single:";X:F=1
250 S=1:READ D
260 IF S<>2 THEN PRINT "FAIL: 12% into a double is not ?SN":F=1
300 DATA .29,.29,.29E0,12%,12%
890 ON ERROR GOTO 0:IF F THEN PRINT "RDSCALE FIXTURE FAILED":ERROR 5
895 PRINT "RDSCALE FIXTURE OK":END
900 C=ERR/2+1
910 IF S=1 AND C=2 THEN S=2:RESUME 260
930 PRINT "FAIL: UNEXPECTED ERROR";C;"IN";ERL;"S=";S:F=1:RESUME 890
