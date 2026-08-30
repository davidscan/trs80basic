# trs80basic

## What it is

A TRS-80 Model I LEVEL II BASIC interpreter — the 1978 Radio Shack dialect,
with its 64x16 screen and semigraphics, cassette (`CLOAD`/`CSAVE` as text
files), Disk BASIC file I/O, and an `OLLAMA` channel for talking to a local
LLM from BASIC. It runs `.bas` listings interactively at a `READY` prompt or
non-interactively from a script. It is a single GNU awk script with no build
step; it writes only the files your BASIC program tells it to.

## Quick start

```bash
gawk --version | head -1                        # needs GNU awk >= 5.0
./basic --seed 1 programs/examples/hilo.bas < programs/examples/hilo.in   # <1s — runs a program, prints its screen text
./basic                                         # interactive READY prompt; type BYE to leave
programs/examples/run_examples.sh               # ~5s — every example against its checked-in transcript, all "ok"
```

Inside the interpreter, `man PRINT` documents any keyword, `help meta` lists
the metacommands, `help keys` the key bindings.

## Commands and arguments

### `./basic [options] [program.bas]`

Runs the interpreter. With a file, LOADs and RUNs it non-interactively and
exits; without one, starts the interactive prompt. **Writes:** nothing on its
own. Whatever the BASIC program `OPEN`s, `CSAVE`s or `SAVE`s lands relative to
*your current directory*, not the repo.

| argument | default | what it does | when you'd use it |
|---|---|---|---|
| `program.bas` | none (interactive) | LOAD + RUN it, then exit 0/1/2 | scripting, tests, piping `INPUT` answers from stdin |
| `--seed N` | time-based | seeds `RND`; `RANDOM` re-applies N | repeatable runs, transcripts you can diff |
| `--screen` | off | keep the TRS-80 cursor/screen control codes in batch output | capturing what the 64x16 screen looked like rather than a text transcript |
| `--` | | end of options | a program file whose name starts with `-` |
| `-h`, `--help` | | usage and exit status meanings | |

Exit status: **0** clean run, **1** uncaught BASIC error (also printed to
stderr as `?SN ERROR IN 40`), **2** bad invocation or unreadable file.
Running out of stdin while a program is at `INPUT` is a BASIC error
(`?BATCH: END OF INPUT`).

Environment variables the interpreter reads:

| variable | default | what it does | when you'd use it |
|---|---|---|---|
| `TRS80_GFX` | Unicode sextants | `braille` or `ascii` for the semigraphics glyphs | your terminal font lacks the "Symbols for Legacy Computing" block |
| `TRS80_DUMB` | unset | `1` forces plain streamed output even on a terminal | logging a session, or a terminal that can't do the 64x16 grid |
| `TRS80_MHZ` | full speed | throttle execution to a period-correct feel (also `speed` metacommand) | games that are unplayable at modern speed |
| `TRS80_PRINTER` | unset (discard) | file that `LPRINT`/`LLIST` append to | you want the printer output |
| `TRS80_EXT` | `0` | `1` accepts a few forms real Level II rejects (bare `INPUT`, `DIM` of a scalar; also `ext on`) | running listings that use those idioms; leave off to keep strict `?SN` behaviour |
| `TRS80_MANFILE` | `support/manpages.txt` next to `basic` | where `man` reads its text | only if you relocate the file |
| `TRS80_OLLAMA_MODEL` | none | default model for `OPEN "OLLAMA"` when the name gives none | every OLLAMA program without a hard-coded model |
| `TRS80_OLLAMA_HOST` | `localhost:11434` | the Ollama server | Ollama on another machine |
| `TRS80_OLLAMA_TIMEOUT` | `300` | seconds to wait for a reply | slow models |
| `TRS80_OLLAMA_THINK`, `TRS80_OLLAMA_KEEPALIVE` | unset | defaults for the `@THINK` / `@KEEPALIVE` directives | thinking models; keeping a model loaded between calls |
| `TRS80_OLLAMA_CURL` | unset | replaces the `curl` command (test hook) | deterministic tests with `programs/tests/ollama_stub.sh` |

### `python3 tools/detok.py [-o DIR] [-s] [--check] IMAGE...`

Converts tokenized cassette/disk images (binary, first byte `0xFF`) into the
text listings this interpreter reads. **Writes:** `DIR/<name>.bas` per input
with `-o`; otherwise to stdout.

| argument | default | what it does | when you'd use it |
|---|---|---|---|
| `-o DIR`, `--outdir DIR` | stdout | write one `.bas` per input into DIR | converting more than one file |
| `-s`, `--space-keywords` | off | re-separate keywords the ROM ran together (`FORX=1TOR` → `FOR X=1 TO R`) | **always, for this interpreter** — it lexes `FORX` as one identifier |
| `--check` | off | parse only, report problems, write nothing | finding out whether a file is really a tokenized image |
| `--raw-newlines` | off | keep CR/LF inside strings and REMs byte-for-byte | archival fidelity only; the result will not reload |
| `--table TSV` | `tools/level2_tokens.tsv` | alternate token table | never, unless you are studying another ROM |

### `python3 tools/tok.py [-o DIR] [--round-trip] LISTING...`

The inverse: a text listing back to a tokenized image. **Writes:** `DIR/<name>.bas`
with `-o`, else stdout.

| argument | default | what it does | when you'd use it |
|---|---|---|---|
| `-o DIR`, `--outdir DIR` | stdout | write one image per input | producing files for a real machine or emulator |
| `--round-trip` | off | detokenize each *image*, re-tokenize, compare bytes; writes nothing | checking that a conversion is lossless |
| `--base ADDR` | `0x42E9` | load address for the line pointers | matching a specific machine's memory layout |
| `-v` | off | show every mismatch in `--round-trip` | when a round trip fails |

### `programs/examples/run_examples.sh [--update]`

Runs every `programs/examples/*.bas` with `--seed 1` and its `.in` file, in a
scratch directory, against the OLLAMA stub, and diffs against the checked-in
`.out`. **Writes:** nothing, unless `--update`, which rewrites the `.out` files.

| argument | default | what it does | when you'd use it |
|---|---|---|---|
| `--update` | off | regenerate the transcripts instead of checking them | after a deliberate change to an example or to output formatting — read the diff first |

### `windows/make_windows_zip.sh [--project NAME]...`

Builds the no-install Windows package (bundled gawk + `basic.bat`).
**Writes:** `dist/trs80basic-windows-<date>.zip`; downloads gawk once into
`windows/cache/`.

| argument | default | what it does | when you'd use it |
|---|---|---|---|
| `--project NAME` | none | also bundle `~/development/NAME` (needs a `MANIFEST.txt`, see `BUNDLED_PROJECTS.md`); repeatable | shipping a BASIC program to someone as one zip |

`WINDOWS.md` covers what the Windows package can and cannot do.

## User manual

### Workflow

**Run a listing.** `./basic game.bas`. Text the program prints appears on
stdout; BASIC errors on stderr; the exit status says how it ended. Feed
`INPUT` from stdin (`printf '5\n10\n' | ./basic game.bas`). A good result is
exit 0 and the transcript you expected. Wrap in `timeout 30` if the program
might loop forever — there is no built-in guard.

**Play interactively.** `./basic` with no file gives the `READY` prompt. Type
BASIC directly, `LOAD "game.bas"` or `CLOAD "game.bas"` to load one, `RUN`,
Ctrl-C to break, `CONT` to resume, `BYE` to leave. The screen is the real
64x16 grid; long output pages with PgUp/PgDn.

**Convert an archived program.** Most TRS-80 programs found online are
tokenized images, and `CLOAD` reads only text:

```bash
python3 tools/detok.py --check IMAGE.BAS       # is it tokenized?
python3 tools/detok.py -s -o listings/ IMAGE.BAS
./basic listings/IMAGE.bas
```

**Talk to a model.** `OPEN "O",1,"OLLAMA:llama3.2"` opens a chat channel;
`PRINT #1` lines build the prompt, `LINE INPUT #1` sends it and reads the
reply line by line until `EOF(1)`. `programs/examples/oracle.bas` is a
complete program; `man OLLAMA` has the directives (`@TOKENS`, `@THINK`,
`@KEEPALIVE`).

**Worked example — the examples directory.** Each program demonstrates one
area and runs as a fixture:

| program | shows |
|---|---|
| `hilo.bas` | `INPUT` from stdin, `--seed`, a deliberate non-zero exit |
| `logbook.bas` | sequential files: `OPEN "O"/"E"/"I"`, `PRINT#`, `LINE INPUT#`, `EOF`, `KILL`; `ON ERROR` for a missing file |
| `starfile.bas` | random-access files: `FIELD`, `LSET`, `PUT`/`GET`, `MKI$`/`CVI`, `LOF` |
| `life.bas` | `SET`/`RESET`/`POINT` on the 128x48 grid (run it interactively to watch) |
| `palette.bas` | colour semigraphics, `SET(x,y,c)` — an extension; colour shows only in the interactive grid |
| `oracle.bas` | the `OLLAMA` channel with `@TOKENS` steering the reply |
| `trapper.bas` | `ON ERROR GOTO`, `ERR`, `ERL`, `RESUME`, `ERROR n` |

`run_examples.sh` prints `ok` per program. If one prints `FAIL` and a diff,
either the interpreter's behaviour changed or the example did; decide which
before `--update`.

### Decision points

- **Before `--update` on the examples**: read the diff. The transcripts are
  the specification of current behaviour; updating them silently accepts a
  change.
- **After `detok.py`**: skim the listing for `?`-marked bytes or lines that
  do not start with a number. `--check` first tells you whether the file is
  an image at all; a plain-text file passed to detok is not damage, it is
  already a listing.
- **`TRS80_EXT`**: leave it off unless a listing fails with `?SN` on a bare
  `INPUT` or a `DIM` of a scalar. Turning it on makes the interpreter accept
  what real Level II would not.

### Gotchas

- **Relative paths belong to the program.** You might expect `OPEN "I",1,"DATA.TXT"`
  to look next to the `.bas` file; actually it resolves against *your*
  current directory, because the interpreter never changes directory. Run
  from where the program's data is, or call `basic` by absolute path.
- **Batch output has no graphics, and no colour anywhere but the grid.** You
  might expect `SET` to show up in `./basic prog.bas` output; actually only
  printed text is streamed, because the screen grid is not rendered without
  a terminal. `--screen` keeps the control codes; interactive mode shows the
  picture. `SET(x,y,c)` colour renders only in the interactive grid, and
  `POINT` reports lit/unlit regardless of colour.
- **Printing scrolls the picture.** You might expect `POINT` to read back
  what `SET` drew; actually any `PRINT` that reaches the bottom line scrolls
  the whole screen, pixels included — read before you print, or use
  `PRINT@` to place text.
- **`FORX` is an identifier.** You might expect `FORX=1TO10` to work as on the
  real machine; actually it is one variable name, because this interpreter
  lexes text greedily. `detok.py -s` inserts the spaces from the token stream.
- **Metacommands are lowercase.** `dir`, `man`, `help`, `fullscreen` are
  metacommands; `DIR` or `MAN` reach BASIC and give `?SN ERROR`. This keeps
  the two namespaces apart.
- **`LOF` is for random files only.** On a sequential channel it raises `?BM`;
  use `LOC(n)` for lines read or written.
- **`ERR` is not the error code.** As on the real machine, `ERR/2+1` is the
  code (1 = NF, 2 = SN, 11 = /0, 29 = FF). `man ERR` lists them.
- **Ctrl-C is BREAK, not exit.** It stops the program and returns to `READY`;
  `BYE` leaves.
- **A named OLLAMA thread persists.** `OPEN "O",1,"OLLAMA:llama3.2:story"`
  writes `story.ollama` in the current directory and reloads it as
  conversation context next time; `KILL "story.ollama"` forgets it.

### Undo / recovery

There is no undo. The interpreter only writes what a program tells it to
(`OPEN "O"`/`"E"`/`"R"`, `CSAVE`, `SAVE`, `KILL`, OLLAMA thread files), always
under your current directory. `KILL` deletes without confirmation. Run
unfamiliar programs from a scratch directory. `run_examples.sh --update`
overwrites `.out` files; `git diff` shows exactly what changed.

### Tips

- `printf 'ANSWER\n' | ./basic prog.bas` scripts any `INPUT`; a heredoc does
  the same for many.
- `./basic prog.bas > run.txt 2> errors.txt` separates the transcript from
  BASIC errors.
- `help <text>` searches the keyword documentation; `man` needs the exact word.
- `speed 1.77` (or `TRS80_MHZ=1.77`) slows a game to the original machine's pace.
- `TRS80_GFX=ascii` works on every terminal, including the raw Linux console.
- The interactive grid needs a terminal of at least 64x20.

### Not supported

- Machine code: `USR` and `DEFUSR` are stubs; `POKE`/`PEEK` address a
  simulated memory, not a Z80.
- Native Windows keyboard: the Windows package is line-mode (`INKEY$`-driven
  games need WSL). See `WINDOWS.md`.
- Loading tokenized images directly — convert with `detok.py` first.
- Reading OCR-damaged listings — that is a different problem (repair, not
  conversion) and lives in a separate tool.

## Files and logs

| path | what it holds | written by | safe to delete? |
|---|---|---|---|
| `trs80basic.awk` | the whole interpreter, one file | `cat src/p*.awk > trs80basic.awk` | no — regenerate from `src/` if you edit there |
| `src/p*.awk` | the interpreter's source modules, concatenated in name order | you | no |
| `basic` | launcher: finds gawk and the manpages, passes flags through | you | no |
| `support/manpages.txt` | text behind `man` and `help`; plain format, edit freely | you | no — `man` stops working |
| `programs/*.bas` | demo programs (`aethelgard`, `tictactoe`, `demo_*`, `gfxtest`) | you | yes |
| `programs/examples/` | feature examples with `.in` inputs and `.out` transcripts | `run_examples.sh --update` (transcripts) | transcripts regenerate; programs do not |
| `programs/tests/t*.txt`, `prog1.bas` | interactive-mode input scripts for regression checks | you | no |
| `programs/tests/ollama_stub.sh` | canned Ollama replies for tests | you | no — `oracle` and `t29` need it |
| `tools/detok.py`, `tools/tok.py`, `tools/level2_tokens.tsv` | image ↔ listing converters and the Level II token table | you | no |
| `tools/test_*.py` | their tests (`python3 -m unittest`) | you | no |
| `tools/DETOK.md` | the token format and conversion notes | you | yes |
| `windows/` | `basic.bat`, packaging script, Windows notes | you | no |
| `windows/cache/` | downloaded gawk zip and its licence | `make_windows_zip.sh` | yes — re-downloaded (gitignored) |
| `dist/` | built Windows zips | `make_windows_zip.sh` | yes (gitignored) |
| `*.ollama` in your cwd | OLLAMA conversation threads | a program using a named thread | yes — `KILL` or `rm` forgets the conversation |
| `RELEASE_NOTES.md` | keyword inventory and documented deviations from Level II | you | yes |
| `BUNDLED_PROJECTS.md`, `WINDOWS.md` | the Windows package and `--project` manifest format | you | yes |

## License

Copyright (c) 2026 David Forbis. GNU General Public License v3.0 — see
`LICENSE`. Distributed WITHOUT ANY WARRANTY.

This is an independent, from-scratch reimplementation of the LEVEL II BASIC
language's *behaviour*, written against the published Radio Shack LEVEL II
BASIC Reference Manual (1978) as a functional specification. It contains no
ROM code, no disassembly, no Microsoft or Tandy source, and no text of the
manual. **TRS-80**, **Radio Shack** and **Tandy** are trademarks of their
respective owners, used only to describe compatibility; this project is not
affiliated with or endorsed by them. Programs under `programs/` are original
to this project.
