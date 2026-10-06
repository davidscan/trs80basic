#!/bin/sh
# mem.sh -- MEM, FRE and CLEAR n are the ROM's arithmetic (p75, mem_*).
# MEM and FRE(n) are the stack pointer less the end of the arrays (27C9H,
# 27D4H); FRE(a$) is the string area less the strings in it (27E5H-27F2H);
# the area is 50 bytes below the top of memory at power-on (00EFH) and n
# bytes below after CLEAR n (1E7AH-1E9CH), which is ?FC negative, ?OV past
# 32767 and ?OM when it would reach the program.  The anchor is the
# manual's own number: PRINT MEM on a 16K machine with no program is
# 15572.  Until 2026-09-25 MEM and FRE were that constant and CLEAR n was
# thrown away (the 2026-09-23 audit, L-15, L-4).
# Self-checking: exits 1 on a mismatch.  Run from the repo root:
#     sh programs/tests/mem.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
fail() { echo "MEM FAILED: $1"; printf '%s\n' "$2"; exit 1; }
repl() { printf '%b' "$2" | TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" -- --memsize "$1" 2>&1 | sed -n '/^>/,$p'; }

# the 16K map with no program: 32767 - 50 - 17131 - 14
out=$(repl 32767 'PRINT MEM\nPRINT FRE(0)\nPRINT FRE("")\nA$="HELLO"+"!":PRINT FRE("")\nCLEAR 1000:PRINT FRE("");MEM\nCLEAR -1\nCLEAR 40000\nCLEAR 32000\nCLEAR\nPRINT FRE("")\n')
want='>PRINT MEM
 15572 
READY
>PRINT FRE(0)
 15572 
READY
>PRINT FRE("")
 50 
READY
>A$="HELLO"+"!":PRINT FRE("")
 44 
READY
>CLEAR 1000:PRINT FRE("");MEM
 1000  14622 
READY
>CLEAR -1
?FC ERROR
READY
>CLEAR 40000
?OV ERROR
READY
>CLEAR 32000
?OM ERROR
READY
>CLEAR
READY
>PRINT FRE("")
 1000 
READY
>'
[ "$out" = "$want" ] || fail "MEM, FRE and CLEAR n at READY on a 16K map" "$out"

# the 48K map: 65535 - 50 - 17131 - 14
out=$(repl 65535 'PRINT MEM\n')
[ "$out" = '>PRINT MEM
 48340 
READY
>' ] || fail "MEM on the 48K map" "$out"

# in a program: a literal in its line takes no string space, a built string
# its length; a single is 7 bytes, a string 6, DIM C(9) 48 (6 + 2 + 10 * 4);
# a GOSUB frame is 5 (1EB7H-1EC0H; it was 6 until 2026-10-05, BL-2) and
# a FOR frame 17; CLEAR's errors keep the variables
out=$(repl 32767 '10 A$="HELLO":PRINT FRE("");MEM\n20 B$="HEL"+"LO":PRINT FRE("");MEM\n30 DIM C(9):PRINT MEM\n40 X=MEM:GOSUB 100\n50 FOR I=1 TO 1:PRINT X-MEM:NEXT\n60 DEFINT J:J=1:PRINT X-MEM\n70 CLEAR 32000\n80 PRINT "NOT REACHED"\n100 PRINT X-MEM:RETURN\nRUN\nPRINT A$;B$;X\n')
want='>10 A$="HELLO":PRINT FRE("");MEM
>20 B$="HEL"+"LO":PRINT FRE("");MEM
>30 DIM C(9):PRINT MEM
>40 X=MEM:GOSUB 100
>50 FOR I=1 TO 1:PRINT X-MEM:NEXT
>60 DEFINT J:J=1:PRINT X-MEM
>70 CLEAR 32000
>80 PRINT "NOT REACHED"
>100 PRINT X-MEM:RETURN
>RUN
 50  15400 
 45  15394 
 15346 
 5 
 24 
 12 
?OM ERROR IN 70
READY
>PRINT A$;B$;X
HELLOHELLO 15339 
READY
>'
[ "$out" = "$want" ] || fail "MEM's arithmetic inside a program" "$out"

# a variable READ in an expression is never created (the lookup called from
# the evaluator answers a zero and allocates nothing, 269CH -> 26D5H), and
# LET makes its target BEFORE the expression is evaluated (1F21H, then
# 1F2EH): X=MEM counts X, PRINT Y;Z;Y$ costs nothing, and a target whose
# expression fails is there afterwards; FOR's index is stored before the
# frame is pushed, so the body sees the frame alone.  Until 2026-09-27 every read cost
# 7 or 6 bytes and X=MEM missed X (the 2026-09-26 audit, M-8).
out=$(repl 32767 'PRINT Y;Z;Y$;MEM
PRINT MEM
X=MEM:PRINT X-MEM
Z=1/0
PRINT MEM
FOR I=MEM TO 0:PRINT I-MEM:NEXT
')
want='>PRINT Y;Z;Y$;MEM
 0  0  15572 
READY
>PRINT MEM
 15572 
READY
>X=MEM:PRINT X-MEM
 0 
READY
>Z=1/0
?/0 ERROR
READY
>PRINT MEM
 15558 
READY
>FOR I=MEM TO 0:PRINT I-MEM:NEXT
 17 
READY
>'
[ "$out" = "$want" ] || fail "a read never creates a variable; LET creates its target first" "$out"

# ?OS: a string that does not fit the area is Out of String Space (28C0H-
# 28DDH), and the old value still counts while the new one is made; a
# literal in a program line, and a READ from DATA, take none of it
out=$(repl 32767 'CLEAR 10:A$=STRING$(20,"X")\nPRINT LEN(A$)\nCLEAR 30:A$=STRING$(20,"X"):A$=STRING$(20,"X")\nPRINT LEN(A$);FRE("")\n10 CLEAR 30:A$="ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789":READ B$:PRINT FRE("")\n20 ON ERROR GOTO 100:C$=A$+"X"\n30 PRINT "NOT REACHED"\n90 DATA "0123456789012345678901234567890123456789"\n100 PRINT ERR/2+1;ERL;LEN(C$):END\nRUN\n')
want='>CLEAR 10:A$=STRING$(20,"X")
?OS ERROR
READY
>PRINT LEN(A$)
 0 
READY
>CLEAR 30:A$=STRING$(20,"X"):A$=STRING$(20,"X")
?OS ERROR
READY
>PRINT LEN(A$);FRE("")
 20  10 
READY
>10 CLEAR 30:A$="ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789":READ B$:PRINT FRE("")
>20 ON ERROR GOTO 100:C$=A$+"X"
>30 PRINT "NOT REACHED"
>90 DATA "0123456789012345678901234567890123456789"
>100 PRINT ERR/2+1;ERL;LEN(C$):END
>RUN
 30 
 14  20  0 
READY
>'
[ "$out" = "$want" ] || fail "?OS" "$out"

# ?OM: a GOSUB, a FOR or a DIM that the free memory cannot hold (1963H-
# 197AH, with its 58-byte margin), so a runaway recursion ends (at 3099
# five-byte GOSUB frames on a 16K map; 2583 while they counted 6); ERR/2+1
# is 7, and the variables stay
out=$(repl 32767 '10 N=N+1:GOSUB 10\nRUN\nPRINT N\nNEW\n10 ON ERROR GOTO 100\n20 D=D+1:IF D<2500 THEN GOSUB 20\n25 IF D=2500 THEN PRINT "DEPTH OK";D\n27 D=D-1:IF D>0 THEN RETURN\n30 DIM A(3000):PRINT "DIM OK":DIM B(5000)\n40 PRINT "NOT REACHED"\n100 PRINT ERR/2+1;ERL;MEM>0:END\nRUN\n')
want='>10 N=N+1:GOSUB 10
>RUN
?OM ERROR IN 10
READY
>PRINT N
 3099 
READY
>NEW
READY
>10 ON ERROR GOTO 100
>20 D=D+1:IF D<2500 THEN GOSUB 20
>25 IF D=2500 THEN PRINT "DEPTH OK";D
>27 D=D-1:IF D>0 THEN RETURN
>30 DIM A(3000):PRINT "DIM OK":DIM B(5000)
>40 PRINT "NOT REACHED"
>100 PRINT ERR/2+1;ERL;MEM>0:END
>RUN
DEPTH OK 2500 
DIM OK
 7  30 -1 
READY
>'
[ "$out" = "$want" ] || fail "?OM" "$out"

# an entry is 3 bytes and its value: 2 for an integer, 4 a single, 8 a
# double, typed by the reference's suffix before the DEF table; an array
# is 6 + 2 per dimension + its elements at that size.  The entry keeps the
# type it was made with: a DEFDBL after V%=1 does not resize V.  Until
# 2026-09-29 the size came from the DEF table alone, so Z% cost 7 and
# DIM A%(9) 48 (the 2026-09-26 audit, R-8, its accounting half)
out=$(repl 32767 '10 M=MEM:Z%=1:Y#=1:X!=1:PRINT M-MEM\n20 M=MEM:READ R#:FOR I%=1 TO 1:NEXT:DIM Q%:PRINT M-MEM\n30 M=MEM:DIM A%(9),B#(9):C%(1)=1:PRINT M-MEM\n40 M=MEM:V%=1:DEFDBL V:W=1:PRINT M-MEM\n50 DATA 1\nRUN\n')
want='>10 M=MEM:Z%=1:Y#=1:X!=1:PRINT M-MEM
>20 M=MEM:READ R#:FOR I%=1 TO 1:NEXT:DIM Q%:PRINT M-MEM
>30 M=MEM:DIM A%(9),B#(9):C%(1)=1:PRINT M-MEM
>40 M=MEM:V%=1:DEFDBL V:W=1:PRINT M-MEM
>50 DATA 1
>RUN
 23 
 21 
 146 
 12 
READY
>'
[ "$out" = "$want" ] || fail "type sizes" "$out"

echo "MEM OK"
