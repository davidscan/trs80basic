#!/bin/sh
# mem.sh -- MEM, FRE and CLEAR n are the ROM's arithmetic (p75, mem_*).
# MEM and FRE(n) are the stack pointer less the end of the arrays (27C9H,
# 27D4H); FRE(a$) is the string area less the strings in it (27E5H-27F2H);
# the area is 50 bytes below the top of memory at power-on (00EFH) and n
# bytes below after CLEAR n (1E7AH-1E9CH), which is ?FC negative, ?OV past
# 32767 and ?OM when it would reach the program.  The manual prints 15572
# for PRINT MEM on a 16K machine with no program; ROM 1.3 says 15568 at
# MEM SIZE 32767, which it stores as 32765 (00DEH, 00E7H), and inside the
# PRINT the evaluator holds 2 more bytes (the 2026-09-30 audit, p60 e_or).  Until
# 2026-09-25 MEM and FRE were
# the constant 15572 and CLEAR n was thrown away (the 2026-09-23 audit).
# Self-checking: exits 1 on a mismatch.  Run from the repo root:
#     sh programs/tests/mem.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
fail() { echo "MEM FAILED: $1"; printf '%s\n' "$2"; exit 1; }
repl() { printf '%b' "$2" | TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" -- --memsize "$1" 2>&1 | sed -n '/^>/,$p'; }

# the 16K map with no program: 32765 - 50 - 17131 - 14 - 2
out=$(repl 32767 'PRINT MEM\nPRINT FRE(0)\nPRINT FRE("")\nA$="HELLO"+"!":PRINT FRE("")\nCLEAR 1000:PRINT FRE("");MEM\nCLEAR -1\nCLEAR 40000\nCLEAR 32000\nCLEAR\nPRINT FRE("")\n')
want='>PRINT MEM
 15568 
READY
>PRINT FRE(0)
 15568 
READY
>PRINT FRE("")
 50 
READY
>A$="HELLO"+"!":PRINT FRE("")
 44 
READY
>CLEAR 1000:PRINT FRE("");MEM
 1000  14618 
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

# the 48K map: 65535 - 50 - 17131 - 14 - 2 (ENTER; --memsize past 65529
# is ENTER, since the machine's reader refuses it)
out=$(repl 65535 'PRINT MEM\n')
[ "$out" = '>PRINT MEM
 48338 
READY
>' ] || fail "MEM on the 48K map" "$out"

# in a program: a literal in its line takes no string space, a built string
# its length; a single is 7 bytes, a string 6, DIM C(9) 48 (6 + 2 + 10 * 4);
# a GOSUB frame is 5 (1EB7H-1EC0H; it was 6 until 2026-10-05) and
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
 50  15396 
 45  15390 
 15342 
 15 
 34 
 22 
?OM ERROR IN 70
READY
>PRINT A$;B$;X
HELLOHELLO 15333 
READY
>'
[ "$out" = "$want" ] || fail "MEM's arithmetic inside a program" "$out"

# a variable READ in an expression is never created (the lookup called from
# the evaluator answers a zero and allocates nothing, 269CH -> 26D5H), and
# LET makes its target BEFORE the expression is evaluated (1F21H, then
# 1F2EH): X=MEM counts X, PRINT Y;Z;Y$ costs nothing, and a target whose
# expression fails is there afterwards; FOR's index is stored before the
# frame is pushed, so the body sees the frame alone.  Until 2026-09-27 every read cost
# 7 or 6 bytes and X=MEM missed X (the 2026-09-26 audit).
out=$(repl 32767 'PRINT Y;Z;Y$;MEM
PRINT MEM
X=MEM:PRINT X-MEM
Z=1/0
PRINT MEM
FOR I=MEM TO 0:PRINT I-MEM:NEXT
')
want='>PRINT Y;Z;Y$;MEM
 0  0  15568 
READY
>PRINT MEM
 15568 
READY
>X=MEM:PRINT X-MEM
 10 
READY
>Z=1/0
?/0 ERROR
READY
>PRINT MEM
 15554 
READY
>FOR I=MEM TO 0:PRINT I-MEM:NEXT
 25 
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
 3095 
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
# DIM A%(9) 48 (the 2026-09-26 audit, its accounting half)
out=$(repl 32767 '10 M=MEM:Z%=1:Y#=1:X!=1:PRINT M-MEM\n20 M=MEM:READ R#:FOR I%=1 TO 1:NEXT:DIM Q%:PRINT M-MEM\n30 M=MEM:DIM A%(9),B#(9):C%(1)=1:PRINT M-MEM\n40 M=MEM:V%=1:DEFDBL V:W=1:PRINT M-MEM\n50 DATA 1\nRUN\n')
want='>10 M=MEM:Z%=1:Y#=1:X!=1:PRINT M-MEM
>20 M=MEM:READ R#:FOR I%=1 TO 1:NEXT:DIM Q%:PRINT M-MEM
>30 M=MEM:DIM A%(9),B#(9):C%(1)=1:PRINT M-MEM
>40 M=MEM:V%=1:DEFDBL V:W=1:PRINT M-MEM
>50 DATA 1
>RUN
 33 
 31 
 156 
 22 
READY
>'
[ "$out" = "$want" ] || fail "type sizes" "$out"

# ?OS while an expression builds a string (2857H -> 28BFH, Farvour): every
# string it makes (a concatenation 298FH, LEFT$/RIGHT$/MID$ 2A61H, CHR$
# 2A1FH, STRING$ 2A2FH, STR$ 2836H) is allocated as it is made, and must
# fit beside the variables' strings and the temporaries still held -- the
# left operand of a + or a relation, LEFT$'s string argument (2A73H), but
# not STRING$'s character (2A47H lets it go first).  LET copies a
# variable's string from string space (1F5FH -> 2843H) and leaves one
# that points into its line.  Each case on both sides of its limit.
# Until 2026-10-27 only stores counted: LEN(A$+A$) at 17 was 34, CHR$
# beside 50 bytes printed, B$=A$ took nothing.
out=$(repl 32767 'CLEAR 50:A$=STRING$(16,"A"):PRINT LEN(A$+A$)\nCLEAR 50:A$=STRING$(17,"A"):PRINT LEN(A$+A$)\nCLEAR 50:A$=STRING$(8,"A"):PRINT LEN(A$+A$+A$)\nCLEAR 50:A$=STRING$(10,"A"):PRINT LEN(A$+A$+A$)\nCLEAR 50:A$=STRING$(49,"A"):PRINT CHR$(65)\nCLEAR 50:A$=STRING$(50,"A"):PRINT CHR$(65)\nCLEAR 50:A$=STRING$(45,"A"):PRINT STR$(1234)\nCLEAR 50:A$=STRING$(46,"A"):PRINT STR$(1234)\nCLEAR 50:A$=STRING$(19,"A"):PRINT LEN(LEFT$(A$+"B",10))\nCLEAR 50:A$=STRING$(20,"A"):PRINT LEN(LEFT$(A$+"B",10))\nCLEAR 50:A$=STRING$(10,"A"):PRINT LEN(STRING$(39,A$+"B"))\nCLEAR 50:A$=STRING$(15,"A"):IF A$+A$=A$+A$ THEN PRINT "EQ"\nCLEAR 50:A$=STRING$(20,"A"):PRINT FRE(A$+A$)\n10 A$=STRING$(10,"A"):B$=A$:C$="XY":D$=C$:PRINT FRE("")\nRUN\n')
want='>CLEAR 50:A$=STRING$(16,"A"):PRINT LEN(A$+A$)
 32 
READY
>CLEAR 50:A$=STRING$(17,"A"):PRINT LEN(A$+A$)
?OS ERROR
READY
>CLEAR 50:A$=STRING$(8,"A"):PRINT LEN(A$+A$+A$)
 24 
READY
>CLEAR 50:A$=STRING$(10,"A"):PRINT LEN(A$+A$+A$)
?OS ERROR
READY
>CLEAR 50:A$=STRING$(49,"A"):PRINT CHR$(65)
A
READY
>CLEAR 50:A$=STRING$(50,"A"):PRINT CHR$(65)
?OS ERROR
READY
>CLEAR 50:A$=STRING$(45,"A"):PRINT STR$(1234)
 1234
READY
>CLEAR 50:A$=STRING$(46,"A"):PRINT STR$(1234)
?OS ERROR
READY
>CLEAR 50:A$=STRING$(19,"A"):PRINT LEN(LEFT$(A$+"B",10))
 10 
READY
>CLEAR 50:A$=STRING$(20,"A"):PRINT LEN(LEFT$(A$+"B",10))
?OS ERROR
READY
>CLEAR 50:A$=STRING$(10,"A"):PRINT LEN(STRING$(39,A$+"B"))
 39 
READY
>CLEAR 50:A$=STRING$(15,"A"):IF A$+A$=A$+A$ THEN PRINT "EQ"
?OS ERROR
READY
>CLEAR 50:A$=STRING$(20,"A"):PRINT FRE(A$+A$)
?OS ERROR
READY
>10 A$=STRING$(10,"A"):B$=A$:C$="XY":D$=C$:PRINT FRE("")
>RUN
 30 
READY
>'
[ "$out" = "$want" ] || fail "?OS while a string is built" "$out"

# LET copies a string unless its bytes lie in the program (1F46H-1F57H):
# a lone variable, array element or parenthesised one whose string is a
# DATA item takes no string space, in a direct statement too; one in
# string space, or a literal typed in a direct statement (the input buffer
# is below the program), is copied.  A sort that swaps READ strings
# through Z$ never runs out.  Until 2026-10-29 an element and a direct
# statement were always copied: such a sort stopped ?OS.
out=$(repl 32767 '10 DIM A$(3):READ A$(1):A$(2)=A$(1):A$(3)=(A$(2)):PRINT FRE("")\n20 DATA ABCDEFGHIJ\nRUN\nB$=A$(3):PRINT FRE("")\nNEW\n10 DIM A$(2):READ A$(1),A$(2)\n20 FOR I=1 TO 9:Z$=A$(1):A$(1)=A$(2):A$(2)=Z$:NEXT:PRINT FRE("");A$(1)\n30 DATA ABCDEFGHIJKLMNOPQRSTUVWXY,0123456789012345678901234\nRUN\nNEW\n10 DIM A$(2):A$(1)=STRING$(10,"X"):A$(2)=A$(1):PRINT FRE("")\nRUN\nNEW\nA$="ABCDEFGHIJ":B$=A$:PRINT FRE("")\n')
want='>10 DIM A$(3):READ A$(1):A$(2)=A$(1):A$(3)=(A$(2)):PRINT FRE("")
>20 DATA ABCDEFGHIJ
>RUN
 50 
READY
>B$=A$(3):PRINT FRE("")
 50 
READY
>NEW
READY
>10 DIM A$(2):READ A$(1),A$(2)
>20 FOR I=1 TO 9:Z$=A$(1):A$(1)=A$(2):A$(2)=Z$:NEXT:PRINT FRE("");A$(1)
>30 DATA ABCDEFGHIJKLMNOPQRSTUVWXY,0123456789012345678901234
>RUN
 50 0123456789012345678901234
READY
>NEW
READY
>10 DIM A$(2):A$(1)=STRING$(10,"X"):A$(2)=A$(1):PRINT FRE("")
>RUN
 30 
READY
>NEW
READY
>A$="ABCDEFGHIJ":B$=A$:PRINT FRE("")
 30 
READY
>'
[ "$out" = "$want" ] || fail "LET leaves a string that lies in the program" "$out"

# Each term of that rule exactly at its limit, where one byte of slack
# shows: a concatenation's right operand is held too (A$+(B$+C$) needs
# 2*LEN(A$)+3*(LEN(B$)+LEN(C$)) <= 50), a concatenation costs the sum of
# its operands, STRING$ costs its count, RIGHT$/MID$ cost their result
# (2A61H), holding a string argument it was given (each case with A$+"B"
# fitting, so only the function's own result crosses the limit), and a
# 0-length result costs nothing.  A temporary that nothing
# points at any more is reclaimed: when the area is full the ROM keeps only
# the strings the variables, the arrays and the string pointer table hold
# (28E1H-2903H) and retries, so a string function abandoned by an error in
# a later argument (here LEFT$ holding A$+A$ when 1/0 fails) costs nothing
# past RESUME (p70's per-statement STMP reset is the model of that; a
# leak would print LEAK).
out=$(repl 32767 'CLEAR 50:A$=STRING$(10,"A"):B$=STRING$(5,"B"):C$=STRING$(5,"C"):PRINT LEN(A$+(B$+C$))\nCLEAR 50:A$=STRING$(11,"A"):B$=STRING$(5,"B"):C$=STRING$(5,"C"):PRINT LEN(A$+(B$+C$))\nCLEAR 50:A$=STRING$(20,"A"):B$=STRING$(5,"B"):PRINT LEN(A$+B$)\nCLEAR 50:A$=STRING$(20,"A"):B$=STRING$(6,"B"):PRINT LEN(A$+B$)\nCLEAR 50:A$=STRING$(11,"A"):PRINT LEN(STRING$(39,A$+"B"))\nCLEAR 50:A$=STRING$(11,"A"):PRINT LEN(STRING$(40,A$+"B"))\nCLEAR 50:A$=STRING$(30,"A"):PRINT LEN(RIGHT$(A$,20))\nCLEAR 50:A$=STRING$(30,"A"):PRINT LEN(RIGHT$(A$,21))\nCLEAR 50:A$=STRING$(30,"A"):PRINT LEN(MID$(A$,2,20))\nCLEAR 50:A$=STRING$(30,"A"):PRINT LEN(MID$(A$,2,21))\nCLEAR 50:A$=STRING$(30,"A"):PRINT LEN(MID$(A$,11))\nCLEAR 50:A$=STRING$(30,"A"):PRINT LEN(MID$(A$,10))\nCLEAR 50:A$=STRING$(24,"A"):PRINT LEN(RIGHT$(A$+"B",1))\nCLEAR 50:A$=STRING$(25,"A"):PRINT LEN(RIGHT$(A$+"B",1))\nCLEAR 50:A$=STRING$(20,"A"):PRINT LEN(RIGHT$(A$+"B",9))\nCLEAR 50:A$=STRING$(20,"A"):PRINT LEN(RIGHT$(A$+"B",10))\nCLEAR 50:A$=STRING$(20,"A"):PRINT LEN(MID$(A$+"B",13))\nCLEAR 50:A$=STRING$(20,"A"):PRINT LEN(MID$(A$+"B",12))\nCLEAR 50:A$=STRING$(20,"A"):PRINT LEN(MID$(A$+"B",2,9))\nCLEAR 50:A$=STRING$(20,"A"):PRINT LEN(MID$(A$+"B",2,10))\nCLEAR 50:A$=STRING$(20,"A"):PRINT LEN(LEFT$(A$+"B",9))\nCLEAR 50:A$=STRING$(20,"A"):PRINT LEN(LEFT$(A$+"B",10))\nCLEAR 50:A$=STRING$(30,"A"):PRINT LEN(RIGHT$(A$,0))\nCLEAR 50:A$=STRING$(50,"A"):PRINT LEN(MID$(A$,51))\n1 CLEAR 50:A$=STRING$(8,"A"):ON ERROR GOTO 100\n10 X$=LEFT$(A$+A$,1/0)\n20 PRINT LEN(A$+A$+A$):END\n100 IF R THEN PRINT "LEAK":END ELSE R=1:RESUME 20\nRUN\nPRINT "BACK"\n')
want='>CLEAR 50:A$=STRING$(10,"A"):B$=STRING$(5,"B"):C$=STRING$(5,"C"):PRINT LEN(A$+(B$+C$))
 20 
READY
>CLEAR 50:A$=STRING$(11,"A"):B$=STRING$(5,"B"):C$=STRING$(5,"C"):PRINT LEN(A$+(B$+C$))
?OS ERROR
READY
>CLEAR 50:A$=STRING$(20,"A"):B$=STRING$(5,"B"):PRINT LEN(A$+B$)
 25 
READY
>CLEAR 50:A$=STRING$(20,"A"):B$=STRING$(6,"B"):PRINT LEN(A$+B$)
?OS ERROR
READY
>CLEAR 50:A$=STRING$(11,"A"):PRINT LEN(STRING$(39,A$+"B"))
 39 
READY
>CLEAR 50:A$=STRING$(11,"A"):PRINT LEN(STRING$(40,A$+"B"))
?OS ERROR
READY
>CLEAR 50:A$=STRING$(30,"A"):PRINT LEN(RIGHT$(A$,20))
 20 
READY
>CLEAR 50:A$=STRING$(30,"A"):PRINT LEN(RIGHT$(A$,21))
?OS ERROR
READY
>CLEAR 50:A$=STRING$(30,"A"):PRINT LEN(MID$(A$,2,20))
 20 
READY
>CLEAR 50:A$=STRING$(30,"A"):PRINT LEN(MID$(A$,2,21))
?OS ERROR
READY
>CLEAR 50:A$=STRING$(30,"A"):PRINT LEN(MID$(A$,11))
 20 
READY
>CLEAR 50:A$=STRING$(30,"A"):PRINT LEN(MID$(A$,10))
?OS ERROR
READY
>CLEAR 50:A$=STRING$(24,"A"):PRINT LEN(RIGHT$(A$+"B",1))
 1 
READY
>CLEAR 50:A$=STRING$(25,"A"):PRINT LEN(RIGHT$(A$+"B",1))
?OS ERROR
READY
>CLEAR 50:A$=STRING$(20,"A"):PRINT LEN(RIGHT$(A$+"B",9))
 9 
READY
>CLEAR 50:A$=STRING$(20,"A"):PRINT LEN(RIGHT$(A$+"B",10))
?OS ERROR
READY
>CLEAR 50:A$=STRING$(20,"A"):PRINT LEN(MID$(A$+"B",13))
 9 
READY
>CLEAR 50:A$=STRING$(20,"A"):PRINT LEN(MID$(A$+"B",12))
?OS ERROR
READY
>CLEAR 50:A$=STRING$(20,"A"):PRINT LEN(MID$(A$+"B",2,9))
 9 
READY
>CLEAR 50:A$=STRING$(20,"A"):PRINT LEN(MID$(A$+"B",2,10))
?OS ERROR
READY
>CLEAR 50:A$=STRING$(20,"A"):PRINT LEN(LEFT$(A$+"B",9))
 9 
READY
>CLEAR 50:A$=STRING$(20,"A"):PRINT LEN(LEFT$(A$+"B",10))
?OS ERROR
READY
>CLEAR 50:A$=STRING$(30,"A"):PRINT LEN(RIGHT$(A$,0))
 0 
READY
>CLEAR 50:A$=STRING$(50,"A"):PRINT LEN(MID$(A$,51))
 0 
READY
>1 CLEAR 50:A$=STRING$(8,"A"):ON ERROR GOTO 100
>10 X$=LEFT$(A$+A$,1/0)
>20 PRINT LEN(A$+A$+A$):END
>100 IF R THEN PRINT "LEAK":END ELSE R=1:RESUME 20
>RUN
 24 
READY
>PRINT "BACK"
BACK
READY
>'
[ "$out" = "$want" ] || fail "?OS at each term's limit" "$out"

# INKEY$ (019DH): a key is a 1-byte string and takes its byte as it is
# made, beside a variable's 49 bytes but not its 50, whether it is kept or
# only compared; no key is the null string and costs nothing.  Piped, the
# key is the byte after RUN.  One case per run: INKEY$ reads stdin.
for c in '49:K$=INKEY$:IF K$="" THEN NEXT\n20 PRINT LEN(K$): 1 ' \
         '50:K$=INKEY$:IF K$="" THEN NEXT\n20 PRINT LEN(K$):?OS ERROR IN 10' \
         '49:IF INKEY$="" THEN NEXT:PRINT "NONE":END\n20 PRINT "GOT":GOT' \
         '50:IF INKEY$="" THEN NEXT:PRINT "NONE":END\n20 PRINT "GOT":?OS ERROR IN 10'; do
    prog=${c%:*}; want=${c##*:}
    out=$(repl 32767 "10 CLEAR 50:A\$=STRING\$(${prog%%:*},\"A\"):FOR I=1 TO 20:${prog#*:}\nRUN\nX" | sed -n '/^>RUN/{n;p;}')
    [ "$out" = "$want" ] || fail "INKEY\$ beside ${prog%%:*} bytes" "$out"
done
out=$(repl 32767 '10 CLEAR 50:A$=STRING$(50,"A"):PRINT LEN(INKEY$)\nRUN\n' | sed -n '/^>RUN/{n;p;}')
[ "$out" = " 0 " ] || fail "INKEY\$ with no key" "$out"

echo "MEM OK"
