10 REM PRINT USING: what the ROM does with a number that does not fit, and
20 REM where ^^^^ puts its digits (ROM 10CA-1108, 1110-1123, 11AA-11FE).
30 REM The number is formatted FIRST, then the field's start is looked for:
40 REM a lone 0 before the point gives way (#.## of -.5 is -.50); anything
50 REM else gets a % in front of the FORMATTED number (##.## of 123.456 is
60 REM %123.46, and a trailing sign still follows).  ^^^^ keeps one position
70 REM for the sign unless the field has a leading + or a trailing sign, so
80 REM ##.##^^^^ of 234.56 is " 2.35E+02"; with no # before the point that
90 REM place falls behind it: .####^^^^ of 1234.5 is .0123E+05.
100 REM Until 2026-09-21: %-.5, %123.456, 23.46E+01 and %1234.5.
110 REM The up-arrow is byte 5BH: a period listing shows [[[[, a terminal
115 REM types ^^^^; both are the exponent field (ROM 2D81H).
118 REM USING cannot print into a string, so the screen is read back.
120 F=0:CLS:DIM M$(30)
130 DATA "#.##",-.5,"-.50"
140 DATA "##.##",123.456,"%123.46"
150 DATA "##.##-",-123.456,"%123.46-"
160 DATA "#.##",-1.5,"%-1.50"
170 DATA "##.##",.5," 0.50"
180 DATA ".##",.5,".50"
190 DATA "##.##[[[[",234.56," 2.35E+02"
200 DATA "##.##[[[[",-234.56,"-2.35E+02"
210 DATA ".####[[[[-",888888,".8889E+06 "
220 DATA "+.##[[[[",123,"+.12E+03"
230 DATA "#.##[[[[",123,"0.12E+03"
240 DATA "#.##[[[[",-123,"-.12E+03"
250 DATA ".####^^^^",1234.5,".0123E+05"
260 DATA "##.##^^^^",999.99," 1.00E+03"
270 DATA "##.##[[[[",0," 0.00E+00"
280 DATA "###[[[[",123456," 12E+04"
290 DATA "##.##[[[[",.000123," 1.23E-04"
300 DATA "##,###.##",1E17,"%1E+17"
310 DATA "**##.##",1212.12,"1212.12"
320 DATA "END",0,""
330 READ U$,V,W$:IF U$="END" THEN 400
340 PRINT@0,STRING$(20,32);:PRINT@0,USING U$;V;
350 G$="":FOR I=0 TO LEN(W$)-1:G$=G$+CHR$(PEEK(15360+I)):NEXT
360 IF PEEK(15360+LEN(W$))<>32 THEN G$=G$+"..."
370 IF G$<>W$ THEN F=F+1:M$(F)="FAIL: "+U$+STR$(V)+" GAVE ["+G$+"] NOT ["+W$+"]"
380 GOTO 330
400 CLS:FOR I=1 TO F:PRINT M$(I):NEXT
410 IF F THEN PRINT "USING FIXTURE FAILED":ERROR 5
420 PRINT "USING FIXTURE OK":END
