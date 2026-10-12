10 REM CMD"T" AND CMD"R" -- Disk BASIC's clock-interrupt switches -- do nothing and the
20 REM program goes on (EXT, st_cmd in p80; Barden, More TRS-80 Assembly-Language
30 REM Programming p.269).  Only the exact strings "T" and "R", alone in their statement;
40 REM every other CMD string is still ?SN.  Built 2026-10-12.
50 F=0:S=0:E=0:ON ERROR GOTO 900
60 N=0:CMD"T":N=N+1:CMD"R":N=N+1
70 IF N<>2 THEN PRINT "FAIL: CMD"+CHR$(34)+"T"+CHR$(34)+":... did not go on, N=";N:F=1
80 N=0:CMD "T":N=N+1:CMD "R" :N=N+1
90 IF N<>2 THEN PRINT "FAIL: CMD with blanks, N=";N:F=1
100 N=0:IF 1 THEN CMD"T" ELSE N=9
110 IF N<>0 THEN PRINT "FAIL: THEN CMD"+CHR$(34)+"T"+CHR$(34)+" ELSE ran the ELSE":F=1
120 IF 0 THEN N=9 ELSE CMD"R":N=N+1
130 IF N<>1 THEN PRINT "FAIL: ELSE CMD"+CHR$(34)+"R"+CHR$(34)+":N=N+1, N=";N:F=1
135 IF E<>0 THEN PRINT "FAIL: CMD"+CHR$(34)+"T"+CHR$(34)+" OR CMD"+CHR$(34)+"R"+CHR$(34)+" RAISED";E;"ERRORS":F=1
140 E=0:S=1:CMD"S"
150 S=3:CMD"TIME"
160 S=5:CMD"t"
170 S=7:CMD"T"X
180 S=9:CMD"R",1
190 S=11:CMD"D"
200 IF E<>6 THEN PRINT "FAIL: only";E;"OF THE 6 OTHER CMD FORMS WERE ?SN":F=1
210 A$="T":E=0:S=13:CMD A$
220 IF E<>1 THEN PRINT "FAIL: CMD A$ is not ?SN":F=1
800 ON ERROR GOTO 0:IF F THEN PRINT "CMDTR FIXTURE FAILED":ERROR 5
810 PRINT "CMDTR OK":END
900 IF ERR<>2 THEN PRINT "FAIL: S=";S;"WAS ERROR";ERR/2+1;"NOT ?SN":F=1
910 E=E+1:RESUME NEXT
