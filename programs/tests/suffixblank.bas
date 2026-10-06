10 REM A BLANK BEHIND A # ! % LITERAL ENDS THE EXPRESSION (trs-80.com ROM bug list, bug 7;
20 REM Farvour 0EF2H: the suffix is stepped over by INC HL, not RST 10H, so the blank is the
30 REM next character the evaluator sees).  PRINT takes what follows as a new item; LET has
40 REM stored and is ?SN at the blank; IF, FOR, a parenthesis, a function argument, a
50 REM subscript and DIM are ?SN; the byte readers (ON, POKE's value, OUT, SET, RESET, TAB(,
60 REM the counts of STRING$ LEFT$ RIGHT$ MID$) and CLEAR go on past it.  A name's suffix and
70 REM a blank inside a number are unaffected.  Built 2026-10-05 (the audit's B-7).
80 F=0:S=0:ON ERROR GOTO 900
90 CLS
100 E$=" 2  3 ":L$="PRINT 2# +3":PRINT @0,2# +3;:GOSUB 970
110 E$=" 5  3 ":L$="PRINT 3+2# +3":PRINT @0,3+2# +3;:GOSUB 970
120 E$=" 2  7 ":L$="PRINT 2! +3+4":PRINT @0,2! +3+4;:GOSUB 970
130 E$="-2  3 ":L$="PRINT -2# +3":PRINT @0,-2# +3;:GOSUB 970
140 E$=" 5 -2 ":L$="PRINT 5% -2":PRINT @0,5% -2;:GOSUB 970
150 E$=" 2  3 ":L$="PRINT 2 # +3":PRINT @0,2 # +3;:GOSUB 970
160 E$=" 2  3 ":L$="PRINT 2# ;3":PRINT @0,2# ;3;:GOSUB 970
170 E$=" 2 B":L$="PRINT 2# then a string":PRINT @0,2# "B";:GOSUB 970
180 E$=" 5.5  5  2.5  3 ":L$="no suffix, no break":PRINT @0,2.5 +3;2 +3;2.5# +3;:GOSUB 970
190 E$=" 100001  100001 ":L$="an exponent is no suffix":PRINT @0,1D5 +1;1E5 +1;:GOSUB 970
200 A=2:B=3:E$=" 5  5 ":L$="a name's suffix reads past blanks":PRINT @0,A! +B;A% +B;:GOSUB 970
210 E$=" 2 3":L$="PRINT USING 2# ;3":PRINT @0,USING "##";2# ;3;:GOSUB 970
220 E$="   1 ":L$="TAB(2# )":PRINT @0,TAB(2# );1;:GOSUB 970
230 E$="AAABBCBC":L$="the string counts":PRINT @0,STRING$(2# ,"A");LEFT$("ABC",2# );RIGHT$("ABC",2# );MID$("ABCDE",2# ,2# );:GOSUB 970
240 E$=" 2       3 ":L$="PRINT 2# :PRINT":PRINT @0,2# :PRINT @8,3;:GOSUB 970
250 POKE 16000,2# :IF PEEK(16000)<>2 THEN PRINT "FAIL: POKE's value":F=1
260 ON 1% GOTO 270:PRINT "FAIL: ON 1% GOTO fell through":F=1
270 SET(2# ,3# ):IF POINT(2,3)<>-1 THEN PRINT "FAIL: SET(2# ,3# )":F=1
280 RESET(2# ,3# ):IF POINT(2,3)<>0 THEN PRINT "FAIL: RESET(2# ,3# )":F=1
290 OUT 255,0#
300 REM ---- ?SN, the value stored first where LET is the verb ----
310 A=7:S=1:A=2# +3
320 IF A<>2 THEN PRINT "FAIL: LET stores before the blank is ?SN, A=";A:F=1
330 S=3:X=2# :X=X+7
335 IF X<>9 THEN PRINT "FAIL: X=2# :X=X+7 gives";X:F=1
340 S=5:PRINT (2# +3)
350 S=7:PRINT SQR(4# )
360 S=9:IF 2# =2 THEN F=1
365 IF S<>10 THEN PRINT "FAIL: IF 2# =2 ran"
370 S=11:FOR I=1% TO 3
380 S=13:DIM Q(3% )
390 S=15:PRINT @0,2# * 3;
400 S=17:PRINT @0,USING "##";2# +3;
410 S=19:PRINT STRING$(2,65# )
420 S=21:PRINT PEEK(2# )
430 S=23:PRINT 2# THEN
440 IF S<>24 THEN PRINT "FAIL: an error was missed, S=";S:F=1
450 CLS
890 ON ERROR GOTO 0:IF F THEN PRINT "SUFFIXBLANK FIXTURE FAILED":ERROR 5
895 PRINT "SUFFIXBLANK FIXTURE OK":END
900 C=ERR/2+1
910 IF S=2*INT(S/2)+1 AND C=2 THEN S=S+1:RESUME NEXT
930 PRINT "FAIL: UNEXPECTED ERROR";C;"IN";ERL;"S=";S:F=1:RESUME NEXT
960 REM the top screen row against E$ (and a blank behind it); then the row is cleared and
965 REM the cursor parked on the last row, so a FAIL message never lands in row 0
970 R$="":FOR I=15360 TO 15360+LEN(E$):R$=R$+CHR$(PEEK(I)):NEXT
975 PRINT @0,STRING$(64," ");:PRINT @960,"";
980 IF R$<>E$+" " THEN PRINT "FAIL: ";L$;" [";R$;"]":F=1
990 RETURN
