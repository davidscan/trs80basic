# Security

trs80basic runs old BASIC listings, and many of the listings people run are
ones they found online. This page says what such a program can and cannot
do on your computer, what the interpreter promises, and what it does not.

It describes the current `main` branch (v2.1.2 and the fixes since) on
macOS and Linux. Native Windows (cmd or PowerShell)
is not supported yet; under WSL it behaves as on Linux.

## Who is trusted

| Trusted (yours) | Not trusted |
|---|---|
| Your command line and options | A BASIC listing, and everything it computes: file names, PRINT output, POKEd bytes, USR machine code |
| Your environment variables (`TRS80_*`) | Every file a program loads: `.bas` text or tokenized, `.cas`, `/CMD` object files |
| What you type at the `READY` prompt, including metacommands such as `dir` and `cat` | Replies from the Ollama server |
| The files in your checkout, and the sibling `trs80_z80_core` the launcher finds | |

Anything in the left column can make the interpreter do anything you can
do; that is by design (for example, `TRS80_OLLAMA_CURL` replaces the
command used to reach Ollama). The promises below are about the right
column.

## What a program can do

- **Read any file you can read.** `LOAD`, `RUN "file"`, `MERGE`, `CLOAD`,
  `SYSTEM` and `OPEN "I"` take any path. This is deliberate: programs such
  as text adventures load data by absolute path.
- **Write, and `KILL`, only inside the directory you started it in.**
  `OPEN "O"`/`"E"`/`"R"`, `SAVE`, `CSAVE` and `KILL` refuse an absolute
  path or a `..` component with `?FD ERROR`, and the check follows where a
  name leads: a symbolic link that points outside the directory is refused
  too. `KILL` deletes without asking.
- **Send text to your Ollama server** through the `OLLAMA` channel, and
  keep a conversation file (`*.ollama`) in the working directory. The
  server is `TRS80_OLLAMA_HOST` (default `localhost:11434`). Together with
  the first point, this means a program can send the contents of a file it
  read to that server.
- **Run Z80 machine code** with `USR`, `SYSTEM` or a POKEd routine. It runs
  in an emulated Z80 (the separate `trs80_z80_core` process), inside the
  emulated 64K machine. It has no way to make a system call; the core
  answers only a small fixed set of trapped entry points.
- **Change a few interpreter settings** with `REM META:` remarks, and only
  when you have turned `ext on`: `speed`, `fullscreen` and `memory`. No
  `REM META:` remark runs a shell command or touches a file.

## What a program cannot do

- Reach the shell. Every string the interpreter hands to a shell is quoted
  (the `curl` call to Ollama, and the `dir` and `cat` metacommands you
  type).
- Open a network socket or a file descriptor by naming it. GNU awk treats
  names such as `/inet/tcp/...`, `/dev/fd/N` and `-` specially; the
  interpreter refuses them, and devices, directories, FIFOs and dangling
  links, wherever a program supplies a file name.
- Put a control character on your terminal. Nothing a program prints,
  reads from a file or `LIST`s reaches the terminal as a raw control
  character (ESC, BEL, the C1 range): not in plain output, not in the
  full-screen display. TAB completion never offers or lists a file name
  that holds one.
- Crash the session through a file name. A write that would fail (an
  unwritable path, a directory) is checked first and becomes a BASIC
  error, so the session and your unsaved program survive.

`programs/tests/special.sh`, `hostwrite.sh`, `termsafe.sh` and
`kbd_pty.py` test these promises.

## Known limits

- Reads are not confined (see above): the interpreter does not sandbox
  what a program can read.
- The launcher runs the sibling `../trs80_z80_core/core.py` without
  checking it. Keep that checkout as trustworthy as this one, or set
  `TRS80_Z80=` (empty) to run with no core.

## Running a listing you do not trust

Run it from an empty scratch directory: that is where any writes and
`KILL`s land. If it should not read your files or reach Ollama, run it in a
container or as a user that cannot read them; the interpreter does not
sandbox reads.

## Reporting a problem

Open an issue on GitHub for anything. If you find a way for a program to
get past the limits above, please use GitHub's private vulnerability
reporting instead (the repository's Security tab, "Report a
vulnerability"), so it can be fixed before it is public.
