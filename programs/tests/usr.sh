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
      | TRS80_USR_TRACE=1 TRS80_DUMB=1 gawk -b -f "$here/trs80basic.awk" 2>&1 >/dev/null | grep '^USR ')
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
      | TRS80_USR_TRACE=1 TRS80_DUMB=1 gawk -b -f "$here/trs80basic.awk" 2>&1 >/dev/null | grep '^USR ')
want='USR slot=0 entry=513 arg=3
USR slot=0 entry=513 arg=4'
if [ "$err" != "$want" ]; then
    echo "USR FRAME FIXTURE FAILED (vector path)"; echo "--- expected:"; echo "$want"; echo "--- got:"; echo "$err"; exit 1
fi
echo "USR FRAME FIXTURE OK"
