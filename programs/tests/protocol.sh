#!/bin/sh
# protocol.sh -- PROTOCOL.md agrees with the code: the version its handshake
# lines state is the interpreter's Z80PROTO and the reference stub's, and
# the core's copy, when a core is checked out beside this repo, is
# byte-identical (the 2026-09-30 audit, XM-4a: nothing opened the file, so
# a stale number or a drifted mirror passed every suite).
# Self-checking: exits 1 on any mismatch.  Run from the repo root:
#     sh programs/tests/protocol.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
fail() { echo "PROTOCOL FIXTURE FAILED: $1"; exit 1; }

doc=$(sed -n 's/^interpreter -> core   HELLO proto=\([0-9]*\) .*/\1/p' "$here/PROTOCOL.md")
reply=$(sed -n 's/^core -> interpreter   Z80 proto=\([0-9]*\) .*/\1/p' "$here/PROTOCOL.md")
awkv=$(sed -n 's/^ *Z80PROTO = \([0-9]*\)$/\1/p' "$here/src/p77_z80.awk")
stub=$(sed -n 's/^PROTO = os.environ.get("Z80_STUB_PROTO", "\([0-9]*\)")$/\1/p' "$here/programs/tests/z80_stub.py")
[ -n "$doc" ] || fail "no 'HELLO proto=N' line in PROTOCOL.md"
[ "$reply" = "$doc" ] || fail "PROTOCOL.md: HELLO says proto=$doc, the Z80 reply proto=$reply"
[ "$awkv" = "$doc" ] || fail "PROTOCOL.md says proto=$doc, src/p77_z80.awk Z80PROTO is '$awkv'"
[ "$stub" = "$doc" ] || fail "PROTOCOL.md says proto=$doc, z80_stub.py's PROTO is '$stub'"

peer="$here/../trs80_z80_core/PROTOCOL.md"
if [ -f "$peer" ]; then
    cmp -s "$here/PROTOCOL.md" "$peer" || fail "the core's PROTOCOL.md is not a byte-identical mirror of this one ($peer)"
    echo "PROTOCOL FIXTURE OK"
else
    echo "PROTOCOL FIXTURE OK (SKIPPED: the mirror check, no core at $peer)"
fi
