#!/bin/sh
# usr.sh -- the USR call frame resolves as documented (p60 usr_resolve).
# Self-checking: exits 1 on any mismatch.  Run from the repo root:
#     sh programs/tests/usr.sh
# Covers every spelling (USR( / USRn( / USR n(, DEFUSR= / DEFUSRn= /
# DEF USR n=), the precedence rule (DEF USRn wins; slot 0 falls back to the
# 408EH vector; slots 1-9 undefined until defined; an unwritten vector is
# undefined), the -1 and -25536 address wrap, and that the stub still returns its
# argument.
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
got=$(printf '\nX=USR(1)\nDEFUSR=&H7000\nDEF USR 1=28427\nDEFUSR2=-1\nDEF USR3=-25536\nX=USR(5)\nX=USR0(6)\nX=USR 1(7)\nX=USR2(8)\nX=USR3(9)\nX=USR4(10)\nPOKE 16526,1:POKE 16527,2\nDEFUSR=100\nX=USR(12)\nPRINT USR 3(13);USR3(14)\nBYE\n' \
      | TRS80_USR_TRACE=1 TRS80_DUMB=1 gawk -b -f "$here/trs80basic.awk" 2>&1 >/dev/null | grep '^USR slot')
want='USR slot=0 entry=undefined arg=1
USR slot=0 entry=28672 arg=5
USR slot=0 entry=28672 arg=6
USR slot=1 entry=28427 arg=7
USR slot=2 entry=65535 arg=8
USR slot=3 entry=40000 arg=9
USR slot=4 entry=undefined arg=10
USR slot=0 entry=100 arg=12
USR slot=3 entry=40000 arg=13
USR slot=3 entry=40000 arg=14'
if [ "$got" != "$want" ]; then
    echo "USR FRAME FIXTURE FAILED"; echo "--- expected:"; echo "$want"; echo "--- got:"; echo "$got"; exit 1
fi
# the 408EH vector alone (no DEF USR this session) resolves slot 0.
# Keep the streams apart: the frame trace is on stderr, the returned value on
# stdout, and merging them through a pipe reorders the lines.
err=$(printf '\nPOKE 16526,1:POKE 16527,2\nPRINT USR(3);USR 0(4)\nBYE\n' \
      | TRS80_USR_TRACE=1 TRS80_DUMB=1 gawk -b -f "$here/trs80basic.awk" 2>&1 >/dev/null | grep '^USR slot')
want='USR slot=0 entry=513 arg=3
USR slot=0 entry=513 arg=4'
if [ "$err" != "$want" ]; then
    echo "USR FRAME FIXTURE FAILED (vector path)"; echo "--- expected:"; echo "$want"; echo "--- got:"; echo "$err"; exit 1
fi
# the stub is not silent: one stderr line per run tallies the calls that
# were not executed, by entry address in first-call order (ruled 2026-09-11).
note=$(printf '\n10 DEFUSR=&H7000\n20 X=USR(5):Y=USR(6):Z=USR1(7)\nRUN\nBYE\n' \
      | TRS80_DUMB=1 gawk -b -f "$here/trs80basic.awk" 2>&1 >/dev/null | grep '^USR STUB')
want='USR STUB: 3 CALLS NOT EXECUTED (7000H x2, UNDEFINED x1): no Z80 core, each returned its argument; TRS80_USR=strict raises ?FC instead'
if [ "$note" != "$want" ]; then
    echo "USR FRAME FIXTURE FAILED (stub notice)"; echo "--- expected:"; echo "$want"; echo "--- got:"; echo "$note"; exit 1
fi
# and a run with no USR call prints nothing
none=$(printf '\n10 PRINT 1\nRUN\nBYE\n' | TRS80_DUMB=1 gawk -b -f "$here/trs80basic.awk" 2>&1 >/dev/null | grep -c '^USR STUB')
if [ "$none" != "0" ]; then echo "USR FRAME FIXTURE FAILED (notice without a call)"; exit 1; fi
# TRS80_USR=strict: the call raises ?FC and batch exits 1
tmp=$(mktemp) || exit 2
printf '10 X=USR(5)\n20 PRINT "AFTER"\n' > "$tmp"
out=$(TRS80_Z80="" TRS80_USR=strict "$here/basic" "$tmp" 2>&1); rc=$?   # the stub, not a core beside the checkout
rm -f "$tmp"
if [ "$rc" != "1" ] || [ "$out" != "?FC ERROR IN 10" ]; then
    echo "USR FRAME FIXTURE FAILED (strict): rc=$rc out=$out"; exit 1
fi
# TRS80_USR_TRACE=2: the frame's memory image (p75 fr_build).  Frame 1 is
# full; later frames are deltas -- a POKE shows up once, a packed string
# when its value or place changed, and cells CLEAR unmapped come back as
# 255 (ruled 2026-09-11; the string and the screen by change since
# 2026-09-25, M-12).
# The strings are joined (+) so they live in string space: a lone literal
# stays in its program line, as the ROM's LET leaves it (1F46H-1F57H).
dump=$(printf '\n10 POKE 30000,7:A$="HEL"+"LO":V=VARPTR(A$)\n20 X=USR(1)\n30 POKE 30001,8:X=USR(2)\n40 A$="WORLD"+"S":X=USR(3)\n50 CLEAR:X=USR(4)\nRUN\nBYE\n' \
      | TRS80_USR_TRACE=2 TRS80_DUMB=1 gawk -b -f "$here/trs80basic.awk" 2>&1 >/dev/null \
      | awk '/^USR FRAME/ { g = $3; print; next } /^  / && g != "" { print g " " $1 }')
chk() { if ! printf '%s\n' "$dump" | grep -q -- "$1"; then echo "USR FRAME FIXTURE FAILED (image): missing $1"; printf '%s\n' "$dump" | head -40; exit 1; fi; }
nochk() { if printf '%s\n' "$dump" | grep -q -- "$1"; then echo "USR FRAME FIXTURE FAILED (image): unexpected $1"; exit 1; fi; }
chk '^USR FRAME gen=1 full=1 slot=0 entry=-1 arg=1 sp=65527 himem=65535 ramtop=65535 bytes=1205 runs=17$'   # +20 window bytes and +4 seeded driver-vector bytes, 2026-09-11; +1 seeded 403DH print-flag byte (16445), 2026-09-13; +6 image bytes for the two joins, 2026-09-23; +26 the DEF-type table 4101-411AH, 2026-09-23
chk '^gen=1 16445:0$'                       # the seeded ROM print-flag byte, 403DH
chk '^gen=1 30000:7$'                       # the POKE
chk '^gen=1 16396:201$'                     # the seeded DOS probe byte
chk '^gen=1 17129:13,67,10,0,'              # the image: next pointer 430DH, line 10
chk '^gen=1 65528:72,69,76,76,79,5,248,255$'   # HELLO, then its descriptor
chk '^USR FRAME gen=2 full=0 '
chk '^gen=2 30001:8$'; nochk '^gen=2 30000:'; nochk '^gen=2 17129:'   # delta: only the new POKE
nochk '^gen=2 65528:'                          # the string, unchanged: not resent
nochk '^gen=2 15360:'                          # nor the screen, untouched since frame 1
# WORLDS outgrew HELLO's five cells: the assignment re-homed it below (FFF2H),
# the old cells are unmapped and the descriptor names the new address
chk '^USR FRAME gen=3 full=0 slot=0 entry=-1 arg=3 sp=65521 '
chk '^gen=3 65522:87,79,82,76,68,83,255,255,255,255,255,6,242,255$'
chk '^USR FRAME gen=4 full=0 slot=0 entry=-1 arg=4 sp=65535 '   # CLEAR: SP back at HIMEM
chk '^gen=4 65522:255,255,255,255,255,255$'                      # the unmapped cells read 255
chk '^gen=4 65533:255,255,255$'                                  # and the descriptor's

# A delta carries what changed since the last frame, and no more (the
# 2026-09-23 audit, M-12; until 2026-09-25 the screen and every VARPTR'd
# cell went in every frame).  A string assigned the same length in the same
# place is resent for its value; untouched, it is not; a number the same;
# a POKE into a mapped cell is resent once; a PRINT resends its cells and
# a CLS the whole screen.
dump=$(printf '\n10 A$="HEL"+"LO":V=VARPTR(A$):PRINT "X";:X=USR(1)\n20 X=USR(2)\n30 A$="JEL"+"LO":X=USR(3)\n40 PRINT@64,"Q";:X=USR(4)\n50 CLS:X=USR(5)\n60 B=7:W=VARPTR(B):X=USR(6)\n70 B=8:X=USR(7)\n80 POKE V+1,PEEK(V+1):X=USR(8)\nRUN\nBYE\n' \
      | TRS80_USR_TRACE=2 TRS80_DUMB=1 gawk -b -f "$here/trs80basic.awk" 2>&1 >/dev/null \
      | awk '/^USR FRAME/ { g = $3; print; next } /^  / && g != "" { print g " " $1 }')
chk '^gen=1 65528:72,69,76,76,79,5,248,255$'
chk '^gen=1 15360:'
nochk '^gen=2 65528:'; nochk '^gen=2 15[3-9][0-9][0-9]:'; nochk '^gen=2 16[0-3][0-9][0-9]:'   # nothing changed: neither the string nor a screen cell
chk '^gen=3 65528:74,69,76,76,79,5,248,255$'                     # JELLO: same place, new value
nochk '^gen=4 65528:'; chk '^gen=4 15424:81$'; nochk '^gen=4 15360:'   # PRINT@64,"Q": that cell alone
chk '^gen=5 15360:32,32,32,32,32,32,32,32,'                      # CLS: the whole screen
chk '^gen=6 65524:0,0,96,131$'; chk '^gen=7 65524:0,0,0,132$'; nochk '^gen=8 65524:'   # B: VARPTRed, changed, then untouched
chk '^gen=8 65534:248$'                                          # the POKE of the same byte: resent once

# The core's own video writes come back through the screen and are ITS
# bytes: the next delta does not resend them (z80_stub.py paints HI at
# 7000H); what BASIC prints in between is resent.
dump=$(printf '\n10 DEFUSR0=&H7000:X=USR0(0):X=USR0(0):PRINT@384,"P";:X=USR0(0)\nRUN\nBYE\n' \
      | TRS80_USR_TRACE=2 TRS80_DUMB=1 TRS80_Z80="python3 $here/programs/tests/z80_stub.py" gawk -b -f "$here/trs80basic.awk" 2>&1 >/dev/null \
      | awk '/^USR FRAME/ { g = $3; print; next } /^  / && g != "" { print g " " $1 }')
chk '^USR FRAME gen=3 full=0 '                 # the dump is the frame sent: gen 1, 2, 3, no NEED
nochk '^gen=2 15360:'
nochk '^gen=3 15360:'; chk '^gen=3 15744:80$'
echo "USR FRAME FIXTURE OK"
