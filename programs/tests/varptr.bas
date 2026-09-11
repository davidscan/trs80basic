10 REM VARPTR IS STABLE AND STRING SPACE DOES NOT LEAK (fixed 2026-09-10)
20 REM self-checking batch fixture: ./basic programs/tests/varptr.bas exits 1 on any mismatch
30 DIM Z(1):F=0
40 A$="ABCDEFGHIJ"
50 IF VARPTR(A$)<>VARPTR(A$) THEN PRINT "FAIL idempotent":F=1
60 V=VARPTR(A$):IF PEEK(V)<>10 THEN PRINT "FAIL len byte":F=1
70 D=PEEK(V+1)+256*PEEK(V+2):IF D<>V-10 THEN PRINT "FAIL data just below descriptor":F=1
80 REM the two-call period idiom must compose the real data address
90 D2=PEEK(VARPTR(A$)+1)+256*PEEK(VARPTR(A$)+2):IF D2<>D THEN PRINT "FAIL two-call idiom";D2;D:F=1
100 POKE D2,90:IF LEFT$(A$,1)<>"Z" THEN PRINT "FAIL write-through via two-call address":F=1
110 REM the inline pack loop must neither die nor miss
120 B$=STRING$(200,65)
130 FOR I=0 TO 199:POKE PEEK(VARPTR(B$)+1)+256*PEEK(VARPTR(B$)+2)+I,66:NEXT
140 IF B$<>STRING$(200,66) THEN PRINT "FAIL inline pack loop":F=1
150 REM 2000 calls must not exhaust string space
160 FOR I=1 TO 2000:X=VARPTR(B$):NEXT:IF X<>VARPTR(B$) THEN PRINT "FAIL stable across loop":F=1
170 REM same-length reassignment keeps the same bytes live
180 A$="0123456789":IF PEEK(D)<>48 THEN PRINT "FAIL live read after same-length assign":F=1
190 REM growth repoints the descriptor, descriptor itself stays put
200 A$=A$+"XYZ":IF VARPTR(A$)<>V THEN PRINT "FAIL descriptor moved on growth":F=1
210 IF PEEK(V)<>13 THEN PRINT "FAIL len after growth":F=1
220 D3=PEEK(V+1)+256*PEEK(V+2):IF PEEK(D3+12)<>90 THEN PRINT "FAIL data after growth";PEEK(D3+12):F=1
230 REM shrinking never moves anything
240 A$="AB":IF VARPTR(A$)<>V OR PEEK(V+1)+256*PEEK(V+2)<>D3 THEN PRINT "FAIL shrink moved data":F=1
250 REM numerics and array elements are stable too
260 N=5:IF VARPTR(N)<>VARPTR(N) THEN PRINT "FAIL numeric idempotent":F=1
270 DIM S$(3):S$(2)="HI":IF VARPTR(S$(2))<>VARPTR(S$(2)) THEN PRINT "FAIL array element idempotent":F=1
280 IF VARPTR(S$(1))=VARPTR(S$(2)) THEN PRINT "FAIL distinct elements share a descriptor":F=1
290 REM the USR vector poked through two VARPTR calls must point at the string
300 POKE 16526,PEEK(VARPTR(B$)+1):POKE 16527,PEEK(VARPTR(B$)+2)
310 IF PEEK(PEEK(16526)+256*PEEK(16527))<>66 THEN PRINT "FAIL vector via two-call":F=1
320 IF F THEN PRINT "VARPTR FIXTURE FAILED":Z(9)=0
330 PRINT "VARPTR FIXTURE OK"
