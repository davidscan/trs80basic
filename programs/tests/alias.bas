10 REM STRING ALIASING VIA THE DESCRIPTOR: POKE VARPTR(A$)+1/+2 (seam audit finding 7, built 2026-09-11)
20 REM self-checking batch fixture: ./basic programs/tests/alias.bas exits 1 on any mismatch
30 DIM Z(1):F=0
40 REM --- read direction: alias onto video RAM and read the screen into the string
50 POKE 15360,72:POKE 15361,69:POKE 15362,76:POKE 15363,76:POKE 15364,79
60 A$="     ":V=VARPTR(A$):IF V<0 THEN V=V+65536:REM the ROM's integer is negative above 32767 (L-43)
70 POKE V+1,0:POKE V+2,60
80 IF A$<>"HELLO" THEN PRINT "FAIL read screen through alias: ";A$:F=1
90 IF PEEK(V+1)<>0 OR PEEK(V+2)<>60 THEN PRINT "FAIL poked cells read back";PEEK(V+1);PEEK(V+2):F=1
100 IF PEEK(V)<>5 THEN PRINT "FAIL length byte";PEEK(V):F=1
110 IF MID$(A$,2,3)<>"ELL" THEN PRINT "FAIL MID$ of aliased":F=1
120 IF LEN(A$)<>5 THEN PRINT "FAIL LEN of aliased":F=1
130 REM --- write direction: LSET paints the screen, MID$= pokes one cell
140 LSET A$="WORLD"
150 IF PEEK(15360)<>87 OR PEEK(15364)<>68 THEN PRINT "FAIL LSET write-through";PEEK(15360);PEEK(15364):F=1
160 MID$(A$,1,1)="X"
170 IF PEEK(15360)<>88 THEN PRINT "FAIL MID$= write-through";PEEK(15360):F=1
180 IF A$<>"XORLD" THEN PRINT "FAIL read after write: ";A$:F=1
190 RSET A$="AB"
200 IF PEEK(15360)<>32 OR PEEK(15363)<>65 OR PEEK(15364)<>66 THEN PRINT "FAIL RSET write-through":F=1
210 REM --- the length byte governs how much is seen
220 POKE V,3
230 IF A$<>"   " THEN PRINT "FAIL length 3 view: [";A$;"]":F=1
240 POKE V,5
250 IF A$<>"   AB" THEN PRINT "FAIL length back to 5: [";A$;"]":F=1
260 REM --- an assignment moves the descriptor: alias gone, screen untouched
270 A$="NEW"
280 IF A$<>"NEW" THEN PRINT "FAIL assign after alias: ";A$:F=1
290 IF PEEK(15360)<>32 OR PEEK(15364)<>66 THEN PRINT "FAIL assignment touched the screen":F=1
300 D=PEEK(V+1)+256*PEEK(V+2):IF D=15360 THEN PRINT "FAIL cells still point at video":F=1
310 IF PEEK(D)<>78 THEN PRINT "FAIL cells point at own data";D;PEEK(D):F=1
320 V2=VARPTR(A$):IF V2<0 THEN V2=V2+65536
322 IF V2<>V THEN PRINT "FAIL VARPTR moved":F=1
330 REM --- indirect form and an array element, onto system RAM (4010H)
340 POKE 16400,65:POKE 16401,66:POKE 16402,67
350 DIM B$(2):B$(1)="..."+"":W=VARPTR(B$(1)):IF W<0 THEN W=W+65536
360 L=16400-INT(16400/256)*256:H=INT(16400/256)
370 POKE W+1,L:POKE W+2,H
380 IF B$(1)<>"ABC" THEN PRINT "FAIL array element alias: ";B$(1):F=1
390 IF B$(0)<>"" OR B$(2)<>"" THEN PRINT "FAIL neighbours affected":F=1
400 LSET B$(1)="xyz"
410 IF PEEK(16400)<>120 OR PEEK(16402)<>122 THEN PRINT "FAIL array element write-through":F=1
420 REM --- poking the cells back to the own data clears the alias
430 E=W-3:POKE W+1,E-INT(E/256)*256:POKE W+2,INT(E/256)
440 IF B$(1)<>"..." THEN PRINT "FAIL alias cleared by repoint: ";B$(1):F=1
450 REM --- alias onto a packed string: contract rule 4 resolves it
460 P$="PACKED":Q$="      ":PV=VARPTR(P$):QV=VARPTR(Q$):IF PV<0 THEN PV=PV+65536
462 IF QV<0 THEN QV=QV+65536
470 PD=PEEK(PV+1)+256*PEEK(PV+2)
480 POKE QV+1,PD-INT(PD/256)*256:POKE QV+2,INT(PD/256)
490 IF Q$<>"PACKED" THEN PRINT "FAIL alias onto packed string: ";Q$:F=1
500 MID$(Q$,1,1)="J"
510 IF P$<>"JACKED" THEN PRINT "FAIL write-through into packed string: ";P$:F=1
520 REM --- ordinary strings are untouched throughout
530 C$="PLAIN":C$=C$+"!":IF C$<>"PLAIN!" THEN PRINT "FAIL ordinary string":F=1
540 IF F THEN PRINT "ALIAS FIXTURE FAILED":ERROR 5
550 CLEAR:IF A$<>"" THEN PRINT "ALIAS FIXTURE FAILED: CLEAR":X=1/0
560 PRINT "ALIAS FIXTURE OK"
