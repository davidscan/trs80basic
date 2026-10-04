# Contributing

Bug reports, fixes and new tests are welcome. Open an issue first for
anything larger than a fix, so the change can be agreed before you build
it. A security problem goes through [SECURITY.md](SECURITY.md) instead.

## A good bug report

- The listing (or the smallest part of it that shows the problem), what you
  typed, what the interpreter printed, and what the TRS-80 prints instead.
- How you know what the machine does: the Level II or Disk BASIC manual,
  a period book or magazine, or a run on real hardware or an emulator.
- `./basic --version`, your OS, and `gawk --version`.

## Building and testing

`trs80basic.awk` is **generated**: it is the concatenation of
`src/p*.awk`, in name order. Edit the files in `src/`, never the generated
file, then rebuild and run the whole suite:

    cat src/p*.awk > trs80basic.awk
    sh programs/tests/run_all.sh

Commit both the `src/` change and the rebuilt `trs80basic.awk`; CI fails a
commit where the two disagree. The suite must pass before a pull request.
If the companion core ([trs80_z80_core](https://github.com/davidscan/trs80_z80_core))
is checked out beside this repository, the suite runs against it too.

When invoking gawk directly, always pass `-b`: strings are byte strings,
and without it a UTF-8 locale corrupts every byte above 127.

## What a change must keep

**Behaviour follows the machine.** A change in what a BASIC program sees
moves toward what Level II BASIC on the TRS-80 does, and the pull request
says where that is documented (the manuals, or a published book about the
Level II ROM). Every fix comes with a test in `programs/tests/` that fails
without it. Tests assert on the program's output, not just the exit
status: the bugs that matter here exit 0 and print something plausible.

**Extensions are marked.** Anything beyond the 1978 manual carries an
`EXT` comment in the source saying why it cannot break a period program.
Metacommands (`dir`, `cat`, `speed` and the rest) stay lowercase-only, so
they never collide with a keyword a real listing uses.

**A program is untrusted input.** [SECURITY.md](SECURITY.md) lists what a
BASIC program can and cannot do; a change must keep those promises. Three
rules carry them in the code (the helpers are in `src/p90_util.awk`, and
`slurp_bytes()` in `src/p40_repl.awk`):

1. **A program-chosen file name is checked before gawk sees it.** gawk
   treats names such as `/inet/tcp/...`, `/dev/fd/N` and `-` as sockets
   and descriptors, not files. Any new path that hands a name a program
   chose to `getline <` or an output redirect asks `host_special()` first,
   or goes through `slurp_bytes()`, `host_writable()` or `host_exists()`,
   which do. (`programs/tests/special.sh`)
2. **Every write to a program-chosen path is probed first.** A failed gawk
   output redirect is fatal: it ends the session and loses the user's
   unsaved program. So every `print >`, `>>` or `printf >` to such a path
   checks `host_writable()` first and turns a failure into a BASIC error.
   A program's writes and `KILL`s also stay inside the working directory.
   (`programs/tests/hostwrite.sh`)
3. **Every string a shell parses is quoted with `shq()`.** Never place
   text, typed or read back from `ls`, raw inside `'...'` in a command.

**The memory contract is shared.** `src/p75_mem.awk` documents how every
address resolves for `PEEK` and `POKE`. The companion core relies on it to
execute the right bytes, so a change to `dopeek` or `poke_byte` updates
that contract and [PROTOCOL.md](PROTOCOL.md) in the same pull request.

## Licence

The project is GPL-3.0 ([LICENSE](LICENSE)); a contribution is offered
under the same licence. Do not add third-party listings, book text or
ROM bytes to the repository.
