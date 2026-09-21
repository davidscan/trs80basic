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

# The request body's scratch file (the 2026-09-19 audit, M-5).  Its name
# must not be guessable from the pid -- on a shared /tmp a planted symlink
# under a known name has the body written over any file the user can
# write -- it is private (0600), it is gone after the request, a temp
# directory with a quote and a blank in its name is one shell word, and a
# temp directory that cannot be written is a BASIC error, not a gawk fatal.
cat > "$dir/spy.sh" <<SPY
#!/bin/sh
for a; do f=\$a; done
printf '%s\n' "\$f" > "$dir/spy.name"
ls -l "\$f" | cut -c1-10 > "$dir/spy.mode"
exec sh "$here/programs/tests/ollama_stub.sh" "\$@"
SPY
cat > "$dir/u.bas" <<'BAS'
10 ON ERROR GOTO 90
20 OPEN "O",1,"OLLAMA:stub"
30 PRINT#1,"Q1":LINE INPUT#1,A$:PRINT "Q1 -> ";A$
40 PRINT "SURVIVED":END
90 PRINT "ERROR";ERR/2+1;"IN";STR$(ERL):RESUME 40
BAS
mkdir "$dir/t m'p" || exit 2
out=$(cd "$dir" && TMPDIR="$dir/t m'p" TRS80_Z80= TRS80_OLLAMA_CURL="sh $dir/spy.sh" \
      "$here/basic" u.bas 2>&1)
want='Q1 -> Msgs=1 T=- K=-, hello
SURVIVED'
[ "$out" = "$want" ] || fail "a temp directory with a quote and a blank in its name" "$out"
name=$(cat "$dir/spy.name")
case $name in
"$dir/t m'p/"*) ;;
*) fail "the request file is made in TMPDIR" "$name" ;;
esac
case ${name##*/} in
*_[0-9]*.json|"") fail "the request file's name is not built from the pid" "$name" ;;
esac
[ "$(cat "$dir/spy.mode")" = "-rw-------" ] || fail "the request file is private" "$(cat "$dir/spy.mode")"
[ ! -e "$name" ] || fail "the request file is removed after the request" "$name"
[ -z "$(ls -A "$dir/t m'p")" ] || fail "nothing is left in TMPDIR" "$(ls -A "$dir/t m'p")"

out=$(cd "$dir" && TMPDIR="$dir/nowhere" TRS80_Z80= TRS80_OLLAMA_CURL="sh $dir/spy.sh" \
      "$here/basic" u.bas 2>&1)
want='ERROR 22 IN 30
SURVIVED'
[ "$out" = "$want" ] || fail "a temp directory that cannot be written is an error, not a fatal" "$out"
# The JSON string decoder: \b and \f are the backspace and form feed, not
# the letters "b" and "f", and a SURROGATE PAIR is one code point -- the
# pair D83D DE00 is U+1F600, four UTF-8 bytes, not two 3-byte halves
# (CESU-8, which no reader accepts).  Both were wrong (the 2026-09-19
# audit, L-36).  An UNPAIRED surrogate is still encoded as it stands;
# strictly it should become U+FFFD, but that is beyond the finding.
#
# The stub emits its JSON with cat and a QUOTED heredoc, not printf:
# macOS's printf interprets \uHHHH even in a %s argument, so a printf stub
# would hand over the emoji as raw UTF-8 and never reach the decoder.
cat > "$dir/esc.sh" <<'STUBEOF'
#!/bin/sh
# B is one backslash, built rather than written: every layer between here
# and the file (printf, the editor, the heredoc) has its own opinion about
# a literal backslash-u, and this way none of them gets to have one.
B=$(printf '%s' '\')
Q='"'
cat <<JEOF
{"message":{"role":"assistant","content":"A${B}bB${B}fC|${B}u00E9|${B}uD83D${B}uDE00|${B}uD83D|${B}${B}|${B}/|${B}${Q}q${B}${Q}"},"done":true}
JEOF
STUBEOF
cat > "$dir/e.bas" <<'BAS'
10 OPEN "O",1,"OLLAMA:stub"
20 PRINT#1,"Q":LINE INPUT#1,A$
30 FOR I=1 TO LEN(A$):PRINT ASC(MID$(A$,I,1)):NEXT:CLOSE
BAS
out=$(cd "$dir" && TRS80_Z80= TRS80_OLLAMA_CURL="sh $dir/esc.sh" \
      "$here/basic" e.bas 2>&1 | tr -d ' ' | tr '\n' ',')
#  A  \b  B  \f  C  |  U+00E9   |  U+1F600            |  lone D83D    |  \  |  /  |  "  q  "
want='65,8,66,12,67,124,195,169,124,240,159,152,128,124,237,160,189,124,92,124,47,124,34,113,34,'
[ "$out" = "$want" ] || fail "the JSON escapes b, f and a surrogate pair" "$out"

rm -rf "$dir"
echo "OLLAMA OK"
