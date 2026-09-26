# ===================== errors and numeric utilities =========================

# DIRECTLN is the line number of a statement typed at the prompt.  The ROM
# keeps ONE cell for the line it is executing, 40A2H, and marks the Input
# Phase by putting FFFFH there (1A36), so a real line 0 and "no line" are
# told apart -- which a plain 0 cannot do (the 2026-09-19 audit, L-4).  ERL
# reads it through 40EAH (19A5), so ERL is 65535 after a direct-mode error.
function inln(n) { return (n == DIRECTLN) ? "" : " IN " n }

function raise(c) {
    if (E) return
    E = c
    ERR_AT = CLN
    ERRV = (c - 1) * 2
    ERLV = CLN
    # "." becomes the line with the error, trapped or not: the ROM notes it
    # with ERL, before it looks for an ON ERROR handler (19A5-19A8), so
    # LIST . and EDIT . go to the line that failed
    if (CLN != DIRECTLN) LASTLN = CLN
}

function report_err(   c, msg) {
    c = E; E = 0
    if (!(c in ERRC)) c = 20                  # the table is sparse past 23 (the file codes)
    # ROM 1A11-1A14 prints the line unless H AND L is FF, that is unless it
    # is 65535 -- so an error in line 0 reports " IN 0"
    msg = "?" ERRC[c] " ERROR" inln(ERR_AT)
    # ROM 19E3H-19E4H: every error that is PRINTED clears the handler flag
    # (40F2H), so a handler that failed is over -- the trap stays armed
    # (40F0H is cleared only by RUN's initializer, 1B74H) and a RESUME typed
    # afterwards is ?RW.  Until 2026-09-24 the flag stayed set: later errors
    # were not trapped, and a stray RESUME resumed the dead handler (M-5).
    # The CONT point is NOT cleared: the error routine's exit (19B1H ->
    # 1B9AH, past the 1B77H clear) leaves 40F5H/40F7H as execloop set
    # them, so CONT re-runs the statement that failed (H-1).
    INHANDLER = 0
    # only UNCAUGHT errors reach here (ON ERROR GOTO is handled in execloop),
    # so this is the one place batch mode needs for its exit-1 status
    if (BATCH) { BATCHERR = 1; diag_err(msg); batch_hint(c); return }
    if (CUR % 64 != 0) s_nl()
    s_puts(msg); s_nl()
    sync_cursor()
}

# LEVEL II-style number formatting: leading space or -, trailing space,
# BY TYPE, since 2026-09-26 (L-16): an integer in full; a single to 6
# significant digits, no leading zero on a fraction, E notation for the
# extremes (so a single 1000000 is 1E+06, as on the machine); a double
# to 16 significant digits with D as its exponent letter (the manual:
# "stored with 17 digits but printed out with only 16"; Barden shows
# 1.23456789D+18).  Until then every exact integer below 1e15 printed
# in full, because values carried no type.
# The last digit is rounded HALF UP on the magnitude: the ROM scales the
# value to six integer digits, adds .5 and truncates (12EA-12F0).  sprintf
# rounds an exact tie to even (100000.5 -> 100000, 1/512 -> .00195312), so
# a following digit of 5 is rounded here, on the decimal digits; the
# double path does the same at its seventeenth.
function fmtnum(x, ty,   s, ax, t) {
    ax = (x < 0) ? -x : x
    if (ty == "I") s = sprintf("%d", x)
    else if (ty == "D") {
        t = sprintf("%.16e", ax)                 # d.dddddddddddddddde+xx: 17 digits
        if (substr(t, 18, 1) == "5")
            x = (x < 0 ? -1 : 1) * (((substr(t, 1, 1) substr(t, 3, 15)) + 1) "e" (substr(t, 20) - 15))
        s = sprintf("%.16g", x)
        sub(/e/, "D", s)
        sub(/^0\./, ".", s)
        sub(/^-0\./, "-.", s)
    } else {
        t = sprintf("%.16e", ax)                 # d.dddddddddddddddde+xx
        if (substr(t, 8, 1) == "5")
            x = (x < 0 ? -1 : 1) * (((substr(t, 1, 1) substr(t, 3, 5)) + 1) "e" (substr(t, 20) - 5))
        s = sprintf("%.6g", x)
        sub(/e/, "E", s)
        sub(/^0\./, ".", s)
        sub(/^-0\./, "-.", s)
    }
    return (x < 0 ? s : " " s) " "
}

# The ROM's ASCII-to-binary routine (0E65H/0E6CH), the one reader behind
# VAL, INPUT, READ and INPUT#.  It reads what it can and stops; NUMEND is
# left at the first character it did not take, and the CALLER decides what
# may follow (VAL: anything; READ and INPUT: nothing but blanks, p80).
#   * a sign is taken only as the very FIRST character (0E77-0E80): READ
#     and INPUT skip the item's leading blanks before they call, VAL does
#     not, so VAL(" -5") is 0 on the machine and here
#   * every later character is fetched through RST 10H, which skips blank,
#     tab and line feed (1D78-1D88): VAL("1 2") is 12, "1 E 3" is 1000
#   * a second "." ends the number (0EE4-0EE6); a lone "." is 0
#   * E or D with no digits behind it is an exponent of 0: "1E" is 1
#   * "!" and "#" are taken and end the number (0EF5-0EF9).  "%" is taken
#     only while the value is still an INTEGER -- no ".", no exponent, not
#     past 32767, and not the double-precision entry (dp) -- and is ?SN
#     otherwise (0EEE-0EEF, JP P,1997H).  VAL always enters there (2AD8H),
#     so VAL("12%") is ?SN.  READ and INPUT enter there for a # variable;
#     a variable's precision is not tracked here, so they never do.
# Lower-case e/d is kept as an exponent: the Model I keyboard had no
# lower case to type, a terminal types nothing else.
function valnum(s, dp,   i, c, sg, m, dot, isint, ex, exs, x, expd, sig, sx) {
    i = 1; m = ""; ex = ""; isint = !dp; expd = 0; sx = ""
    c = substr(s, 1, 1)
    if (c == "-" || c == "+") { sg = c; i = 2 }
    for (;;) {
        while (substr(s, i, 1) ~ /^[ \t\n]$/) i++
        c = substr(s, i, 1)
        if (c ~ /^[0-9]$/) { m = m c; i++; continue }
        if (c == ".") {
            if (dot) break
            dot = 1; isint = 0; m = m c; i++; continue
        }
        if (c ~ /^[EeDd]$/) {
            expd = (c ~ /^[Dd]$/); i++
            while (substr(s, i, 1) ~ /^[ \t\n]$/) i++
            c = substr(s, i, 1)
            if (c == "-" || c == "+") { exs = c; i++ }
            for (;;) {
                while (substr(s, i, 1) ~ /^[ \t\n]$/) i++
                c = substr(s, i, 1)
                if (c !~ /^[0-9]$/) break
                ex = ex c; i++
            }
            break
        }
        if (c == "%") {
            if (!isint || m + 0 > 32767) { raise(2); return 0 }
            sx = "I"; i++
        } else if (c == "#" || c == "!") { sx = (c == "#") ? "D" : "S"; i++ }
        break
    }
    NUMEND = i; NUMSTR = s
    # VALTYPE: the type the reader gives the number (VAL returns it), by
    # tk_number's rule (p50): I while there is no point or exponent and it
    # fits 15 bits, D from the eighth significant digit or a D exponent
    if (sx != "") VALTYPE = sx
    else {
        sig = m; sub(/\./, "", sig); sub(/^0+/, "", sig)
        if (isint && !dot && ex == "" && !expd && m + 0 <= 32767 && m != "") VALTYPE = "I"
        else if (expd || length(sig) > 7) VALTYPE = "D"
        else VALTYPE = "S"
    }
    if (m == "" || m == ".") m = "0"
    x = numconv(sg m "E" exs (ex == "" ? "0" : ex))
    return x
}

# READ's and INPUT's use of it: is the rest of the item just read blank?
function numrest() {
    return substr(NUMSTR, NUMEND) ~ /^[ \t\n]*$/
}

# string -> number honoring the D (double-precision) exponent marker, which
# awk's own conversion would stop at ("1D3" + 0 == 1).
# The ROM's ASCII-to-binary routine (0E6CH) is the one reader behind VAL,
# INPUT, READ and INPUT#, and it leaves through 07B2H, ?OV, when the
# exponent overflows; the limit is the one a literal in a line has (p60).
# Every caller checks E before it stores: nothing is assigned.
function numconv(s,   x) {
    sub(/[Dd]/, "E", s)
    x = s + 0
    if (x >= FMAX || x <= -FMAX) { raise(6); return 0 }
    return x
}

# A SINGLE'S 24-BIT ROUNDING (ROM 0796H-07A9H): every single-precision
# result is normalized to a 24-bit mantissa, and the guard byte's top bit
# bumps the least significant bit -- half up on the magnitude, never to
# even.  Here the IEEE double result is rounded to the same 24 bits, so a
# sum of singles drifts as the machine's does: FOR X=0 TO 1 STEP .1 makes
# 10 passes, not 11 (the 2026-09-23 audit, M-15).  Since 2026-09-26.
function sround(x,   ax, e, q, r) {
    if (x == 0) return 0
    ax = (x < 0) ? -x : x
    e = int(log(ax) / LN2)
    if (2 ^ e > ax) e--
    else if (2 ^ (e + 1) <= ax) e++
    q = 2 ^ (e - 23)                        # one unit of the 24-bit mantissa in this binade
    r = int(ax / q + 0.5) * q
    return (x < 0) ? -r : r
}

# The range of a single or double result: past FMAX it is ?OV (0796H's
# overflow, 07B2H); below 2^-128 the exponent byte runs out and the
# result is ZERO, silently (0793H JR NC,0778H).  Returns the value,
# with E set for ?OV.  Since 2026-09-26 (M-10's underflow half).
function frange(x) {
    if (x >= FMAX || x <= -FMAX) { raise(6); return 0 }
    if (x < FMIN && x > -FMIN) return 0
    return x
}

# BASIC INT(): floor
function bfloor(x,   f) {
    f = int(x)
    if (x < 0 && f != x) f--
    return f
}

# ---- 16-bit logical operators (two's complement) ----------------------------
# Level II converts to an integer by rounding DOWN, not to nearest: "the
# largest integer not greater than the argument ... CINT(1.5) returns 1;
# CINT(-1.5) returns -2" (Level II manual, CINT; limits -32768 <= x <
# 32768).  AND, OR, NOT, CINT and MKI$ all take their operands this way, so
# the period nibble idiom V/16 AND 15 yields the high hex digit and
# CINT(D/256) the high byte.  Rounding to nearest (until 2026-09-19) made
# both wrong for any fraction of .5 or more.
function to16(x,   r) {
    r = bfloor(x)
    if (r > 32767 || r < -32768) { raise(6); return 0 }
    return r
}

function toU(x,   r) {
    r = to16(x)
    if (r < 0) r += 65536
    return r
}

function band16(v, r) {
    if (!isN(v) || !isN(r)) { raise(13); return 0 }
    return toS(and(toU(num(v)), toU(num(r))))
}

function bor16(v, r) {
    if (!isN(v) || !isN(r)) { raise(13); return 0 }
    return toS(or(toU(num(v)), toU(num(r))))
}

function toS(u) { return (u > 32767) ? u - 65536 : u }

# ---- authentic ROM RND (LEVEL2BASIC RND at 14C9-1540H) ----------------------
# 24-bit LCG over the seed stored at 40AA-40ACH (dec 16554-16556, LSB/mid/MSB,
# POKEable -- dopeek/poke_byte map it):
#   seed' = (seed*4253261 + 372837) mod 2^24
# (multiplier bytes 40 E6 4D at 4090H, addend 05B065H).  RND(0) = seed'/2^24;
# RND(n) = INT(RND(0)*n + 1) with the multiply rounded to single precision
# (sngl).  All arithmetic is exact in doubles (products < 2^48).  Boot and
# the RANDOM statement write ONLY the middle byte (the ROM takes it from the
# Z80 R register; we take it from gawk rand(), so --seed stays repeatable).
# Authentic quirks reproduced: RND(1) is always 1 (the corpus dialect trap),
# and seed E20F02H yields mantissa FFFFFF, which PRINTs as 1.
function rnd_next() {
    RNDSEED = (RNDSEED * 4253261 + 372837) % 16777216
    return RNDSEED / 16777216
}

# round x (>0) to a 24-bit significand -- the MS single-precision multiply
# tail, which rounds the guard bits half away from zero
function sngl(x,   s) {
    if (x <= 0) return 0
    s = 1
    while (x >= 16777216) { x /= 2; s *= 2 }
    while (x < 8388608)   { x *= 2; s /= 2 }
    return int(x + 0.5) * s
}

# the RANDOM statement / boot init: replace the seed's middle byte
function rnd_setmid(b) {
    RNDSEED = int(RNDSEED / 65536) * 65536 + (b % 256) * 256 + RNDSEED % 256
}

function rnd_peek(i) {
    if (i == 0) return RNDSEED % 256
    if (i == 1) return int(RNDSEED / 256) % 256
    return int(RNDSEED / 65536)
}

function rnd_poke(i, b,   lo, mid, hi) {
    lo = RNDSEED % 256; mid = int(RNDSEED / 256) % 256; hi = int(RNDSEED / 65536)
    if (i == 0) lo = b; else if (i == 1) mid = b; else hi = b
    RNDSEED = hi * 65536 + mid * 256 + lo
}

# ---- host shell gates (WINDOWS.md) -----------------------------------------
# WINNATIVE (probed once in BEGIN, src/p10_head.awk) means a native Windows
# gawk: every system()/pipe is serviced by cmd.exe, so each helper carries a
# cmd arm.  The Unix arms are the pre-gate command strings kept verbatim --
# on macOS/Linux these helpers run byte-identical commands to the old inline
# calls.  cmd.exe has no single-quote quoting, so the cmd arms double-quote
# the name and refuse names containing a double quote (illegal on Windows).

# can we create/append f?  probed before awk output redirects, whose open
# failures are fatal in gawk (that is why this stays a shell-out).  touch
# alone is not the probe: it succeeds on a directory, and on a read-only
# file the owner may still set times -- both then killed gawk at the
# redirect, losing the program in memory (the 2026-09-19 audit, C-1).  So: not a
# directory, creatable, and writable once it exists.
# gawk does not treat every name as a file.  /inet/tcp/0/host/80 (and
# /inet4, /inet6) is a SOCKET, /dev/fd/N and "-" are the interpreter's own
# descriptors, and the rest of /dev/ is devices (/dev/zero never ends a
# slurp).  A BASIC program chooses its file names -- OPEN takes an
# expression -- so without this gate a listing could open a network
# connection, carry out a file it had read in the host part of the name,
# or LOAD and RUN whatever a server sent (the 2026-09-19 audit, H-1).  gawk
# matches these names as literal prefixes, so that is the test here.  It is
# only half the gate: any OTHER spelling of a device -- //dev/zero,
# /./dev/zero, /Dev/zero on a case-insensitive filesystem -- is not gawk's
# name, so gawk hands it to the OS, which resolves it to the device: a
# slurp that never ends, a write that lands raw on the terminal (the
# 2026-09-23 audit, H-3).  The other half is host_kind below: a program
# READS a regular file and WRITES a regular file or a name that does not
# exist yet; a device, a directory, a FIFO or a socket is ?FD however it
# is spelled.  EVERY path that hands a BASIC-chosen name to getline or to
# a redirect asks both: LOAD/RUN/MERGE (host_found, p40), CLOAD and
# SYSTEM (p40), OPEN (p85), SAVE/CSAVE and the OLLAMA transcript
# (host_writable), KILL (host_exists).  The batch program named on the
# command line is the user's own and is not kind-checked: a FIFO there is
# read once and works (special.sh).
function host_special(f) {
    return f == "-" || f ~ /^\/inet[46]?\// || f ~ /^\/dev\//
}

# what f names: "f" a regular file (through a symbolic link), "x" anything
# else that is there (a directory, a device, a FIFO, a socket, a dangling
# link), "" nothing.  One shell-out; cmd.exe knows only "is it there".
function host_kind(f,   cmd, s, r) {
    if (WINNATIVE) {
        if (f ~ /"/) return "x"
        return system("if exist \"" f "\" (exit 0) else (exit 1)") == 0 ? "f" : ""
    }
    cmd = "if [ -f " shq(f) " ]; then echo f; elif [ -e " shq(f) " ] || [ -L " shq(f) " ]; then echo x; fi"
    s = ""
    r = (cmd | getline s)
    close(cmd)
    return (r > 0) ? s : ""
}

function host_writable(f) {
    if (host_special(f)) return 0
    if (WINNATIVE)
        return f !~ /"/ && system("type nul >> \"" f "\" 2>nul") == 0
    # a regular file or a new name (H-3), then: not a directory, creatable,
    # and writable once it exists (C-1)
    return system("{ test ! -e " shq(f) " || test -f " shq(f) "; } && test ! -d " shq(f) \
                  " && touch -- " shq(f) " 2>/dev/null && test -w " shq(f)) == 0
}

# f could be written, WITHOUT creating it: an existing plain file we may
# write, or a new name in a directory we may write.  For a path handed to
# another process to open later (the `sound wav` capture, which the core
# opens at its next start), so naming it leaves no empty file behind.
function host_canwrite(f) {
    if (host_special(f)) return 0
    if (WINNATIVE) return f !~ /"/
    return system("if [ -e " shq(f) " ]; then [ -f " shq(f) " ] && [ -w " shq(f) " ]; " \
                  "else d=$(dirname -- " shq(f) ") && [ -d \"$d\" ] && [ -w \"$d\" ]; fi") == 0
}

# can gawk append to f, the printer path (TRS80_PRINTER)?  That path is
# the USER's, from the environment, not a program's, so the kind rule does
# not apply: a device is a fine printer (/dev/null discards, /dev/stdout
# shows the printout in a capture).  What is refused is exactly what makes
# gawk's redirect fatal -- a directory, a name in a directory that is not
# there or cannot be written, a file that cannot be written -- and a
# socket name, which gawk would try to connect (the 2026-09-23 audit,
# M-1, the C-1 class).  Asked once at start (p10, LPBAD); nothing is
# created by asking, the redirect makes the file when something prints.
function host_appendable(f) {
    if (f ~ /^\/inet[46]?\//) return 0
    if (WINNATIVE) return f !~ /"/
    return system("if [ -e " shq(f) " ]; then [ ! -d " shq(f) " ] && [ -w " shq(f) " ]; " \
                  "else d=$(dirname -- " shq(f) ") && [ -d \"$d\" ] && [ -w \"$d\" ]; fi") == 0
}

# s as one single-quoted sh word: each ' becomes '\'' (close the quote,
# an escaped quote, reopen).  For names the shell must never parse, such
# as file names read back from ls (p30 rl_complete, the 2026-09-19 audit, C-2).
function shq(s) {
    gsub(/'/, "'\\''", s)
    return "'" s "'"
}

# the byte length of f, or -1 when it cannot be had.  This is a COMMAND
# pipe, not `getline < f`, on purpose: LOF can be asked while the channel's
# own read of the same name is part way through the file, and gawk keys a
# file redirection by its name -- closing it to measure the file would
# restart the read from the top (the 2026-09-19 audit, L-34).
function host_size(f,   cmd, s, r) {
    if (host_special(f)) return -1
    if (WINNATIVE) {
        if (f ~ /"/) return -1
        cmd = "for %I in (\"" f "\") do @echo %~zI"
    } else
        cmd = "wc -c < " shq(f) " 2>/dev/null"
    s = ""
    r = (cmd | getline s)
    close(cmd)
    if (r <= 0) return -1
    gsub(/[^0-9]/, "", s)
    return (s == "") ? -1 : s + 0
}

# f is a regular file (KILL, host_found): a device by any spelling is not
function host_exists(f) {
    if (host_special(f)) return 0
    return host_kind(f) == "f"
}

# 1 when f is gone afterwards.  rm's own complaint is swallowed: stderr is
# the BASIC program's error channel, and a KILL that fails has an error code
# of its own to report (the 2026-09-19 audit, L-5).  The OLLAMA request file
# is removed with the same helper and ignores the answer -- a temp file left
# behind is not the program's business.
function host_delete(f) {
    if (WINNATIVE) {
        if (f ~ /"/) return 0
        return system("del /f /q \"" f "\" 2>nul") == 0
    }
    return system("rm -f -- " shq(f) " 2>/dev/null") == 0
}

function host_tmpdir() {
    if (WINNATIVE) return ENVIRON["TEMP"] != "" ? ENVIRON["TEMP"] : "."
    return ENVIRON["TMPDIR"] != "" ? ENVIRON["TMPDIR"] : "/tmp"
}

# a fresh, empty scratch file, or "" when none can be made.  A name built
# from the pid is predictable, and an awk redirect writes through whatever
# is already there: on a shared /tmp another local user could plant a
# symlink under that name and have our output land on any file we can
# write (the 2026-09-19 audit, M-5).  mktemp picks the name and creates
# the file exclusively, mode 0600, so what the redirect then opens is ours;
# a temp directory that cannot be written is "" here instead of a gawk
# fatal at the redirect.  %TEMP% on Windows is per user and cmd.exe has no
# mktemp, so that arm keeps the pid name.
function host_mktemp(stem,   cmd, f) {
    if (WINNATIVE) {
        f = host_tmpdir() "/" stem "_" PROCINFO["pid"] ".tmp"
        return host_writable(f) ? f : ""
    }
    cmd = "mktemp " shq(host_tmpdir() "/" stem ".XXXXXX") " 2>/dev/null"
    f = ""
    cmd | getline f
    close(cmd)
    return f
}
