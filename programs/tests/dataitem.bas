10 REM READ and malformed DATA (ROM 225A-2260).  After an item the ROM
20 REM wants a comma or the end of the statement.  DATA "AB"CD has neither
30 REM behind its closing quote, and a quoted "12" read into a number
40 REM leaves the reader sitting on the quote: both are ?SN in the DATA
50 REM line WHEN READ REACHES the item, and the pointer stays on it.
55 REM Blank, tab and line feed behind the quote are skipped (RST 10H).
60 REM Until 2026-09-21 the first dropped the rest of its line silently
70 REM and the second read as 12.  What the reader took is STORED first
75 REM (2240-224A; BL-7): 0 for the quoted 12, AB for "AB"CD (until
76 REM 2026-10-08 the variable kept its old value).
80 F=0:S=0:ON ERROR GOTO 900
90 READ A$,B$:IF A$<>"OK" OR B$<>"X,Y" THEN PRINT "FAIL: QUOTED ITEMS ";A$;"/";B$:F=1
100 READ C$:IF C$<>"OPEN" THEN PRINT "FAIL: A QUOTE LEFT OPEN AT THE LINE'S END ";C$:F=1
110 S=1:C=7:READ C
120 IF S<>2 OR C<>0 THEN PRINT "FAIL: A QUOTED 12 READ INTO A NUMBER WAS NOT ?SN";C:F=1
130 READ C$:IF C$<>"12" THEN PRINT "FAIL: THE POINTER MOVED OFF THE QUOTED 12 ";C$:F=1
140 READ D$:IF D$<>"GOOD" THEN PRINT "FAIL: THE ITEM BEFORE THE BAD ONE ";D$:F=1
150 S=3:E$="KEPT":READ E$
160 IF S<>4 OR E$<>"AB" THEN PRINT "FAIL: TEXT BEHIND A CLOSING QUOTE WAS NOT ?SN ";E$:F=1
170 S=5:READ E$
180 IF S<>6 THEN PRINT "FAIL: THE POINTER MOVED OFF THE BAD ITEM":F=1
190 ON ERROR GOTO 0:IF F THEN PRINT "DATAITEM FIXTURE FAILED":ERROR 5
200 PRINT "DATAITEM FIXTURE OK":END
300 DATA "OK"	 , "X,Y"	
310 DATA "OPEN
320 DATA "12"
330 DATA GOOD,"AB"CD,EF
900 C9=ERR/2+1
910 IF S=1 AND C9=2 AND ERL=320 THEN S=2:RESUME NEXT
920 IF (S=3 OR S=5) AND C9=2 AND ERL=330 THEN S=S+1:RESUME NEXT
930 PRINT "FAIL: ERROR";C9;"IN";ERL;"AT STEP";S:F=1:RESUME NEXT
