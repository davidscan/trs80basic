#!/bin/sh
# hints.sh -- batch mode's note behind the ROM's message, on stderr only.
# Two errors a period listing meets here because a keystroke that lived
# OUTSIDE the listing is missing: ?OS with string space never CLEARed (the
# Level II manual: CLEAR n before RUN), and ?OV at CLEAR MEM-n on a map where
# MEM exceeds 32767.  The note names the option that plays the keystroke
# (--clear N, --memsize 32767) or says why none can help (the program's own
# CLEAR wins).  The ROM's message, the program's output and the exit status
# are untouched; a trapped error and the prompt get no note.  Self-checking:
# exits 1 on any mismatch.  Run from the repo root:  sh programs/tests/hints.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
tmp=$(mktemp) || exit 2
fail() { echo "HINTS FAILED: $1"; printf '%s\n' "$2"; rm -f "$tmp"; exit 1; }
run() { TRS80_Z80= "$here/basic" "$@" "$tmp" 2>&1 </dev/null; }
runout() { TRS80_Z80= "$here/basic" "$@" "$tmp" 2>/dev/null </dev/null; }

# ?OS with no CLEAR at all: the note says --clear
printf '10 PRINT "A";\n20 A$=STRING$(100,"A"):B$=STRING$(100,"B")\n30 PRINT "NOT REACHED"\n' > "$tmp"
want='A?OS ERROR IN 20
basic: string space is 50 bytes until CLEAR n (Level II manual, CLEAR); the listing assumed one typed before RUN: try --clear 1000'
out=$(run); rc=$?
[ $rc -eq 1 ] && [ "$out" = "$want" ] || fail "?OS with no CLEAR (rc=$rc)" "$out"
out=$(runout);           [ "$out" = "A" ] || fail "the note reached stdout" "$out"
out=$(run --clear 1000); [ "$out" = "ANOT REACHED" ] || fail "--clear 1000 runs it" "$out"

# --clear too small: raise it
want='A?OS ERROR IN 20
basic: --clear 100 is too small for this program'"'"'s strings: raise it'
out=$(run --clear 100);  [ "$out" = "$want" ] || fail "--clear too small" "$out"

# the program's own CLEAR is too small: --clear cannot help
printf '10 CLEAR 60\n20 A$=STRING$(100,"A"):B$=STRING$(100,"B")\n' > "$tmp"
want='?OS ERROR IN 20
basic: the program'"'"'s own CLEAR 60 in line 10 is too small for its strings; --clear cannot help, the program'"'"'s CLEAR wins -- or try --memory host (EXT: no string space limit)'
out=$(run);              [ "$out" = "$want" ] || fail "the program's own CLEAR" "$out"
out=$(run --clear 1000); [ "$out" = "$want" ] || fail "the program's own CLEAR under --clear" "$out"

# a CLEAR that comes too late is the first case until it runs
printf '10 A$=STRING$(100,"A")\n20 CLEAR 500\n' > "$tmp"
out=$(run); case $out in "?OS ERROR IN 10"*"try --clear 1000") ;; *) fail "a CLEAR that comes too late" "$out" ;; esac

# ?OV at CLEAR MEM-n on the 64K map: the note says --memsize 32767; on a
# 16K map the same line runs.  A count past 32767 on any map is a ceiling
# `memory host` lifts (EXT), so that note names it; any other ?OV gets none
printf '10 CLEAR MEM-1000\n20 PRINT "RAN"\n' > "$tmp"
want='?OV ERROR IN 10
basic: CLEAR'"'"'s count is an integer (?OV past 32767) and MEM exceeds 32767 on this memory map: the listing was written for a 16K or 32K machine, try --memsize 32767 (or, for new code, try --memory host)'
out=$(run); rc=$?
[ $rc -eq 1 ] && [ "$out" = "$want" ] || fail "?OV at CLEAR MEM-n (rc=$rc)" "$out"
out=$(run --memsize 32767); [ "$out" = "RAN" ] || fail "CLEAR MEM-n under --memsize 32767" "$out"
printf '10 CLEAR 40000\n' > "$tmp"
out=$(run --memsize 32767); case $out in "?OV ERROR IN 10
basic: a subscript, DIM bound or CLEAR count past 32767"*"--memory host"*) ;; *) fail "?OV at CLEAR 40000 on a 16K map names --memory host, not --memsize" "$out" ;; esac
printf '10 X%%=40000\n' > "$tmp"
out=$(run); [ "$out" = "?OV ERROR IN 10" ] || fail "another ?OV has no note" "$out"

# a trapped ?OS is the program's business: no note
printf '10 ON ERROR GOTO 100\n20 A$=STRING$(100,"A")\n30 END\n100 PRINT "ERR";ERR/2+1:END\n' > "$tmp"
out=$(run); rc=$?
[ $rc -eq 0 ] && [ "$out" = "ERR 14 " ] || fail "a trapped ?OS (rc=$rc)" "$out"

# at the prompt the ROM's message stands alone
out=$(printf '\nA$=STRING$(100,"A")\nCLEAR MEM-1000\n' | TRS80_DUMB=1 TRS80_Z80= "$here/basic" 2>&1)
case $out in *"basic:"*) fail "a note at the prompt" "$out" ;; esac
case $out in *"?OS ERROR"*"?OV ERROR"*) ;; *) fail "the prompt's own messages" "$out" ;; esac

rm -f "$tmp"
echo "HINTS OK"
