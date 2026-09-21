#!/bin/sh
# tokload.sh -- CLOAD of a TOKENIZED image (R1, the per-line byte escrow in
# src/p40_repl.awk and pm_body/pm_detok in src/p75_mem.awk).  Self-checking:
# exits 1 on any mismatch.  Run from the repo root:  sh programs/tests/tokload.sh
#
# The image is built here byte by byte, not by tools/tok.py, because it has to
# contain what a text listing cannot: a CR inside a string, a LF inside a REM,
# a payload line of raw bytes (a DATA token, a quote, a REM token, a CR, and
# bytes with no token), and an empty body.  What is checked:
#   1. the program image (PEEK from 42E9H to the 40F9H end) is the file's
#      bytes exactly, relinked at 42E9H -- CR bytes and all;
#   2. the real BASIC lines run (keyword spacing: FORI=1TO3, IFA=1THEN, GOTO259);
#   3. LIST/CSAVE show the detokenized text with the rewrites detok makes;
#   4. CLOAD? verifies the loaded program against the same image;
#   5. a typed replacement, DELETE and NAME drop the escrow (the image is
#      re-crunched from text and no longer byte-identical), NEW clears it;
#   6. a desync (an unterminated last line) is a ?FD line and LOADBAD.
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
tmp=$(mktemp -d) || exit 2
fail() { echo "TOKLOAD FIXTURE FAILED: $1"; [ -n "$2" ] && printf '%s\n' "$2"; rm -rf "$tmp"; exit 1; }

python3 - "$tmp" <<'EOF' || fail "python could not build the image"
import sys
d = sys.argv[1]
def rec(ln, body):
    return ln, body
lines = [
    # 1 GOTO259  -- glued, as the ROM stores it
    (1, b'\x8d259'),
    # 2 the payload: raw bytes, never executed.  88H is the DATA token, 93H REM,
    # 22H a quote, 0DH a CR, FCH/FEH have no token, 00 cannot appear.
    (2, b'\x88\x22\x93\x0d\xfc\xfe\x3e\x0a\x21\x00'.replace(b'\x00', b'')),
    # 3 an empty body (real images carry them)
    (3, b''),
    # 259 FORI=1TO3:A=A+I:NEXT  -- keywords glued to identifiers
    (259, b'\x81I\xd51\xbd3:A\xd5A\xcdI:\x87'),
    # 260 IFA=6THENPRINT"SUM OK":ELSEPRINT"SUM BAD"
    (260, b'\x8fA\xd56\xca\xb2"SUM OK":\x95\xb2"SUM BAD"'),
    # 261 PRINT"A"+CHR$(13)+"B" stored as a literal CR inside the string,
    #     then a REM with a LF in its prose, then the ' form
    (261, b'\xb2"A\x0dB":\x93 LF\x0aHERE'),
    (262, b'\xb2LEN("X"):\x3a\x93\xfb TICK'),
    # 263 DATA 1,\x0d2  -- a CR inside a DATA item becomes a space in the text.
    #     No READ in this program: line 2's 88H byte IS a DATA statement to
    #     READ's scan, here as on the ROM, and would be consumed first.
    (263, b'\x88 1,\x0d2'),
    # 264 N=PEEK(16548)+256*PEEK(16549):PRINT"PAY";PEEK(N+9+4);PEEK(N+9+4+3)
    #     line 1's record is 9 bytes, so N+13 is the payload's first byte (the
    #     DATA token, 136) and N+16 its CR (13) -- the byte detok cannot keep
    (264, b'N\xd5\xe5(16548)\xcd256\xcf\xe5(16549):\xb2"PAY";\xe5(N\xcd9\xcd4);\xe5(N\xcd9\xcd4\xcd3)'),
    (265, b'\xb2"DONE"'),
]
base = 0x42E9
addr = base
img = bytearray(b'\xff')
for ln, body in lines:
    nn = addr + 4 + len(body) + 1
    img += bytes([nn & 255, nn >> 8, ln & 255, ln >> 8]) + body + b'\x00'
    addr = nn
img += b'\x00\x00'
open(d + '/img.bas', 'wb').write(img)
# the same image with the last line's terminator and the end marker cut off
open(d + '/trunc.bas', 'wb').write(bytes(img[:-3]))
# what PEEK must return: everything after the FF marker
open(d + '/expect.bin', 'wb').write(bytes(img[1:]))
EOF

# --- 1 + 2: batch RUN of the image; the program prints the sum, the string
# with its CR (a newline on the streamed screen), and two payload bytes it PEEKs
out=$(TRS80_DUMB=1 "$here/basic" "$tmp/img.bas" 2>"$tmp/err" </dev/null); rc=$?
err=$(cat "$tmp/err")
want='SUM OK
A
B
 1 
PAY 136  13 
DONE'
[ "$rc" = "0" ] || fail "batch run rc=$rc" "$out
$err"
[ "$out" = "$want" ] || fail "batch run output" "$(printf '%s' "$out" | od -c | head -20)"
[ -z "$err" ] || fail "batch run stderr" "$err"

# --- 1: the image bytes, PEEKed from the running interpreter
printf '\nCLOAD "%s"\nFOR I=17129 TO PEEK(16633)+256*PEEK(16634)-1:PRINT PEEK(I):NEXT\n' "$tmp/img.bas" \
    | TRS80_DUMB=1 gawk -b -f "$here/trs80basic.awk" 2>&1 | grep -E '^ *[0-9]+ *$' | tr -d ' ' > "$tmp/peek.txt"
python3 - "$tmp" <<'EOF' || fail "image bytes differ from the file (see above)"
import sys
d = sys.argv[1]
want = open(d + '/expect.bin', 'rb').read()
got = bytes(int(x) for x in open(d + '/peek.txt').read().split())
if got != want:
    diffs = [i for i in range(min(len(got), len(want))) if got[i] != want[i]]
    print('len got %d want %d; first diffs %s' % (len(got), len(want),
          [(hex(0x42E9 + i), want[i], got[i]) for i in diffs[:6]]))
    sys.exit(1)
EOF

# --- 3: LIST text (CSAVE writes the same text) and 4: CLOAD? verify
printf '\nCLOAD "%s"\nCSAVE "%s/text.bas"\nCLOAD? "%s"\nPRINT "VERIFIED"\n' "$tmp/img.bas" "$tmp" "$tmp/img.bas" \
    | TRS80_DUMB=1 gawk -b -f "$here/trs80basic.awk" > "$tmp/out2" 2>&1
grep -q '^VERIFIED' "$tmp/out2" || fail "CLOAD? did not verify" "$(cat "$tmp/out2")"
grep -q '^BAD' "$tmp/out2" && fail "CLOAD? said BAD" "$(cat "$tmp/out2")"
want='1 GOTO 259
3 REM
259 FOR I=1 TO 3:A=A+I:NEXT
260 IF A=6 THEN PRINT"SUM OK":ELSE PRINT"SUM BAD"
261 PRINT"A"+CHR$(13)+"B":REM LF HERE
262 PRINT LEN("X"):'"'"' TICK
263 DATA 1, 2
264 N=PEEK(16548)+256*PEEK(16549):PRINT"PAY";PEEK(N+9+4);PEEK(N+9+4+3)
265 PRINT"DONE"'
got=$(grep -v '^2 ' "$tmp/text.bas")
[ "$got" = "$want" ] || fail "detokenized text" "$got"
grep -q '^2 ' "$tmp/text.bas" || fail "payload line missing from the text"

# --- 5: escrow invalidation -- after each edit the image must NOT equal the file
check_changed() {
    printf '\nCLOAD "%s"\n%s\nFOR I=17129 TO PEEK(16633)+256*PEEK(16634)-1:PRINT PEEK(I):NEXT\n' "$tmp/img.bas" "$1" \
        | TRS80_DUMB=1 gawk -b -f "$here/trs80basic.awk" 2>&1 | grep -E '^ *[0-9]+ *$' | tr -d ' ' > "$tmp/peek2.txt"
    python3 - "$tmp" "$2" <<'EOF' || fail "escrow not dropped by: $1"
import sys
d, mode = sys.argv[1], sys.argv[2]
want = open(d + '/expect.bin', 'rb').read()
got = bytes(int(x) for x in open(d + '/peek2.txt').read().split())
if mode == 'changed' and got == want: sys.exit(1)
if mode == 'empty' and got != b'\x00\x00': sys.exit(1)
EOF
}
check_changed '2 REM TYPED' changed          # a typed replacement of the payload line
check_changed 'DELETE 2' changed             # DELETE
check_changed 'NAME 100,259' changed         # renumber drops every escrow: line 1 GOTO 259 is rewritten too
check_changed 'NEW' empty                    # NEW clears it

# --- 6: a desync stops the walk with a ?FD line, LOADBAD makes batch exit 2
out=$(TRS80_DUMB=1 "$here/basic" "$tmp/trunc.bas" 2>&1 </dev/null); rc=$?
[ "$rc" = "2" ] || fail "truncated image rc=$rc" "$out"
printf '%s' "$out" | grep -q 'FD ERROR - FILE LINE 10 (UNTERMINATED LINE)' || fail "truncated image message" "$out"

# --- 7: a one-byte-short 00 00 end marker is a COMPLETE program.  A tail of
# NUL is a harmless truncation of the marker itself; tools/detok.py has
# always taken it, and this rejected it with ?FD (the 2026-09-19 audit,
# L-19).  The two readers of the same image must agree.
python3 - "$tmp" "$here" <<'PYEOF' || fail "could not build the images" ""
import sys, os
d, here = sys.argv[1], sys.argv[2]
sys.path.insert(0, os.path.join(here, "tools"))
import tok, detok
tbl = detok.load_tokens()
img = tok.tokenize(b'10 PRINT "HI"\n20 END\n', tbl)
open(os.path.join(d, "fullmark.bin"), "wb").write(img)
open(os.path.join(d, "cutmark.bin"), "wb").write(img[:-1])       # one marker byte gone
open(os.path.join(d, "junkmark.bin"), "wb").write(img[:-1] + b"*")  # not NUL
# detok takes the cut image as complete -- that is the agreement being pinned
assert detok.detokenize(img[:-1], tbl) == detok.detokenize(img, tbl)
PYEOF
for f in fullmark cutmark; do
    out=$(TRS80_DUMB=1 TRS80_Z80= "$here/basic" "$tmp/$f.bin" 2>&1 </dev/null); rc=$?
    [ "$out" = "HI" ] || fail "$f.bin ran differently" "$out"
    [ "$rc" = 0 ] || fail "$f.bin exit status" "$rc"
done
# ... while a byte that is NOT NUL where the marker should be is still cut short
out=$(TRS80_DUMB=1 TRS80_Z80= "$here/basic" "$tmp/junkmark.bin" 2>&1 </dev/null); rc=$?
printf '%s' "$out" | grep -q 'TRUNCATED HEADER' \
    || fail "a non-NUL tail should still be cut short" "$out"
[ "$rc" = 2 ] || fail "junkmark.bin exit status" "$rc"

rm -rf "$tmp"
echo "TOKLOAD FIXTURE OK"
