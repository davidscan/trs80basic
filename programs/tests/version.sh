#!/bin/sh
# version.sh -- the interpreter names its release: `./basic --version` and the
# `version` metacommand print "trs80basic vX.Y", with "(build <git describe>)"
# behind it when the launcher's checkout is past the tag or dirty.  The
# release is VERSION in p10, bumped in the commit that carries the tag; the
# build is BUILDID, which only the launcher passes.  Self-checking: exits 1
# on any mismatch.  Run from the repo root:  sh programs/tests/version.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
fail() { echo "VERSION FAILED: $1"; printf '%s\n' "$2"; exit 1; }

out=$(TRS80_Z80= "$here/basic" --version 2>&1); rc=$?
[ $rc -eq 0 ] || fail "--version exits 0 (rc=$rc)" "$out"
case $out in "trs80basic v"[0-9]*.[0-9]*) ;; *) fail "the release line" "$out" ;; esac
case $out in *" (build "*")") ;; *"("*) fail "the build's form" "$out" ;; *) ;; esac
[ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] || fail "one line" "$out"
# the release alone without the launcher: no BUILDID
raw=$(gawk -b -f "$here/trs80basic.awk" -- --version 2>&1)
case $raw in "trs80basic v"[0-9]*.[0-9]*) ;; *) fail "the release without the launcher" "$raw" ;; esac
case $raw in *"(build"*) fail "no build outside the launcher" "$raw" ;; esac
rel=$raw
# the launcher's build is the checkout's describe, when git is here
if command -v git >/dev/null 2>&1 && d=$(git -C "$here" describe --tags --always --dirty 2>/dev/null) && [ -n "$d" ]; then
    v=${rel#trs80basic }
    if [ "$d" = "$v" ]; then [ "$out" = "$rel" ] || fail "at the tag, the release alone" "$out"
    else [ "$out" = "$rel (build $d)" ] || fail "past the tag, the build" "$out"; fi
fi
# --version with anything else: still the version, exit 0
out=$(TRS80_Z80= "$here/basic" --seed 1 --version 2>&1); [ "$out" = "$rel" ] || [ "${out%% (build*}" = "$rel" ] || fail "--version behind another option" "$out"
# the metacommand, at the prompt, from a pipe
out=$(printf '\nversion\n' | TRS80_Z80= TRS80_DUMB=1 gawk -b -f "$here/trs80basic.awk" 2>&1)
case $out in *"$rel"*) ;; *) fail "the version metacommand" "$out" ;; esac
echo "OK -- version: $out" | head -1 >/dev/null
echo "OK -- $rel names itself from the shell and at the prompt"
