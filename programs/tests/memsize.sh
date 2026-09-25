#!/bin/sh
# memsize.sh -- --memsize N answers MEM SIZE? for a run with no prompt.
# Batch mode otherwise sees all 64K, and a program written on a 16K machine
# can depend on a smaller one: it makes an address byte signed (IF H>127
# THEN H=H-256) and POKEs it, which is ?FC -- on the machine too -- wherever
# string space sits above 32767.  Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/memsize.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
tmp=$(mktemp) || exit 2
fail() { echo "MEMSIZE FAILED: $1"; printf '%s\n' "$2"; rm -f "$tmp"; exit 1; }
run() { TRS80_Z80= "$here/basic" "$@" "$tmp" 2>&1 </dev/null; }

printf '10 PRINT PEEK(16561)+256*PEEK(16562)\n' > "$tmp"
out=$(run);                  [ "$out" = " 65535 " ] || fail "default top of memory" "$out"
out=$(run --memsize 32767);  [ "$out" = " 32767 " ] || fail "--memsize 32767" "$out"
out=$(run --memsize=20000);  [ "$out" = " 20000 " ] || fail "--memsize=20000" "$out"

# the 16K idiom: the string's address, high byte made signed, POKEd back
printf '10 A$="AB"+"CD":V=VARPTR(A$):L=PEEK(V+1):H=PEEK(V+2):IF H>127 THEN H=H-256\n20 POKE 16526,L:POKE 16527,H:PRINT "OK";PEEK(16527)\n' > "$tmp"
out=$(run); rc=$?
[ $rc -eq 1 ] && [ "$out" = "?FC ERROR IN 20" ] || fail "the signed high byte is ?FC on a 48K map (rc=$rc)" "$out"
out=$(run --memsize 32767); rc=$?
case $out in "OK 12"[0-7]" ") ;; *) fail "the 16K idiom under --memsize 32767 (rc=$rc)" "$out" ;; esac

# bad values are a usage error, exit 2
for v in 17279 65536 abc ""; do
    out=$(run --memsize "$v"); rc=$?
    [ $rc -eq 2 ] || fail "--memsize '$v' was accepted (rc=$rc)" "$out"
done

# at the prompt the option answers MEM SIZE?, so the first piped line is a command
out=$(printf 'PRINT PEEK(16561)+256*PEEK(16562)\n' | TRS80_DUMB=1 TRS80_Z80= "$here/basic" --memsize 30000 2>&1)
case $out in *"MEM SIZE? 30000"*" 30000 "*) ;; *) fail "--memsize at the prompt" "$out" ;; esac

rm -f "$tmp"
echo "MEMSIZE OK"
