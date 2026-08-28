10 REM PALETTE -- colour semigraphics, an extension to LEVEL II.
20 REM SET(x,y,c) lights a pixel AND colours its character cell with one
30 REM of the nine CoCo Color BASIC colours; plain SET or printing over the
40 REM cell returns it to black and white.  POINT ignores colour on purpose.
50 REM Colour shows in the interactive grid only; run ./basic and LOAD this.
60 CLS
70 FOR C=0 TO 8: READ N$(C): NEXT
80 REM ---- a labelled swatch of every colour, one row each ----
90 FOR C=0 TO 8
100 PRINT@ C*64, USING "# ";C;: PRINT N$(C);
110 FOR X=32 TO 63: SET(X,C*3,C): SET(X,C*3+1,C): SET(X,C*3+2,C): NEXT X
120 NEXT C
130 REM ---- a bar chart: monthly rainfall, coloured by how wet ----
140 PRINT@ 640,"RAINFALL (IN):";
150 FOR M=1 TO 12: READ R
160 IF R<2 THEN C=2 ELSE IF R<4 THEN C=1 ELSE C=3
170 H=INT(R*2+.5): IF H>16 THEN H=16
180 FOR Y=0 TO H-1: SET(M*4,47-Y,C): SET(M*4+1,47-Y,C): NEXT Y
190 NEXT M
200 PRINT@ 960,"YELLOW <2  GREEN <4  BLUE 4+   TOTAL";
210 RESTORE: FOR C=0 TO 8: READ N$: NEXT: T=0: FOR M=1 TO 12: READ R: T=T+R: NEXT
220 PRINT USING " ##.#";T;
230 REM ---- a plain SET un-colours a cell; POINT still says lit ----
240 SET(32,0): PRINT@ 62,"P=";POINT(32,0);
250 DATA BLACK,GREEN,YELLOW,BLUE,RED,BUFF,CYAN,MAGENTA,ORANGE
260 DATA 1.2,0.8,1.9,2.6,3.4,4.8,6.1,5.2,3.7,2.1,1.4,0.9
