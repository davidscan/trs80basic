# trs80basic.awk — TRS-80 Model I/III LEVEL II BASIC interpreter in GNU awk

## Running it

    ./basic                     # or: gawk -b -f trs80basic.awk

Requirements: GNU awk 5.x, a POSIX shell, a VT100/ANSI terminal at least 64x20
that displays UTF-8 (iTerm2 is fine). Always run gawk with `-b`: BASIC strings
are byte strings, and without `-b` a UTF-8 locale turns `CHR$(200)` into a
two-byte character and corrupts raw bytes above 127 read from a program
file (graphics, packed machine code). The launcher passes it; running the
file directly without it prints a one-line warning. The script uses `stty`,
`dd` and `od` for raw keyboard input. Exit with `BYE` (restores your terminal). If the
interpreter is ever killed abnormally, type `stty sane` to recover the tty.

At startup you get the authentic `MEMORY SIZE?` prompt (press ENTER), the
`RADIO SHACK LEVEL II BASIC` banner, and `READY`. The top 16 terminal rows
are the simulated 64x16 TRS-80 display; everything (prompt, echo, LIST,
program output) passes through the simulated screen buffer and scrolls
exactly as displayed memory. Display memory is PEEK/POKEable at
15360-16383 (`addr = 15360 + row*64 + col`).

**BREAK key = Ctrl-C.** It stops a running program (`BREAK IN nnnn`),
cancels the current input line, stops a LIST, and exits AUTO. `CONT`
resumes after BREAK/STOP/END (not after an error or program edit). A
program can disable BREAK the period way (2026-09-11): 16396 (400CH) is
the ROM's BREAK vector, and `POKE 16396,23` (or 175, 165) turns Ctrl-C
off until `POKE 16396,201` (or 195) restores it. While disabled, three
Ctrl-C presses in a row break anyway, so a runaway program can always be
stopped; the keyboard matrix still shows the key either way.

**Other keys** (`help keys` lists them; control keys work shifted or
unshifted): **Ctrl-S** pauses a running program or LIST — the real
SHIFT-@ — and any key resumes (Ctrl-C breaks); **Ctrl-L** is the CLEAR
key at the `>` prompt; **Ctrl-U** erases the input line (SHIFT-left-
arrow); **Ctrl-A**/**Ctrl-E** jump to start/end of the line;
**left/right arrows** move the cursor (insert happens at the cursor);
**up/down arrows** recall command history at the `>` prompt (the
`history` / `h` metacommand lists it; memory-only, per session);
**PgUp/PgDn** (or **Ctrl-B**/**Ctrl-F**) page long metacommand output
below the grid;
**TAB** completes a filename at the `>` prompt — longest common prefix,
`/` appended to a unique directory match, candidates listed below the
grid when ambiguous. In fullscreen mode, editing a line longer than the
terminal width has cosmetic glitches (backspace-based redraw); the grid
editor handles full 255-char lines.

**Unquoted filenames**: CLOAD/CLOAD?/CSAVE accept an unquoted filename,
which runs to the end of the line with case, `/`, and `.` preserved
(`CLOAD programs/demo.bas`). A `:`-statement cannot follow an unquoted
name; quote it instead. Metacommand output (`dir`, `cat`, `speed`,
`history`, `help`, `man`, `ext`) renders below the 64x16 grid, not on the
simulated screen; long output pages with PgUp/PgDn.

## Implemented statements and commands

AUTO [n[,inc]], BYE, CLEAR [n], CLOAD "f", CLOAD? "f", CLS, CONT,
CSAVE "f", DATA, DELETE range, DIM (multi-dimensional, numeric + string),
END, ERROR n, FOR/TO/STEP...NEXT [v[,v...]], GOSUB/RETURN, GOTO,
IF/THEN/ELSE (all forms: `IF e THEN n`, `IF e GOTO n`, `IF e THEN stmt`,
`IF e stmt`, `...ELSE stmt|n`, nested), INPUT (with a "prompt" literal or
string expression, then ; or ,),
LET (optional), LIST (LIST / n / n- / -n / n-m / .), NEW,
ON e GOTO/GOSUB list, ON ERROR GOTO n, RESUME [0|NEXT|n], POKE, PRINT
(with ; , @ TAB() POS(0), USING), RANDOM, READ/RESTORE, REM (and `'`),
RESET, RUN [n], SET, STOP, TRON/TROFF, `?` as PRINT shorthand.

Functions: ABS INT FIX SGN SQR SIN COS TAN ATN LOG EXP RND CINT CSNG CDBL
PEEK INP POINT POS FRE LEN ASC VAL CHR$ STR$ STRING$ LEFT$ RIGHT$ MID$ (2-
and 3-arg) INKEY$ ERR ERL MEM VARPTR USR.

Operators: ^ (also `[`, the Model I up-arrow byte), * / + - (string
concatenation with +), = < > <= >= <> (also =< => ><), AND OR NOT (16-bit
integer semantics, true = -1), parentheses, unary +/-. LEVEL II precedence
including `-2^2 = -4`; `2^3^2 = 64` (left-associative).

Behavioral details matched to the 1978 manual: FOR bodies execute at least
once (test at NEXT); loop start/limit/step evaluated once; re-using an
active FOR variable discards the older frame; `NEXT V` unwinds inner
frames; statement-level GOSUB/RETURN and CONT; READY/`>` prompt flow;
DATA items collected in line order (quoted strings may contain commas and
colons); READ type mismatch reports `?SN ERROR` at the DATA line; INPUT
re-prompts `?REDO FROM START` on bad numeric input, `??` for missing
items, `?EXTRA IGNORED` for extras; PRINT comma zones are 16 columns with
a newline from the 4th zone; numbers print with leading sign space,
trailing space, no leading zero on fractions (`.5`), ~6 significant
digits, E-notation for extremes; errors are `?XX ERROR IN nnnn` with the
full 23-code table (NF SN RG OD FC OV OM UL BS DD /0 ID TM OS LS ST CN NR
RW UE MO FD L3); `ERR/2+1` gives the error code; unPOKEd RAM that is
not a live cell (see the memory map under *Omissions and deviations*)
PEEKs as 255; POKE stores value AND 255; negative addresses wrap
(+65536); line numbers 0-65529; a bare line number deletes the line
(?UL ERROR if absent); keyboard lines cap at 255 chars; syntax errors are
diagnosed at RUN, not at entry; RUN resets variables/arrays/stacks/DATA
pointer but does not clear the screen.

## Display, semigraphics, character set

The 2x3 semigraphics cells (codes 128-191, bits TL=1 TR=2 ML=4 MR=8 BL=16
BR=32) render as Unicode "Symbols for Legacy Computing" sextant glyphs —
an exact bit-for-bit mapping (blank=space, 21=left half, 42=right half,
63=full block). If your font lacks sextants set `TRS80_GFX=braille` or
`TRS80_GFX=ascii` before starting for alternative renderings. The
*internal byte values are always exact* regardless of glyph choice:
SET/RESET/POINT (128x48 grid), PRINT CHR$(128..191), PRINT@, POKE/PEEK of
display memory and string-packing tricks all share one screen buffer.

EXT (2026-08-12): SET takes an optional third argument, `SET(x,y,c)` with
c 0-8 — the CoCo Color BASIC palette — coloring the character cell in grid
mode (`man SET` for the palette and rules). Valid LEVEL II never writes the
third argument, so period programs are unaffected; POINT still returns
exactly -1/0.

PRINTing codes 192-255 performs LEVEL II space compression (192+n prints
n spaces); POKEing 192-255 into display memory renders the same glyph as
128-191 (the Model I ignores bit 6 of graphics bytes — real hardware
behavior). Control codes on PRINT: 8 backspace-erase, 10/13 newline,
24-27 cursor moves, 28 home, 29 carriage-return-to-col-0, 30 erase to end
of line, 31 erase to end of screen; 14/15/23 accepted and ignored.
Codes 96-126 render as ASCII lowercase.

## CLOAD / CSAVE

Text-file stand-ins for cassette: `CSAVE "prog.bas"` writes a plain
listing (overwrites); `CLOAD "prog.bas"` NEWs and loads; `CLOAD? "f"`
verifies the file against memory and prints `BAD` on mismatch. Quotes
around the filename are optional (an unquoted bare word works). Invalid
lines in a loaded file are reported and skipped, never fatal: each skip
prints `?FD ERROR - FILE LINE n (reason)`, where `n` is the physical line
number *within the .bas file* (not a BASIC line number) and the reason is
`LINE NUMBER > 65529`, `EMPTY LINE BODY`, or `NO LINE NUMBER`. This catches
only structural problems; a syntactically bad but well-numbered line loads
and is diagnosed later at RUN.

`CLOAD` reads two forms. A plain-ASCII program listing (line number
followed by the line text, exactly what `CSAVE` writes), and — since
2026-09-12 — the tokenized "crunched" cassette format: a binary image
beginning with a `0xFF` header, storing keywords as single bytes 0x80-0xFB
in a linked list of lines, which is how most archived commercial programs
survive. `LOAD`, `MERGE` and batch mode accept it too. Every line's
original body bytes are kept and imaged at 42E9H exactly as the file holds
them, relinked, so a machine-language payload stored as fake BASIC lines
(CR bytes and all) is what `PEEK` and a `USR` routine see; `LIST` shows
the detokenized text, with the same keyword spacing `detok.py -s` inserts.
The loader is one-way: `CSAVE` and `SAVE` write text. A line that is
retyped, `DELETE`d, overwritten by a text `MERGE`, or renumbered with
`NAME` (which touches every line) becomes text again and is re-crunched
from its listing. A malformed image stops at the first desync — truncated
header, unterminated line, line number above 65529, duplicate line number
— with a `?FD ERROR - FILE LINE n (reason)` line; lines before it stay
loaded. An empty stored body stays empty in the image and lists as `REM`.

To read or edit an image as text, convert a copy with `tools/detok.py`:

    python3 tools/detok.py -s -o listings/ IMAGE.BAS

Use `-s`. Level II stores what you typed and `LIST` expands tokens tight, so
a faithful rendering is `FORX=1TOR`, which this interpreter reads as the
single identifier `FORX` (see *Compressed keyword-adjacent source*, below).
`-s` separates them using the exact boundaries in the token stream.

`tools/tok.py` is the inverse, and turns a listing back into a cassette
image. See `tools/DETOK.md` for the format, the two places conversion cannot
be byte-faithful, and the round-trip verification.

The interpreter itself does no content cleanup on load — it tolerates only
container noise (trailing CR, leading whitespace, blank lines) and reports any
line without a line number rather than guessing. That boundary is deliberate.

## Disk BASIC file I/O

File access is simulated the same way as CLOAD/CSAVE: the BASIC filename is a
literal host file path (created in the current directory), and files are plain
text. Channels are 1..15.

Statements: `OPEN mode$, [#]n, name$ [, reclen]` with modes `"I"` (sequential
input), `"O"` (output, truncates), `"E"` (extend/append), `"R"` (random
access, reclen 1..256, default 256); `CLOSE [[#]n, ...]` (no args = close
all; closing an unopened channel is a no-op); `KILL name$`; `PRINT #n, ...`
(`USING` honored, as with PRINT); `INPUT #n, vars` (legal in
immediate mode; items split on commas, quotes respected, and an unfinished
line carries over to the next INPUT#); `LINE INPUT ["prompt";] v$` and
`LINE INPUT #n, v$` (whole line, no splitting, no `? ` prompt);
`FIELD [#]n, w AS v$, ...`; `GET`/`PUT [#]n [, record]` (record defaults to
the next one); `LSET`/`RSET v$ = expr$`.

Functions: `EOF(n)` (-1 at end, 0 otherwise; true look-ahead, so
`IF EOF(1)`-guarded read loops work), `LOF(n)` (records in a random file),
`LOC(n)` (lines read/written, or last record), `MKI$/MKS$/MKD$` and
`CVI/CVS/CVD` (Microsoft Binary Format: 2-byte int, 4-byte single, 8-byte
double — real FIELD widths from published listings work unchanged).

New error codes 24..31: `BN` bad file number, `NO` file not open, `AO` file
already open (also: same host file on two channels, or KILL of an open
file), `IE` input past end, `BM` bad file mode, `FF` file not found, `BR`
bad record number, `FO` field overflow. `ERR`/`ERL` and `ON ERROR GOTO`
work with all of them.

Simulation notes and deviations:

- Sequential files are ordinary text lines — write them with PRINT#, read
  them with INPUT#/LINE INPUT#, or edit them in any text editor.
- Random files hold one record per line, space-padded to the record length;
  backslash and non-printable bytes (e.g. inside MK*$ values) are escaped
  as `\\` / `\xNN` on disk and restored on OPEN "R". Record data lives in
  memory between OPEN "R" and CLOSE; CLOSE rewrites the whole file.
  RUN/NEW/CLEAR/CLOAD/END/BYE close (and flush) all channels — STOP does
  not, so BREAK + CONT keeps files open.
- `,` in PRINT# writes no display-zone padding (zone spaces would corrupt
  comma-delimited re-reading; print an explicit `","` between items, as the
  manuals themselves recommend). A trailing `;`/`,` holds the partial line
  until the next PRINT# or CLOSE.
- The cassette form `PRINT#-1` is not supported (channels are 1..15).
- Fielded string variables are refreshed on GET/LSET/RSET; a plain
  `A$="X"` assignment detaches the variable from its buffer until the next
  GET — the same footgun as on real hardware.
- `MKD$`'s 56-bit mantissa exceeds awk's 53-bit doubles, so the last
  mantissa byte of extreme values may differ from real hardware (harmless:
  CVD round-trips exactly).
- OPEN/KILL/statement keywords (OPEN, CLOSE, FIELD, GET, PUT, LSET, RSET,
  KILL, LINE) and function names (EOF, LOF, LOC, MKI$, MKS$, MKD$, CVI,
  CVS, CVD) are now reserved, as in real Disk BASIC.

## OLLAMA device channel (talk to a local LLM from BASIC)

OPENing a file whose name starts with `OLLAMA` turns that channel into a
bidirectional link to a local [Ollama](https://ollama.com) server — the
device-file idiom of TRS-DOS, applied to an LLM:

    10 OPEN "O",1,"OLLAMA:llama3.2:story"
    20 PRINT #1, "Continue this story in 3 sentences:"
    30 PRINT #1, "It was a dark and stormy night."
    40 LINE INPUT #1, L$        ' blocks: sends prompt, gets reply
    50 PRINT L$
    60 IF NOT EOF(1) THEN 40
    70 CLOSE 1

Semantics:

- The OPEN mode letter is accepted and ignored; the channel is
  bidirectional. `PRINT #n` accumulates prompt lines (a trailing `;`
  holds a partial line exactly as with disk files). The **first
  INPUT#/LINE INPUT# after a PRINT#** sends the accumulated prompt —
  blocking until the model answers — and the reply becomes pending
  input, read line by line. `EOF(n)` is -1 once the reply is consumed
  and never itself triggers a send.
- `LINE INPUT #n` is the natural way to read prose. `INPUT #n` also
  works and splits on commas — tell the model to answer as
  comma-separated values and INPUT# parses them straight into BASIC
  variables. Trailing blank lines that models pad replies with are
  trimmed.
- Naming: `OLLAMA[:model[:thread]]`. With 3+ colon-separated parts the
  *last* part is the thread and the middle parts (rejoined) are the
  model, so tagged models work: `OLLAMA:mistral:7b:mychat`. A tagged
  model with *no* thread needs a trailing colon (`OLLAMA:mistral:7b:`).
  No model part → `TRS80_OLLAMA_MODEL` env var (else ?MO).
- Conversation state: the interpreter holds the full message history and
  resends it on every call (`/api/chat` is stateless), so multi-turn
  context is real. A *named* thread appends every completed exchange to
  `<thread>.ollama` (one escaped line per message, same `\xNN` escaping
  as random-access files) and reloads it as context on OPEN — so a
  conversation survives CLOSE, RUN, and even interpreter restarts.
  `KILL "<thread>.ollama"` resets it. `LOC(n)` = messages in history.
  Threadless opens (`OLLAMA` / `OLLAMA:model`) are memory-only.
- Multiple channels with independent threads may be open at once.
- Transport: `curl` POST to `http://$TRS80_OLLAMA_HOST/api/chat`
  (default `localhost:11434`), `stream:false`, timeout
  `TRS80_OLLAMA_TIMEOUT` seconds (default 300) via curl `--max-time`.
  The JSON body travels through a temp file, so prompts with quotes,
  commas, or newlines need no escaping in BASIC.
- Errors: transport/HTTP/JSON failure raises ?FD and rolls the
  unanswered prompt back out of the history (the exchange can be
  retried); reading with nothing pending and nothing to send raises
  ?IE. While the model is generating, the interpreter is blocked inside
  the HTTP call — BREAK does not interrupt it (the timeout is the
  backstop).
- `TRS80_OLLAMA_CURL` replaces the whole curl command (the body-file
  path is appended) — used by the test stub, also handy for proxies.
- **Directives (2026-08-21).** A completed `PRINT #n` line whose first
  character is `@` steers the channel and is never sent to the model:

      90 PRINT #1, "@TOKENS REFUSE,ADMIT_ALLEY"
      100 PRINT #1, "Detective: this is your glove, Victor."
      110 LINE INPUT #1, T$      ' T$ is exactly REFUSE or ADMIT_ALLEY
      120 LINE INPUT #1, L$      ' the spoken reply follows

  `@TOKENS A,B,C` applies to the next send only: the request carries
  Ollama's structured-output `format` (a JSON schema with `token` as an
  enum of the list and `reply` a string), and the reply is delivered as
  the token on line 1 and the reply text after — constrained decoding
  means line 1 *cannot* be anything but a listed token. If the content
  is not unpackable the raw text is delivered. `@THINK 0|1` (send
  `think:false/true` — thinking models otherwise spend tens of seconds
  reasoning before a one-line answer) and `@KEEPALIVE 30m` (hold the
  model loaded between calls) are sticky for the channel; env defaults
  `TRS80_OLLAMA_THINK` and `TRS80_OLLAMA_KEEPALIVE`. `@@text` sends a
  literal line beginning with `@`; an unknown directive raises ?FC.
  Test: `programs/tests/t29.txt` with the stub, which now echoes the
  option fields and answers a schema with its last enum value.

### OCR'd / PDF listings

Listings copy/pasted out of PDFs or OCR scans are damaged text, not a
different encoding, and are out of scope here: `detok.py` will not help, and
the interpreter reports the first `?SN`. Repairing them is a separate tool
(basclean), maintained outside this repository.

## Omissions and deviations (documented)

- EDIT is not implemented (excluded by design). AUTO and DELETE are.
- SYSTEM is the one machine-language feature still excluded. OUT is an
  accepted no-op (2026-08-12: both expressions evaluate, the port write
  does nothing). INP(p) is implemented (2026-09-11): port 255, the
  cassette/video-mode port, is live (127 in 64-character mode, 63 after
  CHR$(23)); every other port reads 255, the open bus, so RS-232, floppy
  and joystick probes take their "not present" branch.
- USR (2026-09-10/11): `DEF USRn=addr` is stored as slot n's entry
  address (?FC on a bad one), and slot 0 falls back to the POKEd vector
  at 16526/7 (408EH), so period loaders that never say DEF USR still
  resolve. With `TRS80_Z80=<command>` naming the companion Z80 core, a
  USR call sends the machine's memory image to the core and the routine
  RUNS (the wire format is `PROTOCOL.md`; `TRS80_Z80_TIMEOUT` is the
  per-reply guard in milliseconds, default 5000). THE CORE EXISTS
  (2026-09-12): `TRS80_Z80="python3 ../trs80_z80_core/core.py"` runs the
  routine for real — a full Z80 validated against 1.6 million single-step
  vectors, serving 01C9H (CLS), 0A7FH (argument to HL) and 0A9AH (HL to
  result) as the only ROM entry points, the USR return pushed as the
  sentinel 2FFDH, port FFH reading 127 and every OUT discarded; any other
  jump into ROM space is ?FC with the address on stderr. Without a core the
  call is a stub that returns its argument — and is no longer silent: a
  run that called USR ends with one stderr line naming the entries and
  call counts that were not executed, and `TRS80_USR=strict` raises ?FC
  at the call instead, so a routine that silently did nothing is never
  mistaken for one that worked.
- VARPTR IS implemented (2026-08-14): for a string it returns a live
  [len][addr lo][addr hi] descriptor whose byte region PEEKs and POKEs
  through to the value (the string-packing sprite idiom works); for a
  numeric, the address of its 4 Microsoft-single bytes, also live both
  ways. The address is STABLE (2026-09-10): one address per variable per
  run, data re-homed only when a string grows, so the two-call idiom
  `PEEK(VARPTR(A$)+1)+256*PEEK(VARPTR(A$)+2)` composes the real address.
  POKEing the descriptor repoints the string (2026-09-11): `POKE
  VARPTR(A$)+1,lo:POKE VARPTR(A$)+2,hi` aliases A$ onto video or system
  RAM, the screen-editor trick, and LSET/RSET/MID$= then write through
  to that memory; an ordinary assignment to A$ ends the alias.
- LPRINT and LLIST work (2026-08-12): the line printer is a host stream —
  set TRS80_PRINTER=path to append printed output to that file; unset,
  output is discarded (the hardware analog of no printer attached).
  LPRINT supports ; , TAB and USING with its own column counter, and
  the printer status at 14312/3 always reads 63 (attached and ready).
  The ROM device vectors re-route output (2026-09-11): `POKE 16414,141:
  POKE 16415,5` sends PRINT to the printer, `POKE 16422,88:POKE 16423,4`
  sends LPRINT to the screen, `POKE 16422,103:POKE 16423,0` silences
  the printer, and restoring the ROM values (88,4 / 141,5) puts it back;
  the printer's lines-per-page, line counter and column at 16424, 16425
  and 16539 are live.
- Disk BASIC file I/O IS implemented (see "Disk BASIC file I/O" above),
  as are LOAD/SAVE, RUN "file", INSTR, TIME$, &H/&O literals, the
  MID$ statement (2026-08-12: in-place replace, target length never
  changes), and RESTORE n (2026-08-12: DATA pointer to the first item
  at/after line n, ?UL if the line is missing), DEF FN (2026-08-13:
  real user functions, all three spellings), MERGE (2026-08-14: no
  implicit NEW; file lines overwrite/interleave, variables clear,
  returns to command level), and NAME (2026-08-14: renumber with full
  reference rewrite — GOTO/GOSUB/ON.. lists/THEN/ELSE/RESTORE/RESUME/
  RUN; ERL comparisons cannot be fixed). Still absent: CMD (raises ?SN).
- CLEAR takes any numeric expression (2026-08-12 conformance fix —
  CLEAR M, CLEAR FR!-8000 appear throughout period listings).
- Gated extensions (2026-08-12): `ext on` (metacommand; or TRS80_EXT=1)
  additionally accepts the INPUT"PRESS ENTER"; pause idiom and DIM of
  scalars (declaration lists). Off by default so damaged OCR listings
  still fail loudly; `ext` alone shows the state.
- REM META: directives (2026-09-07, same gate): a remark beginning
  `META:` carries a metacommand that fires when execution reaches the
  line — `10 REM META:fullscreen on`, `500 REM META:speed 1.77` — so a
  program can state its own display and pacing. `speed` and `fullscreen`
  are the entire whitelist; anything else after META: is ignored in
  silence, and `dir`/`cat` are deliberately unreachable from a file.
  With the gate off the line is an ordinary remark, so such a listing
  stays valid Level II everywhere else.
- DEFSTR is honored (2026-08-12): bare names under a DEFSTR letter range
  resolve as strings everywhere — assignment, arrays, INPUT, READ, FOR
  (?TM), file I/O. DEFINT/DEFSNG/DEFDBL clear the DEFSTR flag for their
  range but numeric precision is still ignored (all numerics are gawk
  doubles; `%` `!` `#` suffixes accepted and stripped, so an explicit
  suffix does not override DEFSTR the way it would on hardware).
- PRINT USING honors the picture string: # . , ** $$ **$ fields, leading
  + / trailing + or - signs, ^^^^ exponent form, ! and %spaces% string
  fields, literal passthrough, picture reuse across the value list, and
  the % overflow prefix for too-wide numbers. Wrong-type values raise
  ?TM; a fieldless picture with values remaining raises ?FC. Rounding is
  half-up (as the ROM), and in ^^^^ form the significant digits fill
  every integer position with the exponent adjusted (a sign, when shown
  on the left, takes one position). USING may appear at ANY item
  position, not only at the head of the list (2026-09-07 conformance
  fix): PRINT TAB(57) USING X$;EC is the period idiom, and USING takes
  over formatting for the rest of the statement. PRINT#, LPRINT and
  LLIST accept it in the same places.
- Numeric literals in E/D exponent form (1E3, 1.5D-2) are parsed in
  source, VAL, DATA and INPUT; `.5`, `5.` etc. too. Doubles mean exact
  integers print in full (e.g. 12345678, where real single-precision
  hardware would show 1.23457E+07), and E vs D carries no precision
  difference.
- Variable names are fully significant (the ROM's 2-character rule is not
  enforced): SUM and SU are different variables.
- Strings may be arbitrarily long (ROM caps at 255).
- Compressed keyword-adjacent source (`IFA=1THEN100`) is not tokenized —
  `IFA` lexes as one identifier. This is the dominant failure when running
  archived listings, which are full of it; `tools/detok.py -s` re-separates
  them from the token stream when converting a cassette image.
- RND runs the authentic ROM 24-bit LCG (2026-08-14): RND(0) a float
  in [0,1), RND(n) an integer 1..n, RND(1) always 1 (as on hardware).
  The seed is PEEK/POKEable at 16554-16556; RANDOM (and boot) rewrite
  only the middle byte, like the ROM's R-register read. `--seed N`
  makes the whole sequence repeatable.
- The memory map (`man PEEK` has the full list). Live cells, each read
  from the state it names: the keyboard matrix at 14336-14591 (INKEY$'s
  key, row by row); printer status 14312/3; the display at 15360-16383;
  the BREAK vector 16396; the video and printer driver vectors 16414/5
  and 16422/3; the system variable window (2026-09-11) — cursor position
  and character 16416-16418, printer lines-per-page, line counter and
  column 16424/16425/16539, the Model I clock 16449-16454, the current
  line number 16546/7, AUTO's flag, line and increment 16609-16613
  (`POKE 16609,1` starts AUTO), the TRON flag 16667; the USR vector
  16526/7; the program base 16548/9, start of variables 16633/4, and top
  of memory 16561/2; the RND seed 16554-16556. Everything else is RAM
  that reads 255 until POKEd.
- The stored program is PEEKable in the authentic tokenized format from
  17129 (42E9H); a numeric answer to MEMORY SIZE? becomes HIMEM, the
  ceiling string space allocates below. Memory above HIMEM is reserved,
  not absent — still readable and writable, which is what makes the
  classic reserve-then-load idiom work (corrected 2026-09-08; it used to
  read 255 and discard POKEs). 16561/2 is also WRITABLE, so `POKE
  16561,lo:POKE 16562,hi:CLEAR n` moves HIMEM from inside a program, the
  way listings reserve their own space (2026-09-08; the POKE used to be
  silently dropped). POKEs into the program region are not read back
  (no self-modifying code). A program too large for the space below the
  top of memory is imaged up to the last whole line that fits, with the
  terminator there, and one stderr line says so (2026-09-11); the
  program itself still runs in full.
- Model III character modes (2026-08-14): printing CHR$(21) toggles
  codes 192-255 between space compression and character display,
  CHR$(22) picks the set (card suits/Greek/math vs halfwidth Katakana);
  CHR$(23) shifts to the Level II 32-character double-width mode (CLS
  returns to 64).
- INPUT is not allowed in immediate mode (?ID ERROR), like the ROM.
- AUTO shows `*` for existing lines; ENTER keeps the old line (or exits
  AUTO on a line that does not exist); BREAK exits.
- Scrolling redraws the whole 16-row window; heavy graphics loops are
  redrawn cell-by-cell (fast in practice).
- STEP 0 loops forever (positive-step test), as on the ROM.

## Testing / automation aids (not LEVEL II features)

Batch mode: `./basic prog.bas` LOADs and RUNs the program non-interactively
and exits 0 on a clean run, 1 on an uncaught BASIC error (also printed to
stderr as `?SN ERROR IN 40`), 2 on a bad invocation or unreadable file.
stdin feeds the program's INPUT statements; `--seed N` makes RND
repeatable; `--screen` keeps the 64x16 screen control codes in the output
(plain text is the default without a tty); `--` ends the options and
`-h`/`--help` prints the usage. Batch mode has no raw keyboard, so INKEY$
reads whole lines from stdin.

Piped stdin (no tty) is read line-by-line; INKEY$ then consumes input
characters. `TRS80_DUMB=1` disables ANSI positioning for readable
transcripts. `TRS80_KMHOLD=<n>` (default 4) is how many INKEY$ polls one
keypress holds for in the interactive grid, since a terminal sends no
key-up events. The immediate command `@dump` (lowercase only, like the
other metacommands) prints the current 16-row screen buffer. The
`programs/tests/` folder holds the scripted regression transcripts
(t1..t33), self-checking `.bas` fixtures that assert on their own output
(VARPTR, raw bytes, string aliasing, INP, the system variable window),
shell suites for the BREAK and device vectors, the USR frame, image
truncation and the coprocess protocol, and `z80_stub.py`, the reference
stand-in for the Z80 core.

At startup, a short credit/help banner is drawn below the virtual screen (it
shares the region used by `man`/`help`, so the first such call replaces it).

The immediate command `dir` (lowercase only — it is not a BASIC keyword
and `DIR`/`Dir` do not trigger it) runs `ls -al` in the directory the
interpreter was launched in. Anything typed after `dir` is passed to a
real shell along with the `ls -al` invocation, so relative paths, `~`,
globs, and extra dash options all behave exactly as they would at a
Linux prompt — including shell metacharacters like `;` and `|`.

The immediate command `fullscreen on|off|1|0` (lowercase only, like `dir`)
selects the display mode `TRS80_DUMB=1` sets at startup: `fullscreen on` stops
constraining text output to the captive 64x16 grid and lets it stream using the
real terminal's own wrapping and scrollback; `fullscreen off` returns to the
fixed-grid display, repainted from the current screen buffer. A bare
`fullscreen` with no argument prints the current state. (This replaces the older
bare `fullscreen`/`trs80screen` pair.) This only affects text output —
graphics/semigraphics addressing is unchanged either way.

The immediate command `speed <mhz>` (lowercase only) throttles program
execution to emulate a slow clock: each BASIC statement is charged a fixed delay
derived from the target megahertz, so loops run at a period-authentic pace.
`speed 0` (the default) runs at full host speed; a bare `speed` prints the
current setting. `TRS80_MHZ=<n>` sets the initial value at startup. The delay is
batched (one `sleep` per ~30ms of accumulated debt) to stay smooth. This is a
feel knob, not a cycle-accurate emulator.

The immediate command `man <KEYWORD>` (lowercase only) shows a one-line syntax
form plus an example for any BASIC statement or function (e.g. `man PRINT`,
`man MID$`). In grid mode the help is drawn in a self-clearing region *below*
the 64x16 screen (rows 18+), so it never disturbs the display and each `man`
call overwrites the previous one; in `fullscreen on` mode it simply streams.

The help text is loaded at startup from `support/manpages.txt` — a plain,
user-editable file. Each entry begins with a `:KEYWORD` line (list several
keywords to share one body, e.g. `:DEFINT DEFSNG DEFDBL DEFSTR`); the lines up
to the next `:` are its body, and `#` lines are comments. Edit or extend it
freely; set `TRS80_MANFILE` to load from a different path. If the file is
missing, `man` reports that no entries are loaded and everything else works.

The immediate command `help` (lowercase only) is a discovery aid over the same
help text, rendered in the same below-grid region. `help meta` lists the
metacommands; `help keys` the terminal key bindings; `help <text>` shows the
page directly when `<text>` is an exact command name (`help ollama`,
`help print`), otherwise finds every BASIC command whose name *or* man text
contains `<text>` (case-insensitive) — a single distinct match expands to its
full man page, multiple matches list as name + syntax lines; bare `help` prints
a short usage. Alias groups that share one entry (e.g. the `DEF*` statements)
count once. On exit (`BYE`), the shell prompt is parked at the bottom of the
terminal, clear of the below-grid text.

## Demo programs

- `demo_showcase.bas` — math, strings, arrays, FOR/NEXT, GOSUB nesting,
  DATA/READ/RESTORE, ON ERROR/RESUME, PEEK/POKE (255 default), zones,
  TAB, PRINT@.
- `demo_graphics.bas` — draws a semigraphics house via SET, POKE of 191s
  and CHR$ graphics; bouncing-ball animation using INKEY$, POINT
  collision, RESET. Q quits.
- `gfxtest.bas` — the graphics bit-layout self-test: prints CHR$(128) to
  CHR$(191), then SET/POINT/PEEK cross-check (expects six -1s and 191).

Load any of them with e.g. `CLOAD "programs/demos/demo_graphics.bas"` then `RUN`
(paths as of 2026-09-15: the interactive demos live in `programs/demos/`,
`demo_showcase` moved to `programs/examples/` with a transcript, and
`gfxtest.bas` was removed)
(paths resolve against the directory you started in).
