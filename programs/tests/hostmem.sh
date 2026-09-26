#!/bin/sh
# hostmem.sh -- `--memory host` (EXT): the machine's capacity ceilings lifted
# for new code, the default `--memory rom` untouched.  Host mode never says
# ?OM, ?OS or ?LS, takes any subscript, DIM bound or CLEAR count, any string
# length and count, reads a file's line or item whole, and a piped INPUT
# line whole; MEM and FRE count against a 2^31-1 top.  PEEK, POKE, VARPTR
# and the program image stay the 64K machine (a long string's length byte
# is 255, its first 255 bytes are packed).  Batch mode's stderr note behind
# ?OM, ?OV, ?LS and the program's-own-CLEAR ?OS names the option.  The
# switch has four forms: the option, TRS80_MEMORY=host, the `memory`
# metacommand and REM META: memory host under the ext gate.  Self-checking:
# exits 1 on any mismatch.  Run from the repo root:  sh programs/tests/hostmem.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
tmp=$(mktemp) || exit 2
dat=$(mktemp) || exit 2
fail() { echo "HOSTMEM FAILED: $1"; printf '%s\n' "$2"; rm -f "$tmp" "$dat"; exit 1; }
run() { TRS80_Z80= TRS80_MEMORY= "$here/basic" "$@" "$tmp" 2>&1 </dev/null; }
runout() { TRS80_Z80= TRS80_MEMORY= "$here/basic" "$@" "$tmp" 2>/dev/null </dev/null; }
host() { run --memory host "$@"; }
HINT='try --memory host'

# --- the machine, and the note that names the option -----------------------
printf '10 DIM A(100000)\n' > "$tmp"
out=$(run); rc=$?
case $out in "?OV ERROR IN 10
basic: "*"$HINT"*) ;; *) fail "DIM past 32767 is ?OV with the note (rc=$rc)" "$out" ;; esac
[ $rc -eq 1 ] || fail "?OV exit status" "$rc"
out=$(runout);           [ "$out" = "" ] || fail "the note reached stdout" "$out"
printf '10 A(40000)=1\n' > "$tmp"
out=$(run); case $out in "?OV ERROR IN 10
basic: "*"$HINT"*) ;; *) fail "a subscript past 32767" "$out" ;; esac
printf '10 CLEAR 200000\n' > "$tmp"
out=$(run); case $out in "?OV ERROR IN 10
basic: "*"$HINT"*) ;; *) fail "CLEAR past 32767" "$out" ;; esac
printf '10 DIM A(20000)\n' > "$tmp"
out=$(run); case $out in "?OM ERROR IN 10
basic: "*"$HINT"*) ;; *) fail "a DIM that does not fit is ?OM with the note" "$out" ;; esac
printf '10 CLEAR 1000:A$=STRING$(200,"A"):B$=A$+A$\n' > "$tmp"
out=$(run); case $out in "?LS ERROR IN 10
basic: "*"$HINT"*) ;; *) fail "?LS with the note" "$out" ;; esac
printf '10 CLEAR 60\n20 A$=STRING$(100,"A"):B$=STRING$(100,"B")\n' > "$tmp"
out=$(run); case $out in "?OS ERROR IN 20
basic: the program's own CLEAR 60"*"$HINT"*) ;; *) fail "the program's own CLEAR names the option too" "$out" ;; esac
# an unrelated ?OV gets no note: the flag is per raise
printf '10 A%%=40000\n' > "$tmp"
out=$(run); [ "$out" = "?OV ERROR IN 10" ] || fail "a numeric ?OV has no note" "$out"
printf '10 CLEAR 1000\n20 GOSUB 20\n' > "$tmp"
out=$(run); case $out in "?OM ERROR IN 20"*) ;; *) fail "runaway GOSUB is ?OM on the machine" "$out" ;; esac

# --- host mode: the ceilings lifted -----------------------------------------
printf '10 PRINT MEM>2E9;FRE(0)>2E9;FRE("")>2E9\n' > "$tmp"
out=$(host); [ "$out" = "-1 -1 -1 " ] || fail "MEM and FRE against the virtual top" "$out"
printf '10 CLEAR 200000:DIM A(100000),B(40000):A(100000)=7:B(40000)=3:PRINT A(100000);B(40000);FRE("")>1E9\n' > "$tmp"
out=$(host); [ "$out" = " 7  3 -1 " ] || fail "CLEAR, DIM and a subscript past 32767" "$out"
printf '10 DIM A(20000),B$(30000):PRINT MEM<2147483647-80000\n' > "$tmp"
out=$(host); [ "$out" = "-1 " ] || fail "MEM still counts the arrays" "$out"
printf '10 CLEAR 60\n20 A$=STRING$(255,"A"):B$=A$+A$+A$:PRINT LEN(B$);LEN(LEFT$(B$,600));LEN(MID$(B$,300));LEN(MID$(B$,2,700));LEN(RIGHT$(B$,500));LEN(STRING$(1000,"X"));INSTR(700,B$,"A")\n' > "$tmp"
out=$(host); [ "$out" = " 765  600  466  700  500  1000  700 " ] || fail "long strings and counts" "$out"
printf '10 GOSUB 20:PRINT N:END\n20 N=N+1:IF N<10000 THEN GOSUB 20\n30 RETURN\n' > "$tmp"
out=$(host); [ "$out" = " 10000 " ] || fail "10000 GOSUB frames" "$out"
# a file's line and item come back whole
awk 'BEGIN { s = sprintf("%2082s", ""); gsub(/ /, "A", s); print s; print "END"; t = sprintf("%300s", ""); gsub(/ /, "B", t); print t ",X" }' > "$dat"
printf '10 CLEAR 3000:OPEN "I",1,"%s":LINE INPUT #1,A$:LINE INPUT #1,B$:INPUT #1,C$,D$:PRINT LEN(A$);B$;LEN(C$);D$\n' "$dat" > "$tmp"
out=$(host); [ "$out" = " 2082 END 300 X" ] || fail "LINE INPUT# and INPUT# read whole" "$out"
out=$(run);  case $out in " 255 AAAAAAAAAA"*) ;; *) fail "the machine cuts at 255 (unchanged)" "$out" ;; esac
# a piped INPUT line comes back whole, and the cut note is silent
printf '10 CLEAR 1000:LINE INPUT A$:PRINT LEN(A$)\n' > "$tmp"
long=$(awk 'BEGIN { s = sprintf("%500s", ""); gsub(/ /, "Q", s); print s }')
out=$(printf '%s\n' "$long" | TRS80_Z80= "$here/basic" --memory host "$tmp" 2>&1)
case $out in *" 500 ") ;; *) fail "a piped INPUT line past 240" "$out" ;; esac
out=$(printf '%s\n' "$long" | TRS80_Z80= "$here/basic" "$tmp" 2>&1)
case $out in *"INPUT LINE CUT AT 240"*" 240 ") ;; *) fail "the machine cuts a piped line at 240 (unchanged)" "$out" ;; esac
# VARPTR of a long string: the length byte is 255, the first 255 bytes are packed
printf '10 A$=STRING$(255,"A")+"B":V=VARPTR(A$):P=PEEK(V+1)+256*PEEK(V+2):IF P>32767 THEN P=P-65536
20 PRINT LEN(A$);PEEK(V);PEEK(P);PEEK(P+254)\n' > "$tmp"
out=$(host); [ "$out" = " 256  255  65  65 " ] || fail "a long string through VARPTR" "$out"
# an image past 65535 still runs; the truncation note stays, said (on
# stderr) the first time the image is consulted, as ever
awk 'BEGIN { s = sprintf("%230s", ""); gsub(/ /, "R", s); for (i = 1; i <= 260; i++) print i * 10, "REM " s; print 2700, "PRINT \"OK\"" }' > "$tmp"
out=$(host); [ "$out" = "OK" ] || fail "an oversized image runs, silently until the image is consulted" "$out"
awk 'BEGIN { s = sprintf("%230s", ""); gsub(/ /, "R", s); for (i = 1; i <= 260; i++) print i * 10, "REM " s; print 2700, "X=MEM:PRINT \"OK\"" }' > "$tmp"
out=$(host); case $out in "PROGRAM IMAGE TRUNCATED: LINE "*"OK") ;; *) fail "the note when the image is consulted" "$out" ;; esac
out=$(runout --memory host); [ "$out" = "OK" ] || fail "the note is stderr" "$out"

# --- the four switch forms --------------------------------------------------
printf '10 DIM A(100000):PRINT "OK"\n' > "$tmp"
out=$(host);                        [ "$out" = "OK" ] || fail "--memory host" "$out"
out=$(run --memory=host);           [ "$out" = "OK" ] || fail "--memory=host" "$out"
out=$(run --memory rom); case $out in "?OV ERROR IN 10"*) ;; *) fail "--memory rom" "$out" ;; esac
out=$(TRS80_Z80= TRS80_MEMORY=host "$here/basic" "$tmp" 2>&1 </dev/null); [ "$out" = "OK" ] || fail "TRS80_MEMORY=host" "$out"
out=$(TRS80_Z80= TRS80_MEMORY=host "$here/basic" --memory rom "$tmp" 2>&1 </dev/null); case $out in "?OV ERROR IN 10"*) ;; *) fail "--memory rom overrides the environment" "$out" ;; esac
out=$(TRS80_Z80= TRS80_MEMORY=ROM "$here/basic" "$tmp" 2>&1 </dev/null); case $out in "?OV ERROR IN 10"*) ;; *) fail "only the word host turns it on" "$out" ;; esac
out=$(run --memory big); rc=$?; [ $rc -eq 2 ] || fail "--memory big is a usage error (rc=$rc)" "$out"
case $out in "basic: --memory takes host or rom"*) ;; *) fail "the usage message" "$out" ;; esac
out=$(run --memory host --memsize 32767); rc=$?; [ $rc -eq 2 ] || fail "--memory host with --memsize is a usage error (rc=$rc)" "$out"
case $out in "basic: --memory host and --memsize cannot be combined"*) ;; *) fail "the combination message" "$out" ;; esac
printf '10 REM META: memory host\n20 DIM A(100000):PRINT "OK"\n' > "$tmp"
out=$(TRS80_Z80= TRS80_EXT=1 "$here/basic" "$tmp" 2>&1 </dev/null); [ "$out" = "OK" ] || fail "REM META: memory host under the gate" "$out"
out=$(run); case $out in "?OV ERROR IN 20"*) ;; *) fail "REM META: memory host is a remark with the gate off" "$out" ;; esac
printf '10 REM META: memory rom\n20 DIM A(100000):PRINT "OK"\n' > "$tmp"
out=$(TRS80_Z80= TRS80_EXT=1 "$here/basic" --memory host "$tmp" 2>&1 </dev/null); case $out in "?OV ERROR IN 20"*) ;; *) fail "REM META: memory rom" "$out" ;; esac
# the metacommand at the prompt: shows, sets, takes effect at once
out=$(printf '\nmemory\nmemory host\nmemory\n10 DIM A(100000):PRINT "OK"\nRUN\nmemory rom\nRUN\nmemory bogus\n' | TRS80_Z80= TRS80_DUMB=1 gawk -b -f "$here/trs80basic.awk" 2>&1)
case $out in *"MEMORY ROM"*"MEMORY HOST"*"OK"*"?OV ERROR IN 10"*"USAGE: memory host|rom"*) ;; *) fail "the memory metacommand" "$out" ;; esac
case $out in *"MEMORY HOST"*"MEMORY ROM"*"OK"*) fail "memory host was reported before it was set" "$out" ;; esac

rm -f "$tmp" "$dat"
echo "OK -- host memory mode: the ceilings lifted, the machine unchanged, the notes, the four switch forms"
