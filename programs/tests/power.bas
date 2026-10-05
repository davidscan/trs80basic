10 REM A minus behind ^ is the ROM's unary minus (2532H): it evaluates what
20 REM follows at precedence 7DH, below ^ and above * and /, and negates
30 REM that.  So 2^-3^2 is 2^-(3^2) = 2^-9, while 2^-3*2 is (2^-3)*2.
40 REM ^ itself stays left-associative, and a plus is only skipped.
50 REM Until 2026-09-21 2^-3^2 was (2^-3)^2 = 1/64.
52 REM ^ is EXP(y*LOG(x)) in single precision (13F2H-1478H), so a power is compared here by
54 REM what it prints: 2^9 is 512.001 and 2^-9 not exactly 1/512, as on the machine.
60 F=0
70 IF STR$(2^-3^2)<>" 1.95312E-03" THEN PRINT "FAIL: 2^-3^2 =";2^-3^2:F=1
80 IF STR$(2^3^2)<>" 64" THEN PRINT "FAIL: 2^3^2 =";2^3^2:F=1
90 IF STR$(2^-3*2)<>" .25" THEN PRINT "FAIL: 2^-3*2 =";2^-3*2:F=1
100 IF STR$(2^+3^2)<>" 64" THEN PRINT "FAIL: 2^+3^2 =";2^+3^2:F=1
110 IF STR$(2^--3^2)<>" 512.001" THEN PRINT "FAIL: 2^--3^2 =";2^--3^2:F=1
120 IF STR$(-2^2)<>"-4" OR STR$(2*-3^2)<>"-18" THEN PRINT "FAIL: -2^2, 2*-3^2 =";-2^2;2*-3^2:F=1
130 X=3:IF STR$(2^-X^2)<>" 1.95312E-03" OR STR$(2^-X)<>" .125" THEN PRINT "FAIL: WITH A VARIABLE";2^-X^2;2^-X:F=1
140 IF F THEN PRINT "POWER FIXTURE FAILED":ERROR 5
150 PRINT "POWER FIXTURE OK":END
