#!/bin/sh
# pmtrunc.sh -- a program too big for the 16-bit window is TRUNCATED at a
# whole line, the chain is terminated where it stops, 40F9H reports that end,
# and one stderr line says so (window overflow policy, p75 pm_build, ruled
# 2026-09-11).  Self-checking: exits 1 on any mismatch.  Run from the repo
# root:  sh programs/tests/pmtrunc.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
tmp=$(mktemp) || exit 2
{
  # the checks run first (low line numbers); the bulk follows and is what
  # overflows: 1200 records of 57 bytes = 68,400 > the 48,407 that fit
  printf '1 F=0:E=PEEK(16633)+256*PEEK(16634)\n'
  printf '2 IF E>65536 THEN PRINT "FAIL 40F9H above the address space";E:F=1\n'
  printf '3 A=17129:N=0:L=0\n'
  printf '4 NX=PEEK(A)+256*PEEK(A+1):IF NX=0 THEN 7\n'
  printf '5 N=N+1:L=PEEK(A+2)+256*PEEK(A+3):IF NX<=A OR NX>65535 THEN PRINT "FAIL bad link";A;NX:F=1:GOTO 7\n'
  printf '6 A=NX:GOTO 4\n'
  printf '7 IF A+2<>E THEN PRINT "FAIL terminator not where 40F9H says";A;E:F=1\n'
  printf '8 IF N<10 OR N>=1207 THEN PRINT "FAIL line count";N:F=1\n'
  printf '9 IF L>=1200 THEN PRINT "FAIL last line kept";L:F=1\n'
  printf '10 IF PEEK(65535)<>255 THEN PRINT "FAIL byte at RAMTOP";PEEK(65535):F=1\n'
  printf '11 IF PEEK(E)<>255 THEN PRINT "FAIL byte past the end";PEEK(E):F=1\n'
  printf '12 IF A>65533 THEN PRINT "FAIL terminator crosses RAMTOP";A:F=1\n'
  printf '13 IF F THEN ERROR 1\n'
  printf '14 PRINT "LINES";N;"LAST";L;"END";E:END\n'
  i=100
  while [ $i -lt 1300 ]; do
    printf '%d REM %s\n' $i XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
    i=$((i+1))
  done
} > "$tmp"
out=$("$here/basic" "$tmp" 2>"$tmp.err"); rc=$?
err=$(cat "$tmp.err")
rm -f "$tmp" "$tmp.err"
if [ "$rc" != "0" ]; then echo "PMTRUNC FIXTURE FAILED: rc=$rc"; echo "$out"; echo "$err"; exit 1; fi
case "$out" in
  "LINES "*" LAST "*" END "*) ;;
  *) echo "PMTRUNC FIXTURE FAILED: unexpected output"; echo "$out"; exit 1 ;;
esac
n=$(printf '%s\n' "$err" | grep -c '^PROGRAM IMAGE TRUNCATED: LINE [0-9]* AND AFTER DO NOT FIT BELOW 65535; PEEK AND MACHINE CODE SEE A CHAIN ENDING AT [0-9]*$')
if [ "$n" != "1" ]; then echo "PMTRUNC FIXTURE FAILED: expected exactly one truncation note, got $n"; echo "$err"; exit 1; fi
# a program that fits prints no note at all
none=$(printf '\n10 PRINT PEEK(17129)\nRUN\nBYE\n' | TRS80_DUMB=1 gawk -b -f "$here/trs80basic.awk" 2>&1 >/dev/null | grep -c 'TRUNCATED')
if [ "$none" != "0" ]; then echo "PMTRUNC FIXTURE FAILED: note without overflow"; exit 1; fi
echo "PMTRUNC FIXTURE OK ($out)"
