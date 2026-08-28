#!/bin/sh
# run_examples.sh -- run every example under ./basic and compare its output
# with the checked-in <name>.out transcript.  --update rewrites the .out files.
#
#   programs/examples/run_examples.sh            # check
#   programs/examples/run_examples.sh --update   # regenerate transcripts
#
# Each example runs with --seed 1, stdin from <name>.in when present, in a
# scratch directory so the file-I/O demos never litter the repo.  The oracle
# talks to the test stub, not a real model, so its transcript is stable.
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 2
root=$(CDPATH= cd -- "$here/../.." && pwd)
update=0; [ "$1" = "--update" ] && update=1
work=$(mktemp -d) || exit 2
trap 'rm -rf "$work"' EXIT
export TRS80_OLLAMA_CURL="sh $root/programs/tests/ollama_stub.sh" TRS80_OLLAMA_MODEL=stub
fail=0
for bas in "$here"/*.bas; do
    name=$(basename "$bas" .bas)
    in="$here/$name.in"; [ -f "$in" ] || in=/dev/null
    got="$work/$name.got"
    (cd "$work" && timeout 30 "$root/basic" --seed 1 "$bas" <"$in" >"$got" 2>&1; echo "exit=$?" >>"$got")
    if [ $update = 1 ]; then
        cp "$got" "$here/$name.out"; echo "updated $name.out"
    elif cmp -s "$got" "$here/$name.out"; then
        echo "ok   $name"
    else
        echo "FAIL $name"; diff "$here/$name.out" "$got" | head -20; fail=1
    fi
done
exit $fail
