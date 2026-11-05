#!/bin/sh
# name.sh -- NAME is Level II's 418EH vector, as on the machine (Farvour's
# RAM vector table, 418E NAME; "TRS-80 ROM Routines Documented", The
# Alternate Source, introduction p. 8): the boot bytes C3 2D 01 jump to
# ?L3, error 23, typed or in a program, trappable; a program that puts its
# own JP there runs machine code with NAME.  The routine enters with HL on
# the first non-blank byte after the token, A that byte and F the flags
# of the ROM's next-character fetch (Farvour 1D78H-1D8FH), and the
# statement ends where it leaves HL: ":" or 00 there, else ?SN (1D2CH).
# Renumbering is the `renum` metacommand now (renum.sh).
# Part 1 needs no core; part 2 runs the real core, skipped when absent.
# Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/name.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
fail() { echo "NAME FAILED: $1"; printf "%s\n" "$2"; exit 1; }
filt() { grep '^[A-Z?=0-9 ]' | grep -v '^READY\|^MEM SIZE\|^TRS-80\|^R/S L2\|^man \|^"help\|^ *Codeveloped\|^USR STUB' | sed 's/ *$//' ; }  # trailing blanks off: PRINT's number blank
nocore() { TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" 2>&1 | filt ; }

# --- part 1: the vector as booted, and the stub ---------------------------
out=$(nocore <<'EOF'

PRINT PEEK(16782);PEEK(16783);PEEK(16784)
NAME
NAME:PRINT "NOT REACHED"
10 PRINT "A":NAME:PRINT "B"
RUN
NEW
10 ON ERROR GOTO 100
20 NAME 5
30 PRINT "AFTER":END
100 PRINT "ERR";ERR/2+1;"ERL";ERL:RESUME NEXT
RUN
EOF
)
want=' 195  45  1
?L3 ERROR
?L3 ERROR
A
?L3 ERROR IN 10
ERR 23 ERL 20
AFTER'
[ "$out" = "$want" ] || fail "the boot vector is ?L3" "$out"

# no core: the stub skips the rest of the statement, and says so on stderr
out=$(printf '\nPOKE 16783,0:POKE 16784,125\nNAME 1,2,3:PRINT "X"\n' \
      | TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" 2>&1 | grep '^X\|^USR STUB')
case "$out" in
    "X
USR STUB: 1 CALL NOT EXECUTED (418EH x1)"*"NAME, which skipped the rest of its statement"*) ;;
    *) fail "the stub skips the statement" "$out" ;;
esac
out=$(printf '\nPOKE 16783,0:POKE 16784,125\nNAME\n' \
      | TRS80_DUMB=1 TRS80_Z80= TRS80_USR=strict gawk -b -f "$here/trs80basic.awk" 2>&1 | grep '^?')
[ "$out" = "?FC ERROR" ] || fail "TRS80_USR=strict: a stubbed NAME is ?FC" "$out"
echo "NAME OK (no core)"

# --- part 2: the real core ------------------------------------------------
core=${TRS80_Z80-"python3 $here/../trs80_z80_core/core.py"}
set -- $core
[ -f "$2" ] || { echo "NAME CORE PART SKIPPED: no core at $2"; exit 0; }
withcore() { TRS80_DUMB=1 TRS80_Z80="$core" gawk -b -f "$here/trs80basic.awk" 2>&1 | filt ; }

# a RET routine: NAME is an empty statement; an argument left over is ?SN
out=$(withcore <<'EOF'

POKE 32000,201:POKE 16783,0:POKE 16784,125
NAME:PRINT "BACK"
NAME 5:PRINT "X"
10 NAME:NAME:NAME:PRINT "THREE"
20 FOR I=1 TO 3:NAME:NEXT:PRINT I
30 IF 1 THEN NAME:PRINT "T"
40 IF 0 THEN NAME ELSE PRINT "E"
RUN
EOF
)
want='BACK
?SN ERROR
THREE
 4
T
E'
[ "$out" = "$want" ] || fail "a RET routine" "$out"

# the entry state: a routine stores HL, A and F at 7E00H-7E04H and returns
# (LD (7E00H),HL / LD (7E02H),A / PUSH AF / POP BC / LD (7E04H),BC / RET).
# Line 4's NAME token sits 69 bytes into the program: HL 70 is the byte
# after it, blanks skipped ("4 NAME@" is NAME and a trailing blank); F is the fetch's (":" 6AH, a digit 23H, a
# letter 3AH, "," 2AH, the line's 00 42H).  A typed line is crunched at
# 41E6H, so its token is at 16870.
out=$(sed 's/@$/ /' <<'EOF' | withcore

1 DATA 34,0,126,50,2,126,245,193,237,67,4,126,201
FOR I=0 TO 12:READ B:POKE 32000+I,B:NEXT:POKE 16783,0:POKE 16784,125
3 ON ERROR GOTO 9:GOTO 4
6 END
9 PRINT "ERR";ERR/2+1;PEEK(32256)+256*PEEK(32257)-(PEEK(16548)+256*PEEK(16549));PEEK(32258);PEEK(32260):RESUME 6
4 NAME 5
5 PRINT "OK";PEEK(32256)+256*PEEK(32257)-(PEEK(16548)+256*PEEK(16549));PEEK(32258);PEEK(32260)
RUN 3
4 NAME  X
RUN 3
4 NAME
RUN 3
4 NAME:REM
RUN 3
4 NAME,1
RUN 3
4 NAME@
RUN 3
NAME 7
PRINT PEEK(32256)+256*PEEK(32257);PEEK(32258);PEEK(32260)
NAME:
PRINT PEEK(32256)+256*PEEK(32257);PEEK(32258);PEEK(32260)
EOF
)
want='ERR 2  71  53  35
ERR 2  72  88  58
OK 70  0  66
OK 70  58  106
ERR 2  70  44  42
OK 71  0  66
ERR 2 -257  55  35
 16872  55  35
 16871  58  106'
[ "$out" = "$want" ] || fail "the routine's entry HL, A and F" "$out"

# a routine that takes its argument: LD (HL),A / INC HL / RET.  The
# statement goes on from the byte after it -- ":" or the line's end; a
# blank there is ?SN, the driver skips none (1D2CH)
out=$(withcore <<'EOF'

1 DATA 119,35,201
FOR I=0 TO 2:READ B:POKE 32000+I,B:NEXT:POKE 16783,0:POKE 16784,125
NAME 1:PRINT "X"
NAME  E :PRINT "Y"
NAME 12:PRINT "Z"
10 NAME 1:PRINT "A";
20 NAME A:NAME B:PRINT "B";
30 PRINT "C":NAME 2
40 IF 1 THEN NAME 7 ELSE PRINT "NO"
RUN
EOF
)
want='X
?SN ERROR
?SN ERROR
ABC
?SN ERROR IN 40'
[ "$out" = "$want" ] || fail "a routine that steps over its argument" "$out"
echo "NAME OK (core)"
