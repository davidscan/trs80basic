#!/usr/bin/env python3
"""Regression tests for detok --- run: python3 tools/test_detok.py

The corpus sweep in DETOK.md is the accuracy measure; these pin the individual
decisions that a sweep cannot localise -- literal-region handling and the
documented rewrites. No dependencies beyond the standard library.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from detok import DetokError, detokenize, expand, load_tokens  # noqa: E402

TBL = load_tokens()
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
    except DetokError as exc:
        check(fragment in str(exc), "%s: wrong message %r" % (what, str(exc)))
        return
    check(False, "%s: no DetokError raised" % what)


def image(*lines):
    """Build a tokenized image from (line number, body bytes) pairs."""
    out = bytearray([0xFF])
    for number, body in lines:
        # Any non-zero next-line pointer will do -- detok frames records by the
        # NUL terminator and only reads the pointer to spot the 0x0000 end
        # marker, so a zero here would end the program early.
        out += b"\x01\x01" + bytes([number & 0xFF, number >> 8]) + body + b"\x00"
    return bytes(out + b"\x00\x00")


def listing(*lines):
    return detokenize(image(*lines), TBL)


# --- token expansion ------------------------------------------------------

# Level II LIST runs tokens straight together: 81=FOR D5="=" BD=TO
eq(listing((10, b"\x81X\xd51\xbd4")), b"10 FORX=1TO4\n", "keywords expand with no added spaces")
eq(listing((10, b"A\xd5B\xcdC\xceD\xcfE\xd0F\xd1G")), b"10 A=B+C-D*E/F[G\n", "operators are tokens too ([ is the up-arrow byte 0x5B)")
eq(listing((10, b" \x84")), b"10  CLS\n", "a body's own leading space is kept (LIST shows two; tok.py needs it)")

# --- literal regions ------------------------------------------------------

# 0xB2 is PRINT, but inside quotes it is a graphics byte and must survive.
eq(expand(b'\xb2"\xb2\xb2"', TBL), b'PRINT"\xb2\xb2"', "semigraphics in a string are not expanded")
eq(expand(b"\x93 \xb2\x81", TBL), b"REM \xb2\x81", "REM text is literal to end of line")
# ' is stored as :REM' (3A 93 FB); LIST shows only the apostrophe.
eq(expand(b"\x84:\x93\xfb hi \xb2", TBL), b"CLS' hi \xb2", "apostrophe comment collapses its stored colon")
# The colon before ELSE must survive: "B=C:ELSE" collapsed to "B=CELSE" re-lexes
# as the identifier CELSE and the branch silently never runs.
eq(expand(b"\x8f A\xcaB\xd5C:\x95 D", TBL), b"IF ATHENB=C:ELSE D", "ELSE keeps its stored colon")
eq(expand(b"\x88 \xb2,\xb2:\xb2", TBL), b"DATA \xb2,\xb2:PRINT", "DATA items are literal until a colon")
# The quote branches are checked before the DATA branch precisely for this.
eq(expand(b'\x88 "a:b",\xb2', TBL), b'DATA "a:b",\xb2', "a colon inside a quoted DATA item does not end it")

# --- documented rewrites --------------------------------------------------

eq(expand(b'\xb2"a\rb"', TBL), b'PRINT"a"+CHR$(13)+"b"', "newline in a string becomes a CHR$ splice")
# ...but never inside a DATA item: READ takes the text literally, so a splice
# there lands as visible characters and breaks the item parse (?OD).
eq(expand(b'\x88"a\rb",7', TBL), b'DATA"a b",7', "newline in a quoted DATA item becomes a space, not a splice")
eq(expand(b'\x88"a\rb":\xb2"c\rd"', TBL), b'DATA"a b":PRINT"c"+CHR$(13)+"d"',
   "a colon ends the DATA region and restores the splice")
eq(expand(b'\x88"a\rb"', TBL, raw_newlines=True), b'DATA"a\rb"', "--raw-newlines wins in DATA strings too")
eq(expand(b"\x8d100\n\x93x", TBL), b"GOTO100 REMx", "newline in statement position becomes a space")
eq(expand(b'\xb2"a\rb"', TBL, raw_newlines=True), b'PRINT"a\rb"', "--raw-newlines keeps bytes verbatim")
eq(listing((10, b""), (20, b"\x84")), b"10 REM\n20 CLS\n", "an empty body is filled with REM")

_stats = {}
detokenize(image((10, b'\xb2"a\rb"'), (20, b"")), TBL, None, _stats)
eq(_stats, {"newline_rewrites": 1, "empty_bodies": 1}, "rewrites are counted")

# --- keyword spacing (-s): boundaries come from the tokens, never a guess ---

def sp(body): return expand(body, TBL, space_keywords=True)

eq(sp(b"\x81X\xd51\xbd4"), b"FOR X=1 TO 4", "run-together keywords are separated exactly")
eq(sp(b"\x8d100"), b"GOTO 100", "a keyword glued to a digit is separated")
eq(sp(b"\x93."), b"REM.", "no space where nothing can glue -- '.' cannot continue an identifier")
eq(sp(b"\x93BRANDT"), b"REM BRANDT", "but an alphanumeric after REM must be separated")
# chr(0xCD) is 'I-acute', which str.isalnum() calls a letter; ASCII-only test.
eq(sp(b"\x93\xcd\xc5"), b"REM\xcd\xc5", "a binary REM payload is left alone")
eq(sp(b"\x88LLLLL,SLLLL"), b"DATA LLLLL,SLLLL", "DATA needs the space; BASIC strips it back off")
eq(sp(b'\xb2"\xb2\x81"'), b'PRINT"\xb2\x81"', "string contents are never spaced")
eq(sp(b"A\xd5B"), b"A=B", "operator tokens are not word-spaced")

# --- framing and malformed input -----------------------------------------

eq(detokenize(image((10, b"\x84")) + b"\x1c\xff", TBL), b"10 CLS\n", "trailing junk after the end marker is ignored")
eq(detokenize(b"\x15" + image((10, b"\x84")), TBL), b"10 CLS\n", "the header may sit behind a few junk bytes")

raises(lambda: listing((65535, b"\x84")), "exceeds the maximum", "a line number above 65529 is rejected")
raises(lambda: listing((10, b"\x84"), (10, b"\x84")), "duplicate", "a duplicate line number is rejected")
raises(lambda: detokenize(b"10 CLS\n", TBL), "no 0xFF header", "a missing header is rejected")

# 0xFC has no Level II token; it must not vanish or turn into a marker.
_unknown = {}
eq(expand(b"\xfc", TBL, _unknown), b"\xfc", "an unknown token byte passes through")
eq(_unknown, {0xFC: 1}, "an unknown token byte is counted")

print("\n%d passed, %d failed" % (_PASS, _FAIL))
sys.exit(1 if _FAIL else 0)
