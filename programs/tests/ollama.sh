#!/bin/sh
# ollama.sh -- the OLLAMA channel (EXT) against ollama_stub.sh.  A prompt
# that is waiting goes out at the NEXT read, even when lines of the
# previous reply are still unread: a program that takes only line 1 of
# each answer (the @TOKENS pattern) must get line 1 of the NEW answer, not
# line 2 of the old one.  The stub's reply counts the messages it was
# sent, so which request produced a line is visible.  Self-checking: exits
# 1 on any mismatch.  Run from the repo root:  sh programs/tests/ollama.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
dir=$(mktemp -d) || exit 2
fail() { echo "OLLAMA FAILED: $1"; printf '%s\n' "$2"; rm -rf "$dir"; exit 1; }
cat > "$dir/t.bas" <<'BAS'
10 OPEN "O",1,"OLLAMA:stub"
20 PRINT#1,"Q1":LINE INPUT#1,A$:PRINT "Q1 -> ";A$
30 PRINT#1,"Q2":LINE INPUT#1,A$:PRINT "Q2 -> ";A$
40 LINE INPUT#1,A$:PRINT "Q2 LINE 2 -> ";A$
50 PRINT#1,"@TOKENS NO,YES":PRINT#1,"Q3":LINE INPUT#1,T$:PRINT "Q3 TOKEN -> ";T$
60 PRINT#1,"@TOKENS YES,NO":PRINT#1,"Q4";:LINE INPUT#1,T$:PRINT "Q4 TOKEN -> ";T$
70 LINE INPUT#1,A$:PRINT "Q4 REPLY -> ";A$
80 LINE INPUT#1,A$:PRINT "EOF";EOF(1);".":CLOSE 1
BAS
out=$(cd "$dir" && TRS80_Z80= TRS80_OLLAMA_CURL="sh $here/programs/tests/ollama_stub.sh" \
      "$here/basic" t.bas 2>&1)
want='Q1 -> Msgs=1 T=- K=-, hello
Q2 -> Msgs=3 T=- K=-, hello
Q2 LINE 2 -> line "two"
Q3 TOKEN -> YES
Q4 TOKEN -> NO
Q4 REPLY -> Msgs=7 T=- K=-
EOF-1 .'
[ "$out" = "$want" ] || fail "a waiting prompt is sent at the next read" "$out"
rm -rf "$dir"
echo "OLLAMA OK"
