# The USR coprocess protocol, version 1

How `trs80basic` (the interpreter, GNU awk) drives `trs80_z80_core` (the Z80
engine, Python) to execute a `USR` routine.  The interpreter's side is
`src/p77_z80.awk`; the reference implementation of the core's side is
`programs/tests/z80_stub.py`, a stub that speaks this protocol and behaves
in canned ways per entry address.  **The core conforms to this document and
passes `programs/tests/z80.sh` with `TRS80_Z80` pointing at it; the shim does
not adapt to the core.**  This file is mirrored into the core repository;
the two copies must be identical.

Ratified shape (2026-09-02/04, rulings 2026-09-11): a companion engine,
never vendored; one persistent gawk `|&` coprocess per session; a frame of
memory out, a write-set back; the keyboard as the only live callback; video
streamed during the call; graceful fallback to the argument-returning stub
when there is no core.

## Transport

*   The interpreter runs the command in `TRS80_Z80` as a coprocess (`|&`).
    If `TRS80_Z80` is unset the core is absent and `USR` is the stub.
*   Text, one message per line, `\n`-terminated, ASCII.  **Both sides flush
    after every line** -- an unflushed line deadlocks the other side.
*   Every message is `KEYWORD [args]`.  Header arguments are `key=value`
    pairs separated by single spaces, in the order given below; a reader
    may parse them by key.  Byte runs are `addr:b,b,b` -- a decimal start
    address and decimal bytes 0-255 at consecutive addresses.
*   The interpreter waits at most `TRS80_Z80_TIMEOUT` milliseconds (default
    5000) for each line from the core.  A timeout marks the core dead for
    the rest of the session, raises `?FC` at the `USR` call, and later
    calls use the stub.  A core that runs a long routine keeps the
    interpreter alive with `T` ticks.
*   A core that has exited is met the same way, whether the interpreter
    finds out on a read or on a write (a core that died between calls is
    found on the next `CALL`): dead for the rest of the session, `?FC` at
    that `USR` call, the stub afterwards.

## Session

```
interpreter -> core   HELLO proto=1 mhz=<clock> ramtop=<addr>
core -> interpreter   Z80 proto=1 name=<text>
...calls...
interpreter -> core   BYE
```

*   `HELLO` is the first line the core reads.  `mhz` is the interpreter's
    `speed` setting (0 = unthrottled); a core that paces cycles paces to
    it.  `ramtop` is the physical top of RAM (65535); above it memory is
    absent on both sides.
*   `Z80` is the first line the core writes.  `proto` must equal the
    interpreter's constant.  On a mismatch the interpreter prints one
    stderr notice, closes the core, and uses the stub for the session.
    `pid=<n>` (optional, recommended) is the core's process id: when a
    call times out the interpreter kills that process before closing the
    pipe, because closing a coprocess waits for it to exit.
*   `BYE` ends the session; the core exits.  The interpreter also closes
    the pipe on exit, so a core must exit on EOF on stdin too.

## A call

```
interpreter -> core   CALL gen=<n> full=<0|1> slot=<0-9> entry=<addr> arg=<number> sp=<addr> himem=<addr> ramtop=<addr> runs=<k>
interpreter -> core   M <addr>:<b>,<b>,...          (k lines)
interpreter -> core   GO
core -> interpreter   (any number of V / K / T lines, in any order)
core -> interpreter   RET hl=<0-65535> result=<0|1> cycles=<n> break=<0|1> writes=<k>
core -> interpreter   W <addr>:<b>,<b>,...          (k lines)
```

### The frame (`CALL` + `M` + `GO`)

*   `gen` counts frames from 1 within a session.  `full=1` means the `M`
    lines carry EVERY defined address and the core must discard its RAM
    and start from 255 everywhere.  `full=0` means a DELTA: only what may
    have changed since frame `gen-1`; the core applies it over the RAM it
    kept.  The first frame of a session is always full.
*   If the core did not see frame `gen-1` (it restarted, or lost state),
    it answers the `GO` with `NEED full` instead of running.  The
    interpreter then resends the call as a full frame with `gen=1`.
*   What a delta contains, so the core never has to guess: the 11
    constant and pointer bytes (37E8/9H, 40A4/5H, 40AA-40ACH, 40B1/2H,
    40F9/FAH) and the 20 system variable window cells (4020H-4022H,
    4028/4029H, 409BH, 4041H-4046H, 40A2/A3H, 40E1H-40E5H, 411BH) -- these
    always -- the screen cells (3C00-3FFFH) the interpreter wrote since the
    last frame (the whole screen after a scroll or CLS; the core's own `V`
    writes are not resent), every VARPTR'd string and numeric cell whose
    value, place or descriptor changed, the program image when it was
    rebuilt, and every other address the interpreter wrote or unmapped
    since the last frame.  A core that keeps its RAM between frames, as
    the protocol requires, sees no difference from a larger delta.
    Every
    byte is what a BASIC `PEEK` would return -- the address-resolution
    contract in `src/p75_mem.awk` -- so the core reproduces nothing; it
    just applies the runs.  Addresses NOT in any frame read 255.
    The keyboard, 3800-38FFH, is never in a frame, even after a store
    there: reading it is the live matrix, which is what `K` is for.
*   `slot` is the USR slot digit (0-9).  `entry` is the resolved routine
    address (DEF USRn wins; slot 0 falls back to the 408EH POKE vector).
    An undefined entry never reaches the core: the interpreter raises
    `?FC` itself.
*   `arg` is the BASIC argument as a number (possibly non-integer, possibly
    negative).  The core converts it as the ROM's 0A7FH routine does when
    the routine calls that address: floored to an integer, into HL, and
    `ERR ov` when it is outside -32768..32767 (see Errors).
*   `sp` is the initial stack pointer: the interpreter's `SSP`, the bottom
    of allocated string space (HIMEM when nothing is packed), which is
    where Level II keeps its stack.  The core owns SP for the call and
    pushes into its own RAM beneath it; those bytes come back in the
    write-set like any other store.  Before jumping to `entry` the core
    pushes its RETURN SENTINEL, a fixed address in 0000-2FFFH (ROM space,
    which holds no bytes on either side); the routine's final `RET` to it
    ends the call.  Any other jump or call into 0000-2FFFH is either a
    documented entry point the core serves as an HLE trap (01C9H CLS,
    0A7FH argument to HL, 0A9AH HL to result, ...) or an `ERR rom`.
    A STORE into 0000-2FFFH changes nothing, as on the machine: the core
    drops it (it is not in the write-set) and the interpreter's POKE
    drops it too, so the range stays empty on both sides.
*   `himem` is the MEMORY SIZE? fence; `ramtop` as in HELLO.

### During the call

*   `V <addr>:<b>,...` -- video bytes the routine stored, 3C00-3FFFH only.
    The interpreter draws them immediately, so an animation is visible
    while the routine runs.  The core batches them: one `V` line per tick
    at most per contiguous run is plenty.  Video bytes need not be
    repeated in the write-set.
*   `K <sel>` -- the routine read keyboard address 3800H+sel (sel 0-255,
    the row-select bits).  The interpreter answers `K <value>` with the
    live matrix byte.  This is the ONLY callback; every other read is
    served from the core's own RAM.
*   `MODE <w>` -- the video width changed: `w=1` is 32-column mode, `w=0`
    is 64-column.  The core sends it when a routine's `OUT (FFH)` flips
    bit 3 (the same latch `CHR$(23)` sets from BASIC), pending video
    flushed first so the switch lands between the right frames.  The
    interpreter re-renders the screen in the new width; a routine that
    sets 32-column text then clears it for full-width graphics (the
    Dancing Demon) is drawn correctly.  CLS (01C9H) also restores
    64-column mode, as the ROM and BASIC's own CLS do: the core clears
    bit 3 of the ROM's port image at 403DH (in the write-set, so the
    interpreter's 32-column print flag follows and the BASIC PRINT after
    the call steps one byte) and emits `MODE 0`.  No reply.
*   `T <cycles>` -- a tick: the T-states executed since the last tick.
    The core sends one every few thousand T-states (every ~5 ms of
    emulated time at 1.77 MHz is a good rate) so the interpreter can poll
    for BREAK and so the timeout guard never fires on a long routine.
    The interpreter answers `OK`, or `BREAK` when the user pressed BREAK;
    on `BREAK` the core stops as soon as it can and returns with
    `break=1`.  Pacing to real time is the core's job (using `mhz`).

### The return

*   `result=1` means the routine went through 0A9AH (HL to result): `hl`
    is the HL it handed over there, 0-65535 (the last one, if it did so
    more than once), and the value of the `USR` expression is that, as a
    signed 16-bit integer.  0A9AH returns to its caller, as the ROM
    routine does: the usual `JP 0A9AH` ends the call because the return
    pops the sentinel, and a routine that `CALL`s it runs on.  A core
    that executes the routine also makes the ROM routine's own stores
    (HL to 4121H, the integer type flag 2 to 40AFH; A comes back 2), and
    they arrive in the write-set like any other store.
    `result=0` means the value is the argument unchanged, as on hardware;
    `hl` is then HL at the sentinel.
*   `cycles` is the total T-states for the call (diagnostic).
*   `break=1` means the call was cut short by BREAK; the interpreter
    reports `BREAK` at the current line after applying the write-set.
*   `ready=1`, present only when it applies, means the routine ended by
    jumping to the ROM's READY entry, 1A19H, instead of returning: it
    handed the machine back to the prompt, so after applying the
    write-set the interpreter ends the program there, as the machine
    would, and does not run the statement after the call.  A `RET`
    without the field is an ordinary return.
*   `writes` counts the `W` lines that follow: every address the routine
    stored to, LAST WRITE WINS per address, ascending, the video range
    omitted (already sent as `V`).  The interpreter applies them in order
    through `poke_byte`, so a Z80 store lands exactly where a BASIC POKE
    would: packed-string bytes write through into the string, 40B1H moves
    HIMEM, a store into the program image sticks and reads back (the image
    is RAM, writable since 2026-09-12; the byte belongs to its line and a
    rebuilt image is resent whole), above RAMTOP is discarded.

### Errors

```
core -> interpreter   ERR <code> <text>
```

Sent instead of `RET`.  The interpreter raises `?FC` at the `USR` call and
prints `USR CORE: <text>` on stderr.  Codes: `rom` (a jump or call into
ROM space that is neither the sentinel nor a served trap; when no frame
and no store ever wrote the entry address, the text adds `-- no routine
at XXXXH: its memory was never written`, the signature of a loader that
never ran), `halt` (the routine executed HALT), `bad` (the core could not
parse a message), and `ov`, which is not a core fault but the machine's
own error: the routine called 0A7FH (the ROM's CINT: the argument is
floored to an integer, -32768 accepted exactly, anything else outside
-32768..32767 exits through 07B2H) with an argument out of that range.
For `ov` the interpreter raises `?OV` at the `USR` call, as the ROM does,
and prints nothing on stderr.  After an `ERR` the core is still up and
the next call proceeds normally.

An `ERR` that ends a routine already running is preceded by the stores the
routine made up to that point: `W` lines in the write-set's form (last
write wins per address, ascending, the video range omitted), with no
count -- the `ERR` line ends them.  The interpreter applies them through
`poke_byte` as it applies a write-set, then raises the `?FC`.  The core
keeps those stores in its own RAM and later frames are deltas of what the
interpreter changed, so a store that stayed behind would never be
corrected: a routine that read the address on a later call would see a
byte BASIC's `PEEK` does not.  `W` anywhere else before `RET` is a
protocol error.

## Fallback

The interpreter uses the stub -- `USRn(x)` returns `x`, and one stderr line
at the end of the run tallies the calls not executed -- whenever: `TRS80_Z80`
is unset; the command cannot be started or does not answer `HELLO`; the
`Z80` line carries another `proto`; a call timed out, or the core exited,
earlier in the session.  Each of those prints one `USR CORE:` notice the first time.
`TRS80_USR=strict` turns stub calls into `?FC`.

## Conformance

`sh programs/tests/z80.sh` runs the whole protocol against
`programs/tests/z80_stub.py`, including NEED, the timeout, ERR, the version
mismatch and the fallback paths, and asserts on BASIC-visible effects.  A
core is conformant when `TRS80_Z80="python3 /path/to/core" sh
programs/tests/z80.sh` passes with the stub's canned entry addresses
implemented as real machine code (the routines are trivial: paint two
bytes, read the keyboard, store three bytes, double HL, return a byte,
push a word, call 01C9H, store a byte and call 0000H).
