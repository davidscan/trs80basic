#!/bin/sh
# stmttail.sh -- a byte behind a complete statement is ?SN.  Every verb
# returns to the execution driver at 1D1EH, which reads the byte at the
# code pointer (1D2CH): a ":" goes on to the next statement (1D5AH), a 00
# ends the line (1D35H), anything else is ?SN (1D32H -> 1997H).  So X=1END
# is ?SN, not an END, and X=1 Y=2 is ?SN, not two assignments.  Until
# 2026-09-25 the leftover started the next statement here, silently.
#
# The verbs that place the pointer themselves are pinned beside it:
#   END, STOP and RETURN refuse a byte of their own (1DAEH, 1DA9H and
#     1EDEH each open with RET NZ, back to the driver's test);
#   RETURN skips the rest of the GOSUB statement (1F03H-1F05H: the DATA
#     scan to ":" or 00), so GOSUB 100 X is fine and X never runs;
#   GOTO, THEN n, ELSE n and ON n GOTO leave the line (1ED8H), so a byte
#     behind the line number is never seen;
#   THEN's statement is dispatched straight from IF (2053H -> 1D5FH);
#   RESUME clears the error flag (1FB7H-1FBBH) BEFORE its tail is tested
#     (1FC4H, 1FCEH), so a handler that ends in RESUME X is entered again
#     for the ?SN;
#   CONT replaces the pointer (1DE4H), so CONT X continues;
#   PRINT's loop owns its tail: 1 2 is the number 12 (0E6CH through
#     RST 10H), and "A""B" is two items (20A0H loops on any other byte).
# Self-checking: exits 1 on a mismatch.  Run from the repo root:
#     sh programs/tests/stmttail.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
tmp=$(mktemp) || exit 2
trap 'rm -f "$tmp"' EXIT
fail() { echo "STMTTAIL FAILED: $1"; printf '%s\n' "$2"; exit 1; }
# a batch run, stdout and stderr in one stream, newlines as blanks
run() { printf '%b' "$1" > "$tmp"; TRS80_Z80= "$here/basic" "$tmp" 2>&1 </dev/null | tr '\n' ' '; }
# a READY transcript, from the first prompt on
repl() { printf '%b' "$1" | TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" 2>&1 | sed -n '/^>/,$p'; }
check() { [ "$2" = "$3" ] || fail "$1" "$2"; }

# 1. the leftover is ?SN, and the statement it would have started never runs
check "X=1END is ?SN, END does not run" \
    "$(run '10 X=1END\n20 PRINT "AFTER"\n')" \
    '?SN ERROR IN 10 '
check "X=1 Y=2 is ?SN" \
    "$(run '10 X=1 Y=2\n20 PRINT Y\n')" \
    '?SN ERROR IN 10 '
check "LET X=1 Y is ?SN" \
    "$(run '10 LET X=1 Y\n')" \
    '?SN ERROR IN 10 '
check "a leftover behind a second statement names the line" \
    "$(run '10 PRINT "A";:X=1 PRINT "B"\n20 PRINT "C"\n')" \
    'A?SN ERROR IN 10 '
check "CLS X is ?SN" \
    "$(run '10 CLS X\n')" \
    '?SN ERROR IN 10 '
check "POKE 16000,1 X is ?SN" \
    "$(run '10 POKE 16000,1 X\n')" \
    '?SN ERROR IN 10 '
check "FOR I=1 TO 2 X=1 is ?SN at the FOR" \
    "$(run '10 FOR I=1 TO 2 X=1\n20 NEXT I\n')" \
    '?SN ERROR IN 10 '
check "NEXT I \"X\" is ?SN (NEXT I X is NEXT IX: the name reader joins them)" \
    "$(run '10 FOR I=1 TO 2\n20 NEXT I "X"\n')" \
    '?SN ERROR IN 20 '
check "ON n GOTO with no jump tests its tail" \
    "$(run '10 X=3:ON X GOTO 100,200 PRINT "NO"\n100 PRINT "ONE"\n200 PRINT "TWO"\n')" \
    '?SN ERROR IN 10 '
check "a statement after THEN tests its tail" \
    "$(run '10 X=1:IF X THEN X=2 Y=3\n20 PRINT X;Y\n')" \
    '?SN ERROR IN 10 '

# 2. the verbs that refuse their own byte, before they act
check "END X is ?SN, nothing ended" \
    "$(run '10 PRINT "A";:END X\n')" \
    'A?SN ERROR IN 10 '
check "STOP X is ?SN, no BREAK" \
    "$(run '10 PRINT "A";:STOP X\n')" \
    'A?SN ERROR IN 10 '
check "RETURN X is ?SN in the subroutine" \
    "$(run '10 GOSUB 100\n20 PRINT "NO"\n100 RETURN X\n')" \
    '?SN ERROR IN 100 '

# 3. the tails that are never seen, or skipped
check "GOSUB 100 X: RETURN skips X" \
    "$(run '10 X=1:GOSUB 100 X=5:PRINT X\n20 END\n100 PRINT "SUB":RETURN\n')" \
    'SUB  1  '
check "GOSUB 100 RETURN: the RETURN is skipped, not run" \
    "$(run '10 GOSUB 100 RETURN\n20 PRINT "BACK":END\n100 PRINT "SUB":RETURN\n')" \
    'SUB BACK '
check "ON n GOSUB list X: RETURN skips to the statement's end" \
    "$(run '10 ON 2 GOSUB 100,200 X=5:PRINT X\n20 END\n100 PRINT "ONE":RETURN\n200 PRINT "TWO":RETURN\n')" \
    'TWO  0  '
check "GOTO 100 X leaves the line" \
    "$(run '10 GOTO 100 X\n20 PRINT "NO"\n100 PRINT "OK"\n')" \
    'OK '
check "THEN 100 X and ELSE 100 X leave the line" \
    "$(run '10 IF 1 THEN 100 X\n20 PRINT "NO"\n100 IF 0 THEN 20 ELSE 200 X\n110 PRINT "NO"\n200 PRINT "OK"\n')" \
    'OK '
check "ON n GOTO with a jump leaves the line" \
    "$(run '10 ON 1 GOTO 100,200 X\n20 PRINT "NO"\n100 PRINT "OK"\n200 PRINT "TWO"\n')" \
    'OK TWO '
check "RESUME NEXT goes on behind the statement that failed" \
    "$(run '10 ON ERROR GOTO 100\n20 PRINT "A";:X=1/0:PRINT "B"\n30 PRINT "C":END\n100 RESUME NEXT\n')" \
    'AB C '
check "RESUME X: the flag is cleared first, so the handler takes the ?SN" \
    "$(run '10 ON ERROR GOTO 100\n20 X=1/0\n30 PRINT "NO"\n100 N=N+1:PRINT "H";N;ERR/2+1:IF N=2 THEN END\n110 RESUME X\n')" \
    'H 1  11  H 2  2  '

# 4. what still runs
check "PRINT 1 2 is 12, PRINT \"A\"\"B\" is two items" \
    "$(run '10 PRINT 1 2;"A""B"\n')" \
    ' 12 AB '
check "IF THEN ELSE both ways, ELSE behind a run branch is skipped" \
    "$(run '10 X=1:IF X THEN PRINT "T"; ELSE PRINT "F";\n20 IF X=0 THEN PRINT "T" ELSE PRINT "F"\n30 IF X THEN 50 ELSE 40\n40 PRINT "NO"\n50 PRINT "OK"\n')" \
    'TF OK '
check "a trailing colon and an empty statement are nothing" \
    "$(run '10 PRINT "A";::PRINT "B":\n')" \
    'AB '
check "NEXT J,I, DEF FN with a body, ON ERROR GOTO 0, STEP" \
    "$(run '10 DEF FNA(X)=X*2+1\n20 FOR I=1 TO 2 STEP 1:FOR J=1 TO 2:S=S+FNA(J):NEXT J,I\n30 ON ERROR GOTO 0:PRINT S\n')" \
    ' 16  '
check "FIELD ... AS, PRINT#, INPUT#, CLOSE, KILL keep their tails" \
    "$(run '10 F$="'"$tmp"'.dat"\n20 OPEN "O",1,F$:PRINT#1,"HELLO":CLOSE 1\n30 OPEN "I",1,F$:INPUT#1,A$:CLOSE 1:PRINT A$;\n40 OPEN "R",1,F$:FIELD 1,4 AS B$:LSET B$="XY":PUT 1,1:GET 1,1:PRINT B$;:CLOSE 1\n50 KILL F$\n')" \
    'HELLOXY  '
rm -f "$tmp.dat"
check "REM, the apostrophe and DATA own their lines" \
    "$(run '10 REM X=1END\n20 DATA 1 2 3:READ A$:PRINT A$;\n30 PRINT "OK" '"'"' Z=1END\n')" \
    '1 2 3OK '

# 5. a line typed at READY goes through the same driver (65535 is the line)
out=$(repl '\nX=1END\nPRINT 1 2\nEND X\n10 PRINT "A":STOP:PRINT "B"\nRUN\nCONT X\n')
want='>X=1END
?SN ERROR
READY
>PRINT 1 2
 12 
READY
>END X
?SN ERROR
READY
>10 PRINT "A":STOP:PRINT "B"
>RUN
A
BREAK IN 10
READY
>CONT X
B
READY
>'
check "the typed line: X=1END ?SN, END X ?SN, CONT X continues" "$out" "$want"

echo "STMTTAIL OK"
