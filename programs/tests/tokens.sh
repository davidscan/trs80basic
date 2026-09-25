#!/bin/sh
# tokens.sh -- the keyword table is kept twice, in pm_init_index (p75) for
# the tokenizer and the program image, and in tools/level2_tokens.tsv for
# tok.py and detok.py, and the two must be one table (the 2026-09-23 audit,
# L-12): a byte that differs makes the interpreter and tok.py disagree on a
# keyword, and the core executes image bytes.  D1H has a second spelling in
# p75 (^ beside [, both the power operator); the first spelling is the table's.
# Self-checking: exits 1 on any difference.
# Run from the repo root:  sh programs/tests/tokens.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
dir=$(mktemp -d) || exit 2
trap 'rm -rf "$dir"' EXIT
fail() { echo "TOKENS FAILED: $1"; printf '%s\n' "$2"; exit 1; }

# the p75 table: the quoted words between `tbl = "` and the closing `'"`
awk '/tbl = "/ { on = 1 } on { print } on && /FB '\''"/ { exit }' "$here/src/p75_mem.awk" \
    | sed 's/^[^"]*"//; s/" *\\$//; s/"$//' | tr -s ' \n' '\n\n' | grep -v '^$' \
    | awk 'NR % 2 { b = $0; next } !(b in seen) { seen[b] = 1; print b "\t" $0 }' > "$dir/p75"
grep -v '^#' "$here/tools/level2_tokens.tsv" | grep -v '^$' > "$dir/tsv"
[ "$(wc -l < "$dir/p75")" -eq 124 ] || fail "the p75 table did not read as 124 entries" "$(wc -l < "$dir/p75")"
diff "$dir/p75" "$dir/tsv" > "$dir/diff" || fail "p75 and level2_tokens.tsv differ" "$(cat "$dir/diff")"
echo "TOKENS OK"
