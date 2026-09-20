#!/usr/bin/env python3
"""Regression tests for tok --- run: python3 tools/test_tok.py

The corpus round-trip in DETOK.md is the accuracy measure; these pin the
inverse-of-detok invariants it cannot localise. No dependencies beyond the
standard library.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from detok import detokenize, load_tokens  # noqa: E402
from tok import TokError, crunch, build_index, derive_base, split_lines, tokenize  # noqa: E402

TBL = load_tokens()
IDX = build_index(TBL)
_PASS = _FAIL = 0


def check(cond, msg):
    global _PASS, _FAIL
    if cond:
        _PASS += 1
    else:
        _FAIL += 1
        print("FAIL: %s" % msg)


def eq(got, want, what):
    check(got == want, "%s\n  got  %r\n  want %r" % (what, got, want))


def raises(fn, fragment, what):
    try:
        fn()
    except TokError as exc:
        check(fragment in str(exc), "%s: wrong message %r" % (what, str(exc)))
        return
    check(False, "%s: no TokError raised" % what)


def cr(text):
    return crunch(text, IDX)


# --- crunching mirrors detok.expand ---------------------------------------

eq(cr(b"FORX=1TO4"), b"\x81X\xd51\xbd4", "keywords and operators become tokens")
eq(cr(b"CLS"), b"\x84", "a lone keyword")

# Longest-first matching, or MID$ would crunch as MID followed by a stray $.
eq(cr(b"MID$(A$,1)"), b"\xfa(A$,1)", "MID$ wins over any shorter prefix")
eq(cr(b"LEFT$(A$,1)"), b"\xf8(A$,1)", "LEFT$ wins over LEF")

# The three literal regions, exactly as detok protects them.
eq(cr(b'PRINT"PRINT"'), b'\xb2"PRINT"', "a keyword inside a string stays text")
eq(cr(b"REM PRINT CLS"), b"\x93 PRINT CLS", "REM text is literal to end of line")
eq(cr(b"DATA PRINT,CLS:PRINT"), b"\x88 PRINT,CLS:\xb2", "DATA is literal until a colon")
eq(cr(b'DATA "a:b",PRINT'), b'\x88 "a:b",PRINT', "a colon in a quoted DATA item does not end it")

# ' is stored as the three bytes :REM' -- detok collapses it, so tok restores it.
eq(cr(b"CLS' hi"), b"\x84:\x93\xfb hi", "the apostrophe comment regains its stored :REM")

# --- line splitting --------------------------------------------------------

eq(split_lines(b"10 CLS\n20 END\n"), [(10, b"CLS"), (20, b"END")], "numbers split from bodies")
eq(split_lines(b"10  CLS\r"), [(10, b" CLS")], "only the separator space is removed, not the body's own")
eq(split_lines(b"10 CLS\r\n20 END\r\n"), [(10, b"CLS"), (20, b"END")], "CRLF endings")
eq(split_lines(b"10 CLS\r20 END\r"), [(10, b"CLS"), (20, b"END")], "CR-only endings, the TRS-80's own ASCII save")
eq(split_lines(b'10 REM A\n   B\r20 END\r'), [(10, b"REM A\n   B"), (20, b"END")], "in a CR file an LF is the in-line line feed")
eq(split_lines(b"10 CLS\r20 END\r\x00\x00\x00"), [(10, b"CLS"), (20, b"END")], "sector padding is not a line")
eq(split_lines(b"10 CLS\r20 END\r\x1a"), [(10, b"CLS"), (20, b"END")], "nor is a 1AH end mark")
raises(lambda: split_lines(b"CLS\n"), "no line number", "an unnumbered line is rejected")
raises(lambda: split_lines(b"70000 CLS\n"), "exceeds the maximum", "a line number above 65529 is rejected")

# --- image framing ---------------------------------------------------------

img = tokenize(b"10 CLS\n20 END\n", TBL, 0x42E9)
eq(img[:1], b"\xff", "the image starts with the 0xFF header")
eq(img[-2:], b"\x00\x00", "and ends with the 0x0000 marker")
# record = pointer(2) + number(2) + body + NUL; first body is one byte (CLS)
eq(img[1:3], bytes([(0x42E9 + 6) & 0xFF, (0x42E9 + 6) >> 8]), "the pointer holds the NEXT record's address")
eq(img[3:5], b"\x0a\x00", "line number is little-endian")
eq(derive_base(img), 0x42E9, "the load address is recoverable from the image")

# --- the round-trip invariant ---------------------------------------------

for listing in (
    b"10 FORX=1TO4:PRINT\"HI\";:NEXTX\n20 END\n",
    b"10 REM PRINT CLS\n20 DATA A,B:CLS\n30 A$=MID$(B$,1,2)\n",
    b"10 CLS' comment\n20 IFA=1THEN50:ELSEPRINT\"no\"\n50 END\n",
):
    eq(detokenize(tokenize(listing, TBL), TBL), listing,
       "listing -> image -> listing is identity for %r" % listing[:28])

print("\n%d passed, %d failed" % (_PASS, _FAIL))
sys.exit(1 if _FAIL else 0)
