10 REM STARFILE -- a random-access star catalog.
20 REM OPEN "R", FIELD, LSET/RSET, PUT/GET, MKI$/CVI, LOF: fixed 26-byte
30 REM records, fetched by number without reading the whole file.
40 CLS: F$="STARS.DAT"
50 OPEN "R",1,F$,26
60 FIELD 1, 12 AS NM$, 2 AS DI$, 12 AS CN$
70 REM ---- write the catalog ----
80 FOR R=1 TO 6
90 READ N$,D,C$
100 LSET NM$=N$: LSET DI$=MKI$(D): LSET CN$=C$
110 PUT 1,R
120 NEXT R
130 PRINT "WROTE";LOF(1);"RECORDS."
140 REM ---- random reads, out of order ----
150 FOR I=1 TO 3: READ R
160 GET 1,R
170 PRINT "#";R;": ";NM$;CVI(DI$);"LY  ";CN$
180 NEXT I
190 REM ---- update one record in place ----
200 GET 1,4: LSET DI$=MKI$(CVI(DI$)+1): PUT 1,4
210 GET 1,4: PRINT "RECORD 4 NOW READS";CVI(DI$);"LY (IT DRIFTED)."
220 CLOSE 1: KILL F$
230 DATA "SIRIUS",9,"CANIS MAJOR","VEGA",25,"LYRA","BETELGEUSE",548,"ORION"
240 DATA "ALTAIR",17,"AQUILA","DENEB",2615,"CYGNUS","PROCYON",11,"CANIS MINOR"
250 DATA 5,2,6
