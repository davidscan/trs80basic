#!/bin/sh
# goto.sh -- "GO TO" is GOTO.  ROM 1C24-1C2A: while the cruncher is matching
# token 8DH, and ONLY that one, it skips a blank in the input, so GO TO
# matches the GOTO keyword.  It was ?SN here (the 2026-09-19 audit, L-16).
# GO SUB does not crunch: the skip belongs to GOTO alone.
#
# Three crunchers have to agree, or the same listing gives two different
# tokenized images: the tokenizer (p50), the program image's pm_crunch (p75)
# and tools/tok.py.  The image check below is the one that catches a drift,
# because the core executes image bytes.
# Self-checking: exits 1 on any mismatch.
# Run from the repo root:  sh programs/tests/goto.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
tmp=$(mktemp) || exit 2
trap 'rm -f "$tmp"' EXIT
fail() { echo "GOTO FAILED: $1"; printf '%s\n' "$2"; exit 1; }
run() { TRS80_Z80= "$here/basic" "$tmp" 2>&1 </dev/null; }

cat > "$tmp" <<'BAS'
10 GO TO 40
20 PRINT "NOT REACHED"
30 PRINT "NOR THIS"
40 PRINT "PLAIN"
50 GO   TO 70
60 PRINT "NOT REACHED EITHER"
70 PRINT "SEVERAL BLANKS"
80 IF 1 THEN GO TO 100
90 PRINT "NOT REACHED AFTER THEN"
100 PRINT "AFTER THEN"
110 ON 1 GO TO 130
120 PRINT "NOT REACHED AFTER ON"
130 PRINT "AFTER ON"
BAS
out=$(run | tr '\n' ' ')
[ "$out" = "PLAIN SEVERAL BLANKS AFTER THEN AFTER ON " ] \
    || fail "GO TO as a statement, after THEN and after ON" "$out"

# GO SUB is still ?SN, as it is on the machine
printf '10 GO SUB 30\n20 END\n30 RETURN\n' > "$tmp"
out=$(run)
[ "$out" = "?SN ERROR IN 10" ] || fail "GO SUB should stay ?SN" "$out"

# a variable whose name begins with GO is untouched
printf '10 GOAL=7:PRINT GOAL\n20 GO=3:PRINT GO\n' > "$tmp"
out=$(run | tr '\n' ' ')
[ "$out" = " 7   3  " ] || fail "a variable named GO or GOAL" "$out"

# the IMAGE: GO TO and GOTO crunch to the same bytes, 8DH among them
printf '10 GO TO 20\n20 FOR I=17129 TO 17140:PRINT PEEK(I);:NEXT\n' > "$tmp"
spaced=$(run)
printf '10 GOTO 20\n20 FOR I=17129 TO 17140:PRINT PEEK(I);:NEXT\n' > "$tmp"
plain=$(run)
[ "$spaced" = "$plain" ] || fail "the image differs between GO TO and GOTO" \
    "GO TO: $spaced
GOTO : $plain"
case $spaced in *" 141 "*) ;; *) fail "the image has no GOTO token (141)" "$spaced" ;; esac

echo "GOTO OK"
