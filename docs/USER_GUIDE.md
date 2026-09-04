# TRS-80 LEVEL II BASIC — User Guide

This is the long-form companion to the [README](../README.md). The README
gets you running; this guide covers everything the interpreter does — with
particular attention to where it **extends, modifies, or appropriates** the
1978 textbook, because that is what you cannot look up anywhere else.

It assumes you know BASIC, or can read the original documentation:

- [Level II BASIC Reference Manual, 1st Ed. (1978, Radio Shack)](https://archive.org/details/Level_II_BASIC_Reference_Manual_1st_Ed._1978_Radio_Shack) —
  the functional specification this interpreter was written against.
- [TRSDOS & Disk BASIC Reference Manual](https://archive.org/details/trsdos-disk-basic-ref) —
  the file I/O statements come from here.
- [Ira Goldklang's TRS-80 Revived Site](https://www.trs-80.com/) — the
  encyclopedic community reference for everything Model I.

Throughout, **EXT** marks behaviour that is an extension — things real
Level II never did. Everything else is intended to match the manuals.

---

## Part I — Getting around

### Starting up

```bash
./basic
```

You get the authentic `MEMORY SIZE?` prompt (press ENTER — or answer with a
number, which really does become the top of RAM: `PEEK` above it reads 255,
`POKE` above it is discarded), the `RADIO SHACK LEVEL II BASIC` banner, and
`READY`. Exit with `BYE`, which restores your terminal; if the interpreter
is ever killed abnormally, `stty sane` recovers the tty.

The top 16 rows of your terminal are the simulated 64x16 display. Everything
— prompt, echo, LIST, program output — passes through the simulated screen
buffer and scrolls exactly as displayed memory. Display memory is
PEEK/POKEable at 15360–16383 (`addr = 15360 + row*64 + col`).

A statement typed without a line number executes at once — that is
**immediate mode**, the `>` prompt; a line that starts with a number is
stored into the program instead. The guide uses the term throughout.

Requirements: GNU awk 5.x, a VT100/ANSI terminal at least 64x20, UTF-8
locale.

### Keys

`help keys` inside the interpreter lists these; control keys work shifted
or unshifted.

| key | does |
|---|---|
| Ctrl-C | **BREAK**: stops a running program (`BREAK IN nnnn`), cancels the input line, stops LIST, exits AUTO. `CONT` resumes after BREAK/STOP/END |
| Ctrl-S | pause a running program or LIST (the real SHIFT-@); any key resumes, Ctrl-C breaks |
| Ctrl-L | CLEAR: wipe the screen at the `>` prompt |
| Ctrl-U | erase the input line (SHIFT-left-arrow) |
| Ctrl-A / Ctrl-E | start / end of the input line |
| left / right arrow keys | move the cursor; insertion happens at the cursor |
| up / down arrow keys | command history at the `>` prompt (`history` lists it; per-session) |
| PgUp / PgDn | page long output below the grid (Ctrl-B / Ctrl-F also work) |
| TAB | filename completion at the `>` prompt — longest common prefix, candidates listed below the grid when ambiguous |

The arrow-key line editor, history, and TAB completion are of course
**EXT** — 1978 gave you SHIFT-left-arrow and resignation. One tuning knob:
a terminal sends no key-up events, so a keypress "holds" for `TRS80_KMHOLD`
`INKEY$` polls (default 4) — raise or lower it if a period game reads your
taps as too long or too short.

### Metacommands (EXT)

A small set of immediate commands that are *not* BASIC keywords. They are
**strictly lowercase** — `dir` is a metacommand, `DIR` reaches BASIC and
raises `?SN ERROR`. That case split is what keeps the two namespaces from
ever colliding with a period program.

| command | does |
|---|---|
| `dir [args]` | `ls -al` passthrough, run where the interpreter started; arguments, globs, `~`, even pipes behave as at a shell prompt |
| `cat <file...>` | show file contents (non-text bytes as `.`) |
| `man <keyword>` | syntax + example for any BASIC word, case-insensitive (`man print`, `man MID$`) |
| `help <text>` | search: exact name shows the page; otherwise every command whose name *or* man text matches, case-insensitive. `help meta`, `help keys` are special pages |
| `ext on\|off` | the gated-extensions switch (see Part IV); bare `ext` shows state |
| `fullscreen on\|off` | stream output with the terminal's own scrollback instead of the captive 64x16 grid; graphics addressing is unchanged either way |
| `speed <mhz>` | throttle execution to a period pace (`speed 1.77` ≈ a real Model I); `speed 0` = full host speed. A feel knob, not a cycle-accurate emulator |
| `history` (or `h`) | list this session's typed commands |
| `@dump` | print the 16-row screen buffer (debugging aid) |

Metacommand output renders *below* the grid, never on the simulated screen.

The `man`/`help` text lives in `support/manpages.txt`, a plain file with a
one-line format described in its own header — edit or extend it freely.

### Loading and saving programs

`CSAVE "prog.bas"` writes a plain-text listing; `CLOAD "prog.bas"` NEWs and
loads it; `CLOAD? "f"` verifies against memory and prints `BAD` on mismatch.
The "cassette" is just a text file holding the program *listing* — the
detokenized form, exactly what `tools/detok.py` produces — and that is the
appropriation that makes everything else pleasant: programs are editable in
any editor and diffable in git. `SAVE` writes the same form; `LOAD` is the Disk BASIC spelling of
the same reader — plain `LOAD` closes all file channels, `LOAD "f",R` runs
the program after loading and *keeps* open channels. `RUN "file"` loads and
runs.
Filenames may be unquoted (`CLOAD programs/demo.bas`), with case, `/` and
`.` preserved; a `:`-statement cannot follow an unquoted name.

Invalid lines in a loaded file are reported and skipped, never fatal:
`?FD ERROR - FILE LINE n (reason)`, where `n` is the physical line in the
file. Only structural problems are caught at load; a well-numbered but
syntactically bad line loads and fails at RUN, like the real machine.

`MERGE "f"` interleaves file lines into the current program (no implicit
NEW); `NAME` renumbers, rewriting every `GOTO`/`GOSUB`/`ON`-list/`THEN`/
`ELSE`/`RESTORE`/`RESUME`/`RUN` reference (`ERL` comparisons cannot be
rewritten).

**Tokenized cassette images** — binary files starting with a `0xFF` byte,
which is how most archived commercial software survives — are *not*
loadable and never will be: the interpreter reads text. Convert first:

```bash
python3 tools/detok.py -s -o listings/ IMAGE.BAS
```

The `-s` matters. Level II stored what you typed, so a faithful listing
reads `FORX=1TOR` — and this interpreter lexes that as the single
identifier `FORX` (see Part IV). `-s` re-separates keywords using the exact
boundaries in the token stream. `tools/tok.py` is the inverse;
`tools/DETOK.md` documents the format.

### Batch mode (EXT)

```bash
./basic prog.bas               # LOAD, RUN, exit
printf '5\n10\n' | ./basic prog.bas   # stdin answers the INPUTs
./basic --seed 42 prog.bas     # repeatable RND
```

Exit status: **0** clean, **1** uncaught BASIC error (also on stderr in the
classic `?SN ERROR IN 40` form), **2** bad invocation. Output is a plain
text transcript (`--screen` keeps the cursor codes; graphics are not
rendered in batch). Running out of stdin at an `INPUT` is an error, so a
test can never hang on a prompt — but there is no loop guard, so wrap a
possibly-non-halting program in `timeout`.

The seven programs in `programs/examples/` are a guided tour — each
demonstrates one area of this guide and doubles as a regression fixture
(`run_examples.sh` checks them against committed transcripts):

| example | demonstrates |
|---|---|
| `hilo.bas` | stdin-fed INPUT, `--seed`, deliberate non-zero exit |
| `logbook.bas` | sequential files, `ON ERROR` for a missing file |
| `starfile.bas` | random-access files, `FIELD`/`MKI$`/`CVI` |
| `life.bas` | `SET`/`RESET`/`POINT` |
| `palette.bas` | colour semigraphics (EXT) |
| `oracle.bas` | the OLLAMA channel, `@TOKENS` |
| `trapper.bas` | `ON ERROR GOTO`, `ERR`/`ERL`, `RESUME`, `ERROR n` |

---

## Part II — The language, briefly

This interpreter implements Level II as the manual describes it: the
statement set, `PRINT` zones/`TAB`/`USING`, string functions, arrays,
`DEF FN` (all three spellings), `DEFINT`/`DEFSNG`/`DEFDBL`/`DEFSTR`,
`ON ERROR GOTO` with `ERR`/`ERL`/`RESUME`, `READ`/`DATA`/`RESTORE n` —
plus the Disk BASIC additions (`INSTR`, `TIME$`, `&H`/`&O` literals, the
`MID$` statement, `LOAD`/`SAVE`, and the file I/O of Part III). If
you knew it in 1980, it is here; if you didn't, the
[reference manual](https://archive.org/details/Level_II_BASIC_Reference_Manual_1st_Ed._1978_Radio_Shack)
teaches it better than this guide should try to. Part V lists every
keyword with syntax and an example — the same text `man` shows.

Things worth knowing even if you know Level II:

- **Error codes**: `ERR` holds `(code-1)*2`, so the code is `ERR/2+1` —
  1 NF, 2 SN, 3 RG, 4 OD, 5 FC, 6 OV, 7 OM, 8 UL, 9 BS, 10 DD, 11 /0,
  12 ID, 13 TM, 14 OS, 15 LS, 16 ST, 17 CN, 18 NR, 19 RW, 20 UE, 21 MO,
  22 FD, 23 L3, and (EXT, for file I/O) 24 BN, 25 NO, 26 AO, 27 IE,
  28 BM, 29 FF, 30 BR, 31 FO. `ERROR n` raises one on purpose.
- `INPUT` is not allowed in immediate mode (`?ID`), like the ROM.
- `AUTO` shows `*` for existing lines; ENTER keeps the old line; BREAK exits.
- `EDIT` does not exist here (by design — you have a real editor and
  `CSAVE`d text files).

---

## Part III — The extensions

The heart of the matter: what this interpreter does that the books don't
describe.

### Graphics, colour, and the character set

`SET`/`RESET`/`POINT` address the authentic 128x48 grid over the 64x16
screen; `CHR$(128..191)` are the 2x3 semigraphics cells (bits TL=1 TR=2
ML=4 MR=8 BL=16 BR=32), rendered as Unicode "Symbols for Legacy Computing"
sextants — a bit-exact mapping. If your font lacks them, `TRS80_GFX=braille`
or `TRS80_GFX=ascii` choose alternative renderings; the *internal* byte
values are always exact regardless, so SET/POINT/PEEK/POKE of display
memory and string-packing tricks all agree.

Authentic oddities preserved: printing codes 192–255 performs space
compression (192+n prints n spaces) while *POKEing* them into display
memory renders the same glyph as 128–191 (the Model I ignores bit 6 —
real hardware behaviour); codes 96–126 render as lowercase; the PRINT
control codes (8, 24–31…) move and erase as on the ROM.

**Colour (EXT).** `SET(x,y,c)` with c 0–8 colours the pixel's character
cell using the CoCo Color BASIC palette: 0 black, 1 green, 2 yellow,
3 blue, 4 red, 5 buff, 6 cyan, 7 magenta, 8 orange. The rules keep period
programs untouched:

- valid Level II never writes a third argument, so nothing old changes;
- **only `SET` colours anything**: printed text cannot be colorized — it is
  always black-and-white, and printing over a coloured cell reverts that
  cell to black-and-white;
- colour is per character cell and the last SET wins;
- `POINT` still returns exactly -1/0 — period idioms compare `=-1`,
  accumulate -1s, and apply NOT, so the return value is frozen;
- colour renders in the interactive grid only (not fullscreen, not batch).

`programs/examples/palette.bas` shows the palette and a colour-coded chart.

**Model III character modes.** Printing `CHR$(21)` toggles codes 192–255
between space compression and character display; `CHR$(22)` picks the
alternate set (card suits/Greek/math vs halfwidth Katakana); `CHR$(23)`
switches to the Level II 32-column double-width mode (CLS returns to 64).

**Beware: printing scrolls the pixels.** The screen is one buffer; a PRINT
that reaches the bottom line scrolls graphics too. Read `POINT` before you
print, or place text with `PRINT@`.

### Disk BASIC file I/O

The full Disk BASIC statement set, appropriated onto host files: the BASIC
filename is a literal host path (relative paths resolve against *your
current directory* — the interpreter never changes directory), and the
files are plain text you can read in an editor.

Sequential: `OPEN "I"/"O"/"E"` (input / truncate / append) on channels
1–15, `PRINT #n` (USING honoured), `INPUT #n` (comma-splitting, quotes
respected), `LINE INPUT #n` (whole line), `EOF(n)` with true look-ahead so
`IF EOF(1)`-guarded loops work, `LOC(n)` = lines read/written, `CLOSE`
(no args = all), `KILL name$`.

Random access: `OPEN "R", n, name$, reclen` (1–256, default 256),
`FIELD n, w AS v$...`, `LSET`/`RSET`, `GET`/`PUT [,record]` (default: the
next one), `LOF(n)` = record count, and the `MKI$`/`MKS$`/`MKD$` /
`CVI`/`CVS`/`CVD` pack functions in genuine Microsoft Binary Format —
real FIELD widths from published listings work unchanged.

Simulation notes, honestly labelled:

- A random file holds one record per line, space-padded to the record
  length, with non-printable bytes escaped `\xNN` on disk; records live in
  memory between OPEN "R" and CLOSE, and CLOSE rewrites the file.
- `RUN`/`NEW`/`CLEAR`/`CLOAD`/`END`/`BYE` close and flush all channels —
  `STOP` does not, so BREAK + `CONT` keeps files open.
- `,` in PRINT# writes **no** zone padding (zone spaces would corrupt
  comma-delimited re-reading; print an explicit `","`, as the manuals
  themselves recommend).
- The cassette form `PRINT#-1` is not supported; channels are 1..15.
- A fielded variable detaches from its buffer if you plainly assign to it —
  the same footgun as real hardware; the next GET re-attaches it.
- Errors 24–31 (table above) all work with `ON ERROR GOTO`.

### The OLLAMA channel (EXT)

The device-file idiom of TRS-DOS, applied to a local LLM: OPEN a "file"
whose name starts with `OLLAMA` and the channel becomes a conversation
with an [Ollama](https://ollama.com) server.

The server and its models are your side of the bargain: this project ships
no LLM and does not install one. It talks to an Ollama you have already
installed and pulled a model into (by default at `localhost:11434`).

```basic
10 OPEN "O",1,"OLLAMA:llama3.2:story"
20 PRINT #1, "Continue this story in 3 sentences:"
30 PRINT #1, "It was a dark and stormy night."
40 LINE INPUT #1, L$        ' blocks: sends prompt, reads reply
50 PRINT L$
60 IF NOT EOF(1) THEN 40
70 CLOSE 1
```

How it works:

- **PRINT# accumulates, INPUT# sends.** The first `INPUT#`/`LINE INPUT#`
  after a `PRINT#` transmits the accumulated prompt, blocks until the model
  answers, and the reply becomes pending input, read line by line;
  `EOF(n)` goes -1 when it is consumed. `INPUT #n` splits on commas — tell
  the model to answer CSV and parse straight into variables.
- **Naming**: `OLLAMA[:model[:thread]]`. With 3+ colon parts the *last* is
  the thread, the middle parts are the model, so tagged models work
  (`OLLAMA:mistral:7b:mychat`; a tagged model with no thread needs a
  trailing colon). No model → `TRS80_OLLAMA_MODEL`, else `?MO`.
- **Conversation state is real**: the full history is resent every call.
  A *named* thread persists each exchange to `<thread>.ollama` in the
  current directory and reloads it on OPEN — the conversation survives
  CLOSE, RUN, and interpreter restarts. `KILL "<thread>.ollama"` forgets
  it. `LOC(n)` = messages in history. Multiple channels with independent
  threads can be open at once.
- **Directives** — a `PRINT #n` line starting with `@` steers the channel
  and is never sent to the model:
  - `@TOKENS A,B,C` (next send only): the request uses Ollama's
    structured output so **line 1 of the reply is exactly one of the
    listed tokens** — constrained decoding, not hope — and the prose
    follows on later lines. This is what makes an LLM usable from a
    branching BASIC program:

    ```basic
    90 PRINT #1, "@TOKENS REFUSE,ADMIT_ALLEY"
    100 PRINT #1, "Detective: this is your glove, Victor."
    110 LINE INPUT #1, T$      ' T$ is REFUSE or ADMIT_ALLEY, nothing else
    120 LINE INPUT #1, L$      ' the spoken reply
    ```
  - `@THINK 0|1` (sticky): suppress or allow a thinking model's hidden
    reasoning — without it, some models spend tens of seconds before a
    one-line answer.
  - `@KEEPALIVE 30m` (sticky): keep the model loaded between calls.
  - `@@text` sends a literal line starting with `@`; unknown directives
    raise `?FC`.
- **Transport and errors**: `curl` to `http://$TRS80_OLLAMA_HOST/api/chat`
  (default `localhost:11434`), timeout `TRS80_OLLAMA_TIMEOUT` (default
  300s). A transport failure raises `?FD` and rolls the unanswered prompt
  back out of the history, so the exchange can be retried; reading with
  nothing pending raises `?IE`. While the model generates, the interpreter
  is blocked — BREAK cannot interrupt the call; the timeout is the
  backstop.
- Env defaults: `TRS80_OLLAMA_MODEL`, `_HOST`, `_TIMEOUT`, `_THINK`,
  `_KEEPALIVE`; `TRS80_OLLAMA_CURL` replaces the curl command entirely
  (how the test stub works — see `programs/tests/ollama_stub.sh`).

`programs/examples/oracle.bas` is a complete worked program.

### The simulated machine

More of the Model I is simulated than a text interpreter strictly needs,
because period programs poke at it:

- **The stored program is PEEKable** in the authentic tokenized format from
  17129 (42E9H), with live system pointers at 16548/9 (program base),
  16633/4 (start of variables), 16561/2 (top of memory). POKEs into the
  program region are not read back — no self-modifying code.
- **Display memory** 15360–16383, live both ways.
- **`VARPTR`** returns a live descriptor: for a string, `[len][addr lo]
  [addr hi]` whose byte region PEEKs and POKEs *through* to the value —
  the string-packing sprite idiom from the magazines works. For a numeric,
  the address of its 4 Microsoft-single bytes, also live.
- **RND is the authentic ROM 24-bit LCG**: `RND(0)` a float in [0,1),
  `RND(n)` an integer 1..n, `RND(1)` always 1, as on hardware. The seed is
  PEEK/POKEable at 16554–16556; `RANDOM` (and boot) rewrite only the middle
  byte, like the ROM's R-register read. `--seed N` (EXT) makes the whole
  sequence repeatable.
- **`MEMORY SIZE?`** really sets the top of RAM — but only as a *fence for
  PEEK and POKE* (above it reads 255, POKEs are discarded, like absent
  chips). Nothing else is limited: program size and string space are
  unbounded, and `MEM` and `FRE(0)` return a constant 15572 rather than a
  real count. What is limited: the PEEKable address space. What is not:
  everything your program can actually run out of.
- **LPRINT/LLIST** print to a host stream: set `TRS80_PRINTER=path` to
  append there; unset, output is discarded — the hardware analogue of no
  printer attached.
- **`OUT` is an accepted no-op** (both expressions evaluate, the port write
  does nothing); **`USR`/`DEF USR` parse and stub** (`USRn(x)` returns its
  argument — no Z80 runs, yet); `INP`, `SYSTEM`, `CMD` do not exist.
- **`speed` / `TRS80_MHZ`** charge each statement a delay derived from the
  target clock — games become playable at their intended pace.

---

## Part IV — Fidelity: deviations and kept quirks

### Where this interpreter differs from the ROM

Honest list, stated as current behaviour:

- **`MEM` and `FRE(0)` are constants** (15572). A program that loops
  "until memory is low", or sizes an array from `MEM`, will not see the
  number move — it would misbehave or never terminate.
- **All numerics are doubles.** There is no single/double/integer
  distinction; `%` `!` `#` suffixes are accepted and stripped (so `G%` and
  `G` are the same variable), `DEFINT`/`DEFSNG`/`DEFDBL` set no precision
  (DEFSTR *is* honoured, everywhere). Consequence: exact integers print in
  full — `12345678` where real single-precision hardware shows
  `1.23457E+07` — and E vs D exponent forms carry no precision difference.
- **Variable names are fully significant.** The ROM's 2-character rule is
  not enforced: `SUM` and `SU` are different variables. A period program
  that *relied* on the truncation would misbehave.
- **Strings may be arbitrarily long** (ROM caps at 255; a program relying
  on `?LS`/`?OS` at the cap will not see the error).
- **Compressed source does not lex.** `IFA=1THEN100` is the identifier
  `IFA`, not `IF A`. This is the dominant failure mode when pasting
  archived listings — `detok.py -s` exists precisely for it.
- **`ext on` (EXT gate).** Two forms that valid Level II rejects are
  accepted only when switched on (`ext on` or `TRS80_EXT=1`): the bare
  `INPUT"PRESS ENTER";` pause idiom, and `DIM` of scalars (declaration
  lists). Off by default so that damaged OCR listings still fail loudly —
  the interpreter doubles as a strict `?SN` oracle.
- **Absent**: `EDIT` (by design), `CMD`, `INP`, `SYSTEM` (machine-language
  territory; `USR` stubs as above).
- `CLEAR` takes any numeric expression (`CLEAR FR!-8000` appears throughout
  period listings and works).

### Quirks kept on purpose

- `RND(1)` is always 1. `STEP 0` loops forever. `?EXTRA IGNORED`.
  `PRINT USING` rounds half-up like the ROM, and the `^^^^` form fills
  every integer position with the exponent adjusted.
- `INPUT` in immediate mode raises `?ID`.
- Numeric literals in E/D form (`1E3`, `1.5D-2`), and `.5` / `5.`, parse in
  source, VAL, DATA and INPUT.
- Semigraphics POKE codes 192–255 draw as 128–191 (bit 6 ignored), while
  *printing* them space-compresses — both authentic, and both surprising.

---

## Part V — Reference

<!-- BEGIN GENERATED REFERENCE (make_userguide.py) -->

*This part is generated from `support/manpages.txt` — the same text `man` shows inside the interpreter. Do not edit it here; edit the manpages and run `python3 tools/make_userguide.py`.*

### Statements

#### PRINT

```text
PRINT [items]   display values on the screen
  Separators control spacing:
    ;        no gap -- the next item starts immediately
    ,        skip to the next 16-column zone (4 zones per 64-col line;
             a 5th comma wraps to the next line)
    @n       print at screen position n (0-1023; row = INT(n/64),
             col = n-64*INT(n/64))
    TAB(n)   pad with spaces out to column n
  Numbers carry their own spacing: a leading space for positive values
  (a '-' for negative) and always one trailing space.  So PRINT 1;2
  gives " 1  2 ", not "12".  A leading 0 is dropped: -0.5 prints as -.5.
  A trailing ; or , at the end of the line suppresses the newline, so the
  next PRINT continues on the same line.
  ? is shorthand for PRINT.  See also: man USING, man PRINT#
  Example: PRINT "SUM=";A+B          -> SUM= 12
  Example: PRINT "X","Y"             -> X at col 1, Y at col 17
  Example: PRINT "WAIT";  : PRINT "ING"   -> WAITING
```

#### USING

```text
PRINT [#n,] USING f$; items   format items through picture f$
  numeric fields: # digit  . decimal  , grouping  ** fill  $$ dollar
    **$ both  leading + / trailing + or - sign  ^^^^ exponent
    too-wide numbers print as %number
  string fields: ! first char   %spaces% n+2 chars
  other chars print literally; picture repeats while items remain
  Example: PRINT USING "$$#,###.##"; 1234.5    ( $1,234.50)
```

#### ?

```text
?   shorthand for PRINT
  Example: ?X*2
```

#### LET

```text
[LET] var=expr   assign a value (LET is optional)
  Example: LET X=5      (same as  X=5)
```

#### IF

```text
IF cond THEN stmt|n [ELSE stmt|n]   run stmt (or jump to line n) when true
  Forms: IF e THEN n / IF e GOTO n / IF e THEN stmt / IF e THEN stmt ELSE stmt
  Truth is numeric, not boolean: any non-zero value is true, 0 is false.
  IF A is a valid test meaning "A is not zero".  Comparisons return -1 for
  true and 0 for false, so they feed straight back into arithmetic.
  Strings compare too, character by character on ASCII code ("ABC"<"ABD").
  The branch is the WHOLE REST OF THE LINE, not just the next statement:
    IF A THEN PRINT "X":PRINT "Y"      both are skipped when A is 0
  So a statement that must always run cannot sit after an IF on the same
  line -- give it its own line.  The same applies after ELSE.
  When the test is false and there is no ELSE, control moves to the next
  LINE, not to the next statement.
  Example: IF A>0 THEN PRINT"POS" ELSE PRINT"NEG"
  Example: IF SC>HI THEN HI=SC           (no ELSE needed)
```

#### THEN

```text
THEN   introduces the true branch of IF (stmt or line n)
  See: man IF
```

#### ELSE

```text
ELSE   introduces the false branch of IF
  See: man IF
```

#### GOTO

```text
GOTO n   jump to line n
  Example: GOTO 100
```

#### GOSUB

```text
GOSUB n   call the subroutine beginning at line n
  Execution jumps to line n and continues until a RETURN sends it back
  to the statement just after the GOSUB.  Calls may nest; each GOSUB
  pushes a return address that its RETURN pops.
  A subroutine is an ordinary range of lines -- nothing marks its start,
  so reaching line n by falling through or by GOTO enters the same code
  without a return address, and its RETURN then raises ?RG ERROR.
  End the main program with END before the first subroutine to stop it
  running on into one.
  Example: 10 GOSUB 100:GOSUB 100:END
           100 C=C+1:PRINT "CALL";C:RETURN     -> CALL 1 / CALL 2
```

#### RETURN

```text
RETURN   go back to the statement after the most recent GOSUB
  Returns to the point of the call, not to the start of a line: if the
  GOSUB sat mid-line, execution resumes with the next statement on that
  same line.
  A RETURN with no matching GOSUB raises ?RG ERROR -- usually a sign the
  program ran into a subroutine instead of calling it.
  Example: 590 RETURN
```

#### FOR

```text
FOR v=start TO limit [STEP s]   begin a counting loop
  The body always runs at least once: the limit is tested at NEXT, not
  at FOR.  So FOR I=1 TO 0 still executes the body one time -- guard with
  IF when an empty range is possible.
  start, limit and s are each evaluated once, on entry; changing the
  variables they came from mid-loop does not move the limit.  STEP
  defaults to 1 and may be negative or fractional.
  Assigning v inside the body does affect the count.  Re-entering an
  already-active FOR on the same variable discards the older frame.
  Example: FOR I=1 TO 5:T=T+I:NEXT I        -> T = 15
  Example: FOR K=10 TO 1 STEP -3:PRINT K;:NEXT  ->  10  7  4  1
```

#### TO

```text
TO   separates FOR's start and limit
  See: man FOR
```

#### STEP

```text
STEP   sets the FOR increment (default 1; 0 loops forever)
  See: man FOR
```

#### NEXT

```text
NEXT [v[,v...]]   close the innermost FOR loop(s)
  Bare NEXT closes the innermost open loop.  Naming the variable is
  clearer and is checked: NEXT J when J is not the innermost open loop
  unwinds the inner frames to reach it.
  One NEXT may close several loops at once, innermost first:
  NEXT J,I is the same as NEXT J followed by NEXT I.
  Example: FOR I=1 TO 2:FOR J=1 TO 3:PRINT I*10+J;:NEXT J,I
             ->  11  12  13  21  22  23
```

#### INPUT

```text
INPUT ["prompt";] var[,var...]   read from the keyboard
  ; keeps the '? '   , drops it.  Bad number => ?REDO FROM START
  The prompt may be a string expression (""+CHR$(10)+"X").
  EXT (needs `ext on` / TRS80_EXT=1): INPUT with no variable at all --
  INPUT"PRESS ENTER"; -- prompts, waits for ENTER, discards the line.
  Example: INPUT "NAME";N$
```

#### READ

```text
READ var[,var...]   assign the next DATA item(s) to variables
  A single pointer walks every DATA statement in the program in line
  order, and it does not reset between READs -- each READ continues from
  where the last one stopped.  RESTORE moves it back.
  Reading a string item into a numeric variable raises ?SN ERROR, and
  the error is reported at the DATA line, not the READ line.
  Running out of items raises ?OD ERROR (out of data).
  Example: FOR I=1 TO 3:READ N$,P:PRINT N$;"=";P:NEXT I
           DATA WIDGET,5,GADGET,12,"BOLT, HEX",3
```

#### DATA

```text
DATA const[,const...]   inline constants for READ to consume
  DATA is never executed -- it is a store of values that READ draws
  from, so it may sit anywhere in the program.  Items are collected in
  line order across every DATA statement.
  Unquoted items are taken literally, with surrounding spaces trimmed.
  Quote an item to keep leading/trailing spaces or to include a comma or
  a colon, which would otherwise end it.
  Example: DATA 1,2,"HELLO"
  Example: DATA "BOLT, HEX",3      (one string item, then a number)
```

#### RESTORE

```text
RESTORE [n]   reset the DATA pointer -- to the first item at or after
  line n when given (Disk BASIC; ?UL if line n does not exist)
  Example: RESTORE 540
```

#### REM

```text
REM text   a comment ('  is shorthand)
  Example: 10 REM INITIALISE
```

#### END

```text
END   stop the program with no message
  Example: 999 END
```

#### STOP

```text
STOP   halt with BREAK IN n; CONT resumes
  Example: STOP
```

#### DIM

```text
DIM name(d[,d...])   declare an array and its bounds
  Subscripts start at 0, so DIM A(20) creates 21 elements A(0)..A(20).
  Arrays may have more than one dimension: DIM B$(5,5) is 6x6 = 36
  string elements.
  Using an array without DIM auto-dimensions it to 10 (0..10) on first
  reference.  DIM after that raises ?DD ERROR (duplicate definition), so
  DIM early -- before the first use, not after.
  Numeric elements start at 0 and string elements at "".
  EXT (needs `ext on` / TRS80_EXT=1): scalar names in the list
  (DIM Z,V,L$) are accepted as declarations and ignored.
  Example: DIM A(20),B$(5,5)
  Example: DIM G(2,2):G(1,2)=5:PRINT G(1,2)    ->  5
```

#### CLS

```text
CLS   clear the screen and home the cursor
  Blanks all 16 rows and leaves the cursor at the top-left, position 0,
  so a following PRINT starts at the upper-left corner.
  Clears only the display -- variables, arrays and the DATA pointer are
  untouched.
  Example: CLS:PRINT@ 540,"CENTRED"
```

#### CLEAR

```text
CLEAR [n]   clear all variables [set string space to n]
  n may be any numeric expression (CLEAR M, CLEAR MEM/2).
  Example: CLEAR 1000
```

#### ON

```text
ON e GOTO n1[,n2...]   branch to the e-th line in the list
ON e GOSUB n1[,n2...]   call the e-th line in the list
  e is rounded down to an integer and counts from 1: ON 2 GOTO a,b picks
  b, and ON 1.9 GOTO a,b picks a.
  If e is 0, or larger than the number of lines listed, nothing happens
  and execution falls through to the next statement -- this is not an
  error, and it is the normal way to handle "none of the above".
  A negative e is ?FC ERROR.
  ON ERROR GOTO n installs an error handler (see: man ERROR, man RESUME).
  Example: ON X GOTO 100,200,300
  Example: ON MENU GOSUB 1000,2000,3000
           PRINT "BAD CHOICE"     (reached when MENU is 0 or > 3)
```

#### POKE

```text
POKE addr,byte   store a byte in memory (0-255)
  Display RAM is 15360..16383.
  Example: POKE 15360,191
```

#### LPRINT

```text
LPRINT list   PRINT to the line printer stream (; , TAB, USING all work)
  The printer is a host stream: set TRS80_PRINTER=path to append printed
  output to that file; unset, output is discarded (no printer attached).
  Example: LPRINT "TOTAL:";TAB(10);T
```

#### LLIST

```text
LLIST [range]   LIST to the line printer stream (see LPRINT)
  Example: LLIST 100-200
```

#### OUT

```text
OUT p,v   Z80 port write -- accepted no-op: both expressions evaluate,
  the write itself does nothing (no port hardware is simulated).
  Example: OUT 255,4
```

#### TAB

```text
TAB(n)   inside PRINT, pad with spaces out to column n
  Columns count from 0, so TAB(10) leaves the next item starting at
  column 10.  It only ever moves the cursor FORWARD: if printing has
  already passed column n, TAB does nothing rather than starting a new
  line.
  Valid only within a PRINT (or LPRINT) list, not as a statement.
  Compare PRINT@, which sets an absolute screen position including the
  row, while TAB works within the current line.
  Example: PRINT TAB(10);"X"
  Example: PRINT A$;TAB(20);B$;TAB(40);C$      (three columns)
```

### Command level

#### RUN

```text
RUN [n]   run the program [starting at line n]
RUN "file"[,R]   load a listing from a host file, then run (Disk BASIC)
  Resets variables/stacks/DATA; does not clear the screen.
  ,R keeps open file channels across the load.
  Example: RUN
```

#### LIST

```text
LIST [n | n- | -n | n-m | .]   list program lines
  . = last-edited line.
  Example: LIST 100-200
```

#### NEW

```text
NEW   erase the program and all variables
  Example: NEW
```

#### CONT

```text
CONT   continue after STOP / BREAK / END
  Not valid after an error or a program edit (?CN).
  Example: CONT
```

#### AUTO

```text
AUTO [n[,inc]]   automatic line numbering (* = exists)
  ENTER keeps a line; BREAK exits.
  Example: AUTO 100,10
```

#### DELETE

```text
DELETE range   remove program lines
  Example: DELETE 100-200
```

#### CLOAD

```text
CLOAD file   NEW then load a plain listing
  CLOAD? file   verify file against memory (prints BAD)
  Quotes optional: an unquoted name runs to end of line, case
  and / . kept.  Example: CLOAD prog.bas   CLOAD "sub/prog.bas"
```

#### CSAVE

```text
CSAVE file   save the program as a plain listing
  Quotes optional (unquoted name runs to end of line).
  Example: CSAVE prog.bas
```

#### LOAD

```text
LOAD "file"[,R]   read a program listing from a host file (Disk BASIC)
  Same reader as CLOAD. ,R runs the program after loading and keeps
  open file channels (flag needs a quoted name); without ,R all
  channels close. Example: LOAD "prog.bas",R
```

#### MERGE

```text
MERGE "file"   read a listing into the CURRENT program (Disk BASIC)
  No implicit NEW: file lines overwrite same-numbered lines and
  interleave with the rest.  Variables clear; a running program stops.
  Example: MERGE "overlay.bas"
```

#### NAME

```text
NAME [n[,[m][,i]]]   renumber the program (Disk BASIC)
  Lines from m onward (default: all) are renumbered starting at n in
  steps of i; n and i both default to 10.
  Every reference is rewritten with them -- GOTO, GOSUB, THEN, ELSE,
  ON..GOTO/GOSUB, RESTORE, RESUME and RUN targets all follow the lines
  they point at.
  What CANNOT be fixed is a line number held in a variable or compared
  against ERL, since those are data rather than references; check any
  ERL test by hand after renumbering.
  ?FC if the new numbering would overlap existing lines or pass 65529.
  Example: NAME                 (renumber everything 10,20,30...)
  Example: NAME 100,,20         (from 100, in steps of 20)
```

#### SAVE

```text
SAVE "file"[,V]   write the program as a plain listing (Disk BASIC)
  Same writer as CSAVE. ,V (cassette verify) is accepted and ignored.
  Example: SAVE "prog.bas"
```

#### BYE

```text
BYE   exit the interpreter (restores your terminal)
  Example: BYE
```

#### TRON

```text
TRON   trace: show <line> as each line runs
  Example: TRON
```

#### TROFF

```text
TROFF   turn line tracing off
  Example: TROFF
```

#### RANDOM

```text
RANDOM   reseed the random number generator
  Without it a program produces the SAME sequence from RND on every run,
  which is ideal while testing and wrong for a game.  Put RANDOM once
  near the start to vary the sequence.
  Conversely, leave it out (or re-seed deliberately) when you want a
  repeatable run.
  See: man RND for the generator and its seed location.
  Example: RANDOM: PRINT RND(6)
```

### Graphics

#### SET

```text
SET(x,y)   light a graphics cell  (x 0-127, y 0-47)
SET(x,y,c)   EXT: also color it (c 0-8, the CoCo Color BASIC palette:
  0 black, 1 green, 2 yellow, 3 blue, 4 red, 5 buff, 6 cyan, 7 magenta,
  8 orange).  Not in LEVEL II -- valid period programs never write the
  third argument.  Color is per character cell, last SET wins; a plain
  SET (or any text printed over the cell) returns it to default B&W.
  POINT(x,y) still returns -1/0 regardless of color: period idioms
  compare =-1, accumulate -1s, and apply NOT, so the return value is
  frozen.  Colors render in grid mode only (not fullscreen/DUMB).
  Example: SET(64,24,4)
```

#### RESET

```text
RESET(x,y)   clear the graphics cell at (x,y)
  The exact inverse of SET, over the same 128x48 grid (x 0-127, y 0-47).
  Clearing a cell that is already clear is harmless, not an error.
  Coordinates outside the grid raise ?FC ERROR.
  Note this is the RESET function, unrelated to any system reset.
  Example: RESET(64,24)
  Example: FOR X=0 TO 127:RESET(X,0):NEXT X    (wipe the top row)
```

#### POINT

```text
POINT(x,y)   -1 if graphics cell (x,y) is lit, 0 if it is clear
  x runs 0-127 across and y runs 0-47 down, the same grid SET and RESET
  use.  The result is a normal truth value, so it can be tested directly
  with IF, and because true is -1 it can also be accumulated: summing
  POINT over a region gives minus the number of lit cells.
  Reading outside the grid raises ?FC ERROR.
  Example: IF POINT(10,10) THEN PRINT "LIT"
  Example: SET(10,10):PRINT POINT(10,10)     -> -1
```

### Error handling

#### ERROR

```text
ERROR n   raise error number n as though it had really happened
  Triggers the ON ERROR handler exactly as a genuine fault would, which
  makes it the way to test a handler without arranging a real failure,
  and the way to signal an application error of your own.
  With no handler installed, it stops the program with that error's
  message, so ERROR 1 reports ?NF ERROR.
  Inside a handler, ERR and ERL report the forced code and the line the
  ERROR statement was on.
  Example: ERROR 6                (raises ?OV, overflow)
```

#### RESUME

```text
RESUME [0 | NEXT | n]   carry on after an ON ERROR handler
  Ends the handler and says where to continue:
    RESUME  or  RESUME 0   retry the statement that failed
    RESUME NEXT            skip it and take the following statement
    RESUME n               jump to line n
  Plain RESUME retries, so use it only after the handler has fixed the
  cause -- otherwise the same error repeats forever.  RESUME NEXT is
  the safe default.
  RESUME outside a handler raises ?RW ERROR.
  Example: RESUME NEXT
  Example: 900 IF ERR/2+1=53 THEN PRINT "NO FILE": RESUME 100
```

#### ERR

```text
ERR   the last error's code, held as (code-1)*2
  The stored value is doubled and offset, so recover the real code with
  ERR/2+1: a division by zero (code 11) leaves ERR as 20.
  Test it inside an ON ERROR handler to tell one failure from another,
  and always convert before comparing.
  Example: PRINT ERR/2+1
  Example: IF ERR/2+1=11 THEN PRINT "DIVIDE BY ZERO": RESUME NEXT
```

#### ERL

```text
ERL   the line number on which the last error happened
  Meaningful inside an ON ERROR handler; 0 when no error has occurred.
  Lets one handler treat failures differently by where they came from:
  IF ERL=250 THEN ...
  Note that RENUMBER/NAME cannot rewrite a number compared against ERL,
  so an ERL test silently goes stale if the program is renumbered --
  prefer testing ERR where you can.
  Example: PRINT "FAILED AT";ERL
```

### Types and definitions

#### DEFINT DEFSNG DEFDBL DEFSTR

```text
DEFINT a[-z]   declare that variables starting with those letters are
DEFSNG / DEFDBL / DEFSTR      integer / single / double / string
  Applies to bare names in the given letter range, so DEFINT I-N makes
  I, J2 and COUNT integer without needing a suffix.
  IMPORTANT in this interpreter: DEFSTR is honored -- a name in its
  range really is a string everywhere (assignment, arrays, INPUT, READ,
  FOR, file I/O), and storing a number into one raises ?TM.
  DEFINT, DEFSNG and DEFDBL are accepted and clear the DEFSTR flag for
  their range, but the numeric precision distinction is NOT enforced:
  every number is held in one type, so DEFINT A does not truncate A.
  The %, ! and # suffixes are likewise accepted and stripped.
  Example: DEFINT I-N
  Example: DEFSTR S: S="TEXT"          (S=1 would be ?TM)
```

#### VARPTR

```text
VARPTR(var)   address of a variable's storage
  String: a live 3-byte descriptor [len][addr lo][addr hi]; the bytes
  at that address PEEK and POKE through to the value (string packing).
  Numeric: address of the value's 4 Microsoft-single bytes, also live.
  Example: D=VARPTR(A$):M=PEEK(D+1)+256*PEEK(D+2):POKE M,191

PEEK(addr)   read a memory byte (unset = 255)
  Display memory 15360-16383 reads the screen.  14336-14591 reads the
  live KEYBOARD MATRIX (row r at 14336+2^r; 14400 = arrows/space/ENTER
  row; 14464 = SHIFT; composite addresses OR rows) synthesized from the
  terminal -- a tapped key reads pressed for a few polls, a held key
  rides auto-repeat.  14312 reads printer status 63 (attached, ready).
  Example: PRINT PEEK(15360)
  Example: IF PEEK(14400) AND 32 THEN X=X-1   ' left arrow held
```

#### USR DEFUSR

```text
USR(x) / USRn(x)   machine-language call STUB: evaluates and returns
  its argument x -- no Z80 routine runs.  Programs whose USR result is
  decorative keep running; result-dependent ones fail visibly.
DEF USR[n] = addr / DEFUSRn = addr   accepted no-op: the address
  expression evaluates (?TM if string) and is discarded.
  Example: DEFUSR=&H7D00 : X=USR(0)
```

#### FN DEFFN

```text
DEF FN name(p,...) = expr   define a user function (Disk BASIC tier).
  Spaced (DEF FN AB), glued (DEF FNAB) and DEFFNAB spellings all work;
  parameterless DEF FNR=expr too.  String functions by name suffix ($)
  or DEFSTR.  Parameters shadow the like-named globals during the call
  and are restored after (recursion nests; runaway recursion ?OM).
  Definitions are wiped by RUN/NEW/CLEAR; ?ID in immediate mode.
FNname(args) / FN name(args)   call it.  An FN-prefixed identifier with
  no matching DEF stays an ordinary variable or array.
  Example: DEF FNSQ(X)=X*X : PRINT FNSQ(7)
```

### Files

#### OPEN

```text
OPEN mode$, [#]n, name$ [,reclen]   open a file on channel n (1-15)
  mode$ picks how the file is used, and it cannot be changed later:
    "I"  input    -- read an existing file from the start
    "O"  output   -- create, or TRUNCATE an existing file to nothing
    "E"  extend   -- append; writes go after what is already there
    "R"  random   -- fixed-length records, read and written by number
  "O" destroys the old contents the moment the file opens, so use "E"
  when adding to a log and "I" when only reading.
  name$ is a host file path.  reclen applies to "R" only (1-256,
  default 256) and must match what the file was written with.
  A channel stays busy until CLOSE; re-opening a busy channel is ?FO.
  A name starting with OLLAMA opens an AI link (see: man OLLAMA).
  Example: OPEN "O",1,"DATA.TXT"
  Example: OPEN "R",2,"REC.DAT",32
```

#### CLOSE

```text
CLOSE [[#]n, ...]   close channels; with no arguments, closes them all
  Closing flushes buffered output -- data written but not yet closed can
  be lost if the program stops first, so close every file you write.
  Closing a channel that was never opened is harmless, not an error.
  END and NEW close everything; a program that stops on an error does
  not, which is why a handler should CLOSE before it gives up.
  Example: CLOSE 1
  Example: CLOSE          (all channels)
```

#### KILL

```text
KILL name$   delete a file from the host disk
  The file must not be open -- CLOSE it first, or ?FO.  There is no
  confirmation and no recovery.
  Deleting a file that does not exist raises ?FE (file not found), so
  guard it when the file may legitimately be absent.
  Example: KILL "DATA.TXT"
  Example: CLOSE 1: KILL "SCRATCH.TMP"
```

#### PRINT#

```text
PRINT #n, items   write text to a sequential file opened "O" or "E"
  Writes the same characters PRINT would put on the screen, so numbers
  carry PRINT's leading sign-space AND its trailing space: PRINT #1,10
  stores " 10 ", not "10".
  Here ; and , are plain separators with no zone padding, because zone
  spaces would corrupt comma-delimited data on the way back in.
  Write the separators you want to read back -- usually a literal comma
  between items -- and end each record with a newline by leaving the
  last separator off.  A trailing ; holds the line open.
  Example: PRINT #1, A$; ","; B$
  Example: PRINT #1, N$;",";MID$(STR$(V),2)     (no stray spaces)
```

#### INPUT#

```text
INPUT #n, vars   read comma-separated items from a file opened "I"
  Splits on commas the way INPUT does at the keyboard, so it undoes a
  PRINT# that wrote commas between items.  Quotes are respected, and a
  quoted item may contain commas.
  Leading spaces are skipped for numbers, so the space PRINT# leaves in
  front of a number is harmless on the way back.
  A line with fewer items than variables carries on into the next line.
  Reading past the end raises ?IE -- test EOF first.
  Use LINE INPUT #n instead to take a whole line, commas included.
  Example: INPUT #1, A$, N
```

#### LINE

```text
LINE INPUT ["prompt";] v$    read a whole keyboard line (no "? ")
LINE INPUT #n, v$            read a whole line from an "I" file
  No comma splitting.  Example: LINE INPUT #1, L$
```

#### FIELD

```text
FIELD [#]n, w AS v$ [, w AS v$...]   name slices of a random record
  Divides the record buffer of an "R" file into fixed-width string
  variables.  The widths must not exceed the record length, or ?FO.
  These variables are windows onto the buffer, not ordinary strings:
  GET refills them, and only LSET/RSET store into them.  Assigning with
  = detaches the name from the buffer and the link is lost.
  Numbers must be packed to a fixed width first (see: man MKI$).
  FIELD may be issued again to re-map the same buffer differently.
  Example: FIELD 1, 10 AS N$, 2 AS I$
  Example: FIELD 1, 10 AS N$, 2 AS I$: GET 1,1: PRINT N$;CVI(I$)
```

#### GET

```text
GET [#]n [,rec]   read a record from a random file into the buffer
  Loads record number rec (the first is 1); with rec omitted, reads the
  record after the last one touched.  Every FIELD variable on that
  channel updates at once -- there is no separate assignment step.
  Reading past the end gives a record of spaces rather than an error, so
  check LOF before trusting what comes back.
  Example: GET 1, 5
  Example: FOR R=1 TO LOF(1): GET 1,R: PRINT N$: NEXT R
```

#### PUT

```text
PUT [#]n [,rec]   write the buffer out as a record of a random file
  Writes whatever the FIELD variables currently hold to record rec (the
  first is 1); with rec omitted, writes the record after the last one
  touched.
  Writing past the end extends the file, so PUT 1,50 on a 2-record file
  makes it 50 records, with the gap filled by empty records.
  Set every field before PUT -- a field left over from an earlier record
  is written again as-is.
  Example: LSET N$="BOB": LSET I$=MKI$(42): PUT 1,1
```

#### LSET RSET

```text
LSET v$=x$   store left-justified  /  RSET v$=x$   store right-justified
  The normal way to put data into a FIELD variable.  The slice keeps its
  width: a shorter value is padded with spaces, a longer one is cut.
  LSET pads on the right, RSET pads on the left -- RSET is what lines
  numbers up in a column.
  On an ordinary (non-fielded) string, both justify within the string's
  existing length rather than changing it.
  Example: LSET N$="BOB"        -> "BOB       "  (10-wide field)
  Example: RSET N$="X"          -> "         X"
  Example: LSET I$=MKI$(42)
```

#### EOF

```text
EOF(n)   -1 when channel n has reached the end of the data, else 0
  The normal way to read a sequential file of unknown length: test
  before each read, not after, or the last read raises ?IE.
  Applies to files opened "I".  The value is a proper truth value, so
  IF EOF(1) THEN ... works directly.
  Example: IF EOF(1) THEN 100
  Example: 10 IF EOF(1) THEN 40
           20 LINE INPUT #1,L$: PRINT L$
           30 GOTO 10
```

#### LOF

```text
LOF(n)   the number of records in the random file on channel n
  Gives the size in records, so it is the right bound for a loop over
  the whole file, and the way to find the end before appending: the
  next free record is LOF(n)+1.
  A file just created with "R" reports 0 until the first PUT.
  Example: FOR R=1 TO LOF(1): GET 1,R: NEXT R
  Example: PUT 1, LOF(1)+1        (append one record)
```

#### LOC

```text
LOC(n)   how far into channel n the file position has got
  For a sequential file, the number of lines read or written so far.
  For a random file, the number of the record last read or written by
  GET or PUT -- which is what a following bare GET or PUT continues
  from.
  Example: PRINT LOC(1)
  Example: GET 1,7: PRINT LOC(1)      ->  7
```

#### MKI$ MKS$ MKD$

```text
MKI$(i) MKS$(x) MKD$(x)   pack a number into 2, 4 or 8 bytes
  A FIELD slice holds only characters, so numbers must be packed to a
  fixed width before LSET can store them.  MKI$ takes an integer
  (-32768..32767), MKS$ a single-precision value, MKD$ a double.
  The result is binary, not readable digits: do not PRINT it or use LEN
  on it expecting a digit count.  Unpack with CVI/CVS/CVD.
  Choose the width you can afford: 2 bytes for a count, 8 only when the
  extra precision is really needed.
  Example: LSET I$=MKI$(42)
  Example: FIELD 1,4 AS P$: LSET P$=MKS$(19.95): PUT 1,1
```

#### CVI CVS CVD

```text
CVI(s$) CVS(s$) CVD(s$)   unpack 2, 4 or 8 packed bytes into a number
  The inverse of MKI$/MKS$/MKD$, used on a FIELD variable after GET.
  The function must match the one that packed the value: reading an
  MKS$ field with CVI gives nonsense rather than an error, since the
  bytes are equally valid either way.
  A string shorter than the width raises ?FC.
  Example: GET 1,1: PRINT CVI(I$)
  Example: PRINT CVS(P$)      (a field packed with MKS$)
```

### The OLLAMA channel

#### OLLAMA

```text
OPEN m$,n,"OLLAMA[:model[:thread]]"   chat with a local LLM
  PRINT #n builds the prompt; the next LINE INPUT #n sends it
  (blocking) and reads the reply line by line until EOF(n).
  Named threads persist to <thread>.ollama and reload as context;
  KILL that file to reset.  LOC(n)=messages.  Env: TRS80_OLLAMA_MODEL.
  Directive lines (PRINT #n "@...") steer the channel, never the model:
    @TOKENS A,B     next send: reply line 1 is one of A,B (enforced by
                    Ollama structured output), the rest is the prose
    @THINK 0        sticky: no hidden reasoning (thinking models)
    @KEEPALIVE 30m  sticky: keep the model loaded between calls
    @@text          a literal line starting with "@"
  Example: OPEN "O",1,"OLLAMA:llama3.2:story"
```

### Numeric functions

#### &H &O

```text
&Hnnnn   hexadecimal constant    /    &Onnn   octal constant
  Write a number in base 16 or base 8 instead of decimal, which is much
  easier to read for addresses and bit masks.  &H1F is 31, &O17 is 15.
  Usable anywhere a number is: POKE &H3C00,42 addresses the screen.
  These are input notations only -- PRINT always shows decimal, so
  PRINT &HFF gives 255.  There is no built-in hex output; build it
  yourself if you need it.
  Example: PRINT &H1F;&HFF;&O17        ->  31  255  15
```

#### ABS

```text
ABS(x)   the absolute value of x -- its size without the sign
  ABS(-5) and ABS(5) are both 5; ABS(0) is 0.
  Common uses: distance between two values, ABS(A-B); and comparing
  floating-point numbers for near-equality, IF ABS(A-B)<.001 THEN ...,
  which is safer than testing A=B on computed values.
  Example: PRINT ABS(-5)        ->  5
  Example: IF ABS(X-T)<.5 THEN PRINT "CLOSE ENOUGH"
```

#### INT

```text
INT(x)   the greatest integer less than or equal to x
  Rounds DOWN, toward minus infinity -- it does not truncate toward zero.
  For positive x the two look the same, but they differ for negatives:
  INT(3.7) is 3, and INT(-3.2) is -4, not -3.
  To truncate toward zero instead, use SGN(x)*INT(ABS(x)).
  To round to nearest, add 0.5 first: INT(x+.5).
  Example: PRINT INT(3.7);INT(-3.2)    ->  3 -4
  Example: PRINT INT(2.5+.5)           ->  3   (rounded to nearest)
```

#### FIX

```text
FIX(x)   x with its fractional part removed -- truncates toward zero
  Differs from INT on negatives, and that is the whole point of having
  both: FIX(-3.7) is -3, while INT(-3.7) is -4.
  Use FIX to drop a fraction and INT when you want a true floor.
  Example: PRINT FIX(3.7);FIX(-3.7)     ->  3 -3
  Example: PRINT INT(-3.7)              -> -4   (compare)
```

#### SGN

```text
SGN(x)   the sign of x: -1 if negative, 0 if zero, 1 if positive
  Reports only direction, never magnitude, so SGN(-9) and SGN(-.001)
  are both -1.
  Pairs with ABS to split a value into sign and size: x = SGN(x)*ABS(x).
  Handy for stepping toward a target by one unit: X=X+SGN(T-X).
  Example: PRINT SGN(-9)         -> -1
  Example: DX=SGN(TX-X):DY=SGN(TY-Y)     (chase one step)
```

#### SQR

```text
SQR(x)   the square root of x
  x must not be negative, or ?FC ERROR -- test first when the value is
  computed (IF D<0 THEN ... before SQR(D)).
  For other roots use the ^ operator: a cube root is X^(1/3).
  Example: PRINT SQR(16)        ->  4
  Example: H=SQR(A*A+B*B)       (hypotenuse)
```

#### SIN

```text
SIN(x)   the sine of x, with x in RADIANS
  Angles are radians, not degrees -- convert with X*.0174533 (that is
  PI/180) when working from degrees.
  PI is not built in; the usual source is ATN(1)*4.
  Example: PRINT SIN(0)                  ->  0
  Example: P=ATN(1)*4: PRINT SIN(P/2)    ->  1
```

#### COS

```text
COS(x)   the cosine of x, with x in RADIANS
  As with SIN, the angle is in radians; multiply degrees by .0174533.
  SIN and COS together step around a circle, which is the usual way to
  plot one on the graphics grid.
  Example: PRINT COS(0)         ->  1
  Example: FOR A=0 TO 6.28 STEP .1: SET(64+30*COS(A),24+20*SIN(A)): NEXT A
```

#### TAN

```text
TAN(x)   the tangent of x, with x in RADIANS
  Grows without limit near PI/2 and its odd multiples, where the true
  value is undefined -- expect a very large number or ?OV there rather
  than a clean error, so avoid feeding it an unchecked angle.
  Example: PRINT TAN(0)         ->  0
```

#### ATN

```text
ATN(x)   the arctangent of x, in RADIANS, between -PI/2 and PI/2
  The inverse of TAN.  Its best-known use is supplying PI, which the
  language does not provide: ATN(1) is PI/4, so ATN(1)*4 is PI.
  Because the result is limited to half a turn, ATN alone cannot tell
  which quadrant a point is in; check the signs of x and y yourself.
  Example: PRINT ATN(1)*4       ->  3.14159
  Example: P=ATN(1)*4           (the usual way to get PI)
```

#### LOG

```text
LOG(x)   the NATURAL logarithm of x -- base e, not base 10
  x must be greater than 0, or ?FC ERROR.
  For base 10, divide by LOG(10); for any base b, LOG(x)/LOG(b).
  EXP is the inverse.
  Example: PRINT LOG(1)                  ->  0
  Example: PRINT LOG(1000)/LOG(10)       ->  3   (base-10 log)
```

#### EXP

```text
EXP(x)   e raised to the power x -- the inverse of LOG
  EXP(1) is e itself, about 2.71828.
  Large x overflows (?OV); very negative x underflows quietly to 0.
  Example: PRINT EXP(0)         ->  1
  Example: PRINT EXP(1)         ->  2.71828
```

#### RND

```text
RND(n)   n>0: integer 1..n;  RND(0): float 0<=r<1
  The authentic ROM 24-bit LCG; the seed lives at 16554-16556 and is
  PEEK/POKEable.  RND(1) is always 1.  RND(neg) is ?FC.  RANDOM reseeds.
  Example: PRINT RND(6)
```

#### CINT

```text
CINT(x)   x rounded to the NEAREST whole number
  Unlike INT (which floors) and FIX (which truncates), CINT rounds:
  CINT(3.7) is 4, CINT(3.2) is 3, and CINT(-3.7) is -4.
  On hardware the result must fit the integer range (-32768..32767) or
  ?FC; here the range is not enforced.
  Example: PRINT CINT(3.7);CINT(3.2);CINT(-3.7)   ->  4  3 -4
```

#### CSNG

```text
CSNG(x)   convert x to single precision
  Accepted and returns its argument's value.  Note this interpreter
  holds every number in one numeric type, so CSNG does not actually
  reduce precision the way it would on hardware -- it is here so that
  period listings using it run unchanged.
  See: man DEFINT for the same caveat on the DEF type statements.
  Example: PRINT CSNG(1/3)
```

#### CDBL

```text
CDBL(x)   convert x to double precision
  Accepted and returns its argument's value.  As with CSNG, this
  interpreter keeps all numbers in a single numeric type, so CDBL does
  not widen anything -- a value is no more precise after it than before.
  Provided so that period listings using it run unchanged.
  Example: PRINT CDBL(1/3)
```

### String functions

#### INSTR

```text
INSTR([n,]a$,b$)   position of b$ inside a$, 0 if absent (Disk BASIC)
  Search starts at n (default 1; range 1..255 else FC error).
  INSTR(n,a$,"") returns n; n past LEN(a$) returns 0.
  Example: PRINT INSTR("HELLO","LL")   prints 3
```

#### LEN

```text
LEN(a$)   how many characters a$ contains
  Counts characters, including spaces; the empty string gives 0.
  Commonly used to test for empty input (IF LEN(N$)=0) and to drive a
  loop over each character with MID$.
  Example: PRINT LEN("HI")     ->  2
  Example: FOR I=1 TO LEN(A$):PRINT MID$(A$,I,1);:NEXT I
```

#### ASC

```text
ASC(a$)   the character code of the first character of a$
  Only the first character is examined; the rest is ignored, so
  ASC("ABC") is 65.  An empty string raises ?FC ERROR -- guard with
  IF LEN(A$) when the source could be empty (INKEY$ often is).
  CHR$ is the inverse.
  Example: PRINT ASC("A")              -> 65
  Example: K$=INKEY$:IF K$<>"" THEN P=ASC(K$)
```

#### VAL

```text
VAL(a$)   the number at the front of a$, or 0 if there is none
  Reads as much of the string as looks like a number and stops at the
  first character that does not fit, so VAL("12.5X") is 12.5.  Leading
  spaces are skipped, a leading sign is honoured, and exponent notation
  is understood: VAL("-3E2") is -300.
  A string that does not begin with a number gives 0 rather than an
  error, so VAL cannot by itself tell "0" from "OFF" -- test the string
  first if that difference matters.
  STR$ is the inverse.
  Example: PRINT VAL("12.5X")   -> 12.5
  Example: PRINT VAL("ABC")     ->  0
```

#### CHR$

```text
CHR$(n)   one-character string for code n
  Control codes on PRINT: 8 bs, 13 newline, 21 toggle Model III special
  characters for 192-255, 22 pick special/Katakana set, 23 shift to 32
  chars per line (CLS returns to 64), 24-31 cursor/erase.
  Example: PRINT CHR$(65)   -> A
```

#### STR$

```text
STR$(x)   the string form of number x, as PRINT would show it
  Includes the leading space PRINT puts in front of a positive number,
  so STR$(12) is " 12" (three characters) while STR$(-12) is "-12".
  Strip it with MID$(STR$(X),2) when concatenating.
  VAL is the inverse.
  Example: PRINT "[";STR$(12);"]"        -> [ 12]
  Example: PRINT "N="+MID$(STR$(12),2)   -> N=12
```

#### STRING$

```text
STRING$(n,c)   a string of n copies of one character
  c may be a one-character string or a character code, so STRING$(5,"*")
  and STRING$(5,42) give the same result.  If a longer string is passed,
  only its first character is used.
  Useful for rules, bar charts and clearing a field to spaces.
  Example: PRINT STRING$(5,"*")     -> *****
  Example: PRINT STRING$(3,65)      -> AAA
  Example: PRINT STRING$(64,"-")    (a full-width rule)
```

#### LEFT$

```text
LEFT$(a$,n)   the leftmost n characters of a$
  Asking for more than the string holds returns the whole string rather
  than raising an error, so LEFT$("AB",99) is "AB".  n=0 gives "".
  Pairs with RIGHT$ and MID$; LEFT$(A$,N) is the same as MID$(A$,1,N).
  Example: PRINT LEFT$("ABCDE",2)       -> AB
  Example: IF LEFT$(A$,1)="Y" THEN ...  (test the first character)
```

#### RIGHT$

```text
RIGHT$(a$,n)   the rightmost n characters of a$
  Counts from the END of the string, so RIGHT$("ABCDE",2) is "DE".
  Asking for more than the string holds returns all of it; n=0 gives "".
  Handy for file extensions and for the last digits of a padded number.
  Example: PRINT RIGHT$("ABCDE",2)      -> DE
  Example: IF RIGHT$(F$,4)=".BAS" THEN ...
```

#### MID$

```text
MID$(a$,p[,n])   substring from position p (n chars)
MID$(v$,p[,n])=e$   statement: replace in place (Disk BASIC).  The
  target's length never changes; the replacement is truncated to n and
  to what fits.  p past the end raises ?FC.
  Example: PRINT MID$("HELLO",2,3) -> ELL
  Example: A$="HELLO": MID$(A$,2,3)="XYZZY" -> A$="HXYZO"
```

### System and screen

#### TIME$

```text
TIME$   current date and time as "MM/DD/YY HH:MM:SS" (Disk BASIC)
  Read-only, 17 characters, from the host clock.
  Example: PRINT TIME$
```

#### POS

```text
POS(n)   the column the cursor is currently on, counting from 0
  The argument is required but ignored; POS(0) is the conventional form.
  Useful for deciding whether the next item still fits on the line, and
  for lining columns up after items of unknown width.
  Example: PRINT "AB";POS(0)            -> AB 2
  Example: IF POS(0)>50 THEN PRINT      (wrap before the edge)
```

#### FRE

```text
FRE(x)   free space; FRE("") reports free STRING space
  The argument decides which pool is reported: a numeric argument asks
  about general free memory, and a string argument (conventionally "")
  asks about the string pool.
  On hardware, calling FRE("") also forces a garbage collection of
  discarded strings, which is why period programs call it when string
  handling has slowed down.
  Example: PRINT FRE("")
  Example: PRINT FRE(0)
```

#### MEM

```text
MEM   the number of bytes of program and variable space still free
  Reported as a single number; it falls as variables, arrays and strings
  are created and rises after CLEAR or NEW.
  Chiefly a period diagnostic -- listings print it to prove a program
  fits.  Because this interpreter does not use the ROM's memory layout,
  treat the figure as indicative rather than an exact hardware count.
  Example: PRINT MEM
```

#### INKEY$

```text
INKEY$   the key being pressed right now, or "" if none
  Returns at once without waiting, and does not echo the character or
  need ENTER -- unlike INPUT, which blocks until a line is entered.  A
  keypress is consumed by the read, so store it before testing it.
  To wait for a key, loop until it is non-empty:
    10 K$=INKEY$:IF K$="" THEN 10
  To poll without stopping (so animation or a clock keeps running), test
  once per pass through the main loop and carry on when it is "".
  Example: K$=INKEY$:IF K$="Q" THEN END
```

<!-- END GENERATED REFERENCE -->
