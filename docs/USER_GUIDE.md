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
**EXT** — 1978 gave you SHIFT-left-arrow and resignation.

### Metacommands (EXT)

A small set of immediate commands that are *not* BASIC keywords. They are
**strictly lowercase** — `dir` is a metacommand, `DIR` reaches BASIC and
raises `?SN ERROR`. That case split is what keeps the two namespaces from
ever colliding with a period program.

| command | does |
|---|---|
| `dir [args]` | `ls -al` passthrough, run where the interpreter started; arguments, globs, `~`, even pipes behave as at a shell prompt |
| `cat <file...>` | show file contents (non-text bytes as `.`) |
| `man <KEYWORD>` | syntax + example for any BASIC word (`man PRINT`, `man MID$`) |
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
any editor and diffable in git. `LOAD`/`SAVE` do the same, and `RUN "file"` loads and runs.
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
`ON ERROR GOTO` with `ERR`/`ERL`/`RESUME`, `READ`/`DATA`/`RESTORE n`,
`&H`/`&O` literals, `INSTR`, `TIME$`, the `MID$` statement, and so on. If
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
PRINT [items]   display values
  ;=no gap  ,=next 16-col zone  @n=position  TAB(n)
  Example: PRINT "SUM=";A+B , "OK"
  PRINT USING f$; items   formatted output (see: man USING)
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
IF cond THEN stmt|n [ELSE stmt|n]   conditional
  Also: IF cond GOTO n
  Example: IF A>0 THEN PRINT"POS" ELSE PRINT"NEG"
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
GOSUB n   call the subroutine at line n (RETURN comes back)
  Example: GOSUB 500
```

#### RETURN

```text
RETURN   return from the most recent GOSUB
  Example: 590 RETURN
```

#### FOR

```text
FOR v=a TO b [STEP s]   begin a counting loop
  Body runs at least once; test is at NEXT.
  Example: FOR I=1 TO 10 STEP 2
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
  Example: NEXT I    or    NEXT J,I
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
READ var[,var...]   take the next DATA item(s)
  Example: READ A,B,N$
```

#### DATA

```text
DATA const[,const...]   inline constants for READ
  Quoted strings may contain , and :
  Example: DATA 1,2,"HELLO"
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
DIM name(d[,d...])   declare an array (auto-dim is 10)
  EXT (needs `ext on` / TRS80_EXT=1): scalar names in the list
  (DIM Z,V,L$) are accepted as declarations and ignored.
  Example: DIM A(20),B$(5,5)
```

#### CLS

```text
CLS   clear the screen
  Example: CLS
```

#### CLEAR

```text
CLEAR [n]   clear all variables [set string space to n]
  n may be any numeric expression (CLEAR M, CLEAR MEM/2).
  Example: CLEAR 1000
```

#### ON

```text
ON e GOTO n1,n2,...   branch to the e-th line (also GOSUB)
  ON ERROR GOTO n   install an error handler
  Example: ON X GOTO 100,200,300
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
TAB(n)   inside PRINT, advance to column n
  Example: PRINT TAB(10);"X"
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
  Lines >= m (default all) become n, n+i, ... (defaults 10,10); every
  GOTO/GOSUB/THEN/ELSE/ON../RESTORE/RESUME/RUN target is rewritten.
  ERL comparisons cannot be fixed.  ?FC on overlap or past 65529.
  Example: NAME 100,,20
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
RANDOM   reseed the random-number generator
  Rewrites only the middle byte of the ROM seed (16555), like the real
  ROM's R-register read.  Example: RANDOM
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
RESET(x,y)   clear a graphics cell
  Example: RESET(64,24)
```

#### POINT

```text
POINT(x,y)   -1 if graphics cell (x,y) is set, else 0
  Example: IF POINT(10,10) THEN ...
```

### Error handling

#### ERROR

```text
ERROR n   force error code n (for testing ON ERROR)
  Example: ERROR 1
```

#### RESUME

```text
RESUME [0 | NEXT | n]   return from an ON ERROR handler
  0/none=retry, NEXT=next stmt, n=goto line n
  Example: RESUME NEXT
```

#### ERR

```text
ERR   (code-1)*2 for the last error; ERR/2+1 = the code
  Example: PRINT ERR/2+1
```

#### ERL

```text
ERL   line number where the last error happened
  Example: PRINT ERL
```

### Types and definitions

#### DEFINT DEFSNG DEFDBL DEFSTR

```text
DEFINT/DEFSNG/DEFDBL/DEFSTR letters   accepted and IGNORED
  All numbers are doubles here.  Example: DEFINT A-Z
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
OPEN mode$, [#]n, name$ [,reclen]   open file on channel n (1-15)
  mode: "I"=input "O"=output(truncate) "E"=append "R"=random access
  name$ is a host file path.  reclen (R only) 1-256, default 256.
  A name starting with OLLAMA opens an AI link (see man OLLAMA).
  Example: OPEN "O",1,"DATA.TXT"     OPEN "R",2,"REC.DAT",32
```

#### CLOSE

```text
CLOSE [[#]n, ...]   close channel(s); no args = close ALL
  Flushes pending output; closing an unopened channel is a no-op.
  Example: CLOSE 1     CLOSE
```

#### KILL

```text
KILL name$   delete a host file (must not be open)
  Example: KILL "DATA.TXT"
```

#### PRINT#

```text
PRINT #n, items   write text to a sequential "O"/"E" file
  ; and , are plain separators (no zone padding); trailing ;
  holds the partial line.  Example: PRINT #1, A$; ","; B$
```

#### INPUT#

```text
INPUT #n, vars   read comma-separated items from an "I" file
  Quotes respected; a part-read line carries to the next INPUT#.
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
FIELD [#]n, w AS v$ [, w AS v$...]   map buffer slices of an "R" file
  Widths must fit the record length (else ?FO).  Use LSET/RSET to
  store, GET/PUT to move records.  Example: FIELD 1, 10 AS N$, 2 AS I$
```

#### GET

```text
GET [#]n [,rec]   read record rec (default: next) into the buffer
  Fielded variables update.  Example: GET 1, 5
```

#### PUT

```text
PUT [#]n [,rec]   write the buffer to record rec (default: next)
  Extends the file if rec is past the end.  Example: PUT 1
```

#### LSET RSET

```text
LSET v$=x$  left-justify  /  RSET v$=x$  right-justify
  Into a fielded buffer slice (pad with spaces / truncate); on a
  plain string var, justifies within its current length.
  Example: LSET N$="BOB"     RSET I$=MKI$(42)

# ================================= functions ===============================
```

#### EOF

```text
EOF(n)   -1 if file channel n is at end of data, else 0
  Example: IF EOF(1) THEN 100
```

#### LOF

```text
LOF(n)   number of records in the random ("R") file on channel n
  Example: FOR R=1 TO LOF(1): GET 1,R: NEXT
```

#### LOC

```text
LOC(n)   lines read/written (sequential) or last record (random)
  Example: PRINT LOC(1)
```

#### MKI$ MKS$ MKD$

```text
MKI$(i) MKS$(x) MKD$(x)   pack a number into 2/4/8 bytes for LSET
  into a fielded buffer (Microsoft Binary Format).
  Example: LSET I$=MKI$(42)
```

#### CVI CVS CVD

```text
CVI(s$) CVS(s$) CVD(s$)   unpack 2/4/8 packed bytes back to a number
  Inverse of MKI$/MKS$/MKD$.  Example: PRINT CVI(I$)
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
&Hxxxx / &Oxxxxxx   hex / octal integer literals (Disk BASIC)
  16-bit two's complement: &HFFFF = -1, &H8000 = -32768. More than
  16 bits raises ?OV. Lowercase &h/&o accepted.
  Example: PRINT &H1F;&O17
```

#### ABS

```text
ABS(x)   absolute value
  Example: PRINT ABS(-5)   -> 5
```

#### INT

```text
INT(x)   greatest integer <= x
  Example: PRINT INT(3.7)   -> 3
```

#### FIX

```text
FIX(x)   truncate toward zero
  Example: PRINT FIX(-3.7)  -> -3
```

#### SGN

```text
SGN(x)   sign: -1, 0, or 1
  Example: PRINT SGN(-9)    -> -1
```

#### SQR

```text
SQR(x)   square root  (x>=0)
  Example: PRINT SQR(9)     -> 3
```

#### SIN

```text
SIN(x)   sine of x radians
  Example: PRINT SIN(0)     -> 0
```

#### COS

```text
COS(x)   cosine of x radians
  Example: PRINT COS(0)     -> 1
```

#### TAN

```text
TAN(x)   tangent of x radians
  Example: PRINT TAN(0)     -> 0
```

#### ATN

```text
ATN(x)   arctangent, in radians
  Example: PRINT ATN(1)*4   -> ~3.14159
```

#### LOG

```text
LOG(x)   natural logarithm  (x>0)
  Example: PRINT LOG(EXP(1)) -> 1
```

#### EXP

```text
EXP(x)   e raised to the x
  Example: PRINT EXP(0)     -> 1
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
CINT(x)   round to the nearest integer
  Example: PRINT CINT(3.5)  -> 4
```

#### CSNG

```text
CSNG(x)   single-precision convert (no-op here)
  Example: PRINT CSNG(1/3)
```

#### CDBL

```text
CDBL(x)   double-precision convert (no-op here)
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
LEN(a$)   number of characters in a$
  Example: PRINT LEN("HI")   -> 2
```

#### ASC

```text
ASC(a$)   code of the first character
  Example: PRINT ASC("A")    -> 65
```

#### VAL

```text
VAL(a$)   leading numeric value of a$
  Example: PRINT VAL("12.5X") -> 12.5
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
STR$(x)   string form of a number (leading sign space)
  Example: PRINT STR$(12)
```

#### STRING$

```text
STRING$(n,c)   n copies of a character
  c is a code or a 1-char string.
  Example: PRINT STRING$(5,"*")  -> *****
```

#### LEFT$

```text
LEFT$(a$,n)   the leftmost n characters
  Example: PRINT LEFT$("HELLO",2) -> HE
```

#### RIGHT$

```text
RIGHT$(a$,n)   the rightmost n characters
  Example: PRINT RIGHT$("HELLO",2) -> LO
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
POS(0)   current print column (0-based)
  Example: PRINT POS(0)
```

#### FRE

```text
FRE(0)   free string space in bytes
  Example: PRINT FRE(0)
```

#### MEM

```text
MEM   free program memory in bytes
  Example: PRINT MEM
```

#### INKEY$

```text
INKEY$   one waiting keypress, or "" if none (no wait)
  Example: K$=INKEY$
```

<!-- END GENERATED REFERENCE -->
