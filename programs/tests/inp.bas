10 REM INP(p) READS A PORT (built 2026-09-11): port 255 is the cassette/video-mode port, the rest open bus
20 REM self-checking batch fixture: ./basic programs/tests/inp.bas exits 1 on any mismatch
30 DIM Z(1):F=0
40 IF INP(255)<>127 THEN PRINT "FAIL port 255 in 64-char mode";INP(255):F=1
50 PRINT CHR$(23);:IF INP(255)<>63 THEN PRINT "FAIL port 255 in 32-char mode";INP(255):F=1
60 CLS:IF INP(255)<>127 THEN PRINT "FAIL CLS restores 64-char mode";INP(255):F=1
70 IF INP(0)<>255 OR INP(232)<>255 OR INP(240)<>255 OR INP(99)<>255 THEN PRINT "FAIL other ports read 255":F=1
80 IF INP(254.9)<>255 THEN PRINT "FAIL argument truncates":F=1
90 IF (INP(232) AND 16)<>16 THEN PRINT "FAIL RS-232 status idiom":F=1
100 OUT 255,4:IF INP(255)<>127 THEN PRINT "FAIL OUT does not disturb INP":F=1
110 ON ERROR GOTO 140
120 X=INP(256):PRINT "FAIL INP(256) should be ?FC":F=1:GOTO 150
130 GOTO 150
140 IF ERR/2+1<>5 THEN PRINT "FAIL wrong error for INP(256)";ERR/2+1:F=1
145 RESUME 150
150 ON ERROR GOTO 0
160 IF F THEN PRINT "INP FIXTURE FAILED":ERROR 5
170 PRINT "INP FIXTURE OK"
