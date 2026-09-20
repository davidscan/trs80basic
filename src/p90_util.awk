# ===================== errors and numeric utilities =========================

function raise(c) {
    if (E) return
    E = c
    ERR_AT = CLN
    ERRV = (c - 1) * 2
    ERLV = CLN
}

function report_err(   c, msg) {
    c = E; E = 0
    if (c < 1 || c > NERRC) c = 20
    msg = "?" ERRC[c] " ERROR" (ERR_AT > 0 ? " IN " ERR_AT : "")
    CONTOK = 0
    # only UNCAUGHT errors reach here (ON ERROR GOTO is handled in execloop),
    # so this is the one place batch mode needs for its exit-1 status
    if (BATCH) { BATCHERR = 1; diag_err(msg); return }
    if (CUR % 64 != 0) s_nl()
    s_puts(msg); s_nl()
    sync_cursor()
}

# LEVEL II-style number formatting: leading space or -, trailing space,
# 6 significant digits, no leading zero on fractions, E notation for extremes.
# (Deviation: exact integers are printed in full up to 15 digits.)
function fmtnum(x,   s, ax) {
    ax = (x < 0) ? -x : x
    if (x == int(x) && ax < 1e15) s = sprintf("%.0f", x)
    else {
        s = sprintf("%.6g", x)
        sub(/e/, "E", s)
        sub(/^0\./, ".", s)
        sub(/^-0\./, "-.", s)
    }
    return (x < 0 ? s : " " s) " "
}

function valnum(s,   t) {
    if (match(s, /^[ \t]*[-+]?([0-9]+(\.[0-9]*)?|\.[0-9]+)([EeDd][-+]?[0-9]+)?/) && RLENGTH > 0) {
        t = substr(s, 1, RLENGTH)
        gsub(/[ \t]/, "", t)
        return numconv(t)
    }
    return 0
}

function strictnum(s) {
    return s ~ /^[ \t]*[-+]?([0-9]+(\.[0-9]*)?|\.[0-9]+)([EeDd][-+]?[0-9]+)?[ \t]*$/
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
    if (x > 1.7e38 || x < -1.7e38) { raise(6); return 0 }
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
# matches these names as literal prefixes, so that is the test.  EVERY path
# that hands a BASIC-chosen name to getline or to a redirect asks here
# first: OPEN, LOAD/RUN/MERGE/CLOAD and SYSTEM (slurp_bytes), SAVE/CSAVE
# and the OLLAMA transcript (host_writable), KILL (host_exists).
function host_special(f) {
    return f == "-" || f ~ /^\/inet[46]?\// || f ~ /^\/dev\//
}

function host_writable(f) {
    if (host_special(f)) return 0
    if (WINNATIVE)
        return f !~ /"/ && system("type nul >> \"" f "\" 2>nul") == 0
    return system("test ! -d " shq(f) " && touch -- " shq(f) " 2>/dev/null && test -w " shq(f)) == 0
}

# s as one single-quoted sh word: each ' becomes '\'' (close the quote,
# an escaped quote, reopen).  For names the shell must never parse, such
# as file names read back from ls (p30 rl_complete, the 2026-09-19 audit, C-2).
function shq(s) {
    gsub(/'/, "'\\''", s)
    return "'" s "'"
}

function host_exists(f) {
    if (host_special(f)) return 0
    if (WINNATIVE)
        return f !~ /"/ && system("if exist \"" f "\" (exit 0) else (exit 1)") == 0
    return system("test -f '" f "'") == 0
}

function host_delete(f) {
    if (WINNATIVE) { if (f !~ /"/) system("del /f /q \"" f "\" 2>nul"); return }
    system("rm -f -- '" f "'")
}

function host_tmpdir() {
    if (WINNATIVE) return ENVIRON["TEMP"] != "" ? ENVIRON["TEMP"] : "."
    return ENVIRON["TMPDIR"] != "" ? ENVIRON["TMPDIR"] : "/tmp"
}
