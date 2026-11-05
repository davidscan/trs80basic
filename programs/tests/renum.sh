#!/bin/sh
# renum.sh -- renum (the renumber metacommand, EXT; the statement NAME
# until 2026-11-04, which is the ROM's 418EH vector now: name.sh) moves the live run state with
# the lines it renumbers: the ON ERROR GOTO target follows its line, as
# the reference in the text does (the Disk manual: "all line references
# within your program will be renumbered"), so an error trapped after a
# renum lands in the handler and not in whatever line now has the old
# number (until 2026-09-25: ?UL, or a wrong line run as the handler; the
# 2026-09-23 audit).  The FOR and GOSUB stacks are cleared, as every
# change to the program clears them (ROM 1B5DH): a typed NEXT is ?NF,
# a typed RETURN ?RG, and CONT ?CN.
# Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/renum.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
fail() { echo "RENUM FAILED: $1"; printf '%s\n' "$2"; exit 1; }
repl() { TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" 2>&1 | grep '^[A-Z?=0-9]' | grep -v '^READY\|^MEM SIZE\|^TRS-80\|^R/S L2\|^man \|^"help' ; }

# the handler follows its line
out=$(repl <<'EOF'

10 ON ERROR GOTO 100
20 PRINT "M"
30 END
100 PRINT "H";ERL:RESUME NEXT
RUN
renum 1000
PRINT 1/0
PRINT "AFTER"
LIST 1030
EOF
)
want='M
H 65535 
AFTER
1030 PRINT "H";ERL:RESUME NEXT'
[ "$out" = "$want" ] || fail "the ON ERROR target after renum" "$out"

# the stacks are cleared: NEXT, RETURN and CONT after a NAME
out=$(repl <<'EOF'

10 FOR I=1 TO 2:GOSUB 30
20 END
30 STOP
40 RETURN
RUN
renum 100
NEXT
RETURN
CONT
PRINT "END"
EOF
)
want='BREAK IN 30
?NF ERROR
?RG ERROR
?CN ERROR
END'
[ "$out" = "$want" ] || fail "the FOR/GOSUB stacks and CONT after renum" "$out"

# a renum typed while a handler is in flight (its STOP) drops the
# handler state with the stacks (the 2026-09-26 audit): the next error is
# trapped by the moved handler (a stale INHANDLER blocked the entry), with
# ERL 65535 for a typed one
out=$(repl <<'EOF'

10 ON ERROR GOTO 100
20 ERROR 5
30 END
100 PRINT "H";ERL:STOP
RUN
renum 1000
ERROR 5
EOF
)
want=$(printf 'H 20 \nBREAK IN 100\nH 65535 \nBREAK IN 1030')
[ "$out" = "$want" ] || fail "renum inside a handler: the next error is trapped" "$out"

# the arguments: a bad one is ?SN, as a statement's tail is; i < 1 ?FC
out=$(repl <<'EOF'

10 END
renum 10,,0
renum X
LIST
EOF
)
want=$(printf '?FC ERROR\n?SN ERROR\n10 END')
[ "$out" = "$want" ] || fail "renum's arguments" "$out"
echo "RENUM OK"
