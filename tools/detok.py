#!/usr/bin/env python3
"""detok --- TRS-80 Level II BASIC detokenizer.

Turns a tokenized ("crunched") cassette image into the plain-ASCII listing that
CLOAD accepts.  Standalone: it reads its keyword table from level2_tokens.tsv
and knows nothing about the interpreter.

    detok.py FILE...              detokenize to stdout
    detok.py -o DIR FILE...       write DIR/<name>.bas per input
    detok.py --check FILE...      parse only; report failures and unknown bytes

Output is bytes, not text.  Level II listings legitimately contain raw
0x80-0xBF semigraphics inside string literals, and the surviving ASCII
listings in the wild keep them as raw bytes -- so this does too.

Exit status: 0 all inputs converted, 1 one or more failed, 2 bad usage.
"""

import argparse
import sys
from pathlib import Path

TOKEN_TABLE = Path(__file__.replace(".py", "")).parent / "level2_tokens.tsv"

HEADER = 0xFF
QUOTE = 0x22
COLON = 0x3A
TOK_DATA = 0x88
TOK_REM = 0x93
TOK_ELSE = 0x95
TOK_APOS = 0xFB
NEWLINES = (0x0A, 0x0D)
MAX_LINE = 65529


def _alnum(byte):
    """ASCII letter or digit -- what BASIC allows to continue an identifier.

    Deliberately not chr(byte).isalnum(), which is Unicode-aware and calls the
    semigraphics letters: chr(0xCD) is 'Í'.  That would push spaces into REM
    payloads holding machine code.
    """
    return 0x30 <= byte <= 0x39 or 0x41 <= byte <= 0x5A or 0x61 <= byte <= 0x7A


def _joins(byte):
    """True if `byte` would glue onto an adjacent alphanumeric keyword."""
    return _alnum(byte) or byte in (0x24, 0x2E, 0x23)  # $ . #


class DetokError(Exception):
    """The byte stream is not a well-formed tokenized program."""


def load_tokens(path=TOKEN_TABLE):
    """byte -> expansion, from the TSV data file."""
    table = {}
    for n, raw in enumerate(path.read_text().splitlines(), 1):
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        try:
            hexbyte, expansion = raw.split("\t", 1)
            table[int(hexbyte, 16)] = expansion.encode("latin-1")
        except ValueError:
            raise DetokError(f"{path}:{n}: malformed row: {raw!r}") from None
    if not table:
        raise DetokError(f"{path}: no token rows found")
    return table


def expand(body, table, unknown=None, stats=None, raw_newlines=False,
           space_keywords=False):
    """Expand one line body's tokens, leaving literal regions alone.

    Three regions are stored verbatim by the crunch routine and must not be
    token-expanded, or semigraphics bytes get mistaken for keywords:
    quoted strings, everything after REM/', and DATA items up to a colon.
    """
    out = bytearray()
    i, n = 0, len(body)
    in_string = False
    in_data = False
    literal_to_eol = False

    while i < n:
        b = body[i]

        if literal_to_eol:
            # A CR/LF in REM prose would split the listing line and strand the
            # tail without a line number.  Nothing reads comment bytes, so a
            # space keeps the line intact harmlessly.
            if b in NEWLINES and not raw_newlines:
                out.append(0x20)
                if stats is not None:
                    stats["newline_rewrites"] = stats.get("newline_rewrites", 0) + 1
            else:
                out.append(b)
            i += 1
            continue

        if in_string:
            # Same problem inside a string literal, but here the byte is real
            # data, so splice it out as a concatenated CHR$() instead of
            # dropping it -- "a"+CHR$(13)+"b" is exactly equivalent and loads.
            # UNLESS the string is a DATA item: READ never evaluates, so the
            # splice would land as literal text and break the item parse
            # ("AAA"+CHR$(10)+"BBB",7 -> ?OD).  A space is the only
            # substitution that keeps the parse, same as bare DATA text.
            if b in NEWLINES and not raw_newlines:
                if in_data:
                    out.append(0x20)
                    if stats is not None:
                        stats["newline_rewrites"] = stats.get("newline_rewrites", 0) + 1
                    i += 1
                    continue
                out += b'"+CHR$(%d)+"' % b
                if stats is not None:
                    stats["newline_rewrites"] = stats.get("newline_rewrites", 0) + 1
                i += 1
                continue
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
            # Checked after the quote branches, so a colon inside a quoted
            # DATA item does not end the statement early.
            if b in NEWLINES and not raw_newlines:
                out.append(0x20)
                if stats is not None:
                    stats["newline_rewrites"] = stats.get("newline_rewrites", 0) + 1
                i += 1
                continue
            if b == COLON:
                in_data = False
            out.append(b)
            i += 1
            continue

        # ' is stored as the three bytes :REM' and LIST shows just the quote.
        # ELSE is stored with a leading colon too, but that colon is NOT
        # dropped: it is the only thing separating ELSE from whatever precedes
        # it, and "B=C:ELSE" collapsed to "B=CELSE" re-lexes as the identifier
        # CELSE -- the branch then silently never runs.  Keeping the colon is
        # both safer and closer to the stored bytes.
        if b == COLON and i + 1 < n:
            nxt = body[i + 1]
            if nxt == TOK_REM and i + 2 < n and body[i + 2] == TOK_APOS:
                out += table[TOK_APOS]
                literal_to_eol = True
                i += 3
                continue

        # A newline in statement position too -- these images really do carry
        # them (masterdi.bas line 585 breaks right before a trailing REM).
        # A space is the only substitution that cannot change the parse; a
        # colon would corrupt an expression that happens to span the break.
        if b in NEWLINES and not raw_newlines:
            out.append(0x20)
            if stats is not None:
                stats["newline_rewrites"] = stats.get("newline_rewrites", 0) + 1
            i += 1
            continue

        if b >= 0x80:
            kw = table.get(b)
            if kw is None:
                # No token at this value.  Real LIST would show the byte as a
                # graphics character, and the surviving ASCII listings keep such
                # bytes raw -- so pass it through and only count it.  (A visible
                # marker would be ambiguous: listings really do contain "<?".)
                if unknown is not None:
                    unknown[b] = unknown.get(b, 0) + 1
                out.append(b)
            else:
                if space_keywords:
                    # Level II LIST runs tokens together (FORX=1TOR), and a
                    # text-based interpreter cannot re-lex that -- FORX is one
                    # identifier.  The token stream marks every keyword boundary
                    # exactly, so separating them here needs no guesswork: this
                    # is the whole ambiguity that a text de-compressor has to
                    # resolve heuristically, already solved by construction.
                    if kw[:1].isalpha() and out and _joins(out[-1]):
                        out.append(0x20)
                    out += kw
                    nxt = body[i + 1] if i + 1 < n else 0
                    # Only an alphanumeric can continue an identifier, so only
                    # that needs separating.  Testing the wider _joins() set
                    # here would push a space into REM prose ("REM." -> "REM .")
                    # and other literal payloads for no parsing benefit.
                    if kw[-1:].isalnum() and _alnum(nxt):
                        out.append(0x20)
                else:
                    out += kw
                if b in (TOK_REM, TOK_APOS):
                    literal_to_eol = True
                elif b == TOK_DATA:
                    in_data = True
            i += 1
            continue

        out.append(b)
        i += 1

    return bytes(out)


def find_header(data):
    """Offset just past the 0xFF header.

    Some archived files carry junk ahead of an otherwise intact header
    (PRINTDIR.BAS in LargeCollection begins 15 FF 06), so accept a header
    within the first few bytes rather than demanding offset 0.
    """
    for off in range(min(4, len(data))):
        if data[off] == HEADER:
            return off + 1
    raise DetokError("no 0xFF header in the first 4 bytes (not tokenized?)")


def detokenize(data, table, unknown=None, stats=None, raw_newlines=False,
               space_keywords=False):
    """Tokenized image -> ASCII listing bytes."""
    pos = find_header(data)
    lines = []
    seen = set()

    while True:
        if pos + 2 > len(data):
            # Ran out before the 0x0000 end marker.  A tail of NUL padding is
            # a harmless truncation of the marker itself; anything else means
            # the image really is cut short.
            if data[pos:].strip(b"\0") == b"":
                break
            raise DetokError(f"truncated line header at offset {pos}")

        pointer = data[pos] | (data[pos + 1] << 8)
        if pointer == 0:
            # Clean end of program.  Cassette images routinely carry trailing
            # junk after the marker (padding, screen control bytes) -- once the
            # marker is seen the program is complete, so ignore the rest.
            break

        if pos + 4 > len(data):
            raise DetokError(f"truncated line header at offset {pos}")

        number = data[pos + 2] | (data[pos + 3] << 8)
        if number > MAX_LINE:
            # Level II cannot store a line above 65529, so the walk has run off
            # the program into padding or an appended binary.  Fail loudly
            # rather than emit a listing built from garbage.
            raise DetokError(f"line number {number} exceeds the maximum {MAX_LINE}")
        pos += 4

        end = data.find(b"\0", pos)
        if end < 0:
            raise DetokError(f"unterminated line {number} at offset {pos}")

        body = expand(data[pos:end], table, unknown, stats, raw_newlines,
                      space_keywords)
        pos = end + 1

        if number in seen:
            raise DetokError(f"duplicate line number {number}")
        seen.add(number)
        if not body.strip():
            # Level II cannot store a bodiless line and the interpreter rejects
            # one, but these images contain them.  A bare REM keeps the line as
            # a branch target instead of dropping a possible GOTO destination.
            body = table[TOK_REM]
            if stats is not None:
                stats["empty_bodies"] = stats.get("empty_bodies", 0) + 1
        # LIST prints the number, one space, then the body -- so a body holding
        # its own leading space really does list with two.  Suppressing the
        # second reads more tidily but is lossy: tok.py cannot then tell the
        # separator from the body's own byte.  Affects 2% of corpus lines.
        lines.append(b"%d %s" % (number, body))

    if not lines:
        raise DetokError("no program lines found")
    return b"\n".join(lines) + b"\n"


def main(argv=None):
    ap = argparse.ArgumentParser(
        prog="detok.py", description="Detokenize TRS-80 Level II BASIC images."
    )
    ap.add_argument("files", nargs="+", type=Path)
    ap.add_argument("-o", "--outdir", type=Path, help="write DIR/<name>.bas per input")
    ap.add_argument("--check", action="store_true", help="parse only, report problems")
    ap.add_argument("--table", type=Path, default=TOKEN_TABLE, help="token table TSV")
    ap.add_argument(
        "--raw-newlines",
        action="store_true",
        help="keep CR/LF inside strings and REMs verbatim (byte-faithful, but "
        "the listing will not reload -- the tail loses its line number)",
    )
    ap.add_argument(
        "-s",
        "--space-keywords",
        action="store_true",
        help="separate run-together keywords (FORX=1TOR -> FOR X=1 TO R) using "
        "the exact boundaries in the token stream; needed by text-based "
        "interpreters that cannot re-lex compressed source",
    )
    args = ap.parse_args(argv)

    if args.outdir and args.check:
        ap.error("--outdir and --check are mutually exclusive")
    if args.outdir:
        args.outdir.mkdir(parents=True, exist_ok=True)
    if not args.outdir and not args.check and len(args.files) > 1:
        ap.error("refusing to concatenate several programs to stdout; use -o DIR")

    table = load_tokens(args.table)
    unknown = {}
    stats = {}
    failed = []

    for path in args.files:
        try:
            listing = detokenize(
                path.read_bytes(), table, unknown, stats, args.raw_newlines,
                args.space_keywords,
            )
        except (DetokError, OSError) as exc:
            failed.append((path, exc))
            print(f"{path}: {exc}", file=sys.stderr)
            continue

        if args.check:
            continue
        if args.outdir:
            (args.outdir / (path.stem + ".bas")).write_bytes(listing)
        else:
            sys.stdout.buffer.write(listing)

    if args.check or failed:
        ok = len(args.files) - len(failed)
        print(f"\n{ok}/{len(args.files)} parsed", file=sys.stderr)
        if stats.get("empty_bodies"):
            print(
                f'empty line bodies filled with REM: {stats["empty_bodies"]}',
                file=sys.stderr,
            )
        if stats.get("newline_rewrites"):
            print(
                f'embedded newlines rewritten: {stats["newline_rewrites"]}',
                file=sys.stderr,
            )
        if unknown:
            hist = ", ".join(
                f"0x{b:02X}x{c}" for b, c in sorted(unknown.items(), key=lambda kv: -kv[1])
            )
            print(f"unknown token bytes: {hist}", file=sys.stderr)

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
