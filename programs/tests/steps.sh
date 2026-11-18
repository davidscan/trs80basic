#!/bin/sh
# steps.sh -- --steps N (EXT, p45/p70): a program file's run stops after N
# BASIC statements with "STEP LIMIT IN n" on stderr and exit 3, at the same
# statement every time.  It is what lets the corpus A/B compare the output
# of a listing that never halts.  Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/steps.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
fail() { echo "STEPS FAILED: $1"; printf '%s\n' "$2"; exit 1; }
t=$(mktemp -d) || exit 2
trap 'rm -rf "$t"' EXIT
run() { TRS80_Z80= TRS80_DUMB=1 "$here/basic" "$@" </dev/null 2>"$t/err" >"$t/out"; }

# an endless loop: the typed RUN is statement 1, then 10, 20, 10, 20, so
# --steps 5 has printed A twice and stops in front of line 10
printf '10 PRINT "A";\n20 GOTO 10\n' > "$t/loop.bas"
run --steps 5 "$t/loop.bas"; rc=$?
[ "$rc" = "3" ] || fail "the limit exits 3 (rc=$rc)" "$(cat "$t/out" "$t/err")"
[ "$(cat "$t/out")" = "AA" ] || fail "two passes before the limit" "$(cat "$t/out")"
[ "$(cat "$t/err")" = "STEP LIMIT IN 10" ] || fail "the message names the line, on stderr" "$(cat "$t/err")"
run --steps=6 "$t/loop.bas"; rc=$?
[ "$rc" = "3" ] && [ "$(cat "$t/err")" = "STEP LIMIT IN 20" ] || fail "--steps=N, stopping at 20 (rc=$rc)" "$(cat "$t/err")"

# the same point at any speed: a throttled run stops where a full-speed one does
run --steps 41 "$t/loop.bas"; a=$(cat "$t/out" "$t/err")
TRS80_MHZ=1.77 run --steps 41 "$t/loop.bas"; b=$(cat "$t/out" "$t/err")
[ "$a" = "$b" ] || fail "the stop point does not depend on the clock" "$a / $b"

# a statement behind THEN or ELSE counts: RUN, 10, the THEN's PRINT, 20 = 4
printf '10 IF 1 THEN PRINT "T";\n20 GOTO 10\n' > "$t/then.bas"
run --steps 4 "$t/then.bas"; rc=$?
[ "$rc" = "3" ] && [ "$(cat "$t/out")" = "T" ] && [ "$(cat "$t/err")" = "STEP LIMIT IN 10" ] \
    || fail "THEN's statement is counted (rc=$rc)" "$(cat "$t/out" "$t/err")"

# a run that ends under the limit is unchanged: 0 for END, 1 for an error
printf '10 FOR I=1 TO 3:PRINT I;:NEXT\n' > "$t/end.bas"
run --steps 1000 "$t/end.bas"; rc=$?
[ "$rc" = "0" ] && [ "$(cat "$t/out")" = " 1  2  3 " ] || fail "a clean end under the limit exits 0 (rc=$rc)" "$(cat "$t/out")"
printf '10 PRINT 1/0\n' > "$t/err.bas"
run --steps 1000 "$t/err.bas"; rc=$?
[ "$rc" = "1" ] || fail "an error under the limit exits 1 (rc=$rc)" "$(cat "$t/err")"

# usage errors: exit 2, one basic: line
for a in "--steps 0" "--steps x" "--steps" "--steps=-1"; do
    out=$(TRS80_Z80= "$here/basic" $a "$t/end.bas" 2>&1 </dev/null); rc=$?
    [ "$rc" = "2" ] && case $out in "basic: --steps needs a statement count of 1 or more"*) true ;; *) false ;; esac \
        || fail "$a is a usage error (rc=$rc)" "$out"
done
out=$(TRS80_Z80= "$here/basic" --steps 5 2>&1 </dev/null); rc=$?
[ "$rc" = "2" ] && case $out in "basic: --steps and --steps-report need a program file"*) true ;; *) false ;; esac \
    || fail "--steps without a program file (rc=$rc)" "$out"
out=$(TRS80_Z80= "$here/basic" -h 2>&1 </dev/null)
case $out in *"--steps N"*"3 the --steps limit stopped it"*) ;; *) fail "--help names --steps and exit 3" "$out" ;; esac

# --steps-report FILE: the run's statement count, one line, on every exit.
# FOR I=1 TO 3:PRINT I;:NEXT is RUN, FOR, then PRINT and NEXT three times: 8
run --steps-report "$t/r1" "$t/end.bas"; rc=$?
[ "$rc" = "0" ] && [ "$(cat "$t/r1")" = "8" ] && [ "$(cat "$t/out")" = " 1  2  3 " ] \
    || fail "the report counts a clean run, output untouched (rc=$rc)" "$(cat "$t/r1" "$t/out")"
run --steps 5 --steps-report "$t/r2" "$t/loop.bas"; rc=$?
[ "$rc" = "3" ] && [ "$(cat "$t/r2")" = "5" ] || fail "a stopped run reports N, not N+1 (rc=$rc)" "$(cat "$t/r2")"
run --steps-report "$t/r3" "$t/err.bas"; rc=$?
[ "$rc" = "1" ] && [ "$(cat "$t/r3")" = "2" ] || fail "an error exit still reports (RUN, PRINT: 2; rc=$rc)" "$(cat "$t/r3")"
run --clear 100 --steps-report "$t/r4" "$t/end.bas"
[ "$(cat "$t/r4")" = "8" ] || fail "--clear's CLEAR is not the run's" "$(cat "$t/r4")"
# the file does not exist while the program runs: it is made at the end
cd "$t" && printf '10 OPEN "I",1,"r6"\n' > see.bas
TRS80_Z80= TRS80_DUMB=1 "$here/basic" --steps-report r6 see.bas </dev/null >"$t/out" 2>&1
cd - >/dev/null
case $(cat "$t/out") in *"ERROR IN 10"*) true ;; *) false ;; esac && [ "$(cat "$t/r6")" = "2" ] \
    || fail "no report file during the run (the program could not open it)" "$(cat "$t/out" "$t/r6")"
# a path that cannot be written is exit 2 before the program runs
run --steps-report "$t/no/such/dir/r" "$t/end.bas"; rc=$?
[ "$rc" = "2" ] && [ ! -s "$t/out" ] && case $(cat "$t/err") in *"--steps-report: cannot write"*) true ;; *) false ;; esac \
    || fail "an unwritable report is exit 2, nothing run (rc=$rc)" "$(cat "$t/out" "$t/err")"
out=$(TRS80_Z80= "$here/basic" --steps-report 2>&1 </dev/null); rc=$?
[ "$rc" = "2" ] && case $out in "basic: --steps-report needs a file name"*) true ;; *) false ;; esac \
    || fail "--steps-report with no name (rc=$rc)" "$out"
out=$(TRS80_Z80= "$here/basic" --steps-report "$t/r5" 2>&1 </dev/null); rc=$?
[ "$rc" = "2" ] && case $out in "basic: --steps and --steps-report need a program file"*) true ;; *) false ;; esac \
    || fail "--steps-report without a program file (rc=$rc)" "$out"
: > "$t/game.cmd"
out=$(TRS80_Z80= "$here/basic" --steps 9 "$t/game.cmd" 2>&1 </dev/null); rc=$?
[ "$rc" = "2" ] && case $out in *"a /CMD file has none"*) true ;; *) false ;; esac \
    || fail "--steps with a /CMD file (rc=$rc)" "$out"

echo "OK -- --steps"
