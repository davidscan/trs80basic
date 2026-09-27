10 REM PRINT and STR$ round the sixth digit HALF UP, on the magnitude: the
20 REM ROM scales to six integer digits, adds .5 and truncates (12EA-12F0).
30 REM An exact tie must not go to the even digit.  The ties here are exact in 24 bits: a literal
35 REM is a single first (.3333335 is .33333349 in 24 bits and prints .333333, as on the machine).
40 F=0
50 READ N
60 FOR I=1 TO N:READ X,W$
70 IF STR$(X)<>W$ THEN PRINT "FAIL:";W$;" CAME OUT AS";STR$(X):F=1
80 NEXT
90 IF STR$(1/512)<>" 1.95313E-03" THEN PRINT "FAIL: 1/512 =";STR$(1/512):F=1
100 IF STR$(-1/512)<>"-1.95313E-03" THEN PRINT "FAIL: -1/512 =";STR$(-1/512):F=1
102 REM the form is decided by the shift count (104BH-1057H): fixed only from .01 up to six
104 REM digits (sixteen for a double), E or D notation outside (Richcraft vol. 2 p.97 has
106 REM 7.8125E-03 for 1/128; until 2026-09-27 every value below .01 was fixed, audit M-10)
107 IF STR$(.01)<>" .01" OR STR$(.001)<>" 1E-03" OR STR$(-.001)<>"-1E-03" OR STR$(.0099999)<>" 9.9999E-03" THEN PRINT "FAIL: .01 is the edge:";STR$(.01);STR$(.001);STR$(.0099999):F=1
108 IF STR$(.05#)<>" .05" OR STR$(.001#)<>" 1D-03" OR STR$(1D-4)<>" 1D-04" OR STR$(1.5D-10)<>" 1.5D-10" THEN PRINT "FAIL: a double below .01 is D notation:";STR$(.001#);STR$(1D-4):F=1
109 IF STR$(1.23457E-5)<>" 1.23457E-05" OR STR$(1E-38)<>" 1E-38" OR STR$(1/128)<>" 7.8125E-03" THEN PRINT "FAIL: E form:";STR$(1.23457E-5);STR$(1/128):F=1
110 DATA 9
120 DATA 100000.5," 100001",-100000.5,"-100001",123456.5," 123457"
130 DATA 999999.5," 1E+06",2.5," 2.5",100000.4," 100000"
140 DATA 1.0000045," 1",1.5E-10," 1.5E-10",100002.5," 100003"
150 IF F THEN PRINT "ROUND FIXTURE FAILED":ERROR 5
160 PRINT "ROUND FIXTURE OK":END
