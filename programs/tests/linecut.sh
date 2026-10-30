#!/bin/sh
# linecut.sh -- where a text listing's lines end.  LF and CR LF, and CR
# alone: that is the TRS-80's own ASCII save format, and until 2026-09-20
# such a file loaded as ONE line under its first line number (it "ran",
# exit 0, printing next to nothing).  In a CR file an LF is the in-line
# line feed and stays in its line; trailing 00H sector padding and a 1AH
# end mark are not lines.  tools/tok.py must cut the same way: the
# tokenized image of the CR file runs the same.
# Self-checking: exits 1 on any mismatch.  Run from the repo root:
#     sh programs/tests/linecut.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
tmp=$(mktemp -d) || exit 2
fail() { echo "LINECUT FAILED: $1"; printf '%s\n' "$2"; rm -rf "$tmp"; exit 1; }
run() { TRS80_Z80= "$here/basic" "$@" 2>&1 </dev/null; }
want="ONE
TWO 3 "

printf '10 PRINT "ONE"\r20 A=3\r30 PRINT "TWO";A\r' > "$tmp/cr.bas"
out=$(run "$tmp/cr.bas"); [ "$out" = "$want" ] || fail "CR-only endings" "$out"

printf '10 PRINT "ONE"\r20 A=3\r30 PRINT "TWO";A' > "$tmp/crnoeol.bas"
out=$(run "$tmp/crnoeol.bas"); [ "$out" = "$want" ] || fail "CR-only, last line unterminated" "$out"

printf '10 PRINT "ONE"\r20 A=3\r30 PRINT "TWO";A\r\0\0\0\0\0\0' > "$tmp/pad.bas"
out=$(run "$tmp/pad.bas"); [ "$out" = "$want" ] || fail "00H sector padding" "$out"

printf '10 PRINT "ONE"\r20 A=3\r30 PRINT "TWO";A\r\032' > "$tmp/eof.bas"
out=$(run "$tmp/eof.bas"); [ "$out" = "$want" ] || fail "1AH end mark" "$out"

printf '10 PRINT "ONE"\r\n20 A=3\r\n30 PRINT "TWO";A\r\n' > "$tmp/crlf.bas"
out=$(run "$tmp/crlf.bas"); [ "$out" = "$want" ] || fail "CR LF endings" "$out"

printf '10 PRINT "ONE"\n20 A=3\n30 PRINT "TWO";A' > "$tmp/lf.bas"
out=$(run "$tmp/lf.bas"); [ "$out" = "$want" ] || fail "LF endings, last line unterminated" "$out"

# an LF inside a CR file's line is part of the line: the string is 3 long
# and the REM's second row is not a line without a number
# (a CR file is one with no CR LF pair and more CRs than LFs)
printf '10 REM FIRST ROW\n       SECOND ROW\r20 A$="A\nB"\r30 PRINT LEN(A$);\r40 PRINT ASC(MID$(A$,2))\r' > "$tmp/inlf.bas"
out=$(run "$tmp/inlf.bas"); [ "$out" = " 3  10 " ] || fail "in-line LF in a CR file" "$out"

# an LF OUTSIDE a string in a CR file stays in its line and is ?SN when
# the statement runs (RST 10H skips 20H and 09H only, 1D78-1D88) -- from
# the text and from the tokenized image alike (the 2026-09-26 audit)
printf '5 REM X\r10 PRINT \n1+2\r' > "$tmp/lfsn.bas"
out=$(run "$tmp/lfsn.bas"); [ "$out" = "?SN ERROR IN 10" ] || fail "LF outside a string, text load" "$out"
python3 "$here/tools/tok.py" -o "$tmp/tsn" "$tmp/lfsn.bas" >/dev/null 2>&1 || fail "tok.py on the LF listing" "rc=$?"
f=$(ls "$tmp/tsn" | head -1)
out=$(run "$tmp/tsn/$f"); [ "$out" = "?SN ERROR IN 10" ] || fail "LF outside a string, tokenized image ($f)" "$out"

# tok.py cuts the same lines: the tokenized image runs the same
python3 "$here/tools/tok.py" -o "$tmp/tok" "$tmp/cr.bas" "$tmp/inlf.bas" >/dev/null 2>&1 || fail "tok.py on a CR file" "rc=$?"
f=$(ls "$tmp/tok" | grep -i '^cr\.' | head -1)
out=$(run "$tmp/tok/$f"); [ "$out" = "$want" ] || fail "tok.py image of the CR file ($f)" "$out"
f=$(ls "$tmp/tok" | grep -i '^inlf\.' | head -1)
out=$(run "$tmp/tok/$f"); [ "$out" = " 3  10 " ] || fail "tok.py image, in-line LF ($f)" "$out"

# blank is what RST 10H skips: a line of blanks and an in-line LF is
# skipped; a line of FF has no number (?FD), as tools/tok.py says
printf '10 PRINT "ONE"\r \n\r20 A=3\r30 PRINT "TWO";A\r' > "$tmp/blanklf.bas"
out=$(run "$tmp/blanklf.bas"); [ "$out" = "$want" ] || fail "a line holding only an in-line LF is blank" "$out"
printf '10 PRINT "ONE"\n\f\n20 PRINT "TWO"\n' > "$tmp/ff.bas"
out=$(run "$tmp/ff.bas"); rc=$?
case $rc,$out in 2,*"FILE LINE 2 (NO LINE NUMBER)"*) ;; *) fail "a line of FF has no number (rc=$rc)" "$out" ;; esac
mkdir "$tmp/tff"; python3 "$here/tools/tok.py" -o "$tmp/tff" "$tmp/ff.bas" >/dev/null 2>&1 && fail "tok.py took a line of FF for a blank line" ""

rm -rf "$tmp"
echo "LINECUT OK"
