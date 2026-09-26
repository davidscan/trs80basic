10 REM ORACLE -- ask a local LLM a yes/no question through the OLLAMA channel.
20 REM PRINT# builds the prompt, LINE INPUT# sends it and reads the reply.
30 REM @TOKENS forces line 1 of the reply to be one of the listed words,
40 REM so the program can branch on it; the prose follows on later lines.
50 REM Needs Ollama running locally and TRS80_OLLAMA_MODEL set (or name the
55 REM model in the OPEN: "OLLAMA:llama3.2").  The test runner uses a stub.
60 CLEAR 2000: CLS: PRINT "THE ORACLE IS LISTENING."
70 ON ERROR GOTO 500
80 OPEN "O",1,"OLLAMA"
100 PRINT #1,"@THINK 0"
110 PRINT #1,"You are a terse oracle. Answer in one sentence."
120 LINE INPUT "ASK A YES/NO QUESTION: ";Q$
130 IF Q$="" THEN 300
140 PRINT #1,"@TOKENS YES,NO,UNCLEAR"
150 PRINT #1,Q$
160 LINE INPUT #1,V$
170 IF V$="YES" THEN PRINT "THE ORACLE NODS." ELSE IF V$="NO" THEN PRINT "THE ORACLE SHAKES ITS HEAD." ELSE PRINT "THE MISTS DO NOT PART."
180 IF EOF(1) THEN 220
190 LINE INPUT #1,L$: PRINT "  ";L$
200 GOTO 180
220 PRINT "(";LOC(1);"MESSAGES IN THIS CONVERSATION)": PRINT: GOTO 120
300 CLOSE 1: PRINT "THE ORACLE RETURNS TO SLEEP.": END
500 PRINT "NO ORACLE ANSWERS (IS OLLAMA RUNNING ON LOCALHOST:11434?)": END
