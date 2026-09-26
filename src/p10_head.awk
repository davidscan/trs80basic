#!/usr/bin/env gawk -f
# ===========================================================================
# trs80basic.awk -- TRS-80 Model I LEVEL II BASIC interpreter in GNU awk
#
# Run:   gawk -f trs80basic.awk        (or ./trs80basic.awk if executable)
# Exit:  BYE   (restores terminal; if killed abnormally, run: stty sane)
# BREAK: Ctrl-C  (stops a running program: "BREAK IN nnnn"; CONT resumes)
#
# Requires: GNU awk >= 5.0 run with -b (./basic does), a VT100/ANSI terminal
# >= 64x20 that displays UTF-8.
# Uses stty for raw keyboard input, and dd/od for the one blocking read
# (permitted external utilities; the polls are gawk's own, p30 kb_fill_tty).
# The simulated TRS-80 display is 64x16 at terminal rows 1-16; display
# memory is 15360..16383; PEEK/POKE/SET/RESET/POINT/PRINT@/CHR$ all share
# the internal screen buffer.  Semigraphics 128-191 render as Unicode
# "sextant" 2x3 block mosaics (exact bit-for-bit); set env TRS80_GFX=braille
# or TRS80_GFX=ascii for fallback renderings if your font lacks sextants.
#
# Batch mode (not part of Level II): given a filename argument the interpreter
# LOADs and RUNs it non-interactively, then exits -- 0 clean, 1 uncaught BASIC
# error, 2 bad invocation.  stdin is reserved for the program's own INPUT/GET;
# BASIC error messages go to stderr.  See `basic --help` and p45_batch.awk.
#
# Debug/testing aids (not part of Level II): with no tty (piped stdin) the
# interpreter reads commands line-by-line from stdin and ANSI positioning
# auto-disables (plain teletype output; --screen keeps the grid, TRS80_DUMB=1
# forces plain even on a tty); immediate command @DUMP prints the 16
# screen-buffer rows.
#
# See RELEASE_NOTES.md for the full command list, omissions and quirks.
#
# Copyright (c) 2026 David Forbis.  Licensed under the GNU General Public
# License v3.0; see the LICENSE file.  No warranty.
# ===========================================================================

BEGIN {
    CONVFMT = "%.17g"; OFMT = "%.17g"
    # native-Windows gate: there system()/pipes go to cmd.exe, no Unix
    # userland (see WINDOWS.md).  COMSPEC is never set on Unix, and Git
    # Bash/MSYS/WSL all set SHELL, so both conditions must hold.
    # TRS80_WINNATIVE=0/1 overrides the probe (branch-selection testing).
    if ("TRS80_WINNATIVE" in ENVIRON) WINNATIVE = ENVIRON["TRS80_WINNATIVE"] + 0
    else WINNATIVE = ("COMSPEC" in ENVIRON && !("SHELL" in ENVIRON))
    if (!parse_args()) { usage("/dev/stderr"); exit 2 }
    if (OPT_HELP) { usage(""); exit 0 }
    if (SEEDED) srand(OPT_SEED); else srand()
    # MUST precede the MEM SIZE? prompt below: that bound reads RAMTOP,
    # and an uninitialised RAMTOP would compare as "" in gawk, silently
    # rejecting every legal answer.  Keep both in this BEGIN block.
    init_tables()
    if (BATCH && !OPT_SCREEN) DUMB = 1      # batch output is plain by default
    if (OPT_SCREEN) DUMB = 0
    kb_init()
    if (!TTYIN && !OPT_SCREEN) DUMB = 1     # no tty: stream plainly (--screen keeps the grid)
    t_init()
    if (BATCH) {
        if (OPT_MEMSIZE) { HIMEM = OPT_MEMSIZE; SSP = HIMEM }
        RC = batch_main()
        fio_closeall()
        t_done()
        exit RC
    }
    s_cls()
    # ROM 1.3's messages (0105H, 010EH: "MEM SIZE" and "R/S L2 BASIC",
    # shortened from "MEMORY SIZE" and "RADIO SHACK LEVEL II BASIC" to make
    # room for its keyboard debounce routine).  The target revision is 1.3,
    # the last Model I ROM (February 1980), ruled 2026-09-25.
    s_puts("MEM SIZE? "); sync_cursor()
    if (OPT_MEMSIZE) { BOOTMS = OPT_MEMSIZE ""; s_puts(BOOTMS) }   # --memsize answered it
    else BOOTMS = rl_read()
    # honored since 2026-08-14 (p75): a numeric answer becomes HIMEM -- the
    # fence string space allocates below, NOT the top of RAM.  Memory above
    # it stays present, readable and writable, which is the entire point of
    # reserving it: the classic idiom loads a machine-language routine into
    # exactly that region.  PEEK(16561)+256*PEEK(16562) reports it (the
    # classic idiom).  ENTER keeps the full 65535.
    if (BOOTMS ~ /^[ \t]*[0-9]+[ \t]*$/ && BOOTMS + 0 >= 17280 && BOOTMS + 0 <= RAMTOP) {
        HIMEM = BOOTMS + 0; SSP = HIMEM
    }
    s_nl()
    s_puts("R/S L2 BASIC"); s_nl()
    show_banner()
    # --clear N: the CLEAR N a period user typed at the first READY (p45).
    # Shown as typed, so the transcript says what happened; its error, if
    # any, is CLEAR's own and READY follows as at the keyboard.
    if (OPT_CLEAR >= 0) {
        s_fresh(); s_puts("READY"); s_nl()
        s_putc(62); s_puts("CLEAR " OPT_CLEAR); s_nl()
        exec_immediate("CLEAR " OPT_CLEAR)
    }
    repl()
    fio_closeall()                          # flush any open files on exit
    t_done()
    exit 0
}

function init_tables(   i, c, m, n) {
    # character code <-> single-char string tables (byte-value semantics)
    for (i = 0; i < 256; i++) { c = sprintf("%c", i); CHR[i] = c; ORD[c] = i }
    # BYTES, NOT CHARACTERS.  A BASIC string is a byte string -- CHR$(200)
    # is one byte, and a loaded file may carry raw bytes 80H-FFH (graphics,
    # packed machine code).  That holds only under gawk -b: in a UTF-8
    # locale without it sprintf("%c", 200) is the character U+00C8 (two
    # bytes on the wire), a raw C8 read from a file is an "invalid" byte
    # that matches nothing in ORD[], and ASC/PEEK/the program image disagree
    # about the same byte with no error.  ./basic passes -b; warn once when
    # someone runs the file directly without it (seam audit 2026-09-10).
    # The probe is a literal two-byte sequence: length() counts CHARACTERS
    # in a UTF-8 locale (so it reads 1 there) and bytes under -b (2).
    if (length("\303\210") != 2)
        printf "trs80basic: run it as ./basic or gawk -b -- without -b, bytes above 127 in files are corrupted\n" > "/dev/stderr"
    # EXT: SET(x,y,c) color codes 0-8 (the CoCo Color BASIC palette) ->
    # xterm-256 foreground numbers.  0 black, 1 green, 2 yellow, 3 blue,
    # 4 red, 5 buff, 6 cyan, 7 magenta, 8 orange.
    split("16 40 226 21 196 230 51 201 208", m, " ")
    for (i = 0; i <= 8; i++) GCANSI[i] = m[i + 1]
    # LPRINT/LLIST printer stream: append to $TRS80_PRINTER, or discard when
    # unset (the hardware analog: printing into no attached printer)
    LPFILE = ("TRS80_PRINTER" in ENVIRON) ? ENVIRON["TRS80_PRINTER"] : ""
    # a path gawk could not append to would be a fatal at the first
    # LPRINT, losing the program: probed once here, and LPRINT/LLIST are
    # ?FD instead (lp_refuse, p80; the 2026-09-23 audit, M-1)
    LPBAD = (LPFILE != "" && !host_appendable(LPFILE))
    LPCOL = 0
    # the SYSTEM VARIABLE WINDOW (p75 sv_*): ROM RAM cells period listings
    # PEEK and POKE, served from live state.  CURCH = the cursor character
    # (4022H; the ROM's default block), LPPAGE/LPLINES = printer lines per
    # page + 1 and lines printed so far (4028H/4029H), AUTOLINE/AUTOINC/
    # AUTOREQ = AUTO's line, increment and "start AUTO at the next prompt"
    # (40E1H-40E5H).
    CURCH = 176; LPPAGE = 67; LPLINES = 0
    # CURON = the cursor-on flag CHR$(14)/CHR$(15) sets (Barden, Programming
    # Techniques for Level II BASIC, ch. 3).  Off while a program prints --
    # the machine shows the cursor when it waits for a key, which is why
    # listings that want one during output turn it on.  CURVIS = what the
    # terminal is currently showing, so sync_cursor only writes on a change.
    CURON = 0; CURVIS = 1
    AUTOLINE = 10; AUTOINC = 10; AUTOREQ = 0; AUTOON = 0
    sv_init()
    # EXT gate: syntax that valid Level II rejects but damaged OCR listings
    # can plausibly spell (bare/prompt-only INPUT, DIM of a scalar) is only
    # accepted when this is on -- `ext on` metacommand or TRS80_EXT=1 --
    # so the interpreter stays a strict ?SN oracle by default.
    EXTON = ("TRS80_EXT" in ENVIRON && ENVIRON["TRS80_EXT"] != "" && ENVIRON["TRS80_EXT"] != "0")
    # TRS80_VARNAMES=2: the ROM's two-character variable names (SUM is SU),
    # applied by the tokenizer (vn_cut, p50).  Unset -- the default, the
    # user's 2026-08-07 ruling -- every character of a name counts.
    VARNAMES2 = (ENVIRON["TRS80_VARNAMES"] == "2")
    # error codes 1..23 in the ROM's order (its table ends there: NERRC),
    # then the file errors at Disk BASIC's own numbers (Model III Disk
    # System manual p.156), sparse: 51 FO field overflow, 53 BN bad file
    # number (a channel out of range, and one not open -- Microsoft's one
    # meaning for it), 54 FF file not found, 55 BM bad file mode, 63 IE
    # input past end, 64 BR bad record number, 70 AO (file access: a busy
    # channel re-opened, KILL of an open file).  They were 24-31 here
    # until 2026-09-21; period listings test ERR against the machine's
    # numbers (ERR=106 for "file not found", 450 comparisons in the corpus)
    # and never against 24-31, so the renumbering wakes their handlers up.
    NERRC = split("NF SN RG OD FC OV OM UL BS DD /0 ID TM OS LS ST CN NR RW UE MO FD L3", ERRC, " ")
    ERRC[51] = "FO"; ERRC[53] = "BN"; ERRC[54] = "FF"; ERRC[55] = "BM"
    ERRC[63] = "IE"; ERRC[64] = "BR"; ERRC[70] = "AO"
    # the VARPTR string-space tables (p75) are typed as arrays HERE: gawk
    # types an untouched name by its first use, and before the first RUN
    # (which is what calls sp_reset) that use was `length(VPDATA)` in the
    # assignment path -- a scalar context -- so VARPTR typed at the READY
    # prompt was a fatal "attempt to use scalar VPDATA as an array" that
    # killed the session (found 2026-09-21)
    delete VPDATA; delete VPDESC; delete VPCAP; delete SPK; delete SPT; delete SPV
    # display glyphs
    GFXMODE = ENVIRON["TRS80_GFX"]
    if (GFXMODE != "braille" && GFXMODE != "ascii") GFXMODE = "sextant"
    for (i = 0; i < 32; i++) GL[i] = " "
    for (i = 32; i < 127; i++) GL[i] = CHR[i]
    GL[127] = " "
    for (i = 128; i < 192; i++) GL[i] = sext_glyph(i - 128)
    for (i = 192; i < 256; i++) GL[i] = GL[i - 64]   # Model I bit-6 aliasing
    # Model III character sets for codes 192-255 (CHR$(21)/CHR$(22), p20):
    # the special set (card suits, Greek, math) and the halfwidth-Katakana
    # alternate set.  Unicode transcription from George Phillips's
    # m3unicode.c (48k.ca/fonts.html); the seven 0xE0xx entries exist only
    # in the Kreative Korp TRS-80 fonts' private-use area and need those
    # fonts to render.  Default display stays Model I bit-6 aliasing.
    n = split("2660 2665 2666 2663 263a 2639 2264 2265 " \
              "3b1 3b2 3b3 3b4 3b5 3b6 3b7 3b8 " \
              "3b9 3ba 3bb 3bc 3bd 3be 3bf 3c0 " \
              "3c1 3c3 3c4 3c5 3c6 3c7 3c8 3c9 " \
              "2126 221a f7 2211 2248 2206 2307 2260 " \
              "2301 e0e9 237e 221e 2713 a7 2318 a9 " \
              "a4 b6 a2 ae e0f4 e0f5 e0f6 211e " \
              "2105 2642 2640 e0fb e0fc e0fd e0fe 2302", m, " ")
    for (i = 0; i < 64; i++) GLSPEC[i] = utf8(strtonum("0x" m[i + 1]))
    GLKANA[0] = utf8(0xa5)                           # C0 = Yen sign
    for (i = 1; i < 64; i++) GLKANA[i] = utf8(0xff60 + i)
    M3MODE = 0; M3KANA = 0; WIDE = 0; LATCH = 0
    # "0" means off, as it does for TRS80_EXT above and TRS80_KBPROTO in
    # p30: TRS80_DUMB=0 used to turn plain mode ON, because any non-empty
    # value counted (the 2026-09-19 audit, L-6).  Unset and empty are both off.
    DUMB = ("TRS80_DUMB" in ENVIRON && ENVIRON["TRS80_DUMB"] != "" && ENVIRON["TRS80_DUMB"] != "0")
    # misc state
    # the ROM marks the Input Phase in its current-line cell 40A2H with
    # FFFFH (1A36), so a typed statement and a real line 0 are distinct
    DIRECTLN = 65535
    # The single-precision overflow threshold.  MBF's largest value is
    # (1 - 2^-24) * 2^127 = 1.70141E38, and the ROM's normalizer rounds the
    # guard byte half up (0796H), so anything at or above (1 - 2^-25) * 2^127
    # carries into an exponent byte of 256: ?OV at 07B2H.  Until 2026-09-25
    # the limit was 1.7E38, so PRINT 1.70141E38 was ?OV (the 2026-09-23
    # audit, M-10).  The p60 operators, a literal, numconv (p90) and the
    # MBF encoder (p85) all test against it.
    FMAX = 2^127 - 2^102
    FMIN = 2^-128                           # the smallest exponent byte (1) is 2^-128; below it a result is 0 (0793H)
    LN2 = log(2)
    CLN = DIRECTLN
    CUR = 0; VCOL = 0; NL = 0; LASTLN = 0; DATADIRTY = 1; NDATA = 0; DP = 1
    FSN = 0; GSN = 0; CONTOK = 0; TRACE = 0
    EHANDLER = 0; INHANDLER = 0; ERRV = 0; ERLV = 0
    E = 0; RLCANCEL = 0; EOFQUIT = 0; PENDBRK = 0
    BRKCTR = 0; BRKEVERY = 400
    FNLIST = " ABS INT FIX SGN SQR SIN COS TAN ATN LOG EXP RND CINT CSNG CDBL PEEK POS FRE LEN ASC VAL CHR$ STR$ STRING$ LEFT$ RIGHT$ MID$ INSTR POINT TAB EOF LOF LOC MKI$ MKS$ MKD$ CVI CVS CVD INP "
    # execution throttle: emulate a target Z80 clock (MHz).  A statement is
    # charged CYCPERSTMT "cycles"; delay = CYCPERSTMT/(MHz*1e6) seconds, owed
    # into DACC and paid in slices by thr_wait (execloop calls it).  MHz<=0
    # => full speed.  Tune the feel via TRS80_MHZ / speed.
    CYCPERSTMT = 1000; DACC = 0; THROTTLE_D = 0; TDUE = 0
    # sleep() comes with gawk's time extension, as gettimeofday() does
    # (km_init's KMCLOCK); reached by an indirect call for the same reason
    THRSLEEP = ("sleep" in FUNCTAB) ? "sleep" : ""
    set_speed(ENVIRON["TRS80_MHZ"] + 0)
    # ROM RND seed (40AA-40ACH): boot writes only the middle byte, like the
    # real ROM's R-register init -- gawk rand() is the entropy source, so
    # --seed makes the whole RND sequence repeatable (rnd_* in p90).
    RNDSEED = 0; rnd_setmid(int(rand() * 256))
    # memory model (p75): RAMTOP is the machine's PHYSICAL top -- a 48K
    # Model I, so FFFFH; above it memory is genuinely absent (255 on read,
    # writes discarded).  HIMEM is the MEM SIZE? answer, at or below it.
    # Between HIMEM and RAMTOP is PROTECTED RAM: present, readable and
    # writable, simply never allocated by string space.  Also a stale flag
    # for the PEEKable tokenized program image, and the VARPTR string-space
    # pointer, which descends from HIMEM.
    RAMTOP = 65535; HIMEM = RAMTOP; PROGDIRTY = 1; PMEND = 0; SSP = HIMEM
    # 400CH (16396): the DOS entry vector.  On a cassette Level II machine
    # it holds a RET (201); under Disk BASIC it holds a jump into DOS, so
    # listings probe it -- `IF PEEK(16396)=201` -- to pick their cassette
    # branch.  This IS a cassette Level II, so 201 is the honest answer.
    # Answering 255 (absent RAM) sent every such listing down its DISK
    # branch and straight into CMD, which is not implemented here: 88
    # rescued listings use the probe, and 29 sit in blocked/cmd/ for no
    # other reason (measured -- Z80 sub-project FINDING 16).  Seeded into
    # MEM rather than special-cased in dopeek so POKE 16396 still works.
    MEM[16396] = 201
    # 401E/401FH and 4026/4027H: the video and printer DRIVER VECTORS, seeded
    # with the ROM's own drivers (0458H = 88,4 and 058DH = 141,5) so a
    # listing that saves them to restore later reads the real values.
    # POKEing them re-routes output (dv_update, p80): the period "send the
    # screen to the printer" and "send LPRINT to the screen" idioms.
    MEM[16414] = 88; MEM[16415] = 4; MEM[16422] = 141; MEM[16423] = 5
    MEM[16445] = 0      # 403DH, the ROM's image of the port-FF bits: bit 3 is its 32-column print flag (s_putc, p20)
    dv_update()
    init_man()
}

# recompute the per-statement throttle delay from a target clock in MHz
function set_speed(mhz) {
    if (WINNATIVE) mhz = 0      # cmd.exe has no sub-second sleep: throttle off
    if ((mhz > 0 ? mhz : 0) != THROTTLE_MHZ) z80_recycle()   # the clock travels on HELLO (p77)
    THROTTLE_MHZ = (mhz > 0 ? mhz : 0)
    THROTTLE_D = (THROTTLE_MHZ > 0 ? CYCPERSTMT / (THROTTLE_MHZ * 1000000) : 0)
    DACC = 0; TDUE = 0
}

# Pay the time the statements since the last call owe (DACC seconds).
# With a clock (the launcher loads gawk's time extension: KMCLOCK, p30)
# the pacing is CLOSED-LOOP: TDUE is the wall-clock moment the emulated
# machine would reach this statement, and the wait is whatever of it is
# still ahead -- so the sleep's own overshoot, the statements' own cost
# and the fork below no longer add up.  Until 2026-09-26 every slice
# forked `sleep` for the whole of DACC, whatever the time already spent,
# and a loop ran 40% slow at 1.77 MHz (the 2026-09-23 audit, L-13); with
# the extension's sleep() nothing is forked.  A slice is 10 ms with the
# clock, 30 ms without: the open loop keeps its fork count down.
#   Falling BEHIND by more than a slice restarts the clock here and
# forgives the debt: the machine was waiting for a key (INPUT), or the
# host could not keep up, and either way the program must not race at
# full speed afterwards to catch up.  Without a clock (a gawk without the
# extension) the open loop stays: sleep the slice, as before.
function thr_wait(   now, ahead, f) {
    if (KMCLOCK == "") { system("sleep " DACC); DACC = 0; return }
    now = km_now()
    if (TDUE < now - THR_SLICE) TDUE = now
    TDUE += DACC; DACC = 0
    ahead = TDUE - now
    if (ahead <= 0) return
    if (THRSLEEP != "") { f = THRSLEEP; @f(ahead) } else system("sleep " ahead)
}

# load help text for the `man` metacommand from an editable text file
# (support/manpages.txt, or the file named by TRS80_MANFILE).  Format: a line
# starting with ':' lists one or more keywords (space/comma-separated) that all
# share the body running to the next ':' line; '#' lines and text before the
# first ':' are ignored.  A missing file just leaves the table empty (man then
# reports "no manual entries loaded") -- everything else works.  MANN counts
# loaded keywords.
function init_man(   fn, line, r, keys, nk, hdr, body, started) {
    MANN = 0; started = 0
    fn = ENVIRON["TRS80_MANFILE"]
    if (fn == "") fn = "support/manpages.txt"
    while ((r = (getline line < fn)) > 0) {
        sub(/\r$/, "", line)
        if (substr(line, 1, 1) == "#") continue
        if (substr(line, 1, 1) == ":") {
            if (started) man_commit(keys, nk, body)
            hdr = substr(line, 2)
            sub(/^[ \t]+/, "", hdr); sub(/[ \t]+$/, "", hdr)
            nk = split(hdr, keys, /[ \t,]+/)
            body = ""; started = 1
            continue
        }
        if (!started) continue
        body = (body == "" ? line : body "\n" line)
    }
    close(fn)
    if (started) man_commit(keys, nk, body)
}

# store one man entry (trailing blank lines trimmed) under each of its keywords
function man_commit(keys, nk, body,   i, k) {
    sub(/\n+$/, "", body)
    for (i = 1; i <= nk; i++) {
        k = toupper(keys[i])
        if (k != "") { MANTXT[k] = body; MANN++ }
    }
}

# TRS-80 semigraphics bitmask m (0..63): TL=1 TR=2 ML=4 MR=8 BL=16 BR=32
# Encode a Unicode code point as UTF-8 BYTES.  The interpreter runs under
# gawk -b (bytes, not locale characters -- see the launcher), where
# sprintf("%c", cp) can only produce a single byte, so terminal glyphs are
# assembled by hand.  Locale-independent: identical output with or without -b.
function utf8(cp) {
    if (cp < 0x80)    return sprintf("%c", cp)
    if (cp < 0x800)   return sprintf("%c%c", 0xC0 + int(cp / 64), 0x80 + cp % 64)
    if (cp < 0x10000) return sprintf("%c%c%c", 0xE0 + int(cp / 4096), 0x80 + int(cp / 64) % 64, 0x80 + cp % 64)
    return sprintf("%c%c%c%c", 0xF0 + int(cp / 262144), 0x80 + int(cp / 4096) % 64, 0x80 + int(cp / 64) % 64, 0x80 + cp % 64)
}

function sext_glyph(m,   b, n) {
    if (GFXMODE == "ascii") {
        n = (m%2) + int(m/2)%2 + int(m/4)%2 + int(m/8)%2 + int(m/16)%2 + int(m/32)
        return substr(" ..:+##@", n + 1, 1)
    }
    if (GFXMODE == "braille") {
        b = 0x2800
        if (m %  2 >= 1) b += 1     # TL -> dot1
        if (int(m/2) % 2)  b += 8   # TR -> dot4
        if (int(m/4) % 2)  b += 2   # ML -> dot2
        if (int(m/8) % 2)  b += 16  # MR -> dot5
        if (int(m/16) % 2) b += 4   # BL -> dot3
        if (int(m/32))     b += 32  # BR -> dot6
        return utf8(b)
    }
    # sextant mode: Unicode "Symbols for Legacy Computing" (bit order matches)
    if (m == 0)  return " "
    if (m == 63) return utf8(0x2588)            # full block
    if (m == 21) return utf8(0x258C)            # left half
    if (m == 42) return utf8(0x2590)            # right half
    return utf8(0x1FB00 + m - 1 - (m > 21 ? 1 : 0) - (m > 42 ? 1 : 0))
}
