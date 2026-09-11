#!/bin/sh
# usr.sh -- the USR call frame resolves as documented (p60 usr_resolve).
# Self-checking: exits 1 on any mismatch.  Run from the repo root:
#     sh programs/tests/usr.sh
# Covers every spelling (USR( / USRn( / USR n(, DEFUSR= / DEFUSRn= /
# DEF USR n=), the precedence rule (DEF USRn wins; slot 0 falls back to the
# 408EH vector; slots 1-9 undefined until defined; an unwritten vector is
# undefined), the -1 address wrap, and that the stub still returns its
# argument.
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
got=$(printf '\nX=USR(1)\nDEFUSR=&H7000\nDEF USR 1=28427\nDEFUSR2=-1\nDEF USR3=40000\nX=USR(5)\nX=USR0(6)\nX=USR 1(7)\nX=USR2(8)\nX=USR3(9)\nX=USR4(10)\nPOKE 16526,1:POKE 16527,2\nDEFUSR=100\nX=USR(12)\nPRINT USR 3(13);USR3(14)\nBYE\n' \
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
out=$(TRS80_USR=strict "$here/basic" "$tmp" 2>&1); rc=$?
rm -f "$tmp"
if [ "$rc" != "1" ] || [ "$out" != "?FC ERROR IN 10" ]; then
    echo "USR FRAME FIXTURE FAILED (strict): rc=$rc out=$out"; exit 1
fi
# TRS80_USR_TRACE=2: the frame's memory image (p75 fr_build).  Frame 1 is
# full; later frames are deltas -- a POKE shows up once, a packed string
# always, and cells CLEAR unmapped come back as 255 (ruled 2026-09-11).
dump=$(printf '\n10 POKE 30000,7:A$="HELLO":V=VARPTR(A$)\n20 X=USR(1)\n30 POKE 30001,8:X=USR(2)\n40 A$="WORLDS":X=USR(3)\n50 CLEAR:X=USR(4)\nRUN\nBYE\n' \
      | TRS80_USR_TRACE=2 TRS80_DUMB=1 gawk -b -f "$here/trs80basic.awk" 2>&1 >/dev/null \
      | awk '/^USR FRAME/ { g = $3; print; next } /^  / && g != "" { print g " " $1 }')
chk() { if ! printf '%s\n' "$dump" | grep -q -- "$1"; then echo "USR FRAME FIXTURE FAILED (image): missing $1"; printf '%s\n' "$dump" | head -40; exit 1; fi; }
nochk() { if printf '%s\n' "$dump" | grep -q -- "$1"; then echo "USR FRAME FIXTURE FAILED (image): unexpected $1"; exit 1; fi; }
chk '^USR FRAME gen=1 full=1 slot=0 entry=-1 arg=1 sp=65527 himem=65535 ramtop=65535 bytes=1148 runs=10$'
chk '^gen=1 30000:7$'                       # the POKE
chk '^gen=1 16396:201$'                     # the seeded DOS probe byte
chk '^gen=1 17129:10,67,10,0,'              # the image: next pointer 4311H, line 10
chk '^gen=1 65528:72,69,76,76,79,5,248,255$'   # HELLO, then its descriptor
chk '^USR FRAME gen=2 full=0 '
chk '^gen=2 30001:8$'; nochk '^gen=2 30000:'; nochk '^gen=2 17129:'   # delta: only the new POKE
chk '^gen=2 65528:72,69,76,76,79,5,248,255$'   # the string, always
chk '^gen=3 65528:87,79,82,76,68,6,248,255$'   # live value, same cells
chk '^USR FRAME gen=4 full=0 slot=0 entry=-1 arg=4 sp=65535 '   # CLEAR: SP back at HIMEM
chk '^gen=4 65528:255,255,255,255,255,255,255,255$'              # the unmapped cells read 255
echo "USR FRAME FIXTURE OK"
