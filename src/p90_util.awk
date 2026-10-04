# ===================== errors and numeric utilities =========================

# DIRECTLN is the line number of a statement typed at the prompt.  The ROM
# keeps ONE cell for the line it is executing, 40A2H, and marks the Input
# Phase by putting FFFFH there (1A36), so a real line 0 and "no line" are
# told apart -- which a plain 0 cannot do (the 2026-09-19 audit, L-4).  ERL
# reads it through 40EAH (19A5), so ERL is 65535 after a direct-mode error.
function inln(n) { return (n == DIRECTLN) ? "" : " IN " n }

function raise(c) {
    if (E) return
    HINTHOST = 0                            # this error is not (yet) a host-mode ceiling (batch_hint, p45)
    E = c
    ERR_AT = CLN
    ERRV = (c - 1) * 2
    ERLV = CLN
    # "." becomes the line with the error, trapped or not: the ROM notes it
    # with ERL, before it looks for an ON ERROR handler (19A5-19A8), so
    # LIST . and EDIT . go to the line that failed.  A statement typed at
    # READY moves it too, to FFFFH (19A8H copies 40A2H as it is), so LIST .
    # then lists nothing and DELETE . is ?FC (audit L-12; until 2026-09-27
    # a typed error left "." alone)
    LASTLN = CLN
}

function report_err(   c, msg) {
    c = E; E = 0
    if (!(c in ERRC)) c = 20                  # the table is sparse past 23 (the file codes)
    # an UNTRAPPED syntax error clears the ERR cell on its way to READY:
    # 1A2BH reads 409AH, SUB 02H leaves 0 for ?SN, and 1A30H's CALL 2E53H
    # stores that 0 back -- so ERR reads 0 afterwards, not 2 (the
    # 2026-09-26 audit, N-5; ERL keeps the line)
    if (c == 2) ERRV = 0
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

# a raise at a ceiling that `memory host` lifts (EXT): batch mode's note
# names the option (batch_hint, p45).  The flag belongs to THIS raise only.
function raise_host(c) { if (E) return; raise(c); HINTHOST = 1 }

# LEVEL II-style number formatting: leading space or -, trailing space,
# BY TYPE, since 2026-09-26 (L-16): an integer in full; a single to 6
# significant digits, a double to 16 with D as its exponent letter (the
# manual: "stored with 17 digits but printed out with only 16"; Barden
# shows 1.23456789D+18).  Until then every exact integer below 1e15
# printed in full, because values carried no type.
# The ROM's converter (103DH-1099H) scales the value by tens until it
# holds six integer digits, 99999.95 <= V < 999999.5 (1201H-1268H; the
# constants at 1229H and 1253H, not the round numbers Farvour's comments
# name), sixteen for a double (1E15 <= V < 1E16, the constants at 136CH
# and 1374H), counting the shifts, then adds .5 and truncates (12EA-12F0,
# 12B4H): the last digit is rounded HALF UP on the magnitude.  sprintf
# rounds an exact tie to even (100000.5 -> 100000, 1/512 -> .00195312),
# so a following digit of 5 is rounded here, on the decimal digits.
# Then the shift count decides the form (104BH-1057H, D = 7 or 11H):
# fixed notation only while the decimal exponent e is -2 <= e <= 5 (15
# for a double), so .01 and 999999 are fixed and .001 is 1E-03, 1000000
# is 1E+06, as on the machine (Richcraft vol. 2 p.97: 7.8125E-03).
# Until 2026-09-27 every value below .01 was fixed (.00195313; the
# 2026-09-26 audit, M-10).  The exponent letter is E or D by type
# (1075H-1079H), the exponent two digits and signed; trailing zeros
# and a bare point are dropped (1066H-106EH), so 1E-03, not 1.00000E-03.
function fmtnum(x, ty,   s, ax, t, nd, ds, e, ip, m) {
    if (ty == "I") return (x < 0 ? "" : " ") sprintf("%d", x) " "
    ax = (x < 0) ? -x : x
    if (ax == 0) return " 0 "
    nd = (ty == "D") ? 16 : 6
    t = sprintf("%.16e", ax)                 # d.dddddddddddddddde+xx: 17 digits
    if (substr(t, nd + 2, 1) == "5")         # the digit behind the last kept one: half up
        ax = ((substr(t, 1, 1) substr(t, 3, nd - 1)) + 1) "e" (substr(t, 20) - (nd - 1))
    t = sprintf("%." (nd - 1) "e", ax)       # no tie is left, so C's rounding agrees
    ds = substr(t, 1, 1) substr(t, 3, nd - 1); e = substr(t, nd + 3) + 0
    if (e < -2 || e > nd - 1) {
        m = substr(ds, 2); sub(/0+$/, "", m)
        s = substr(ds, 1, 1) (m == "" ? "" : "." m) (ty == "D" ? "D" : "E") \
            (e < 0 ? "-" : "+") sprintf("%02d", e < 0 ? -e : e)
    } else if (e == nd - 1) s = ds
    else {
        ip = e + 1                           # digits in front of the point: 0 or -1 means none
        s = (ip <= 0 ? "" : substr(ds, 1, ip)) "." (ip < 0 ? "0" : "") substr(ds, (ip < 1 ? 1 : ip + 1))
        sub(/0+$/, "", s); sub(/\.$/, "", s)
    }
    return (x < 0 ? "-" : " ") s " "
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
#   * only an upper-case E or D is an exponent (0E8CH CP 45H, 0E9FH CP
#     44H): VAL("1e5") is 1, and DATA 1e5 read into a number is ?SN as
#     any letter behind a number is (the reader stops in front of it).
#     Until 2026-09-27 a lower-case letter was taken too (the 2026-09-26
#     audit, L-20); a program line is upper-cased by the cruncher, so
#     only VAL, DATA and typed input ever see one.
function valnum(s, dp,   i, c, sg, m, dot, isint, ex, exs, x, expd, expl, sig, sx) {
    i = 1; m = ""; ex = ""; isint = !dp; expd = 0; expl = 0; sx = ""
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
        if (c == "E" || c == "D") {
            expd = (c == "D"); expl = 1; i++
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
    # VALTYPE: the type the reader gives the number (VAL returns it).  VAL
    # enters at 0E65H, which flags the value DOUBLE before the first digit
    # (0E68H CALL 0AECH), so VAL("1") is a double: VAL("1")/3 prints 16
    # digits and VAL(".1")=.1 is false, as on the machine.  Only an E
    # exponent or a "!" drops it to single (0EA4H/0EF6H reach 0EFBH with
    # Z, the convert-to-single call); "#" and a D exponent keep it.  Until
    # 2026-09-27 VAL typed its number as a literal (the 2026-09-26 audit,
    # M-11).  The 0E6CH entry (READ, INPUT) starts at integer and types by
    # tk_number's rule (p50): I while there is no point or exponent and
    # it fits 15 bits, D from the eighth significant digit or a D exponent,
    # S for an E exponent at any length.
    # At both entries an E exponent or a "!" CONVERTS the value to single
    # (0EFFH CALL Z,0AB1H), so READ or INPUT of 0.1E0, .1E or 0.1! into A#
    # stores .1000000014901161 and 1.23456789E0 stores 1.234567880630493,
    # where a plain 0.1 stays .1.  Until 2026-10-04 the value kept every
    # digit and an E item of eight digits was double (the 2026-09-30
    # audit, BM-3).
    if (sx != "") VALTYPE = sx
    else if (expl && !expd) VALTYPE = "S"
    else if (dp) VALTYPE = "D"
    else {
        sig = m; sub(/\./, "", sig); sub(/^0+/, "", sig)
        if (isint && !dot && ex == "" && !expd && m + 0 <= 32767 && m != "") VALTYPE = "I"
        else if (expd || length(sig) > 7) VALTYPE = "D"
        else VALTYPE = "S"
    }
    if (m == "" || m == ".") m = "0"
    x = numconv(sg m "E" exs (ex == "" ? "0" : ex))
    if (!E && VALTYPE == "S" && (sx == "S" || expl)) x = sround(x)
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
# Every caller checks E before it stores: nothing is assigned.  The
# limit is the type's own (VALTYPE, set by valnum just before the call):
# a D-exponent or # item overflows at the double's limit (p10 DMAX; the
# 2026-09-26 audit, L-24).
function numconv(s,   x, lim) {
    sub(/[Dd]/, "E", s)
    x = s + 0
    lim = (VALTYPE == "D") ? DMAX : FMAX
    if (x >= lim || x <= -lim) { raise(6); return 0 }
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

# A single-precision intermediate: rounded to 24 bits, and 0 below the
# smallest exponent (0793H), as every step of a ROM float routine leaves it.
function sfl(x) {
    if (x < FMIN && x > -FMIN) return 0
    return sround(x)
}

# SIN, COS and TAN as the ROM computes them (1541H-15BAH), step for step
# in single precision.  Since 2026-09-27 (the 2026-09-26 audit, M-12);
# until then they were the host's libm on the raw argument, which gave
# COS(90*.01745329) = 1.94707E-07 where the machine gives 0, and TAN of
# it 5.13592E+06 where the Model III manual (p.239) promises ?/0.
#   SIN (1547H): t = x / 2 pi (08A2H); f = t - INT(t) (0B40H, 0713H), the
#   turn's fraction in [0,1); d = .25 - f (0710H).  d >= 0 (the first
#   quarter, 156DH): the argument is .25 - d; else e = d + .5 (0708H) and
#   the argument is e - .25 for e >= 0, -(e + .25) below (1577H-1584H):
#   a value in [-.25, .25] whose sine is SIN(x).  Then the series at 149AH
#   (Horner in a^2 over the five coefficients at 1594H, times a at 0C32H).
#   COS (1541H) is SIN(x + pi/2).  TAN (15A8H) is SIN(x)/COS(x) through
#   the divider at 08A2H, whose zero test (08A5H) is the ?/0.
# Every product, sum and quotient is rounded as 0796H rounds, so a
# quarter turn typed as 90*.01745329 or 1.5707963 reduces to EXACTLY 0
# and COS of it is 0; the one departure a bit-exact machine could show is
# a last-place difference where the ROM's adder drops bits below its
# guard byte before rounding.
function rom_sin(x,   t, f, d, e, a, a2, s) {
    t = sfl(x / TWOPI)
    f = sfl(t - bfloor(t))
    d = sfl(0.25 - f)
    if (d >= 0) a = sfl(0.25 - d)
    else {
        e = sfl(d + 0.5)
        a = (e >= 0) ? sfl(e - 0.25) : -sfl(e + 0.25)
    }
    a2 = sfl(a * a)
    s = sfl(sfl(SINC1 * a2) + SINC2)
    s = sfl(sfl(s * a2) + SINC3)
    s = sfl(sfl(s * a2) + SINC4)
    s = sfl(sfl(s * a2) + SINC5)
    return sfl(s * a)
}

function rom_cos(x) { return rom_sin(sfl(x + HALFPI)) }

function rom_tan(x,   s, c) {
    s = rom_sin(x); c = rom_cos(x)
    if (c == 0) { raise(11); return 0 }
    s = frange(s / c); if (E) return 0
    return sround(s)
}

# The range of a single or double result: past the type's limit it is
# ?OV (0796H's overflow, 07B2H; the double normalizer carries the same
# way); below 2^-128 the exponent byte runs out and the result is ZERO,
# silently (0793H JR NC,0778H).  t is "D" for a double result (p10
# DMAX; the 2026-09-26 audit, L-24), anything else is the single limit.
# Returns the value, with E set for ?OV.  Since 2026-09-26 (M-10's
# underflow half).
function frange(x, t,   lim) {
    lim = (t == "D") ? DMAX : FMAX
    if (x >= lim || x <= -lim) { raise(6); return 0 }
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
# A DOUBLE is a single first: CINT (0A7FH) calls CSNG's tail for one
# (0A87H CALL NC,0AB9H), which rounds the fourth mantissa byte half up
# (0796H), and only then converts to 16 bits.  So CINT(2.9999999#) is
# 3 and CINT(32767.9999999#) is ?OV, as on the machine (ROM bug 5a's
# mechanism; the 2026-09-26 audit, L-8).  sround leaves a single or an
# integer as it is.  Since 2026-09-27.
function to16(x,   r) {
    r = bfloor(sround(x))
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

# ---- host shell gates ---------------------------------------------------------
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
# A CHR$(0) in a name is refused outright: gawk hands the name to open()
# and to sh as a C string, so both see it cut at the NUL -- "-" CHR$(0) is
# stdin, "//dev/zero" CHR$(0) the device -- while every test here sees the
# whole name (the 2026-09-26 audit, H-1).
function host_special(f) {
    return index(f, sprintf("%c", 0)) > 0 || f == "-" || f ~ /^\/inet[46]?\// || f ~ /^\/dev\//
}

# A file name a PROGRAM WRITES, KILLs or renames stays under the working
# directory: an absolute path, a drive-letter root or a `..` path
# component is refused (?FD at the caller), so a listing cannot append to
# a startup file or delete one outside the directory it was started in
# (the 2026-09-26 audit, R-9; measured 2026-09-28: no listing in the
# corpus names such a path -- the TRSDOS form NAME/EXT:d is an ordinary
# relative path and stays allowed).  READS go anywhere (OPEN "I", LOAD,
# RUN "f", MERGE, CLOAD, SYSTEM; ruled 2026-09-30): reading damages
# nothing, and programs written for this interpreter point a data path
# at an absolute directory (interactiveFiction_BASIC's test harnesses
# aim its SP$ at a story copy elsewhere; v2.1.1 refused them).  Only
# a program's own statement is confined: a name typed at READY is the
# user's (CK "I"), and the batch program's path is the user's command
# line (no statement context).  The name is then followed to where it
# RESOLVES (host_outside): a symbolic link already in the directory, to a
# file, a directory or nothing yet, cannot carry the write or the KILL out
# (the 2026-09-30 audit, BL-37).  Native Windows checks the spelling only.
function host_escape(f) {
    if (CK == "" || CK == "I") return 0
    if (f ~ /^[\/\\]/ || f ~ /^[A-Za-z]:[\/\\]/) return 1
    if (f ~ /(^|[\/\\])\.\.([\/\\]|$)/) return 1
    return WINNATIVE ? 0 : host_outside(f)
}

# 1 when f, followed through every symbolic link (the last component's
# chain, then its directory's physical path), lands outside the working
# directory's physical path.  One shell-out.  It fails closed: a link loop,
# an unreadable link or a directory that cannot be entered is "outside",
# and the caller's ?FD is what such a name would have earned anyway.
function host_outside(f) {
    return system("c=$(pwd -P) && p=" shq(f) " && n=0 && " \
        "while [ -L \"$p\" ]; do n=$((n+1)); [ $n -gt 40 ] && exit 0; " \
        "t=$(readlink -- \"$p\") || exit 0; " \
        "case $t in /*) p=$t ;; *) p=$(dirname -- \"$p\")/$t ;; esac; done; " \
        "r=$(cd -- \"$(dirname -- \"$p\")\" 2>/dev/null && pwd -P) || exit 0; " \
        "case $r in \"$c\"|\"$c\"/*) exit 1 ;; esac; exit 0") == 0
}

# what f names: "f" a regular file (through a symbolic link), "x" anything
# else that is there (a directory, a device, a FIFO, a socket, a dangling
# link), "" nothing.  One shell-out; cmd.exe knows only "is it there".
# It fails closed: a probe that answers nothing is "x", never "nothing
# there", and a name holding a NUL is "x" before any probe (H-1, 2026-09-26).
function host_kind(f,   cmd, s, r) {
    if (index(f, sprintf("%c", 0))) return "x"
    if (WINNATIVE) {
        if (f ~ /"/) return "x"
        return system("if exist \"" f "\" (exit 0) else (exit 1)") == 0 ? "f" : ""
    }
    cmd = "if [ -f " shq(f) " ]; then echo f; elif [ -e " shq(f) " ] || [ -L " shq(f) " ]; then echo x; else echo n; fi"
    s = ""
    r = (cmd | getline s)
    close(cmd)
    if (r <= 0 || (s != "f" && s != "n")) return "x"
    return s == "f" ? "f" : ""
}

function host_writable(f) {
    if (host_special(f) || host_escape(f)) return 0
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
    if (host_special(f) || host_escape(f)) return 0
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
