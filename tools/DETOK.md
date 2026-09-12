# detok --- TRS-80 Level II BASIC detokenizer

> **Measured against a private archive of tokenized Model I images.**
>
> | measure | value |
> |---|---|
> | tokenized files in the collection | 4,795 |
> | detokenized successfully | **4,721 (98.5%)** |
> | of those, listings the interpreter loads | **4,721 / 4,721 (100%)** |
> | files containing an unknown token byte | 49 (all embedded machine code) |

`CLOAD` accepts only plain-ASCII listings (see the CLOAD/CSAVE section of
`RELEASE_NOTES.md`). Most archived TRS-80 programs are *tokenized* cassette images
instead, so they cannot be loaded at all. `detok.py` converts them.

It is a standalone utility. It imports nothing from the interpreter, and the
interpreter does not know it exists.

## Use

    python3 tools/detok.py FILE                  # listing to stdout
    python3 tools/detok.py -o DIR FILE...        # DIR/<name>.bas per input
    python3 tools/detok.py --check FILE...       # parse only; report problems
    python3 tools/detok.py -s FILE               # separate run-together keywords

Exit status is 0 if every input converted, 1 if any failed, 2 on bad usage.
Output is **bytes, not text** --- Level II listings legitimately contain raw
0x80-0xBF semigraphics inside string literals, and the surviving ASCII listings
in the wild keep them raw, so this does too.

## The format

`FF`, then one record per line: a 2-byte next-line pointer, a 2-byte line
number (both little-endian), the tokenized body, and a `00` terminator. A
`0000` pointer ends the program. Bytes below 0x80 are literal; 0x80-0xFB are
keywords, listed in `level2_tokens.tsv`.

The table lives in its own TSV rather than inside the script because it is not
detokenizer-specific: the interpreter's program-memory mapping (`src/p75_mem.awk`) wants the same
table in the write direction, and one hand-typed copy of ~124 keywords is
enough.

Twenty-odd entries were confirmed by hand-decoding bytes out of the corpus
(`0x84` CLS, `0x93` REM, `0x99` DEFINT, `0xB2` PRINT, `0xCE` `-`, `0xD5` `=`,
`0xCA` THEN, `0xBD` TO, `0xBF` USING, ...). The rest are the published Level II
table, exercised by the corpus sweep: only 49 files of 4,721 contain a byte the
table does not cover, and every one is a program with an embedded Z80 block
(the `valkyri*` set is ten copies of one such program).

## What is *not* expanded

The crunch routine stores three regions verbatim, and expanding tokens inside
them corrupts the listing --- a `0xB2` inside quotes is a graphics character,
not `PRINT`. `detok` tracks all three: quoted strings, everything after `REM`
or `'`, and `DATA` items up to a colon. The quote check runs *before* the
`DATA` check so a colon inside a quoted `DATA` item does not end the statement
early.

## Deviations from the stored bytes

Two, both needed to make the output loadable, both counted and reported:

**Embedded newlines (37,759 rewrites).** A stored line may contain a literal
CR or LF --- inside a string, in REM prose, or in statement position. Written
straight out, the tail becomes a line with no number and the file will not
load. Inside a string the byte is real data, so it is spliced out as
`"a"+CHR$(13)+"b"`, which is exactly equivalent --- *except* when the string
is a `DATA` item (fixed 2026-08-12): `READ` takes the text literally, never
evaluating it, so a splice there lands as visible characters and breaks the
item parse (`?OD`). There, and everywhere else, the byte becomes a space
--- the only substitution that cannot change the parse, where a colon would
corrupt an expression spanning the break. `--raw-newlines` keeps the bytes
verbatim and accepts that the listing will not reload.

**Empty line bodies (483 filled).** Level II cannot store a bodiless line and
the interpreter rejects one, but these images contain them. Each becomes a bare
`REM`, which keeps the line as a branch target instead of dropping a possible
`GOTO` destination.

One thing deliberately *not* done: the stored colon before `ELSE` is kept. LIST
hides it, but dropping it turns `B=C:ELSE` into `B=CELSE`, which re-lexes as the
identifier `CELSE` --- the branch then silently never runs. Verified against the
interpreter; silent wrong output is worse than an ugly listing.

## Known limits

**74 files do not parse** (39 duplicate line number, 28 unterminated line, 4
line number above the Level II maximum of 65529, 3 truncated header). These are
desync signals: the record walk has run off the program into padding or an
appended binary. Failing is deliberate --- a listing built from garbage is worse
than no listing.

**Glued keywords --- use `-s`.** Level II stores what you typed and `LIST`
expands tokens tight, so listings come back as `FORX=1TOR`. The interpreter
re-lexes text and reads `FORX` as one identifier. Without
`-s`, **62% of the corpus hits `?SN ERROR` on the first line or two.**

`-s` separates them. It needs no heuristic: a keyword *is* a token byte, so
`\x81 X \xd5 1 \xbd 4` marks every boundary exactly and becomes `FOR X=1 TO 4`.
This is the entire ambiguity a text de-compressor has to guess at (`FORN=1TOR`
--- is that `TO R` or `T OR`?), already resolved by the format.

| over 591 programs | clean run | `?SN` | `?BS` |
|---|---:|---:|---:|
| without `-s` | 139 (24%) | 369 | 70 |
| **with `-s`** | **435 (74%)** | **88** | **3** |

`?TM` rises 7 -> 54, but that is progress, not damage: 22 of 26 sampled had
previously died earlier on `?SN` and now reach genuine unsupported features
like `VARPTR`.

Spacing is provably confined to code. Comparing `-s` output against plain
output under a whitespace-normalising comparison --- which holds whitespace
inside strings and REM payloads significant --- 4,643 of 4,721 files are
identical. The 78 that differ are the two places a space is *required*:
`DATALLLLL` -> `DATA LLLLL` (verified equivalent; BASIC strips the leading
space back off, and the unspaced form does not parse at all) and `REMBRANDT`
-> `REM BRANDT` (needed for REM to be recognised). Nothing is inserted where
nothing can glue: `REM.` stays `REM.`, and a REM holding machine code is left
byte-for-byte alone.

**"Loads" is not "is correct."** The 100% figure means the interpreter accepted
every listing, not that any program produces right answers. Verifying behavior
would need per-program input fixtures.

## Correctness: the round trip

Every other measure here is a proxy. "Loads" and "runs without erroring"
cannot catch a token expanded to the *wrong keyword* when the result still
parses --- and until `tok.py` existed, nothing could.

`tok.py` is the inverse. `--round-trip` detokenizes an image, re-tokenizes the
listing, and compares bytes against the original. It needs no ground truth:
the input file is the oracle.

    python3 tools/tok.py --round-trip IMAGES/*.BAS

| | files | |
|---|---:|---|
| **byte-exact** | **2,974 / 3,002** | **99.1%** |
| differ, but detokenize to the *identical* listing | 28 | tok picked another valid encoding |
| **content divergence** | **0** | |
| excluded: detok rewrote content by design | 1,719 | exactness impossible, see below |
| unparsed | 74 | |

**Zero content divergence across all 3,002 files held to the test.** The 28
byte differences are encoding choices, not errors: a literal `^` that the
original never tokenized, and greedy keyword matching inside identifiers
(`TOTAL` crunching as `TO`+`TAL`, the classic Microsoft quirk). Both
detokenize back to exactly the original listing.

The 1,719 exclusions are honest, not a dodge. A stored line may hold a literal
CR, and **the ASCII listing format cannot represent one** --- writing it out
strands the tail of the line with no line number. detok therefore splices it
to `CHR$(13)` or a space, and fills an empty body with `REM`. Both change
length, so the rebuilt image legitimately differs. That is a property of the
listing format, and it is precisely why CLOAD-able ASCII was a lossy way to
archive these programs.

Two things the round trip found that nothing else had:

- **detok's line-number separator was lossy.** It used to suppress its own
  space when the body already began with one, which reads more tidily but
  destroys the distinction on 2% of corpus lines. Real `LIST` prints number,
  space, body --- so two spaces is both authentic *and* recoverable. Fixed.
- **The load address is per-machine.** Stored pointers are absolute addresses;
  the corpus shows 0x6A46, 0x68BA, 0x6A7D and others varying with memory size
  and DOS. `derive_base()` recovers it from the first record rather than
  assuming Level II's 0x42E9.

Run the round trip on plain output, never `-s`: Level II stores the spaces you
typed, so `-s` separators are real bytes and correctly produce a different
image.

## Tests

    python3 tools/test_detok.py        # 32 checks, stdlib only
    python3 tools/test_tok.py          # 22 checks, stdlib only

These pin the decisions a corpus sweep cannot localise --- literal-region
handling, the two rewrites, the `ELSE` colon, the `-s` spacing rules, framing
of malformed input, and the inverse-of-detok invariants. To re-measure the
corpus, detokenize it to a scratch directory and run each result through
`./basic FILE </dev/null`, where exit code 2 means unloadable.
