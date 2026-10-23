#!/bin/sh
# args.sh -- the command line: what `basic` takes and refuses before any
# program runs.  A usage error is exit 2 with one "basic: ..." line and the
# usage text on stderr, never a gawk fatal.  Self-checking: exits 1 on any
# mismatch.  Run from the repo root:  sh programs/tests/args.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
fail() { echo "ARGS FAILED: $1"; printf '%s\n' "$2"; exit 1; }

# an empty program-file name: a usage error, not gawk's fatal on
# `getline < ""` (the 2026-09-30 audit, BL-18); and an empty first name
# no longer lets a second file past "only one program file"
out=$(TRS80_Z80= "$here/basic" "" 2>&1 </dev/null); rc=$?
[ "$rc" = "2" ] || fail "an empty file name exits 2 (rc=$rc)" "$out"
case $out in "basic: the program file name is empty"*"Usage: basic "*) ;; *) fail "an empty file name is a usage error" "$out" ;; esac
case $out in *gawk*) fail "no gawk message for an empty file name" "$out" ;; esac
out=$(TRS80_Z80= "$here/basic" "" "$here/programs/tests/types.bas" 2>&1 </dev/null); rc=$?
[ "$rc" = "2" ] && case $out in "basic: the program file name is empty"*) true ;; *) false ;; esac || fail "an empty first name, then a file" "$out"

echo "OK -- the command line"
