10 REM LIFE -- Conway's Game of Life on the 128x48 semigraphics grid.
20 REM SET/RESET draw each cell as a 2x2 block; POINT reads one back.
30 REM Run it interactively to watch; in batch mode only the text
40 REM snapshots below appear, since the screen is not streamed.
50 CLS: W=32: H=16: DIM A(W,H),B(W,H),S$(6)
55 PRINT@768,"";: REM park the cursor below the board (row 12)
60 REM a glider (moves one cell diagonally every 4 generations) and a blinker
70 A(2,1)=1: A(3,2)=1: A(1,3)=1: A(2,3)=1: A(3,3)=1
80 A(20,8)=1: A(21,8)=1: A(22,8)=1
90 FOR G=0 TO 8
100 P=0: FOR Y=0 TO H-1: FOR X=0 TO W-1
110 IF A(X,Y) THEN SET(X*2,Y*2): SET(X*2+1,Y*2): SET(X*2,Y*2+1): SET(X*2+1,Y*2+1): P=P+1 ELSE RESET(X*2,Y*2): RESET(X*2+1,Y*2): RESET(X*2,Y*2+1): RESET(X*2+1,Y*2+1)
120 NEXT X: NEXT Y
140 IF G=0 OR G=4 OR G=8 THEN GOSUB 500
150 GOSUB 300
160 NEXT G
170 END
300 REM ---- next generation into B (wrapping edges), then copy back ----
320 FOR Y=0 TO H-1: FOR X=0 TO W-1
330 N=0: FOR DY=-1 TO 1: FOR DX=-1 TO 1
340 IF DX<>0 OR DY<>0 THEN N=N+A((X+DX+W)-INT((X+DX+W)/W)*W,(Y+DY+H)-INT((Y+DY+H)/H)*H)
350 NEXT DX: NEXT DY
360 B(X,Y)=0: IF N=3 OR (N=2 AND A(X,Y)) THEN B(X,Y)=1
380 NEXT X: NEXT Y
390 FOR Y=0 TO H-1: FOR X=0 TO W-1: A(X,Y)=B(X,Y): NEXT X: NEXT Y
400 RETURN
500 REM ---- snapshot of the glider corner, read back with POINT ----
505 REM (PRINT@ puts it beside the board: text printed at the cursor would
506 REM  land on the board and scroll the screen, pixels and all)
510 FOR Y=0 TO 6: S$(Y)=""
520 FOR X=0 TO 9: IF POINT(X*2,Y*2) THEN S$(Y)=S$(Y)+"#" ELSE S$(Y)=S$(Y)+"."
530 NEXT X: NEXT Y
540 PRINT@34,"GEN";G;" POP";P;" TOP-LEFT 10X7:"
550 FOR Y=0 TO 6: PRINT@98+64*Y,"  ";S$(Y): NEXT Y: PRINT@546,""
555 PRINT@768,"";
560 RETURN
