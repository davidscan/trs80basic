#!/bin/sh
# clearopt.sh -- --clear N is the CLEAR N a period user typed before RUN.
# String space is 50 bytes at power-on and only CLEAR n raises it (the Level
# II manual, CLEAR); a listing that assumed the CLEAR was typed first stops
# with ?OS here, as it did on the machine without it.  The option types it:
# after LOAD and before RUN in batch, at the first READY at the prompt.  The
# program's own CLEAR n still wins, and an N the map cannot hold is CLEAR's
# own ?OM.  Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/clearopt.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
tmp=$(mktemp) || exit 2
fail() { echo "CLEAROPT FAILED: $1"; printf '%s\n' "$2"; rm -f "$tmp"; exit 1; }
run() { TRS80_Z80= "$here/basic" "$@" "$tmp" 2>&1 </dev/null; }

# 200 bytes of strings and no CLEAR: ?OS without the option, runs with it
printf '10 A$=STRING$(100,"A"):B$=STRING$(100,"B")\n20 PRINT "OK";LEN(A$+B$)\n' > "$tmp"
out=$(run); rc=$?
case $rc,$out in 1,"?OS ERROR IN 10"*) ;; *) fail "no CLEAR is ?OS (rc=$rc)" "$out" ;; esac
out=$(run --clear 1000); rc=$?
[ $rc -eq 0 ] && [ "$out" = "OK 200 " ] || fail "--clear 1000 (rc=$rc)" "$out"
out=$(run --clear=1000); rc=$?
[ $rc -eq 0 ] && [ "$out" = "OK 200 " ] || fail "--clear=1000 (rc=$rc)" "$out"

# the space is CLEAR's: FRE("") reports it, and the program's own CLEAR wins
printf '10 PRINT FRE("")\n' > "$tmp"
out=$(run);              [ "$out" = " 50 " ]   || fail "default string space" "$out"
out=$(run --clear 1000); [ "$out" = " 1000 " ] || fail "FRE(\"\") under --clear 1000" "$out"
out=$(run --clear 0);    [ "$out" = " 0 " ]    || fail "--clear 0" "$out"
printf '10 CLEAR 60:PRINT FRE("")\n' > "$tmp"
out=$(run --clear 1000); [ "$out" = " 60 " ]   || fail "the program's own CLEAR wins" "$out"

# an N the map cannot hold below the program is CLEAR's ?OM, and no run
printf '10 PRINT "RAN"\n' > "$tmp"
out=$(run --memsize 20000 --clear 19000); rc=$?
case $rc,$out in 2,"?OM ERROR"*"--clear 19000"*) ;; *) fail "--clear past the map is ?OM, exit 2 (rc=$rc)" "$out" ;; esac
case $out in *RAN*) fail "the program ran after CLEAR's ?OM" "$out" ;; esac

# bad values are a usage error, exit 2
for v in -1 32768 abc ""; do
    out=$(run --clear "$v"); rc=$?
    [ $rc -eq 2 ] || fail "--clear '$v' was accepted (rc=$rc)" "$out"
done

# at the prompt the CLEAR is typed at the first READY, shown as typed
out=$(printf '\nPRINT FRE("")\n' | TRS80_DUMB=1 TRS80_Z80= "$here/basic" --clear 500 2>&1)
case $out in *"READY"*">CLEAR 500"*"READY"*" 500 "*) ;; *) fail "--clear at the prompt" "$out" ;; esac

rm -f "$tmp"
echo "CLEAROPT OK"
