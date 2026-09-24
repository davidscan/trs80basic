10 REM A string literal alone on the right of LET in a program line stays in
20 REM the line: the ROM's LET does not copy it (1F46H-1F57H), and READ
30 REM points into the DATA text the same way (2240H -> 1F33H).  So the
40 REM address fits an integer and a POKE there changes the string.
50 F=0:DEFINT I
60 PRINT "ONE";"TWO";:A$="HELLO":PRINT
70 V=VARPTR(A$):D=PEEK(V+1)+256*PEEK(V+2)
80 IF D>32767 OR D<17129 THEN PRINT "FAIL literal not in the program image";D:F=1
90 IF PEEK(D-1)<>34 OR PEEK(D)<>72 OR PEEK(D+4)<>79 THEN PRINT "FAIL not the third literal of line 60";PEEK(D-1);PEEK(D):F=1
100 I=PEEK(V+1)+256*PEEK(V+2):IF I<>D THEN PRINT "FAIL the address does not fit an integer":F=1
110 POKE D,74:IF A$<>"JELLO" THEN PRINT "FAIL a POKE into the literal: ";A$:F=1
120 C$=A$:W=VARPTR(C$):IF PEEK(W+1)+256*PEEK(W+2)<>D OR C$<>"JELLO" THEN PRINT "FAIL C$=A$ does not share the bytes":F=1
130 POKE D,72:IF A$<>"HELLO" OR C$<>"HELLO" THEN PRINT "FAIL shared bytes: ";A$;" ";C$:F=1
140 A$="JOIN"+"ED":E=PEEK(V+1)+256*PEEK(V+2):IF E<32768 OR A$<>"JOINED" OR PEEK(E)<>74 THEN PRINT "FAIL a joined string is not in string space";E:F=1
150 A$="BACK":E=PEEK(V+1)+256*PEEK(V+2):IF E>32767 OR PEEK(E)<>66 OR PEEK(E-1)<>34 THEN PRINT "FAIL a literal again goes back to its line";E:F=1
160 READ Q$,U$:X=VARPTR(Q$):Y=VARPTR(U$)
170 QA=PEEK(X+1)+256*PEEK(X+2):UA=PEEK(Y+1)+256*PEEK(Y+2)
180 IF QA>32767 OR PEEK(QA)<>81 OR PEEK(QA-1)<>34 THEN PRINT "FAIL READ of a quoted item";QA:F=1
190 IF UA>32767 OR PEEK(UA)<>80 OR PEEK(UA+4)<>78 THEN PRINT "FAIL READ of an unquoted item";UA:F=1
200 DIM S$(2):S$(1)="ELEMENT":Z=VARPTR(S$(1)):ZA=PEEK(Z+1)+256*PEEK(Z+2)
210 IF ZA>32767 OR PEEK(ZA)<>69 THEN PRINT "FAIL an array element's literal";ZA:F=1
220 REM poking the address cells away and back keeps the literal the string's own
230 Z=Z-65536*(Z<0):POKE Z+1,0:POKE Z+2,60:POKE Z+1,ZA-256*INT(ZA/256):POKE Z+2,INT(ZA/256)
240 IF S$(1)<>"ELEMENT" THEN PRINT "FAIL repoint back to the literal: ";S$(1):F=1
242 REM LET of the same literal again names the same bytes, POKE and all
244 FOR K=1 TO 2:T$="TEST":TV=VARPTR(T$):TA=PEEK(TV+1)+256*PEEK(TV+2):IF K=1 THEN POKE TA,82
246 NEXT:IF T$<>"REST" THEN PRINT "FAIL a re-assigned literal lost its POKE: ";T$:F=1
250 IF F THEN PRINT "LITERAL FIXTURE FAILED":ERROR 5
260 PRINT "LITERAL FIXTURE OK":END
270 REM "QUOTE IN A REM" does not count
280 DATA "QUOTED", PLAIN
