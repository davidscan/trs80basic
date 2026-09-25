#!/bin/sh
# name.sh -- NAME (Disk BASIC's renumber) moves the live run state with
# the lines it renumbers: the ON ERROR GOTO target follows its line, as
# the reference in the text does (the Disk manual: "all line references
# within your program will be renumbered"), so an error trapped after a
# NAME lands in the handler and not in whatever line now has the old
# number (until 2026-09-25: ?UL, or a wrong line run as the handler; the
# 2026-09-23 audit, L-6).  The FOR and GOSUB stacks are cleared, as every
# change to the program clears them (ROM 1B5DH): a typed NEXT is ?NF,
# a typed RETURN ?RG, and CONT ?CN.
# Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/name.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
fail() { echo "NAME FAILED: $1"; printf '%s\n' "$2"; exit 1; }
repl() { TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" 2>&1 | grep '^[A-Z?=0-9]' | grep -v '^READY\|^MEMORY\|^TRS-80\|^RADIO\|^man \|^"help' ; }

# the handler follows its line
out=$(repl <<'EOF'

10 ON ERROR GOTO 100
20 PRINT "M"
30 END
100 PRINT "H";ERL:RESUME NEXT
RUN
NAME 1000
PRINT 1/0
PRINT "AFTER"
LIST 1030
EOF
)
want='M
H 65535 
AFTER
1030 PRINT "H";ERL:RESUME NEXT'
[ "$out" = "$want" ] || fail "the ON ERROR target after NAME" "$out"

# the stacks are cleared: NEXT, RETURN and CONT after a NAME
out=$(repl <<'EOF'

10 FOR I=1 TO 2:GOSUB 30
20 END
30 STOP
40 RETURN
RUN
NAME 100
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
[ "$out" = "$want" ] || fail "the FOR/GOSUB stacks and CONT after NAME" "$out"
echo "NAME OK"
