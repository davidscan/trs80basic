#!/usr/bin/env python3
"""tok --- TRS-80 Level II BASIC tokenizer, the inverse of detok.py.

Turns a plain-ASCII listing back into a tokenized ("crunched") cassette image.

    tok.py FILE                     image to stdout
    tok.py -o DIR FILE...           DIR/<name>.bas per input
    tok.py --round-trip FILE...     re-tokenize a detok'd image, compare bytes

`--round-trip` is why this exists. Every other measure of detok is a proxy
-- does the listing load, does it run without erroring -- and none of them
can catch a token expanded to the wrong keyword when the result still
parses. Re-tokenizing and comparing against the original image is exact and
needs no ground truth: the input file IS the oracle.

The one thing it cannot catch is a COMPENSATING error, where both directions
agree on a wrong byte for a keyword. That residue is covered separately, by
the table entries hand-decoded out of the corpus and by the corpus sweep in
DETOK.md.

Round-trip detok's plain output, not `-s`: Level II stores the spaces you
typed, so the separators `-s` adds are real bytes and would correctly produce
a different image.

Exit status: 0 all inputs converted (or all round-trips matched), 1 a failure
or mismatch, 2 bad usage.
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from detok import (  # noqa: E402
    COLON,
    HEADER,
    MAX_LINE,
    QUOTE,
    TOK_APOS,
    TOK_DATA,
    TOK_ELSE,
    TOK_REM,
    DetokError,
    load_tokens,
)

# Level II loads a cassette program at 42E9H. The stored next-line pointers are
# absolute addresses, so a faithful image needs a base; nothing reads them back
# (detok frames on the NUL terminator), but writing the authentic value keeps
# round-trips byte-exact against images saved by a real machine.
LOAD_ADDRESS = 0x42E9


TOK_PRINT = 0xB2


class TokError(Exception):
    """The listing cannot be tokenized."""


def build_index(table):
    """Keyword bytes, longest first, so MID$ wins over MID and LEFT$ over LEF.

    0xD1 gets a second spelling: the table renders it `[` (the byte-faithful
    up-arrow, 0x5B on the Model I) but detok emitted `^` before 2026-08-13,
    so listings from either era re-tokenize to the same image.
    """
    items = list(table.items())
    if table.get(0xD1) == b"[":
        items.append((0xD1, b"^"))
    return sorted(items, key=lambda kv: (-len(kv[1]), kv[1]))


def crunch(text, index):
    """One line body, ASCII -> tokens.

    Mirrors detok.expand: the same three regions stay literal, or a PRINT
    inside a string would be swallowed into a token and the text destroyed.

    Outside those regions it crunches as the ROM does (1BC0-1C8F; the
    2026-09-19 audit, L-13), and p75's pm_crunch does the same:
      * a letter is matched, and stored, in UPPER case (1C00-1C0B upper-cases
        the symbol's first character in the buffer, 1C2D-1C31 compares the
        rest that way, and every unmatched letter comes round as a first
        character) -- so `print a` crunches like `PRINT A`;
      * `?` is the PRINT token (1BE4-1BE8);
      * ELSE is stored behind a `:` (1C42-1C49), which is what lets the
        ROM's IF skip to it.  An image made without it never takes ELSE on
        the machine.  ONE DEPARTURE: when the text already has the colon
        -- detok shows the stored one as ":ELSE", on purpose -- no second
        one is added, or image -> listing -> image would grow a byte per
        ELSE per trip.  The ROM, given "A:ELSE" typed by hand, stores two.
    """
    src = text.encode("latin-1") if isinstance(text, str) else text
    up = src.upper()            # bytes.upper() touches ASCII letters only
    out = bytearray()
    i, n = 0, len(src)
    in_string = False
    in_data = False
    literal_to_eol = False

    while i < n:
        b = src[i]

        if literal_to_eol:
            out.append(b)
            i += 1
            continue

        if in_string:
            out.append(b)
            if b == QUOTE:
                in_string = False
            i += 1
            continue

        if b == QUOTE:
            in_string = True
            out.append(b)
            i += 1
            continue

        if in_data:
            if b == COLON:
                in_data = False
            out.append(b)
            i += 1
            continue

        # ROM 1C24-1C2A: matching token 8DH, and only that one, skips a
        # blank in the input, so "GO TO" crunches to GOTO.  p50's tokenizer
        # and p75's pm_crunch do the same; the three must agree or the same
        # listing gives two different images (the 2026-09-19 audit, L-16).
        if up.startswith(b"GO", i):
            j = i + 2
            while j < n and src[j:j + 1] == b" ":
                j += 1
            if up.startswith(b"TO", j) and not src[j + 2:j + 3].isalnum() \
                    and src[j + 2:j + 3] != b"$":
                out.append(0x8D)
                i = j + 2
                continue

        if b == 0x3F:                           # ROM 1BE4-1BE8
            out.append(TOK_PRINT)
            i += 1
            continue

        for value, word in index:
            if up.startswith(word, i):
                # ' is stored as the three bytes :REM' -- detok collapses that
                # back to a bare quote, so re-crunching must restore all three.
                if value == TOK_APOS:
                    out += bytes([COLON, TOK_REM, TOK_APOS])
                elif value == TOK_ELSE and out[-1:] != bytes([COLON]):
                    out += bytes([COLON, TOK_ELSE])
                else:
                    out.append(value)
                if value in (TOK_REM, TOK_APOS):
                    literal_to_eol = True
                elif value == TOK_DATA:
                    in_data = True
                i += len(word)
                break
        else:
            out.append(up[i])
            i += 1

    return bytes(out)


def split_lines(data):
    """(number, body) per listing line, in file order."""
    lines = []
    # The interpreter's loader (prog_load) cuts a listing the same way.  A
    # sector-padded file ends in a run of 00H or a 1AH end mark.  In a CR
    # file -- the TRS-80's own ASCII save: no CR LF pair, more CRs than LFs
    # -- an LF is the in-line line feed and belongs to its line.
    data = data.rstrip(b"\x00\x1a")
    if b"\r\n" not in data and data.count(b"\r") > data.count(b"\n"):
        raws = data.split(b"\r")
    else:
        raws = [r[:-1] if r.endswith(b"\r") else r for r in data.split(b"\n")]
    for raw in raws:
        if not raw.strip():
            continue
        j = 0
        while j < len(raw) and 0x30 <= raw[j] <= 0x39:
            j += 1
        if j == 0:
            raise TokError(f"line has no line number: {raw[:40]!r}")
        number = int(raw[:j])
        if number > MAX_LINE:
            raise TokError(f"line number {number} exceeds the maximum {MAX_LINE}")
        # detok emits one space after the number unless the body supplied its
        # own; that separator is not part of the body and must not come back.
        body = raw[j + 1:] if j < len(raw) and raw[j] == 0x20 else raw[j:]
        lines.append((number, body))
    return lines


def tokenize(data, table, base=LOAD_ADDRESS):
    """ASCII listing -> tokenized image."""
    index = build_index(table)
    records = []
    for number, body in split_lines(data):
        crunched = crunch(body, index)
        records.append((number, crunched))
    if not records:
        raise TokError("no program lines found")

    # Each record is pointer(2) + number(2) + body + NUL, and the pointer holds
    # the ADDRESS of the next record, so sizes must be known before addresses.
    addr = base
    addrs = []
    for _, crunched in records:
        addrs.append(addr)
        addr += 4 + len(crunched) + 1

    out = bytearray([HEADER])
    for (number, crunched), start in zip(records, addrs):
        # Pointers are 16-bit and a long program really can run past 0xFFFF,
        # which on the hardware wraps rather than widening.
        nxt = (start + 4 + len(crunched) + 1) & 0xFFFF
        out += bytes([nxt & 0xFF, nxt >> 8, number & 0xFF, number >> 8])
        out += crunched
        out.append(0x00)
    return bytes(out + b"\x00\x00")


def derive_base(data):
    """The load address this image was saved at, from its first record.

    The stored pointers are absolute addresses on the machine that saved the
    program, so there is no single correct base: the corpus shows 0x6A46,
    0x68BA, 0x6A7D and more, varying with memory size and DOS. Assuming one
    would make every round-trip fail on the pointers alone.
    """
    from detok import find_header

    pos = find_header(data)
    if pos + 4 > len(data):
        raise TokError("image too short to derive a load address")
    pointer = data[pos] | (data[pos + 1] << 8)
    end = data.find(b"\0", pos + 4)
    if pointer == 0 or end < 0:
        raise TokError("image has no first record to derive a load address from")
    return (pointer - (4 + (end - pos - 4) + 1)) & 0xFFFF


def round_trip(path, table):
    """Re-tokenize a detok'd image and diff against the original bytes.

    Returns None on a byte-exact match, the string "rewritten" when detok
    applied one of its documented content rewrites, or a (offset, want, got)
    triple for a genuine mismatch.

    The "rewritten" case is not a failure and cannot be made exact: a stored
    line may hold a literal CR, and the ASCII listing format has no way to
    represent one -- writing it out would strand the tail of the line with no
    line number. detok therefore splices it to CHR$(13) or a space, and an
    empty line body becomes REM. Both change length, so the rebuilt image
    legitimately differs. Only files detok did NOT rewrite are held to
    byte-equality; that is where a wrong token expansion would show up.
    """
    from detok import detokenize

    original = path.read_bytes()
    stats = {}
    listing = detokenize(original, table, None, stats)
    rebuilt = tokenize(listing, table, derive_base(original))

    if rebuilt == original:
        return None
    if stats.get("newline_rewrites") or stats.get("empty_bodies"):
        return "rewritten"
    # Trailing junk after the 0x0000 marker is deliberately dropped by detok
    # (DETOK.md), so the rebuilt image is a PREFIX of such an original rather
    # than a different sequence. That is a match, not a loss.
    if len(original) > len(rebuilt) and original.startswith(rebuilt):
        return None
    trimmed = original
    if rebuilt == trimmed:
        return None
    for k, (x, y) in enumerate(zip(rebuilt, trimmed)):
        if x != y:
            return (k, trimmed[max(0, k - 8):k + 8], rebuilt[max(0, k - 8):k + 8])
    return (min(len(rebuilt), len(trimmed)), b"<length>", b"<length>")


def main(argv=None):
    ap = argparse.ArgumentParser(
        prog="tok.py", description="Tokenize a TRS-80 Level II BASIC listing."
    )
    ap.add_argument("files", nargs="+", type=Path)
    ap.add_argument("-o", "--outdir", type=Path, help="write DIR/<name>.bas per input")
    ap.add_argument("--round-trip", action="store_true",
                    help="detokenize then re-tokenize each input and compare bytes")
    ap.add_argument("--base", type=lambda s: int(s, 0), default=LOAD_ADDRESS,
                    help="load address for the line pointers (default 0x42E9)")
    ap.add_argument("-v", action="store_true", help="show every mismatch")
    args = ap.parse_args(argv)

    if args.outdir and args.round_trip:
        ap.error("--outdir and --round-trip are mutually exclusive")
    if args.outdir:
        args.outdir.mkdir(parents=True, exist_ok=True)
    if not args.outdir and not args.round_trip and len(args.files) > 1:
        ap.error("refusing to concatenate several images to stdout; use -o DIR")

    table = load_tokens()
    failed = shown = rewritten = 0

    for path in args.files:
        try:
            if args.round_trip:
                bad = round_trip(path, table)
                if bad == "rewritten":
                    rewritten += 1
                elif bad:
                    failed += 1
                    if args.v or shown < 10:
                        shown += 1
                        off, want, got = bad
                        print(f"{path}: first difference at offset {off}",
                              file=sys.stderr)
                        print(f"    original: {want.hex(' ')}", file=sys.stderr)
                        print(f"    rebuilt : {got.hex(' ')}", file=sys.stderr)
                continue
            image = tokenize(path.read_bytes(), table, args.base)
        except (TokError, DetokError, OSError) as exc:
            failed += 1
            print(f"{path}: {exc}", file=sys.stderr)
            continue

        if args.outdir:
            (args.outdir / (path.stem + ".bas")).write_bytes(image)
        else:
            sys.stdout.buffer.write(image)

    if args.round_trip or failed:
        ok = len(args.files) - failed
        if args.round_trip:
            exact = ok - rewritten
            held = len(args.files) - rewritten
            print(f"\n{exact}/{held} round-tripped byte-exact "
                  f"({rewritten} excluded: detok rewrote content by design)",
                  file=sys.stderr)
        else:
            print(f"\n{ok}/{len(args.files)} converted", file=sys.stderr)

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
