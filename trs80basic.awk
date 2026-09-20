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
    # MUST precede the MEMORY SIZE? prompt below: that bound reads RAMTOP,
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
    s_puts("MEMORY SIZE? "); sync_cursor()
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
    s_puts("RADIO SHACK LEVEL II BASIC"); s_nl()
    show_banner()
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
    # error codes 1..23 (LEVEL II order), 24..31 (Disk BASIC file I/O):
    # BN bad file number, NO file not open, AO file already open, IE input
    # past end, BM bad file mode, FF file not found, BR bad record number,
    # FO field overflow
    NERRC = split("NF SN RG OD FC OV OM UL BS DD /0 ID TM OS LS ST CN NR RW UE MO FD L3 BN NO AO IE BM FF BR FO", ERRC, " ")
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
    DUMB = (ENVIRON["TRS80_DUMB"] != "")
    # misc state
    CUR = 0; NL = 0; LASTLN = 0; DATADIRTY = 1; NDATA = 0; DP = 1
    FSN = 0; GSN = 0; CONTOK = 0; TRACE = 0
    EHANDLER = 0; INHANDLER = 0; ERRV = 0; ERLV = 0
    E = 0; RLCANCEL = 0; EOFQUIT = 0; PENDBRK = 0
    BRKCTR = 0; BRKEVERY = 400
    FNLIST = " ABS INT FIX SGN SQR SIN COS TAN ATN LOG EXP RND CINT CSNG CDBL PEEK POS FRE LEN ASC VAL CHR$ STR$ STRING$ LEFT$ RIGHT$ MID$ INSTR POINT TAB EOF LOF LOC MKI$ MKS$ MKD$ CVI CVS CVD INP "
    # execution throttle: emulate a target Z80 clock (MHz).  A statement is
    # charged CYCPERSTMT "cycles"; delay = CYCPERSTMT/(MHz*1e6) seconds, batched
    # (see execloop).  MHz<=0 => full speed.  Tune the feel via TRS80_MHZ / speed.
    CYCPERSTMT = 1000; DACC = 0; THROTTLE_D = 0
    set_speed(ENVIRON["TRS80_MHZ"] + 0)
    # ROM RND seed (40AA-40ACH): boot writes only the middle byte, like the
    # real ROM's R-register init -- gawk rand() is the entropy source, so
    # --seed makes the whole RND sequence repeatable (rnd_* in p90).
    RNDSEED = 0; rnd_setmid(int(rand() * 256))
    # memory model (p75): RAMTOP is the machine's PHYSICAL top -- a 48K
    # Model I, so FFFFH; above it memory is genuinely absent (255 on read,
    # writes discarded).  HIMEM is the MEMORY SIZE? answer, at or below it.
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
    DACC = 0
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
# ===================== terminal + simulated 64x16 screen =====================

function t_init(   i) {
    for (i = 0; i < 1024; i++) SCR[i] = 32
    if (DUMB) return
    # grid mode lives on the ALTERNATE screen (like vim/less): terminals
    # forward PgUp/PgDn to the app there instead of scrolling their own
    # scrollback, the grid never pollutes scrollback, and the user's shell
    # content restores on exit.  Fullscreen/DUMB stays on the primary
    # screen, where terminal scrollback is the point.
    printf "\033[?1049h"; ALTSCR = 1
    printf "\033[H\033[2J"
    t_sep()
}

function t_sep(   i, s) {
    if (DUMB) return
    s = ""
    for (i = 0; i < 64; i++) s = s "-"
    printf "\033[17;1H\033[2m%s\033[0m", s
}

function t_done() {
    kb_restore()
    if (!DUMB) { printf "\033[?25h"; CURVIS = 1 }  # the shell gets its cursor back, whoever hid it
    if (ALTSCR) { printf "\033[?1049l\033[0m"; ALTSCR = 0 }
    # park the shell prompt at the BOTTOM of the terminal (999 clamps to the
    # last row) so it doesn't land inside the below-grid help/man text
    else if (!DUMB) printf "\033[999;1H\033[0m\n"
    fflush()
}

# DUMB doubles as the runtime-toggleable "fullscreen" flag (see the
# fullscreen/trs80screen metacommands in p40_repl.awk), not just the
# TRS80_DUMB startup env var.
function t_leave_grid() {
    # back to the primary screen: the pre-grid shell content returns and
    # fullscreen streaming continues below it, with scrollback available
    printf "\033[?25h"; CURVIS = 1        # streamed output never hides it
    if (ALTSCR) { printf "\033[?1049l\033[0m"; ALTSCR = 0 }
    else printf "\033[18;1H\033[0m\n"
    fflush()
}

function t_repaint() {
    if (!ALTSCR) { printf "\033[?1049h"; ALTSCR = 1 }
    printf "\033[H\033[2J"
    t_sep()
    redraw_all()
    if (PGRN > 0) pgr_draw()              # restore the below-grid window
    sync_cursor()
}

# render a help block (newline-separated text) below the 64x16 grid.
# Overwrites any previous block (no scrolling); rows 1-17 stay untouched in
# grid mode.  Capped at 30 lines.  Raw-mode-safe (explicit CR on a tty).
function t_man(txt,   a, n, i) {
    n = split(txt, a, "\n")
    if (DUMB) {
        # streaming to a scrolling terminal: no cap
        for (i = 1; i <= n; i++) printf "%s%s", a[i], (TTYIN ? "\r\n" : "\n")
        fflush()
        return
    }
    # grid mode: retain the whole text and render a window of it -- content
    # taller than the region pages with PgUp/PgDn (or Ctrl-B/F)
    delete PGRL
    PGRN = n
    for (i = 1; i <= n; i++) PGRL[i] = a[i]
    PGRTOP = 1
    pgr_draw()
}

# terminal size, probed once (fallback 24x80); stty prints "rows cols"
function t_rows(   line, a) {
    if (TROWS > 0) return TROWS
    TROWS = 24; TCOLS = 80
    if (("stty size < /dev/tty 2>/dev/null" | getline line) > 0 && split(line, a, " ") >= 2) {
        if (a[1] + 0 >= 20) TROWS = a[1] + 0
        if (a[2] + 0 >= 40) TCOLS = a[2] + 0
    }
    close("stty size < /dev/tty 2>/dev/null")
    return TROWS
}

function t_cols() { if (TROWS == 0) t_rows(); return TCOLS }

# render the below-grid window; a status line appears only when there is
# more than fits
function pgr_draw(   h, last, i, r, s) {
    if (DUMB) return
    h = t_rows() - 17                     # usable rows below the separator
    if (h < 3) h = 3
    if (PGRN > h) h--                     # reserve the last row for status
    if (PGRTOP > PGRN - h + 1) PGRTOP = PGRN - h + 1
    if (PGRTOP < 1) PGRTOP = 1
    printf "\033[18;1H\033[0J"                       # clear row 18 -> end
    last = PGRTOP + h - 1; if (last > PGRN) last = PGRN
    r = 18
    for (i = PGRTOP; i <= last; i++) {
        # truncate to the terminal width: a wrapped line would consume
        # extra physical rows, overflow the region and scroll the screen
        s = PGRL[i]
        if (length(s) >= t_cols()) s = substr(s, 1, t_cols() - 1) ">"
        printf "\033[%d;1H\033[2K%s", r++, s
    }
    if (PGRN > h)
        printf "\033[%d;1H\033[2K-- %d-%d OF %d  PGUP/PGDN OR CTRL-B/CTRL-F --", r, PGRTOP, last, PGRN
    sync_cursor()                                    # cursor back into grid
    fflush()
}

# page the below-grid window; dir = -1 up, +1 down
function pgr_page(dir,   h) {
    if (DUMB || PGRN == 0) return
    h = t_rows() - 17
    if (h < 3) h = 3
    if (PGRN > h) h--
    if (PGRN <= h) return                 # nothing to scroll
    PGRTOP += dir * h
    pgr_draw()
}

# startup credit/help footer, drawn in the same below-grid region as t_man
# (so the first man/help call replaces it)
function show_banner() {
    t_man("------------------------------\n" \
          "TRS-80 LEVEL II BASIC emulator\n" \
          " Codeveloped with Claude, 2026\n" \
          "------------------------------\n" \
          "man pages available for all BASIC commands\n" \
          "\"help meta\" to display supported metacommands")
}

# 32-column mode (CHR$(23)): every visible cell is double width.  Text is
# doubled as glyph + trailing space, which reads fine; a SEMIGRAPHICS cell
# must instead fill both columns with no gap, or the 2x3 block mosaic breaks
# into a grid of specks (the demon's whole dance is in this mode).  So split
# the cell's pattern into its left column and its right column, double each to
# a full 2-wide sextant, and draw the two side by side -- a faithful
# horizontal stretch.  b>=128 is graphics, 192-255 aliased to 128-191 unless
# a Model III set is active, matching GL[]'s own aliasing.
function wide_glyph(b,   m, lm, rm) {
    if (b >= 128 && (b < 192 || !M3MODE)) {
        m = (b < 192 ? b - 128 : b - 192)
        lm = (and(m, 1) ? 3 : 0) + (and(m, 4) ? 12 : 0) + (and(m, 16) ? 48 : 0)
        rm = (and(m, 2) ? 3 : 0) + (and(m, 8) ? 12 : 0) + (and(m, 32) ? 48 : 0)
        return sext_glyph(lm) sext_glyph(rm)
    }
    return GL[b] " "
}

# The port-FF latch, bit 3: the HARDWARE's 32/64-column switch (LATCH).  Set
# by OUT 255,v from BASIC (st_out, p80), by the core's MODE line when a
# machine-language routine writes port FFH (p77; the Dancing Demon clears it
# for its 64-column figure after the intro's 32-column text), and by
# CHR$(23), which also sets the ROM's print-size flag (WIDE, the 403DH bit).
# Rendering follows the latch alone: only even display bytes are visible,
# each double wide, as the video hardware re-interprets RAM the instant the
# bit changes.  The ROM's routines never read the hardware -- they step the
# cursor by the 403DH flag (ROM Routines Documented, 1983, ch. 1 and 5: it
# "contains the current port FFH output bits") -- so OUT 255,8 alone shows
# every other character of what BASIC prints next, and CHR$(23) followed by
# OUT 255,0 prints spaced-out text on a 64-column screen, both as on the
# machine.  Redraw so the whole screen re-renders in the new width.
function s_setwide(w) {
    w = (w ? 1 : 0)
    if (w == LATCH) return
    LATCH = w
    if (!DUMB) { redraw_all(); sync_cursor() }
}

function drawcell(p) {
    if (DUMB) return
    if (LATCH) {
        # the 32-column latch: only even display bytes are visible, each
        # rendered double wide (glyph + trailing space); a write to an
        # odd byte repaints its even partner (no visible change)
        p -= p % 2
        if (p in CCOL)
            printf "\033[%d;%dH\033[38;5;%dm%s\033[39m", int(p / 64) + 1, p % 64 + 1, GCANSI[CCOL[p]], wide_glyph(SCR[p])
        else
            printf "\033[%d;%dH%s", int(p / 64) + 1, p % 64 + 1, wide_glyph(SCR[p])
        return
    }
    if (p in CCOL)
        printf "\033[%d;%dH\033[38;5;%dm%s\033[39m", int(p / 64) + 1, p % 64 + 1, GCANSI[CCOL[p]], GL[SCR[p]]
    else
        printf "\033[%d;%dH%s", int(p / 64) + 1, p % 64 + 1, GL[SCR[p]]
}

# Model III display decoding of codes 192-255 (CHR$(21)/CHR$(22) in s_putc):
# swap GL between Model I bit-6 graphics aliasing, the special set, and the
# Katakana alternate set, then repaint -- like the real video hardware
# reinterpreting the bytes already on screen.
function m3_rebuild(   i) {
    for (i = 192; i < 256; i++)
        GL[i] = M3MODE ? (M3KANA ? GLKANA[i - 192] : GLSPEC[i - 192]) : GL[i - 64]
    if (!DUMB) { redraw_all(); sync_cursor() }
}

# Put the terminal cursor where the simulated one is, and show it only when
# the machine would: a zero cursor character (POKE 16418,0) hides it, and
# otherwise it shows while a read waits for a key (RLWAIT) or the program
# turned it on with CHR$(14).  Only a CHANGE is written: this runs on every
# PRINT, and an escape pair per character would bloat every capture.
function sync_cursor(   vis) {
    if (!DUMB) {
        printf "\033[%d;%dH", int(CUR / 64) + 1, CUR % 64 + 1
        vis = (CURCH != 0 && (CURON || RLWAIT)) ? 1 : 0
        if (vis != CURVIS) { printf "%s", (vis ? "\033[?25h" : "\033[?25l"); CURVIS = vis }
    }
    fflush()
}

function redraw_all(   r, c, s, p, g) {
    if (DUMB) return
    for (r = 0; r < 16; r++) {
        s = ""
        for (c = 0; c < 64; c += (LATCH ? 2 : 1)) {
            p = r * 64 + c
            g = (LATCH ? wide_glyph(SCR[p]) : GL[SCR[p]])
            if (p in CCOL) s = s "\033[38;5;" GCANSI[CCOL[p]] "m" g "\033[39m"
            else s = s g
        }
        printf "\033[%d;1H%s", r + 1, s
    }
}

function s_cls(   i) {
    for (i = 0; i < 1024; i++) SCR[i] = 32
    delete CCOL
    CUR = 0
    LATCH = 0                               # CLS returns to 64 chars per line: the ROM clears
    poke_byte(16445, and(MEM[16445], 247))  # bit 3 of its 403DH image (WIDE follows, p80) and writes the latch
    if (!DUMB) { printf "\033[H\033[2J"; t_sep() }
}

function setcell(p, b) {
    SCR[p] = b
    # character output always retires the cell's SET color (EXT)
    if (p in CCOL) delete CCOL[p]
    drawcell(p)
}

# raw store into display memory (POKE path: no control-code interpretation)
function s_poke(p, b) {
    SCR[p] = b
    # a non-graphics byte retires the cell's SET color (EXT)
    if ((b < 128 || b > 191) && (p in CCOL)) delete CCOL[p]
    drawcell(p)
}

function s_scroll(   i) {
    SCROLLS++                               # counted so rl_draw can track its anchor
    for (i = 0; i < 960; i++) {
        SCR[i] = SCR[i + 64]
        if ((i + 64) in CCOL) CCOL[i] = CCOL[i + 64]; else delete CCOL[i]
    }
    for (i = 960; i < 1024; i++) { SCR[i] = 32; delete CCOL[i] }
    redraw_all()
}

function s_nl(   i) {
    if (VIDTOLP) { lp_nl(); return }
    # On a real tty we hold the line in `stty raw` for our own key handling,
    # so LF alone won't return the carriage -- emit CR+LF when streaming.
    if (DUMB) printf (TTYIN ? "\r\n" : "\n")
    CUR = int(CUR / 64) * 64 + 64
    if (CUR > 1023) { s_scroll(); CUR = 960; return }   # the line scrolled in is blank
    # The ROM's carriage return does not just move down: it falls into the
    # erase-line loop and BLANKS the line it lands on (0564-058BH).  A
    # program that homes the cursor and reprints shorter lines -- the
    # redraw-without-CLS idiom -- relies on it; without it the old text
    # stays on the screen, in PEEK and in the USR frame.  (Running off the
    # end of a line is not a CR and erases nothing: s_putc just steps on.)
    for (i = CUR; i < CUR + 64; i++)
        if (SCR[i] != 32 || (i in CCOL)) setcell(i, 32)
}

# output one byte with LEVEL II display-control semantics
function s_putc(b,   n, r) {
    if (VIDTOLP) {                          # video vector -> the ROM printer driver (p80 dv_update)
        if (b == 13) lp_nl(); else if (b >= 32) lp_puts(CHR[b])
        return
    }
    # printable: 32-191 always; 192-255 too when the Model III special/
    # Katakana mode is on (CHR$(21)) -- then they are characters, not
    # space-compression codes
    if (b >= 32 && (b < 192 || M3MODE)) {
        if (WIDE) {
            # the ROM's 32-column print flag (403DH, set by CHR$(23)):
            # characters land on even display bytes (the ROM masks the
            # low cursor bit) and advance by 2
            CUR -= CUR % 2
            if (DUMB) printf "%s ", GL[b]
            setcell(CUR, b); CUR += 2
        } else {
            # a 1-byte step; with the latch set by OUT 255,8 alone only
            # the even bytes show, so teletype output shows those, wide
            if (DUMB) { if (!LATCH) printf "%s", GL[b]; else if (CUR % 2 == 0) printf "%s ", GL[b] }
            setcell(CUR, b); CUR++
        }
        if (CUR > 1023) { s_scroll(); CUR = 960 }
        return
    }
    if (b >= 192) { for (n = b - 192; n > 0; n--) s_putc(32); return }
    if (b == 13 || b == 10) { s_nl(); return }
    if (b == 8) {
        if (DUMB && TTYIN) printf "\b \b"
        if (CUR > 0) { CUR -= (WIDE ? 2 : 1); if (CUR < 0) CUR = 0; setcell(CUR, 32) }
        return
    }
    # LEVEL II: 14 and 15 turn the cursor on and off.  The cursor is the
    # terminal's here, so this only gates its visibility (sync_cursor).
    if (b == 14 || b == 15) { CURON = (b == 14); sync_cursor(); return }
    # Model III: 21 toggles codes 192-255 between space compression and
    # character display; 22 picks which set that shows (special/Katakana)
    if (b == 21) { M3MODE = !M3MODE; m3_rebuild(); return }
    if (b == 22) { M3KANA = !M3KANA; if (M3MODE) m3_rebuild(); return }
    # LEVEL II: 23 shifts to 32 characters per line (CLS returns to 64):
    # the ROM sets bit 3 of its 403DH image (WIDE follows, p80) and writes
    # the latch
    if (b == 23) { poke_byte(16445, or(MEM[16445], 8)); s_setwide(1); return }
    if (b == 24) { if (CUR > 0) CUR--; return }
    if (b == 25) { if (CUR < 1023) CUR++; return }
    if (b == 26) { if (CUR < 960) CUR += 64; else { s_scroll(); } return }
    if (b == 27) { if (CUR >= 64) CUR -= 64; return }
    # home also returns to 64 characters per line, as CLS does (CLS is 28
    # then 31): the ROM clears bit 3 of 403DH and writes the latch (04C0-04CD)
    if (b == 28) { CUR = 0; poke_byte(16445, and(MEM[16445], 247)); s_setwide(0); return }
    if (b == 29) { CUR = int(CUR / 64) * 64; return }
    if (b == 30) { r = int(CUR / 64) * 64 + 63; for (n = CUR; n <= r; n++) setcell(n, 32); return }
    if (b == 31) { for (n = CUR; n < 1024; n++) setcell(n, 32); return }
    # 0-7, 9, 11, 12, 16-20: ignored
}

function s_puts(s,   i, n, c) {
    n = length(s)
    for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        s_putc((c in ORD) ? ORD[c] : 63)
    }
}

# debug: dump the screen buffer as 16 text rows
function s_dump(   r, c, s) {
    for (r = 0; r < 16; r++) {
        s = ""
        for (c = 0; c < 64; c++) s = s GL[SCR[r * 64 + c]]
        printf "|%s|\n", s
    }
    fflush()
}
# ============ keyboard: raw tty (gawk polls it; dd/od blocks), or piped stdin =

function kb_init() {
    KH = 0; KT = 0; KSCAN = 0; KBMODE = ""
    # the ROM's line input (0361H) takes 240 characters (LD B,0F0H at 036FH)
    # and then stops accepting keys; 255 is the STRING limit, not this one
    RLMAX = 240
    km_init()                   # keyboard-matrix tables: every input mode
    # batch mode always reads the program's input from stdin, never the
    # keyboard -- so don't probe (or disturb) the invoking terminal
    if (BATCH) { TTYIN = 0; return }
    # native Windows has no stty or /dev/tty -- the probe would only make
    # cmd.exe print "'stty' is not recognized" noise before failing anyway
    if (WINNATIVE) { TTYIN = 0; return }
    TTYIN = (system("( stty -g < /dev/tty ) > /dev/null 2>&1") == 0)
    if (TTYIN) {
        ("stty -g < /dev/tty") | getline STTY0
        close("stty -g < /dev/tty")
        kb_mode("line")
    }
}

function kb_restore() {
    kp_pop()
    if (TTYIN && STTY0 != "") system("stty " STTY0 " < /dev/tty 2>/dev/null")
    else if (TTYIN) system("stty sane < /dev/tty 2>/dev/null")
}

function kb_mode(m) {
    if (!TTYIN || KBMODE == m) return
    if (m == "line") system("stty raw -echo min 1 time 0 < /dev/tty")
    else             system("stty raw -echo min 0 time 0 < /dev/tty")
    KBMODE = m
    if (m == "poll") kp_push(); else kp_pop()
}

# ==== key release: the kitty keyboard protocol (EXT, 2026-09-16) =============
# A terminal sends no key-up events, which is why the matrix above has to
# guess how long a key was held.  Terminals that implement the kitty
# keyboard protocol (iTerm2, kitty, WezTerm, Ghostty, foot) can be asked to
# report key repeat and release as separate sequences -- flag 2, "report
# event types" -- while every PRESS still arrives as the byte it always
# was: `a`, ESC [ C for an arrow, 3 for Ctrl-C.  So INKEY$, BREAK, Ctrl-S
# and the line editor see nothing new, and the matrix gets what the
# hardware had: a key is down from its press until its release, chords
# included, and the OS's delay-until-repeat no longer shows as a gap.
#   Entering poll mode sends CSI ? u (the query, once) and CSI > 2 u (push
#   the flag); entering line mode and exiting send CSI < u (pop).  A
#   terminal without the protocol ignores all three and never answers
#   the query, so KBPROTO stays 0 and the timed latch above is used.
#   The reply CSI ? <flags> u, and every event CSI <code> ; <mods> : <ev> u
#   (or ... <ev> A-D for the arrows), is taken out of the byte stream in
#   kb_fill_tty by kp_filter: ev 2 = repeat (keeps the key fresh), ev 3 =
#   release.  The code is the unshifted key; the shift/ctrl bits are in
#   mods-1.  Pressed keys that never see a release (the window lost focus
#   mid-hold) are all released after KP_STUCK seconds with no event at
#   all, since the OS repeats the last held key while any key is down.
#   TRS80_KBPROTO: 0 = never; 1 = even in DUMB mode (the pty test); unset
#   = on at a terminal unless DUMB (a logged session stays plain).
# Why it cannot break a period program: presses are unchanged bytes; a
# program that read the matrix now reads what the machine's matrix read.
# One visible difference on such a terminal: INKEY$ no longer sees the
# terminal's auto-repeat as a stream of bytes, because repeats are events
# now -- which is what Level II did (no auto-repeat).
function kp_on(   e) {
    e = ENVIRON["TRS80_KBPROTO"]
    return TTYIN && e != "0" && (e == "1" || !DUMB)
}

function kp_push() {
    if (!kp_on()) return
    if (!KPQUERIED) { printf "\033[?u"; KPQUERIED = 1 }
    printf "\033[>2u"; fflush()
    KPPUSHED = 1
}

function kp_pop() {
    if (!KPPUSHED) return
    printf "\033[<u"; fflush()
    KPPUSHED = 0
}

# strip the protocol's replies and events from a record of tty bytes,
# applying them to the matrix; return the plain key bytes
function kp_filter(s,   out, i, n, j, body, fin) {
    if (!KPQUERIED) return s
    s = KPPART s; KPPART = ""
    out = ""; n = length(s); i = 1
    while (i <= n) {
        if (substr(s, i, 2) != "\033[") { out = out substr(s, i, 1); i++; continue }
        j = i + 2
        while (j <= n && index("0123456789;:?", substr(s, j, 1))) j++
        if (j > n) {
            if (j > i + 2) { KPPART = substr(s, i); break }   # a sequence cut by the read
            out = out substr(s, i); break                     # a bare ESC or ESC [: keys
        }
        body = substr(s, i + 2, j - i - 2); fin = substr(s, j, 1)
        if (fin == "u" && body ~ /^\?[0-9]*$/) KBPROTO = 1     # the terminal answered: it speaks it
        else if (index(body, ":") && (fin == "u" || fin ~ /^[A-D]$/)) kp_event(body, fin)
        else out = out substr(s, i, j - i + 1)                # an ordinary press sequence
        i = j + 1
    }
    return out
}

function kp_event(body, fin,   a, m, code, mods, ev, r, b) {
    split(body, a, ";"); split(a[2], m, ":")
    mods = m[1] + 0; ev = m[2] + 0
    if (mods < 1) mods = 1
    KPLAST = kp_now()
    if (fin == "u") {
        code = a[1] + 0
        if (and(mods - 1, 4) && code == 99) { r = 6; b = 4 }  # Ctrl-C: the BREAK key
        else if (code in KMR_) { r = KMR_[code]; b = KMB_[code] }
        else return
    } else {                                                  # the arrows
        r = 6
        b = (fin == "A") ? 8 : (fin == "B") ? 16 : (fin == "C") ? 64 : 32
    }
    if (ev == 3) kp_release(r, b)
    else if (ev == 1) kp_press(r, b, and(mods - 1, 1))
}

function kp_press(r, b, sh) {
    if (!and(KPDOWN[r], b)) { KPDOWN[r] = or(KPDOWN[r], b); if (sh) { KPSH[r, b] = 1; KPSHIFT++ } }
    KPLAST = kp_now()
}

function kp_release(r, b) {
    if (!and(KPDOWN[r], b)) return
    KPDOWN[r] = and(KPDOWN[r], compl(b))
    if ((r, b) in KPSH) { delete KPSH[r, b]; if (--KPSHIFT < 0) KPSHIFT = 0 }
}

function kp_release_all(   r) {
    for (r = 0; r < 8; r++) KPDOWN[r] = 0
    delete KPSH; KPSHIFT = 0
}

# read whatever is available from the tty into the queue (>=1 byte if "line").
# Two readers, chosen by the stty state kb_mode set, because gawk's getline
# can serve only one of them:
#   "poll" (min 0 time 0: INKEY$, the matrix, every BREAK poll, the core's
#   K and T lines) -- gawk reads the tty itself.  An empty read is EOF and
#   RS = "^$" never matches (as slurp_bytes), so one getline returns every
#   waiting byte as one record with RT empty; close() clears the EOF for
#   the next poll.  No process at all: 0.007 ms a poll against 2.6-2.9 ms
#   for the pipeline it replaced on 2026-09-16 (the core's FINDING 27,
#   tools/kbd_probe.py; every INKEY$/PEEK loop at a terminal ran 40-60x
#   slower a pass, and a paced routine fell behind real time past ~200
#   keyboard reads a second).  RS = "." (the recipe first measured there)
#   is WRONG: a typed period ends the record and the bytes after it are
#   lost at close().
#   "line" (min 1 time 0: the blocking read behind kb_get) -- dd | od, as
#   before.  Under min 1 gawk's getline reads on until RS or EOF, so it
#   blocks for a SECOND byte before returning the first; READ_TIMEOUT
#   drops the byte it read; min 0 time 1 works but adds 100 ms of echo lag.
#   Once per human keystroke, the pipeline's 3 ms is invisible.
# The reader must match KBMODE: a getline under "line" hangs, dd under
# "poll" returns at once with nothing.
function kb_fill() {
    return (KBMODE == "poll") ? kb_fill_tty() : kb_fill_pipe()
}

function kb_fill_tty(   save, r, i, n, line) {
    save = RS; RS = "^$"
    r = (getline line < "/dev/tty")
    RS = save
    close("/dev/tty")
    if (r <= 0) {
        if (KPPART == "") return 0
        line = KPPART; KPPART = ""          # a held partial that never completed: keys after all
    } else if (KPQUERIED) line = kp_filter(line)
    n = length(line)
    for (i = 1; i <= n; i++) KBQ[++KT] = ORD[substr(line, i, 1)]
    return n
}

function kb_fill_pipe(   cmd, ln, a, n, i, got) {
    cmd = "dd if=/dev/tty bs=256 count=1 2>/dev/null | od -A n -t u1 -v"
    got = 0
    while ((cmd | getline ln) > 0) {
        n = split(ln, a, " ")
        for (i = 1; i <= n; i++) { KBQ[++KT] = a[i] + 0; got++ }
    }
    close(cmd)
    return got
}

# pipe mode: pull the next stdin line into the queue as chars + CR
function kb_pipe_fill(   r, line) {
    fflush()                    # prompt text must land before we block on stdin
    r = (getline line < "/dev/stdin")
    if (r <= 0) { EOFQUIT = 1; return 0 }
    sub(/\r$/, "", line)
    for (r = 1; r <= length(line); r++) {
        line2 = substr(line, r, 1)
        KBQ[++KT] = (line2 in ORD) ? ORD[line2] : 63
    }
    KBQ[++KT] = 13
    return 1
}

# blocking single byte (tty mode)
function kb_get(   tries) {
    if (!TTYIN) {
        if (KH >= KT && !kb_pipe_fill()) return -1
        return KBQ[++KH]
    }
    kb_mode("line")
    tries = 0
    while (KH >= KT) {
        if (kb_fill() == 0) { if (++tries >= 3) { EOFQUIT = 1; return -1 } }
    }
    return KBQ[++KH]
}

# a clean exit after this halt happened at a key poll on exhausted stdin --
# the program's own END/STOP was never reached.  Only tools/reach_scan.py
# needs that distinction, so the note is opt-in.
function kbe_diag() {
    if (KBEDIAG++ || ENVIRON["TRS80_REACH_DIAG"] == "") return
    diag_err("BATCH: END OF INPUT AT KEY POLL, LINE " CLN)
}

# non-blocking single byte; -1 if none (used by INKEY$)
function kb_poll1() {
    if (!TTYIN) {
        if (KH >= KT) {
            if (EOFQUIT || ++INKEYEOF > 200000) { kbe_diag(); PENDBRK = 1; return -1 }
            if (!kb_pipe_fill()) { kbe_diag(); return -1 }
        }
        return KBQ[++KH]
    }
    kb_mode("poll")
    if (KH >= KT) kb_fill()
    if (KH >= KT) return -1
    return KBQ[++KH]
}

# THE BREAK VECTOR, 400CH (16396).  The ROM's BREAK check CALLs 400CH,
# normally a RET (201); period listings patch the byte to disable BREAK --
# 23 (INC HL) under Level II, 175 (XOR A) under DOS, 165 for "BREAK off,
# SHIFT-BREAK still works".  Measured over the corpus 2026-09-11: POKE
# 16396,23 in 32 files, 201 in 19, 175 in 18 (195 and 207 are DOS restore
# values and count as enabled).  Built the same day (tips 26, 27, 37, 43).
# Every site that turns a Ctrl-C into BREAK asks brk_take() first.  THE
# OVERRIDE, so a runaway program that disabled BREAK stays killable from
# the keyboard: three Ctrl-C presses in a row (no other key between) break
# anyway -- the analogue of the SHIFT-BREAK the 165 idiom leaves open.
# The keyboard MATRIX still shows the BREAK key when pressed (hardware);
# only the ROM's reaction is gated.  Batch mode has no keyboard, so a
# Ctrl-C byte fed on stdin follows the same rule (programs/tests/break.sh).
function brk_off() { return (16396 in MEM) && (MEM[16396] == 23 || MEM[16396] == 175 || MEM[16396] == 165) }
function brk_take() {
    if (!brk_off()) { BRKFORCE = 0; return 1 }
    if (++BRKFORCE >= 3) { BRKFORCE = 0; return 1 }
    return 0
}

# check for BREAK (Ctrl-C, byte 3) without consuming other typed-ahead input.
# Ctrl-S (byte 19) = the real SHIFT-@ pause: block until a key; Ctrl-C breaks.
# Every caller reads the tty, the core's ticks (p77) included: the poll is
# 0.007 ms since 2026-09-16 (kb_fill_tty).  Until then a tick's poll forked
# dd|od, ~3 ms of a paced core's 5 ms tick, and p77 read the tty on every
# fourth tick only (the nofill argument, gone with the fork).
# The tty is read on EVERY poll, not only when the queue is empty: a key
# the program never reads (a second ENTER after RUN, a stray letter) stays
# queued for the rest of the run, and while the read waited for an empty
# queue that one byte meant the tty was never read again -- no Ctrl-C, no
# Ctrl-S, the 4096-byte guard below unreachable, and a runaway program
# killable only from another shell (the 2026-09-19 audit, H-14).  KSCAN
# marks how far the queue has been searched for 3 and 19, so type-ahead
# that sits there is looked at once, not on every poll.
function pollbrk(   i, c, j) {
    if (PENDBRK) { PENDBRK = 0; kb_flush(); return 1 }
    if (!TTYIN) return 0
    kb_mode("poll")
    kb_fill()
    if (KSCAN < KH) KSCAN = KH
    for (i = KSCAN + 1; i <= KT; i++) {
        if (KBQ[i] == 3) {
            if (brk_take()) { kb_flush(); return 1 }
            for (j = i; j < KT; j++) KBQ[j] = KBQ[j + 1]   # swallowed: drop it from the queue
            KT--; i--; continue
        }
        if (KBQ[i] == 19) {
            KH = i                          # consume through the Ctrl-S only:
            c = kb_get()                    # typed-ahead after it must survive
            if (c == 3 && brk_take()) { kb_flush(); return 1 }
            return 0
        }
    }
    KSCAN = KT
    if (KT - KH > 4096) kb_flush()
    return 0
}

function kb_flush() { KH = 0; KT = 0; KSCAN = 0 }

# swallow the remainder of an ESC sequence (arrow keys etc.)
function kb_esc(   c, i) {
    c = kb_poll_wait(30)
    if (c == 91 || c == 79) {           # '[' or 'O'
        for (i = 0; i < 8; i++) {
            c = kb_poll_wait(30)
            if (c < 0 || (c >= 64 && c <= 126)) break
        }
    }
    kb_mode("line")
}

function kb_poll_wait(tries,   i, c) {
    for (i = 0; i < tries; i++) {
        c = kb_poll1()
        if (c >= 0) return c
    }
    return -1
}

# ==== memory-mapped keyboard matrix (3800H-38FFH, dec 14336-14591) ==========
# PEEK(14336+sel) returns the OR of the row bytes whose select bits are set
# in sel: row r reads at 14336+2^r, composite addresses OR rows together,
# PEEK(14591) scans all eight.  Row layout (bit 1,2,4,...,128 within a row):
#   row 0  @ A B C D E F G        row 4  0 1 2 3 4 5 6 7
#   row 1  H I J K L M N O        row 5  8 9 : ; , - . /
#   row 2  P Q R S T U V W        row 6  ENTER CLEAR BREAK UP DOWN LEFT
#   row 3  X Y Z                         RIGHT SPACE
#   row 7  SHIFT (bit 1)
# Rows are synthesized from the terminal byte stream: each matrix PEEK
# consumes at most one pending byte and "presses" its key.  A terminal
# sends no key-up events, so a tap reads as a short press and a held key
# rides the terminal's auto-repeat.  HOW LONG a byte presses its key:
#   at a terminal with a clock (the launcher loads gawk's time extension;
#   km_now), TRS80_KMHOLD MILLISECONDS, default 100 -- about a real tap,
#   whatever the program's poll rate.  Before 2026-09-16 it was 4 polls,
#   which was 133 ms in a game polling once a frame but 17 ms in one
#   polling eight times a frame (CATCH --scan 7), so the same tap moved a
#   paddle four frames in one and half a frame in the other.
#   in batch mode, or without the clock, TRS80_KMHOLD POLLS, default 4:
#   deterministic, which the batch suites need; unchanged.
# The pause a terminal shows between a tap and its auto-repeat is the OS's
# delay-until-repeat and no setting here removes it.
# Terminal lowercase = the unshifted (uppercase-labelled) key; terminal
# uppercase/shifted symbols latch the SHIFT row too.  ESC [ A/B/C/D map to
# the arrow keys, as do the Model I's own arrow bytes (91 10 8 9).  Ctrl-C
# in the stream still BREAKs (PENDBRK + flush, mirroring pollbrk).  In pipe
# mode an empty queue pulls the next stdin line, exactly like INKEY$, and
# shares INKEY$'s end-of-input runaway guard.
function km_init(   i) {
    for (i = 64; i <= 90; i++) {                  # @ A-Z rows 0-3
        KMR_[i] = int((i - 64) / 8); KMB_[i] = 2 ^ ((i - 64) % 8)
        KMR_[i + 32] = KMR_[i]; KMB_[i + 32] = KMB_[i]    # a-z: same key
        KMS_[i] = 1                                        # A-Z: shifted
    }
    KMS_[64] = 0                                  # @ is its own key
    km_row("01234567", 4, 0, 0)
    km_row("89:;,-./", 5, 0, 0)
    km_row("!\"#$%&'", 4, 1, 1)                   # shift-1 .. shift-7
    km_row("()*+<=>?", 5, 1, 0)                   # shift-8 9 : ; , - . /
    KMR_[13] = 6; KMB_[13] = 1                    # ENTER
    KMR_[31] = 6; KMB_[31] = 2                    # CLEAR
    KMR_[91] = 6; KMB_[91] = 8                    # up arrow (M1 byte 5BH)
    KMR_[10] = 6; KMB_[10] = 16                   # down arrow
    KMR_[8]  = 6; KMB_[8]  = 32                   # left arrow
    KMR_[9]  = 6; KMB_[9]  = 64                   # right arrow
    KMR_[27] = 6; KMB_[27] = 8;  KMS_[27] = 1     # SHIFT + up    (M1 byte 1BH)
    KMR_[26] = 6; KMB_[26] = 16; KMS_[26] = 1     # SHIFT + down
    KMR_[24] = 6; KMB_[24] = 32; KMS_[24] = 1     # SHIFT + left
    KMR_[25] = 6; KMB_[25] = 64; KMS_[25] = 1     # SHIFT + right
    KMR_[32] = 6; KMB_[32] = 128                  # SPACE
    KMCLOCK = ("gettimeofday" in FUNCTAB) ? "gettimeofday" : ""
    KMHOLD = (ENVIRON["TRS80_KMHOLD"] + 0 > 0) ? ENVIRON["TRS80_KMHOLD"] + 0 : (KMCLOCK != "" ? 100 : 4)
    KMR = -1; KMSH = 0
    KBPROTO = 0; KPQUERIED = 0; KPPUSHED = 0; KPPART = ""; KPSHIFT = 0; KPLAST = 0
    for (i = 0; i < 8; i++) KPDOWN[i] = 0
    # seconds without any event: release everything.  TRS80_KPSTUCK moves it
    # (the pty test does, on a slow CI runner whose own waits are stretched)
    KP_STUCK = (ENVIRON["TRS80_KPSTUCK"] + 0 > 0) ? ENVIRON["TRS80_KPSTUCK"] + 0 : 2
    KPSLACK = (KMCLOCK != "") ? 0 : 1
}

# seconds, sub-millisecond, from the time extension; -1 without it.  The
# indirect call keeps the program loadable when the extension is absent
# (a direct gettimeofday() would be a parse error there).
function km_now(   f) {
    if (KMCLOCK == "") return -1
    f = KMCLOCK
    return @f()
}

# The stuck-key timer's clock.  It counts whole seconds of silence, so it
# does not need the time extension: without one (a gawk whose `time` only
# loads with a warning, see the launcher) systime() serves, and KPSLACK
# adds the second its one-second grain can lose -- an abandoned key then
# lets go after 2-4 s instead of 2.  With no clock at all here, a key whose
# release never came stayed down for the rest of the run.
function kp_now() { return (KMCLOCK != "") ? km_now() : systime() }

# a byte's key is still down: by the clock at a terminal, by polls otherwise
function km_held() {
    if (TTYIN && KMCLOCK != "") return (km_now() - KMT0) * 1000 < KMHOLD
    return --KMTTL > 0
}

function km_row(s, row, sh, fb,   i, c) {
    for (i = 1; i <= length(s); i++) {
        c = ORD[substr(s, i, 1)]
        KMR_[c] = row; KMB_[c] = 2 ^ (fb + i - 1); KMS_[c] = sh
    }
}

function km_latch(r, b, sh) { KMR = r; KMB = b; KMSH = sh; KMTTL = KMHOLD; KMT0 = km_now() }

# next byte of an ESC sequence: already queued in pipe mode, short poll on tty
function km_next(   i) {
    if (!TTYIN) return (KH < KT) ? KBQ[++KH] : -1
    for (i = 0; i < 30; i++) if (KH < KT || kb_fill() > 0) return KBQ[++KH]
    return -1
}

# An ESC byte was just consumed: which TRS-80 key did the terminal mean?
# A terminal sends an arrow as ESC [ A..D (ESC O A..D in application mode),
# with SHIFT as ESC [ 1;2 A..D; the Model I sends ONE byte per arrow -- 91
# 10 8 9, shifted 27 26 24 25 -- and that is what a period program tests
# INKEY$ for.  Returns that byte; 27 for a lone ESC (SHIFT + up arrow is
# what 27 means on the machine), the next key left in the queue; and -1
# for any other sequence (PgUp, F-keys, a kitty event kp_filter let by):
# a key the TRS-80 does not have.  INKEY$ at a terminal and the matrix
# share it, so the two cannot disagree about an arrow again.  The line
# editor has its own reading of these keys (rl_arrow: edit and recall).
function kb_escseq(   c, n, par, a) {
    c = km_next()
    if (c != 91 && c != 79) { if (c >= 0) KH--; return 27 }
    par = ""
    for (n = 0; n < 16; n++) {
        c = km_next()
        if (c < 0 || (c >= 64 && c <= 126)) break
        par = par CHR[c]
    }
    if (c < 0 && n == 0) { KH--; return 27 }      # ESC, then a typed [ or O
    if (c < 65 || c > 68) return -1
    split(par, a, ";")
    if (a[2] + 0 > 0 && and(a[2] - 1, 1))         # the modifier field, 1 + bits: SHIFT is bit 0
        return (c == 65) ? 27 : (c == 66) ? 26 : (c == 67) ? 25 : 24
    return (c == 65) ? 91 : (c == 66) ? 10 : (c == 67) ? 9 : 8
}

# consume at most one pending byte into the latch; age the latch when idle.
# Under the release protocol (KBPROTO) every pending press byte goes into
# the down-set instead, and nothing ages: a key is up when its release
# arrives (kp_filter), or when no event at all has come for KP_STUCK s.
function km_pump(   c) {
    if (TTYIN) { kb_mode("poll"); if (KH >= KT) kb_fill() }
    else if (KH >= KT) {
        if (EOFQUIT || ++INKEYEOF > 200000) { kbe_diag(); PENDBRK = 1; KMR = -1; return }
        if (!kb_pipe_fill()) { kbe_diag(); KMR = -1; return }
    }
    if (KBPROTO) {
        while (KH < KT) kp_byte(KBQ[++KH])
        if (KPLAST > 0 && kp_now() - KPLAST > KP_STUCK + KPSLACK) { kp_release_all(); KPLAST = 0 }
        return
    }
    if (KH >= KT) {
        if (KMR >= 0 && !km_held()) { KMR = -1; KMSH = 0 }
        return
    }
    c = KBQ[++KH]
    if (c == 3) { if (brk_take()) { PENDBRK = 1; kb_flush() }; km_latch(6, 4, 0); return }
    BRKFORCE = 0
    if (c == 27) c = kb_escseq()                  # an arrow, or no TRS-80 key (-1)
    if (c in KMR_) km_latch(KMR_[c], KMB_[c], KMS_[c] + 0)
    else { KMR = -1; KMSH = 0 }                   # key with no matrix position
}

# one press byte under the release protocol: the key goes down and stays
function kp_byte(c) {
    if (c == 3) { if (brk_take()) { PENDBRK = 1; kb_flush() }; kp_press(6, 4, 0); return }
    BRKFORCE = 0
    if (c == 27) c = kb_escseq()
    if (c in KMR_) kp_press(KMR_[c], KMB_[c], KMS_[c] + 0)
}

function kb_matrix(sel,   out, r) {
    km_pump()
    if (KBPROTO) {
        out = 0
        for (r = 0; r < 7; r++) if (KPDOWN[r] && and(sel, 2 ^ r)) out = or(out, KPDOWN[r])
        if (KPSHIFT > 0 && and(sel, 128)) out = or(out, 1)
        return out
    }
    if (KMR < 0) return 0
    out = 0
    if (and(sel, 2 ^ KMR)) out = or(out, KMB)
    if (KMSH && and(sel, 128)) out = or(out, 1)   # row 7 = SHIFT
    return out
}

# line editor: echo into the simulated screen; returns the line.
# Sets RLCANCEL=1 if BREAK (Ctrl-C) pressed; EOFQUIT on end of input.
# Buffer RLS + cursor RLP (chars left of cursor).  Keys: Ctrl-A/E start/end,
# Ctrl-U erase line, left/right arrows, BS/DEL.  With repl=1 (the ">" prompt
# only): up/down history, TAB filename completion, Ctrl-L = CLEAR key.
function rl_read(repl,   c, r, s, oldl, oldp) {
    RLCANCEL = 0
    RLWAIT = 1                              # a waiting read shows the cursor
    sync_cursor()
    if (!TTYIN) {
        r = (getline s < "/dev/stdin")
        if (r <= 0) { EOFQUIT = 1; RLWAIT = 0; return "" }
        sub(/\r$/, "", s)
        # no cursor stops a piped line at the limit, so the cut is said out
        # loud, once: a transcript's long line must not lose its tail silently
        if (length(s) > RLMAX) {
            s = substr(s, 1, RLMAX)
            if (!RLCUTSAID++) diag_err("INPUT LINE CUT AT " RLMAX " CHARACTERS (the Level II keyboard limit)")
        }
        s_puts(s); s_nl()
        RLWAIT = 0
        return s
    }
    RLS = ""; RLP = 0
    RLSTART = CUR
    HIX = 0; RLDRAFT = ""
    for (;;) {
        c = kb_get()
        if (c < 0) { RLWAIT = 0; sync_cursor(); return RLS }
        if (c == 13 || c == 10) {
            if (!DUMB) { CUR = RLSTART + length(RLS); if (CUR > 1023) CUR = 1023 }
            RLWAIT = 0
            s_nl(); sync_cursor()
            return RLS
        }
        if (c == 3) { if (!brk_take()) continue; RLCANCEL = 1; RLWAIT = 0; s_nl(); sync_cursor(); return "" }
        BRKFORCE = 0
        oldl = length(RLS); oldp = RLP
        if (c == 127 || c == 8) {
            if (RLP > 0) {
                RLS = substr(RLS, 1, RLP - 1) substr(RLS, RLP + 1)
                RLP--
                rl_draw(oldl, oldp)
            }
            continue
        }
        if (c == 1) { if (RLP > 0) { RLP = 0; rl_draw(oldl, oldp) } continue }        # Ctrl-A
        if (c == 5) { if (RLP < oldl) { RLP = oldl; rl_draw(oldl, oldp) } continue }  # Ctrl-E
        if (c == 21) { if (oldl) { RLS = ""; RLP = 0; rl_draw(oldl, oldp) } continue }# Ctrl-U
        if (c == 12 && repl) { rl_clear_screen(); continue }                          # Ctrl-L
        if (c == 2) { pgr_page(-1); continue }                                        # Ctrl-B: page up
        if (c == 6) { pgr_page(1); continue }                                         # Ctrl-F: page down
        if (c == 9 && repl) { rl_complete(); continue }                               # TAB
        if (c == 27) { rl_arrow(repl); continue }
        if (c >= 32 && c < 127 && oldl < RLMAX) {
            RLS = substr(RLS, 1, RLP) CHR[c] substr(RLS, RLP + 1)
            RLP++
            rl_draw(oldl, oldp)
        }
    }
}

# repaint the input line after an edit.  Grid mode: repaint from the RLSTART
# anchor (tracking any scroll it causes).  Fullscreen tty mode: plain
# backspace/overprint -- fine up to the terminal width (240-char lines that
# wrap are a documented cosmetic limitation there).
function rl_draw(oldl, oldp,   i, nn, pre, top) {
    nn = length(RLS)
    if (DUMB) {
        for (i = 0; i < oldp; i++) printf "\b"
        printf "%s", RLS
        for (i = nn; i < oldl; i++) printf " "
        top = (nn > oldl) ? nn : oldl
        for (i = top; i > RLP; i--) printf "\b"
        fflush()
        return
    }
    pre = SCROLLS
    CUR = RLSTART
    s_puts(RLS)
    for (i = nn; i < oldl; i++) s_putc(32)
    if (SCROLLS > pre) RLSTART -= 64 * (SCROLLS - pre)
    if (RLSTART < 0) RLSTART = 0
    CUR = RLSTART + RLP
    sync_cursor()
}

# ESC sequence: arrows edit/recall; anything else is swallowed
function rl_arrow(repl,   c, c2, i, oldl, oldp) {
    c = kb_poll_wait(30)
    if (c != 91 && c != 79) { kb_mode("line"); return }
    c2 = kb_poll_wait(30)
    kb_mode("line")
    oldl = length(RLS); oldp = RLP
    if (c2 == 68) { if (RLP > 0) { RLP--; rl_draw(oldl, oldp) } return }      # left
    if (c2 == 67) { if (RLP < oldl) { RLP++; rl_draw(oldl, oldp) } return }   # right
    if (c2 == 65) { if (repl) rl_hist(1, oldl, oldp); return }                # up
    if (c2 == 66) { if (repl) rl_hist(-1, oldl, oldp); return }               # down
    if (c2 == 53 || c2 == 54) {                       # ESC[5~ / ESC[6~: PgUp/PgDn
        i = kb_poll_wait(30)
        kb_mode("line")
        if (i == 126) pgr_page(c2 == 53 ? -1 : 1)
        return
    }
    if (c2 >= 0 && (c2 < 64 || c2 > 126)) {           # unfinished CSI: swallow
        for (i = 0; i < 8; i++) {
            c2 = kb_poll_wait(30)
            if (c2 < 0 || (c2 >= 64 && c2 <= 126)) break
        }
        kb_mode("line")
    }
}

# up/down history recall: HIX steps back from the newest entry; HIX=0 is the
# in-progress draft, restored on the way back down
function rl_hist(dir, oldl, oldp) {
    if (dir > 0) {
        if (HIX >= HN) return
        if (HIX == 0) RLDRAFT = RLS
        HIX++
    } else {
        if (HIX == 0) return
        HIX--
    }
    RLS = (HIX == 0) ? RLDRAFT : HIST[HN - HIX + 1]
    RLP = length(RLS)
    rl_draw(oldl, oldp)
}

# Ctrl-L: the CLEAR key -- wipe the screen, redraw prompt + current line
function rl_clear_screen() {
    if (DUMB) {
        printf (TTYIN ? "\r\n" : "\n")
        s_putc(62)
        rl_draw(0, 0)
        return
    }
    s_cls()
    s_putc(62)
    RLSTART = CUR
    rl_draw(0, 0)
}

# TAB filename completion on the word left of the cursor.  Directory and
# file names contain spaces throughout the archive, so the word boundary
# cannot simply be the last space: every space/tab/quote left of the cursor
# is a CANDIDATE boundary, tried leftmost (longest word) first, and the
# first candidate with filesystem matches wins -- so "Model1/CORAID and
# CO<TAB>" completes across its spaces while plain "CLOAD pr<TAB>" behaves
# as before.  Extends by the longest common prefix of the glob matches; a
# unique directory match gains "/"; ambiguous with nothing to extend lists
# the candidates below the grid.
function rl_complete(   i, c, word, cmd, line, nm, mt, lcp, j, add, oldl, oldp, out) {
    oldl = length(RLS); oldp = RLP
    nm = 0
    for (i = 0; i <= RLP && nm == 0; i++) {
        if (i > 0) {
            c = substr(RLS, i, 1)
            if (!(c == " " || c == "\t" || c == "\"")) continue
        }
        word = substr(RLS, i + 1, RLP - i)
        if (word == "" || index(word, "\"") || word ~ /'/) continue
        cmd = "ls -1d -- " shq(word) "* 2>/dev/null"
        while ((cmd | getline line) > 0) { if (nm < 100) mt[++nm] = line }
        close(cmd)
    }
    if (nm == 0) return
    lcp = mt[1]
    for (j = 2; j <= nm; j++)
        while (lcp != "" && substr(mt[j], 1, length(lcp)) != lcp) lcp = substr(lcp, 1, length(lcp) - 1)
    add = substr(lcp, length(word) + 1)
    # mt[1] is ls output, not typed text: the quote test above never saw
    # it, so it must be quoted for sh (a name with a ' ran as a command)
    if (nm == 1 && system("test -d " shq(mt[1])) == 0) add = add "/"
    if (add != "") {
        if (oldl + length(add) > RLMAX) return
        RLS = substr(RLS, 1, RLP) add substr(RLS, RLP + 1)
        RLP += length(add)
        rl_draw(oldl, oldp)
        return
    }
    out = "MATCHES:"
    for (j = 1; j <= nm && j <= 28; j++) out = out "\n  " mt[j]
    if (nm > 28) out = out "\n  ..."
    t_man(out)
    if (DUMB) { s_putc(62); rl_draw(0, 0) }
}
# ===================== REPL and program management ==========================

function repl(   line, iscmd) {
    for (;;) {
        if (EOFQUIT || QUITFLAG) return
        s_puts("READY"); s_nl()
        for (;;) {
            if (AUTOREQ) {                  # POKE 16609,1: AUTO from the next prompt (p75)
                AUTOREQ = 0
                auto_run(AUTOLINE, (AUTOINC < 1) ? 10 : AUTOINC)
                if (EOFQUIT || QUITFLAG) return
                break
            }
            kb_mode("line")
            s_putc(62)                      # ">" prompt
            line = rl_read(1)               # 1 = REPL read: history/Tab/Ctrl-L on
            if (EOFQUIT || QUITFLAG) return
            if (RLCANCEL) continue
            hist_add(line)
            iscmd = handle_line(line)
            if (EOFQUIT || QUITFLAG) return
            if (iscmd) break                # print READY again
        }
    }
}

# returns 1 if an immediate command ran (=> READY), 0 if a line was stored
function handle_line(line,   s, ln, rest) {
    s = line
    sub(/^[ \t]+/, "", s)
    if (s == "") return 0
    if (s ~ /^@dump[ \t]*$/) { s_dump(); return 0 }
    if (s ~ /^help($|[ \t])/) {
        rest = substr(s, 5); sub(/^[ \t]+/, "", rest); sub(/[ \t]+$/, "", rest)
        st_help(rest)
        return 1
    }
    if (s ~ /^fullscreen($|[ \t])/) {
        rest = substr(s, 11); sub(/^[ \t]+/, "", rest); sub(/[ \t]+$/, "", rest)
        st_fullscreen(rest)
        return 1
    }
    if (s ~ /^man($|[ \t])/) {
        rest = substr(s, 4); sub(/^[ \t]+/, "", rest); sub(/[ \t]+$/, "", rest)
        st_man(rest)
        return 1
    }
    if (s ~ /^speed($|[ \t])/) {
        rest = substr(s, 6); sub(/^[ \t]+/, "", rest); sub(/[ \t]+$/, "", rest)
        st_speed(rest)
        return 1
    }
    if (s ~ /^sound($|[ \t])/) {
        rest = substr(s, 6); sub(/^[ \t]+/, "", rest); sub(/[ \t]+$/, "", rest)
        st_sound(rest)
        return 1
    }
    if (s ~ /^dir($|[ \t])/) {
        rest = substr(s, 4)
        sub(/^[ \t]+/, "", rest)
        st_dir(rest)
        return 1
    }
    if (s ~ /^cat($|[ \t])/) {
        rest = substr(s, 4)
        sub(/^[ \t]+/, "", rest)
        st_cat(rest)
        return 1
    }
    if (s ~ /^ext($|[ \t])/) {
        rest = substr(s, 4); sub(/^[ \t]+/, "", rest); sub(/[ \t]+$/, "", rest)
        st_ext(rest)
        return 1
    }
    if (s ~ /^(history|h)[ \t]*$/) { st_history(); return 1 }
    if (s ~ /^[0-9]/) {
        match(s, /^[0-9]+/)
        ln = substr(s, 1, RLENGTH) + 0
        rest = substr(s, RLENGTH + 1)
        if (ln > 65529) { E = 2; report_err(0); return 1 }
        sub(/^ /, "", rest)
        if (rest == "") {
            if (ln in prog) delline(ln)
            else { E = 8; report_err(0); return 1 }
        } else storeline(ln, rest)
        return 0
    }
    exec_immediate(line)
    return 1
}

# --- command history (memory only; recalled with up/down in rl_read) --------
function hist_add(line,   i) {
    if (line ~ /^[ \t]*$/) return
    if (HN > 0 && HIST[HN] == line) return  # collapse consecutive repeats
    if (HN >= 200) {                        # cap: drop the oldest
        for (i = 1; i < HN; i++) HIST[i] = HIST[i + 1]
        HN--
    }
    HIST[++HN] = line
}

function st_history(   i, from, out) {
    if (HN == 0) { t_man("HISTORY: (empty)"); return }
    from = (HN > 28) ? HN - 27 : 1
    out = "HISTORY:"
    for (i = from; i <= HN; i++) out = out "\n" sprintf("%4d  %s", i, HIST[i])
    t_man(out)
}

function storeline(ln, text) {
    prog[ln] = text
    delete ESC[ln]                  # a typed line is text again (R1 escrow)
    LASTLN = ln
    inval_cache(ln)
    rebuild()
    DATADIRTY = 1
    run_reset()
}

function delline(ln) {
    delete prog[ln]; delete ESC[ln]
    inval_cache(ln)
    rebuild()
    DATADIRTY = 1
    run_reset()
}

# A program line entered, replaced or deleted ends at the ROM's 1B5DH
# (called from 1AEFH), which is RUN's initializer without the jump: the
# variables and DEF FNs go, the type table is single again, the FOR/GOSUB
# stacks, ON ERROR, the RESUME flag and CONT are reset, DATA is RESTOREd
# and (Disk BASIC) the files are closed.  The famous cost of fixing a line
# on a Model I -- and what keeps a RETURN, a NEXT, an FN call or a RESUME
# from running on indexes into a program that has since changed.  DELETE
# ends the same way.  ERR and ERL are not touched.  CLEAR is the same
# routine (st_clear, p70).
function run_reset() {
    clear_vars(0)
    DP = 1
    EHANDLER = 0; INHANDLER = 0
    CONTOK = 0
}

# every path that stores, replaces or drops a program line comes through
# here; PMTOUCH tells pm_build (p75) the line's image bytes are new, so
# nothing POKEd into the old ones survives
function inval_cache(ln) { inval_cache_key(ln ""); PMTOUCH[ln + 0] = 1 }

function rebuild(   l) {
    delete LNS; delete LIDX
    NL = 0
    PROCINFO["sorted_in"] = "@ind_num_asc"
    for (l in prog) { NL++; LNS[NL] = l + 0; LIDX[l + 0] = NL }
    PROCINFO["sorted_in"] = ""
    PROGDIRTY = 1                   # the PEEKable program image is stale (p75)
}

# --- range parsing for LIST/DELETE: [.] | [n][-[m]] | -m  (tokens) ----------
function parse_range(   any) {
    RA = 0; RB = 65529; any = 0
    if (TY[CK, CP] == "o" && TK[CK, CP] == ".") { RA = LASTLN; RB = LASTLN; CP++; return 1 }
    if (TY[CK, CP] == "n") { RA = TK[CK, CP] + 0; RB = RA; CP++; any = 1 }
    if (TY[CK, CP] == "o" && TK[CK, CP] == "-") {
        CP++; RB = 65529; any = 1
        if (TY[CK, CP] == "n") { RB = TK[CK, CP] + 0; CP++ }
    }
    return any
}

# LIST, LLIST, DELETE, AUTO, CLOAD and LOAD (without ,R) all END AT READY on
# the machine, whether typed or met inside a program (ROM: LIST 2B2E-2B54,
# DELETE 2BD9, AUTO 2036, CLOAD 2C7A).  to_ready() is that ending.  Without
# it a program that ran one of them carried on at its old line INDEX in a
# line table that had just been rebuilt under it -- 10 PRINT "A":20 DELETE
# 10:30 PRINT "B" skipped line 30 -- and a CLOADed second part started
# somewhere past its first lines (the 2026-09-19 audit, H-8).
function to_ready() { HALT = 1; CONTOK = 0 }

function st_list(   i, ln) {
    parse_range()
    for (i = 1; i <= NL; i++) {
        ln = LNS[i]
        if (ln < RA) continue
        if (ln > RB) break
        LASTLN = ln                         # "." is the line just listed (ROM 2B5BH)
        s_puts(ln " " prog[ln]); s_nl()
        if (pollbrk()) break
    }
    to_ready()
}

# LLIST: LIST to the printer stream (all the same range forms)
function st_llist(   i, ln) {
    parse_range()
    for (i = 1; i <= NL; i++) {
        ln = LNS[i]
        if (ln < RA) continue
        if (ln > RB) break
        LASTLN = ln
        lp_puts(ln " " prog[ln]); lp_nl()
    }
    to_ready()
}

# DELETE n | n-m | -m | .   The ROM (2BC6-2BD6) takes the range, then
# REFUSES with ?FC, deleting nothing, unless the UPPER line exists ("the
# upper line number to be deleted must be a currently used number", the
# manual) and the first line to go is not past it.  So DELETE 10-25 with no
# line 25 is ?FC, and so are DELETE - and DELETE 10- (the default upper
# line can never exist) and a bare DELETE: a typo cannot take the program
# with it.  The whole statement is parsed first (1B25H: ?SN if anything
# follows the range), so DELETE 10,20 deletes nothing either.
function st_delete(   i, ln, n, hits) {
    parse_range()
    if (!at_stmt_end()) { raise(2); return }
    if (!(RB in prog) || RA > RB) { raise(5); return }
    n = 0
    for (i = 1; i <= NL; i++) {
        ln = LNS[i]
        if (ln >= RA && ln <= RB) { hits[++n] = ln }
    }
    for (i = 1; i <= n; i++) { delete prog[hits[i]]; delete ESC[hits[i]]; inval_cache(hits[i]) }
    rebuild()
    DATADIRTY = 1
    run_reset()                     # the ROM's DELETE leaves through 1B5DH too
    to_ready()
}

function st_auto(   start, inc, line, k) {
    start = 10; inc = 10
    if (TY[CK, CP] == "n") {
        start = int(TK[CK, CP] + 0); CP++
        if (TY[CK, CP] == "o" && TK[CK, CP] == ",") {
            CP++
            if (TY[CK, CP] == "n") { inc = int(TK[CK, CP] + 0); CP++ }
        }
    }
    if (inc < 1) inc = 10
    auto_run(start, inc)
    to_ready()
}

# the AUTO prompt loop; its state is PEEKable through the system variable
# window (p75: 40E1H flag, 40E2/E3H line, 40E4/E5H increment)
function auto_run(start, inc,   line, k) {
    AUTOON = 1; AUTOINC = inc
    while (start <= 65529) {
        AUTOLINE = start
        kb_mode("line")
        k = (start in prog)
        s_puts(start (k ? "*" : " "))
        line = rl_read()
        if (EOFQUIT || RLCANCEL) break
        if (line == "") { if (!k) break }
        else storeline(start, line)
        start += inc
    }
    AUTOON = 0
}

function st_new(   x) {
    for (x in prog) { inval_cache(x); delete prog[x] }
    delete ESC
    rebuild()
    clear_vars()
    FSN = 0; GSN = 0; NDATA = 0; DP = 1; DATADIRTY = 1
    CONTOK = 0; LASTLN = 0; EHANDLER = 0; INHANDLER = 0; ERRV = 0; ERLV = 0
    HALT = 1
}

# keepfiles=1 (LOAD/RUN "file",R) skips the channel close; every existing
# caller omits it, so plain clear_vars() still closes everything
function clear_vars(keepfiles) {
    if (!keepfiles) fio_closeall()
    delete NV; delete SV; delete VA; delete ADIM; delete ASZ
    # DEF FN definitions live in variable space (MS BASIC): RUN/NEW/CLEAR
    # all wipe them and the program re-executes its DEFs
    delete FNPAR; delete FNPARM; delete FNKEY; delete FNPOS
    FNDEPTH = 0
    # the DEF-type table goes back to single precision on RUN, NEW, a
    # program load AND the CLEAR statement: the ROM's CLEAR joins RUN's
    # initializer (1E7A/1EA0 -> 1B61-1B6C), so DEFSTR A:CLEAR 500:A="X" is
    # ?TM on the machine -- period programs CLEAR first, then DEFSTR
    delete DEFS
    sp_reset()                      # VARPTR string space empties with the vars
    FSN = 0; GSN = 0
}

# --- fullscreen metacommand: switch text output between the streamed linux
#     terminal (on) and the captive 64x16 TRS-80 grid (off) ------------------
function st_fullscreen(arg) {
    if (arg == "") { t_man("FULLSCREEN " (DUMB ? "ON" : "OFF")); return }
    if (arg == "on" || arg == "1") {
        if (!DUMB) { t_leave_grid(); DUMB = 1 }
        return
    }
    if (arg == "off" || arg == "0") {
        if (DUMB) { DUMB = 0; t_repaint() }
        return
    }
    t_man("USAGE: fullscreen on|off|1|0")
}

# --- REM META: directives (EXT, gated by `ext on` / TRS80_EXT) --------------
# A REM whose payload starts with META: carries a metacommand that fires when
# execution REACHES the line, so a listing can state its own display needs
# (10 REM META:fullscreen on) or change the throttle part-way through
# (500 REM META:speed 1.77).  In a loop it re-fires every pass; both knobs are
# idempotent, which is why only they are allowed.
#
# The whitelist is display/feel knobs ONLY -- never dir/cat (shell
# passthroughs), never anything touching the filesystem.  Metacommands
# otherwise reach us only from the keyboard; the moment a FILE can fire one, a
# downloaded .bas would be a shell-execution vector on LOAD.  That constraint
# is not negotiable, whatever the gate.
#
# Anything else after META: is ignored in silence -- unknown directive, bad
# argument, a plain English comment that happens to start that way.  The line
# stays a bit-for-bit valid Level II REM on real hardware and through
# CSAVE/tok round-trips, which is the whole point of hiding in a comment.
# The META: marker takes either case; the directive itself is lowercase-only,
# like every metacommand.
function rem_meta(   s, cmd, arg) {
    if (TY[CK, CP + 1] != "r") return
    s = TK[CK, CP + 1]
    if (s !~ /^[ \t]*[Mm][Ee][Tt][Aa]:/) return
    sub(/^[ \t]*[Mm][Ee][Tt][Aa]:[ \t]*/, "", s)
    sub(/[ \t]+$/, "", s)
    if (match(s, /[ \t]/)) {
        cmd = substr(s, 1, RSTART - 1)
        arg = substr(s, RSTART + 1); sub(/^[ \t]+/, "", arg)
    } else { cmd = s; arg = "" }
    if (cmd == "speed") {                   # set_speed, not st_speed: silent
        if (arg ~ /^[0-9]*\.?[0-9]+$/) set_speed(arg + 0)
    } else if (cmd == "fullscreen") {
        if (arg == "on" || arg == "off" || arg == "1" || arg == "0")
            st_fullscreen(arg)              # silent for these four; bare is not
    }
}

# --- ext metacommand: gate for extensions that damaged OCR could spell ------
function st_ext(arg) {
    if (arg == "") { t_man("EXT " (EXTON ? "ON" : "OFF") " (gated: bare/prompt-only INPUT, DIM of a scalar, REM META:)"); return }
    if (arg == "on" || arg == "1") { EXTON = 1; return }
    if (arg == "off" || arg == "0") { EXTON = 0; return }
    t_man("USAGE: ext on|off|1|0")
}

# --- man metacommand: show usage + an example for a BASIC keyword -----------
function st_man(arg,   k) {
    if (MANN == 0) { t_man("NO MANUAL ENTRIES LOADED (support/manpages.txt missing?)"); return }
    k = toupper(arg)
    if (k == "") { t_man("USAGE: man <KEYWORD>   (e.g. man PRINT)"); return }
    if (k in MANTXT) t_man(MANTXT[k])
    else t_man("NO MANUAL ENTRY FOR " k)
}

# --- help metacommand: metacommand list + BASIC-command search --------------
function man_firstline(body,   p) {
    p = index(body, "\n")
    return (p ? substr(body, 1, p - 1) : body)
}

function st_help(arg,   q, k, b, n, i, seen, firsts, bodies, out, cap, more) {
    if (arg == "") {
        t_man("HELP:\n  help meta        list the metacommands\n  help keys        list the terminal key bindings\n  help <text>      find BASIC commands matching <text>\n  man <KEYWORD>    full page for one BASIC command")
        return
    }
    if (arg == "meta") {
        t_man("METACOMMANDS (lowercase only):\n" \
              "  dir [args]            shell 'ls -al' passthrough\n" \
              "  cat <file...>         show file contents (non-text bytes as .)\n" \
              "  ext on|off            gated extensions (bare: show state)\n" \
              "  fullscreen on|off     stream vs 64x16 grid (bare: show state)\n" \
              "  history | h           list this session's typed commands\n" \
              "  man <KEYWORD>         syntax + example for a BASIC command\n" \
              "  help meta             this list\n" \
              "  help keys             terminal key bindings\n" \
              "  help <text>           search BASIC commands\n" \
              "  speed <mhz>           throttle execution (0 = full speed)\n" \
              "  sound on|off          machine-code sound through the Z80 core\n" \
              "  sound wav <path>|off  ...and/or capture it to a WAV file (bare: state)\n" \
              "  @dump                 dump the screen buffer (debug)\n" \
              "IN A PROGRAM (needs ext on): a REM fires speed/fullscreen when\n" \
              "execution reaches it --  10 REM META:fullscreen on")
        return
    }
    if (arg == "keys") {
        t_man("KEYS (control keys work shifted or unshifted):\n" \
              "  Ctrl-C          BREAK (stop a running program; CONT resumes)\n" \
              "  Ctrl-S          pause a running program or LIST (the real\n" \
              "                  SHIFT-@); any key resumes, Ctrl-C breaks\n" \
              "  Ctrl-L          CLEAR: wipe the screen at the > prompt\n" \
              "  Ctrl-U          erase the input line (SHIFT-left-arrow)\n" \
              "  Ctrl-A / Ctrl-E jump to start / end of the input line\n" \
              "  left / right    move the cursor within the line\n" \
              "  up / down       recall command history at the > prompt\n" \
              "  PgUp / PgDn     page long output below the grid (fn-up/down\n" \
              "                  on a Mac laptop; Ctrl-B / Ctrl-F also work)\n" \
              "  TAB             complete a filename at the > prompt")
        return
    }
    if (MANN == 0) { t_man("NO MANUAL ENTRIES LOADED (support/manpages.txt missing?)"); return }
    q = toupper(arg)
    if (q in MANTXT) { t_man(MANTXT[q]); return }   # exact keyword -> its page
    n = 0
    PROCINFO["sorted_in"] = "@ind_str_asc"
    for (k in MANTXT) {
        b = MANTXT[k]
        if (index(toupper(k), q) == 0 && index(toupper(b), q) == 0) continue
        if (b in seen) continue              # collapse alias groups (shared body)
        seen[b] = 1
        n++; bodies[n] = b; firsts[n] = man_firstline(b)
    }
    PROCINFO["sorted_in"] = ""
    if (n == 0) { t_man("NO COMMANDS MATCH " arg); return }
    if (n == 1) { t_man(bodies[1]); return }
    cap = 28
    out = "MATCHES FOR \"" arg "\":"
    more = 0
    for (i = 1; i <= n; i++) {
        if (i > cap) { more = n - cap; break }
        out = out "\n  " firsts[i]
    }
    if (more) out = out "\n  ...and " more " more (narrow your search)"
    t_man(out)
}

# --- speed metacommand: set the emulated clock in MHz (0 = full speed) ------
function st_speed(arg) {
    if (arg == "") { t_man(speed_msg()); return }
    if (arg !~ /^[0-9]*\.?[0-9]+$/) { t_man("USAGE: speed <mhz>   (0 = full speed)"); return }
    set_speed(arg + 0)
    t_man(speed_msg())
}

function speed_msg() {
    return (THROTTLE_MHZ > 0) ? "SPEED " THROTTLE_MHZ " MHZ" : "SPEED: FULL (no throttle)"
}

# --- sound metacommand (EXT): machine-code sound through the Z80 core -------
# Switches only; the player command stays in the environment (p77 header).
function st_sound(arg,   rest) {
    snd_init()
    if (arg == "") { t_man(snd_msg()); return }
    if (arg == "on" || arg == "1") { SNDON = 1; snd_apply(); t_man(snd_msg()); return }
    if (arg == "off" || arg == "0") { SNDON = 0; snd_apply(); t_man(snd_msg()); return }
    if (arg ~ /^wav[ \t]+[^ \t]/) {
        rest = substr(arg, 4); sub(/^[ \t]+/, "", rest)
        SNDWAV = (rest == "off" || rest == "0") ? "" : rest
        snd_apply(); t_man(snd_msg()); return
    }
    t_man("USAGE: sound on|off   sound wav <path>|off   (bare: show state)")
}

# --- dir metacommand: shell passthrough for "ls -al" (below-grid output) ----
function st_dir(args,   cmd, outline, out, n) {
    if (WINNATIVE) cmd = "dir" (args == "" ? "" : " " args) " 2>&1"
    else           cmd = "ls -al" (args == "" ? "" : " " args) " 2>&1"
    out = ""; n = 0
    # no cap: fullscreen streams to a scrolling terminal, and the grid's
    # below-grid region pages long output (PgUp/PgDn / Ctrl-B/F)
    while ((cmd | getline outline) > 0)
        out = out (out != "" ? "\n" : "") outline
    close(cmd)
    t_man(out == "" ? "(no output)" : out)
}

# cat metacommand: show file contents, same shell passthrough as dir.
# Control and high-bit bytes render as "." -- a tokenized .BAS is binary,
# and raw escape bytes could corrupt the grid or exit the alt screen.  The
# byte scrub happens in tr, NOT a gawk gsub: in a UTF-8 locale gawk regexes
# work on characters, and invalid byte sequences slip through the class.
function st_cat(args,   cmd, outline, out) {
    if (args == "") { t_man("USAGE: cat <file...>   (shell passthrough, like dir)"); return }
    if (WINNATIVE) cmd = "type " args " 2>&1"
    else           cmd = "cat -- " args " 2>&1 | LC_ALL=C tr -c '\\11\\12\\40-\\176' '.'"
    out = ""
    while ((cmd | getline outline) > 0) {
        if (WINNATIVE) gsub(/[^\t -~]/, ".", outline)   # best effort natively
        out = out (out != "" ? "\n" : "") outline
    }
    close(cmd)
    t_man(out == "" ? "(no output)" : out)
}

# --- cassette-as-text-file commands ----------------------------------------
# The name is a STRING EXPRESSION, as in Disk BASIC (the ROM evaluates it:
# 2BF8H, 2C32H): "GAME", F$, "PART"+N$, MID$(A$,2).  It is taken as one
# when it starts with a string literal or with a name ending in $ -- a
# string variable or function; until 2026-09-20 only a lone literal was,
# so SAVE F$ wrote a file named F$ and RUN F$ re-ran the program in
# memory.  EXT: anything else is a RAW name, the source text from here to
# the end of the line (case preserved, "/" and "." intact; no ":"-statement
# may follow it -- documented), so LOAD mygame.bas needs no quotes.  The
# cost: an unquoted file name that starts with a $-name cannot be given raw.
function fname_is_expr() {
    return TY[CK, CP] == "s" || (TY[CK, CP] == "i" && TK[CK, CP] ~ /\$$/)
}
function parse_fname(   t, f) {
    t = TY[CK, CP]
    if (fname_is_expr()) {
        f = e_or(); if (E) return ""
        if (isN(f)) { raise(13); return "" }
        return vstr(f)
    }
    if (t == "" || t == "e") return ""
    f = substr(TSRC[CK], TPO[CK, CP])
    gsub(/^[ \t]+|[ \t]+$/, "", f)
    while (!(TY[CK, CP] == "" || TY[CK, CP] == "e")) CP++
    return f
}

function st_csave(   f) {
    f = parse_fname(); if (E) return
    if (f == "") { raise(21); return }
    save_prog(f)
}

function save_prog(f,   i, ln) {
    if ((!WINNATIVE && f ~ /'/) || !host_writable(f)) { raise(22); return }
    printf "" > f
    for (i = 1; i <= NL; i++) { ln = LNS[i]; print ln " " prog[ln] > f }
    close(f)
}

function st_cload(   f, verify) {
    verify = 0
    if (TY[CK, CP] == "o" && TK[CK, CP] == "?") { verify = 1; CP++ }
    f = parse_fname(); if (E) return
    if (f == "") { raise(21); return }
    if (!prog_load(f, verify)) { raise(22); return }
    to_ready()
}

# SYSTEM: the Level II monitor (manual 2-6).  `*?` prompts; a name loads
# that object file; `/` runs it at the file's entry, `/nnnnn` at decimal
# nnnnn; BREAK returns to BASIC.  EXT ONLY IN WHERE THE TAPE COMES FROM,
# exactly as CLOAD: the name is a host file (name, name.cas/.CAS, .cmd/.CMD)
# holding a Model I SYSTEM tape as its byte stream (leader, A5H 55H, the
# six-character name, 3CH blocks with a checksum, 78H entry) or a /CMD load
# module (05H name, 01H load records, 02H entry).  Every byte lands through
# poke_byte, so PEEK, the USR frame and the core see it (built 2026-09-16,
# ruled the same day: the runner for machine-language programs is this
# command, not a separate front end).  A checksum error prints C and
# prompts again, as the manual says; a file that is not there, or is
# neither format, is ?FD like a bad CLOAD.  `/` calls the address through
# the USR frame (p77): the program owns the screen and keyboard until it
# RETurns, reaches 0A9AH, or jumps to the ROM's READY (1A19H), which the
# core serves as "back to BASIC"; then READY, or the next statement when
# a program issued the SYSTEM.  Without a core the
# call is the stub and is tallied as USR's is.  Disk BASIC's SYSTEM
# "command" ran a DOS command: DOS is not served (ruled 2026-09-15), ?FC.
# Why it cannot break a period program: every listing that reaches SYSTEM
# stopped with ?SN before; the corpus holds seven, all waiting for a tape
# or a DOS that is not there.
function st_system(   line, a) {
    if (TY[CK, CP] == "s") {
        diag_err("SYSTEM \"" TK[CK, CP] "\": a DOS command; no DOS is served here (?FC)")
        raise(5); return
    }
    if (!(TY[CK, CP] == "" || TY[CK, CP] == "e")) { raise(2); return }
    if (SYSENTRY == "") SYSENTRY = -1
    for (;;) {
        s_puts("*? ")
        line = rl_read()
        if (RLCANCEL) { dobreak(); return }
        if (EOFQUIT) { if (BATCH) batch_ineof(); STOPPED = 1; return }
        gsub(/^[ \t]+|[ \t]+$/, "", line)
        if (line == "") continue
        # `/` or `/nnnnn` runs; anything else after a slash is a host path
        # (an absolute path is never a valid address, so no listing loses)
        a = substr(line, 2); gsub(/[ \t]/, "", a)
        if (substr(line, 1, 1) == "/" && a ~ /^[0-9]*$/) {
            if (a == "") a = SYSENTRY
            else if (a + 0 > 65535) { raise(5); return }
            if (a + 0 < 0) { raise(5); return }
            sys_exec(a + 0)
            return
        }
        a = sys_load(line)
        if (a == "C") { s_puts("C"); s_nl() }
        else if (a != 1) { raise(22); return }
    }
}

# the host file behind a SYSTEM name, or "": the name as given, then the
# four extensions, first readable wins (slurp_bytes leaves it in SLURPED)
function sys_find(name,   i, f, ext) {
    split("|.cas|.CAS|.cmd|.CMD", ext, "|")
    for (i = 1; i <= 5; i++) {
        f = name ext[i]
        if (slurp_bytes(f) >= 0) return f
    }
    return ""
}

# load a SYSTEM tape or /CMD file: 1, "C" (checksum), "" (no file), "F" (neither format)
# Which format: the file's extension when it has one of ours, as the core's
# loader goes by; otherwise the first byte.  A load module opens with a
# record type (01H, 05H, ...), a tape with its leader of zeros or with A5H
# itself, so that byte tells them apart.  Looking for A5H 55H anywhere came
# first once, and took a load module for a tape whenever its CODE held
# those two bytes -- ordinary Z80 (LD HL,55A5H) -- printing C and loading
# nothing (the 2026-09-19 audit, M-6).
function sys_load(name,   f, data, i, c, ext) {
    f = sys_find(name)
    if (f == "") return ""
    data = SLURPED; SLURPED = ""
    ext = tolower(substr(f, length(f) - 3))
    c = ORD[substr(data, 1, 1)]
    if (ext == ".cmd" || (ext != ".cas" && (c == 1 || c == 2 || c == 5 || c == 7 || c == 31)))
        return sys_load_cmd(data)
    i = index(data, CHR[165])                     # A5H: the tape's sync byte
    if (i > 0 && substr(data, i + 1, 1) == CHR[85]) return sys_load_cas(data, i + 8)
    return "F"
}

# A file that ends with no entry record (78H on a tape, 02H in a load
# module) is a host-file case: on the machine the tape loader never comes
# back without its 78H (it waits at 0235H for the next byte), so there is
# no ROM behavior to follow.  EXT: the entry is then the first block's load
# address, the core loader's rule, so both tools run the same file the same
# way.  Keeping the entry of the file loaded BEFORE had `/` run the previous
# program's code (the 2026-09-19 audit, M-7).  A load that FAILS keeps it,
# as 40DFH is only written at 02ACH, once the 78H record has been read.
function sys_load_cas(data, i,   n, c, cnt, a, sum, j, b, got, first) {
    n = length(data); got = 0
    while (i <= n) {
        c = ORD[substr(data, i, 1)]
        if (c == 60) {                            # 3CH: a data block
            cnt = ORD[substr(data, i + 1, 1)]; if (cnt == 0) cnt = 256
            if (i + 4 + cnt > n) return "C"
            a = ORD[substr(data, i + 2, 1)] + 256 * ORD[substr(data, i + 3, 1)]
            if (!got) first = a
            sum = ORD[substr(data, i + 2, 1)] + ORD[substr(data, i + 3, 1)]
            for (j = 0; j < cnt; j++) {
                b = ORD[substr(data, i + 4 + j, 1)]
                sum += b; poke_byte((a + j) % 65536, b); got++
            }
            if (sum % 256 != ORD[substr(data, i + 4 + cnt, 1)]) return "C"
            i += 5 + cnt
        } else if (c == 120) {                    # 78H: the entry address
            if (i + 2 > n) return "C"
            SYSENTRY = ORD[substr(data, i + 1, 1)] + 256 * ORD[substr(data, i + 2, 1)]
            return got ? 1 : "C"
        } else return "C"
    }
    if (!got) return "C"
    SYSENTRY = first
    return 1
}

function sys_load_cmd(data,   n, i, t, ln, a, j, got, first) {
    n = length(data); i = 1; got = 0
    while (i + 1 <= n) {
        t = ORD[substr(data, i, 1)]; ln = ORD[substr(data, i + 1, 1)]
        if (t == 1 && ln <= 2) ln += 256
        if (i + 1 + ln > n) return "F"
        if (t == 1) {
            a = ORD[substr(data, i + 2, 1)] + 256 * ORD[substr(data, i + 3, 1)]
            if (!got) first = a
            for (j = 0; j < ln - 2; j++) { poke_byte((a + j) % 65536, ORD[substr(data, i + 4 + j, 1)]); got++ }
        } else if (t == 2) {
            if (ln < 2) return "F"
            SYSENTRY = ORD[substr(data, i + 2, 1)] + 256 * ORD[substr(data, i + 3, 1)]
            return got ? 1 : "F"
        } else if (!(t == 5 || t == 7 || t == 16 || t == 26 || t == 31)) return "F"
        i += 2 + ln
    }
    if (!got) return "F"
    SYSENTRY = first
    return 1
}

# run at addr through the USR call frame (p60 usr_resolve fills the frame's
# globals as a USR call would; the address is the monitor's, not the vector's)
function sys_exec(addr) {
    usr_resolve("USR", 0)
    USR_ENTRY = addr
    z80_usr(0)
}

# Disk BASIC LOAD "file"[,R]: host-file CLOAD.  ,R = run after loading,
# keeping open file channels (the manual's chaining device).  The flag is
# only reachable after a QUOTED name -- an unquoted name runs to end of
# line, same as CLOAD.
function st_load(   f, keep) {
    f = parse_fname(); if (E) return
    if (f == "") { raise(21); return }
    keep = 0
    if (TY[CK, CP] == "o" && TK[CK, CP] == ",") {
        CP++
        if (TY[CK, CP] == "i" && TK[CK, CP] == "R") { CP++; keep = 1 }
        else { raise(2); return }
    }
    if (!prog_load(f, 0, keep)) { raise(22); return }
    if (keep) run_start(0, 1)
    else to_ready()
}

# Disk BASIC MERGE "file": read a listing into the CURRENT program -- no
# implicit NEW.  File lines overwrite same-numbered lines and interleave
# with the rest.  Variables clear and BASIC returns to command level (the
# TRSDOS behavior), so a MERGE issued by a running program stops it --
# which also sidesteps executing from a shifted line table.
function st_merge(   f) {
    f = parse_fname(); if (E) return
    if (f == "") { raise(21); return }
    if (!prog_load(f, 0, 0, 1)) { raise(22); return }
    HALT = 1
}

# Disk BASIC SAVE "file"[,V]: host-file CSAVE.  ,V (verify) is accepted and
# ignored -- host writes don't need a cassette verify pass.
function st_save(   f) {
    f = parse_fname(); if (E) return
    if (f == "") { raise(21); return }
    if (TY[CK, CP] == "o" && TK[CK, CP] == ",") {
        CP++
        if (TY[CK, CP] == "i" && TK[CK, CP] == "V") CP++
        else { raise(2); return }
    }
    save_prog(f)
}

# Disk BASIC NAME [n[,[m][,i]]]: renumber.  Lines >= m (default: the whole
# program) get numbers n, n+i, ... (defaults 10, 10); every line-number
# reference in the WHOLE program -- GOTO/GOSUB (incl. ON.. lists), THEN,
# ELSE, RESTORE, RESUME, RUN -- is rewritten in the stored source text,
# spacing preserved (the splice uses the tokenizer's source offsets).
# ERL comparisons cannot be fixed (the manual's own caveat).  References
# to lines that do not exist print UNDEFINED LINE x IN y and stay put;
# ON ERROR GOTO 0 and RESUME 0 keep their special 0.  ?FC when i < 1, the
# new numbers would pass 65529, or the renumbered block would collide with
# or reorder around the un-renumbered head.  Returns to command level.
function st_name(   n, m, i, j, cnt, ln, maxbelow, newn, map, newprog, wa, wn, wi) {
    n = 10; m = 0; i = 10
    if (TY[CK, CP] == "n") { n = int(TK[CK, CP] + 0); CP++ }
    if (TY[CK, CP] == "o" && TK[CK, CP] == ",") {
        CP++
        if (TY[CK, CP] == "n") { m = int(TK[CK, CP] + 0); CP++ }
        if (TY[CK, CP] == "o" && TK[CK, CP] == ",") {
            CP++
            if (TY[CK, CP] == "n") { i = int(TK[CK, CP] + 0); CP++ }
        }
    }
    if (i < 1 || n > 65529) { raise(5); return }
    if (NL == 0) return
    # build old -> new and validate BEFORE touching anything
    cnt = 0; maxbelow = -1
    for (j = 1; j <= NL; j++) {
        ln = LNS[j]
        if (ln < m) { maxbelow = ln; continue }
        newn = n + cnt * i; cnt++
        if (newn > 65529) { raise(5); return }
        map[ln] = newn
    }
    if (cnt == 0) return
    if (maxbelow >= n) { raise(5); return }
    NAMEWARN = ""
    for (j = 1; j <= NL; j++) {
        ln = LNS[j]
        newprog[(ln in map) ? map[ln] : ln] = name_rewrite(prog[ln], ln, map)
        inval_cache(ln)
    }
    delete prog
    delete ESC                      # renumbering rewrites text; the escrowed
                                    # bytes would be stale, so every line is
                                    # text again (R1 ruling, 2026-09-12)
    for (ln in newprog) prog[ln] = newprog[ln]
    rebuild()
    if (LASTLN in map) LASTLN = map[LASTLN]
    DATADIRTY = 1; CONTOK = 0
    if (NAMEWARN != "") {
        wn = split(NAMEWARN, wa, "\n")
        for (wi = 1; wi <= wn; wi++) if (wa[wi] != "") { s_puts(wa[wi]); s_nl() }
    }
    HALT = 1                                # a command: back to command level
}

# rewrite the line-number reference tokens of one line per map; append any
# undefined-target warnings to NAMEWARN
function name_rewrite(text, oldln, map,   t, ty, tx, out, last, o, len, val, list, skip0, prev) {
    tokline("R", text)
    out = ""; last = 1; prev = ""
    for (t = 1; t <= TCN["R"]; t++) {
        ty = TY["R", t]; tx = TK["R", t]
        if (ty == "i" && (tx == "GOTO" || tx == "GOSUB" || tx == "THEN" || \
                          tx == "ELSE" || tx == "RESTORE" || tx == "RESUME" || tx == "RUN")) {
            list = (tx == "GOTO" || tx == "GOSUB")      # ON.. comma lists
            skip0 = (tx == "RESUME" || (tx == "GOTO" && prev == "ERROR"))
            prev = tx
            for (;;) {
                t++
                if (!(TY["R", t] == "n" && TK["R", t] ~ /^[0-9]+$/)) { t--; break }
                val = TK["R", t] + 0
                if (!(skip0 && val == 0)) {
                    if (val in map) {
                        o = TPO["R", t]
                        match(substr(text, o), /^[0-9]+/); len = RLENGTH
                        out = out substr(text, last, o - last) map[val]
                        last = o + len
                    } else if (!(val in prog))
                        NAMEWARN = NAMEWARN "UNDEFINED LINE " val " IN " oldln "\n"
                }
                if (!(list && TY["R", t + 1] == "o" && TK["R", t + 1] == ",")) break
                t++                                     # past the comma
            }
            continue
        }
        prev = (ty == "i") ? tx : ""
    }
    out = out substr(text, last)
    inval_cache_key("R")
    return out
}

# read a text listing into prog[] (CLOAD, MERGE, and the batch-mode program
# load).  verify=1 is CLOAD? -- compare only, don't touch prog[].  merge=1
# (MERGE) keeps the current program: file lines overwrite/interleave instead
# of replacing it.  Returns 0 if the file can't be opened; sets LOADBAD=1 if
# any line was rejected.
function prog_load(f, verify, keepfiles, merge,   l, r, ln, rest, bad, x, nseen, ok, pln, rpt, ra, ri, nn, data, fl, nfl) {
    LOADBAD = 0
    # R1 (2026-09-12): a TOKENIZED image -- the 0xFF-headed cassette/disk
    # form every archived TRS-80 program is in -- loads directly.  The file
    # is read once as bytes to look for the header; a text listing falls
    # through to the line loop below, re-read the ordinary way.
    r = slurp_bytes(f)
    if (r < 0) return 0
    if (r > 0) {
        # Under gawk -b every one-byte string is a key of ORD[].  A first
        # character that is NOT is an invalid multibyte sequence: the run is
        # not byte mode and the file is binary, so say that instead of the
        # four "NO LINE NUMBER" lines the text path would print (seen
        # 2026-09-12 when a stale launcher without -b met a tokenized image).
        # This test MUST precede tok_header(): a bare ORD[x] reference
        # auto-creates the key x, which would make this membership test lie.
        if (!(substr(SLURPED, 1, 1) in ORD)) {
            SLURPED = ""; LOADBAD = 1
            diag("?FD ERROR - BINARY FILE: run the interpreter as ./basic (gawk -b) to load a tokenized image")
            return 1
        }
        if (tok_header(SLURPED)) { data = SLURPED; SLURPED = ""; return prog_load_tok(data, verify, keepfiles, merge) }
    }
    # A text listing ends its lines with LF, CR LF or CR alone.  CR alone is
    # the TRS-80's own ASCII save format (SAVE "F",A), and a record reader
    # that knows only LF took such a file for ONE line and stored it under
    # its first line number.  So the lines are cut from the bytes already
    # read.  In a CR file -- no CR LF pair anywhere, and more CRs than LFs
    # -- an LF is NOT a line end: it is the line feed the down arrow puts
    # INSIDE a line (a REM or a PRINT string that continues on the next
    # screen row), and it stays in the line.  Any other file is cut at LF
    # with one CR before it dropped, as before.  tools/tok.py cuts the
    # same way.  A sector-padded file ends in a run of 00H (or a
    # 1AH end mark): that is not a line.
    data = SLURPED; SLURPED = ""
    sub(/[\000\032]+$/, "", data)
    if (data !~ /\r\n/ && gsub(/\r/, "\r", data) > gsub(/\n/, "\n", data)) {
        sub(/\r$/, "", data)
        nfl = (data == "") ? 0 : split(data, fl, "\r")
    } else {
        sub(/\n$/, "", data)
        nfl = (data == "") ? 0 : split(data, fl, "\n")
        for (x = 1; x <= nfl; x++) sub(/\r$/, "", fl[x])
    }
    data = ""
    if (!verify) {
        if (!merge) { for (x in prog) { inval_cache(x); delete prog[x] }; delete ESC }
        clear_vars(keepfiles)
        NDATA = 0; DP = 1; CONTOK = 0
    }
    ok = 1; nseen = 0
    for (pln = 1; pln <= nfl; pln++) {
        l = fl[pln]
        sub(/^[ \t]+/, "", l)
        if (l != "") {
            if (l ~ /^[0-9]+/) {
                match(l, /^[0-9]+/)
                ln = substr(l, 1, RLENGTH) + 0
                rest = substr(l, RLENGTH + 1)
                sub(/^ /, "", rest)
                if (ln > 65529) { bad = 1; rpt = rpt "?FD ERROR - FILE LINE " pln " (LINE NUMBER > 65529)\n" }
                else if (rest == "") { bad = 1; rpt = rpt "?FD ERROR - FILE LINE " pln " (EMPTY LINE BODY)\n" }
                else if (verify) {
                    nseen++
                    if (!(ln in prog) || prog[ln] != rest) ok = 0
                } else { prog[ln] = rest; delete ESC[ln]; inval_cache(ln); LASTLN = ln }
            } else { bad = 1; rpt = rpt "?FD ERROR - FILE LINE " pln " (NO LINE NUMBER)\n" }
        }
    }
    LOADBAD = (bad ? 1 : 0)
    if (verify) {
        for (x in prog) nseen--
        if (nseen != 0) ok = 0
        if (!ok) diag("BAD")
    } else {
        rebuild()
        DATADIRTY = 1
        if (bad) {
            nn = split(rpt, ra, "\n")
            for (ri = 1; ri <= nn; ri++) if (ra[ri] != "") diag(ra[ri])
        }
    }
    return 1
}

# read a whole file as one byte string into SLURPED.  Returns -1 if it cannot
# be opened, 0 if empty, 1 otherwise.  RS = "^$" never matches, so the first
# record is the entire file; with gawk -b every byte is one character, NULs
# included.  RS = "\0" is NOT an option: a line number below 256 has a 00 high
# byte and would split the record inside the line header.
function slurp_bytes(f,   save, r) {
    if (host_special(f)) { SLURPED = ""; return -1 }   # a socket or a descriptor, not a file (p90)
    save = RS; RS = "^$"
    r = (getline SLURPED < f)
    RS = save
    close(f)
    if (r < 0) { SLURPED = ""; return -1 }
    if (r == 0) { SLURPED = ""; return 0 }
    return 1
}

# the 0xFF header of a tokenized image, within the first four bytes (some
# archived files carry a byte or two of junk ahead of an intact header)
function tok_header(data,   i, c) {
    for (i = 1; i <= 4 && i <= length(data); i++) {
        c = substr(data, i, 1)
        # membership before indexing: a bare ORD[c] would auto-create the key
        if (c in ORD && ORD[c] == 255) { TOKHDR = i; return 1 }
    }
    return 0
}

# ---- R1: THE TOKENIZED LOADER (ruled 2026-09-10, built 2026-09-12) ---------
# A tokenized image is what the 1978 machine wrote to tape and what nearly
# every archived TRS-80 program is.  Converting one to text first (detok)
# is lossy for exactly the programs that matter to the Z80 core: a machine-
# language payload stored as fake BASIC lines can hold CR/LF bytes an ASCII
# listing cannot carry (Dancing Demon: 14 such bytes, all inside the payload,
# 0DH being DEC C), so the converted copy executes corrupted instructions
# with no error.  The escrow keeps the ORIGINAL BODY BYTES of every line that
# arrived this way -- ESC[ln] -- and pm_build (p75) images those bytes
# verbatim instead of re-crunching the text, so PEEK into the image and the
# USR frame see the file's bytes exactly, relinked at 42E9H.  prog[ln] holds
# the detokenized text (pm_detok, p75, keyword spacing included) for LIST,
# EDIT and RUN, and is what a program's real BASIC lines run from.
#
# THE THREE USER-VISIBLE DECISIONS, taken 2026-09-12 (the defaults the
# session recommended; the user did not object):
#   * LIST shows the detokenized text, as the machine's LIST did.  A payload
#     line lists as the glyph soup it always listed as.
#   * The loader is ONE-WAY: CSAVE and SAVE write text, as before.  Writing
#     the tokenized form back is a separate feature if it is ever wanted.
#   * ESCROW INVALIDATION: any typed replacement of a line (storeline, AUTO),
#     DELETE, NEW, MERGE of a text file over the line, and NAME (renumber,
#     which drops EVERY line's escrow, since it rewrites references in
#     text) turn the line back into text.  A line the program never touches
#     keeps its bytes for the life of the program.
#
# Desync signals stop the walk where they occur and are reported like the
# text loader's ?FD lines (LOADBAD, batch exit 2): a truncated header, an
# unterminated line, a line number above 65529, a duplicate line number.
# Lines before the desync stay loaded.  An empty body (real images carry
# them) is kept empty in the image and shown as REM in the text, which is
# what detok does and what keeps the line a valid branch target.
#
# Verification (finding 8b, seam audit): payload lines are NOT excluded
# from datascan.  The ROM's READ scans the program bytes for the DATA token
# and would consume a payload's 88H bytes the same way, so including them
# is the authentic behaviour; the earlier note asked for exclusion on the
# assumption that it was an artefact of text scanning.
function prog_load_tok(data, verify, keepfiles, merge,   n, pos, nxt, ln, z, body, x, bad, rpt, rec, ok, nseen, text, ra, ri, nn, seen) {
    n = length(data)
    pos = TOKHDR + 1
    if (!verify) {
        if (!merge) { for (x in prog) { inval_cache(x); delete prog[x] }; delete ESC }
        clear_vars(keepfiles)
        NDATA = 0; DP = 1; CONTOK = 0
    }
    ok = 1; nseen = 0; rec = 0; bad = 0
    for (;;) {
        if (pos + 1 > n) {                       # fewer than the 2 end-marker bytes left
            if (pos <= n) { bad = 1; rpt = rpt "?FD ERROR - FILE LINE " (rec + 1) " (TRUNCATED HEADER)\n" }
            break
        }
        nxt = ORD[substr(data, pos, 1)] + 256 * ORD[substr(data, pos + 1, 1)]
        if (nxt == 0) break                      # the 00 00 end of program
        if (pos + 3 > n) { bad = 1; rpt = rpt "?FD ERROR - FILE LINE " (rec + 1) " (TRUNCATED HEADER)\n"; break }
        ln = ORD[substr(data, pos + 2, 1)] + 256 * ORD[substr(data, pos + 3, 1)]
        rec++
        z = index(substr(data, pos + 4), CHR[0])
        if (z == 0) { bad = 1; rpt = rpt "?FD ERROR - FILE LINE " rec " (UNTERMINATED LINE)\n"; break }
        body = substr(data, pos + 4, z - 1)
        pos += 4 + z
        if (ln > 65529) { bad = 1; rpt = rpt "?FD ERROR - FILE LINE " rec " (LINE NUMBER > 65529)\n"; break }
        if (ln in seen) { bad = 1; rpt = rpt "?FD ERROR - FILE LINE " rec " (DUPLICATE LINE NUMBER)\n"; break }
        seen[ln] = 1
        text = pm_detok(body)
        if (text == "") text = "REM"
        if (verify) {
            nseen++
            if (!(ln in prog) || prog[ln] != text) ok = 0
        } else { prog[ln] = text; ESC[ln] = body; inval_cache(ln); LASTLN = ln }
    }
    LOADBAD = (bad ? 1 : 0)
    if (verify) {
        for (x in prog) nseen--
        if (nseen != 0) ok = 0
        if (!ok) diag("BAD")
    } else {
        rebuild()
        DATADIRTY = 1
        if (bad) {
            nn = split(rpt, ra, "\n")
            for (ri = 1; ri <= nn; ri++) if (ra[ri] != "") diag(ra[ri])
        }
    }
    return 1
}
# ===================== command line and batch (non-interactive) mode ========
# With a filename argument the interpreter LOADs and RUNs the program, then
# exits.  stdin belongs entirely to the running program (INPUT/LINE INPUT/
# INKEY$ consume it in order); interpreter messages go to stderr so stdout
# carries only what the program PRINTs.  No timeout guard is built in --
# wrap the invocation in the shell's `timeout` if a program may not halt.
#
# Exit status:  0 clean halt (END, STOP, BYE, or falling off the end)
#               1 uncaught BASIC error, or stdin exhausted at an INPUT
#               2 bad arguments, unreadable file, or unloadable source

# parse ARGV; returns 0 on a usage error.  Sets BATCH/BATCHFILE, OPT_SCREEN,
# SEEDED/OPT_SEED, OPT_MEMSIZE, OPT_HELP.  gawk never reads the operands itself: the whole
# interpreter lives in BEGIN and exits there.
function parse_args(   i, a, nofl) {
    BATCH = 0; BATCHFILE = ""; OPT_SCREEN = 0; OPT_HELP = 0
    SEEDED = 0; OPT_SEED = 0; OPT_MEMSIZE = 0; nofl = 0
    for (i = 1; i < ARGC; i++) {
        a = ARGV[i]
        if (!nofl && a == "--") { nofl = 1; continue }
        if (!nofl && a == "--seed") {
            if (++i >= ARGC || ARGV[i] !~ /^-?[0-9]+$/) {
                ARGMSG = "--seed needs an integer"
                return 0
            }
            OPT_SEED = ARGV[i] + 0; SEEDED = 1
            continue
        }
        if (!nofl && a ~ /^--seed=/) {
            a = substr(a, 8)
            if (a !~ /^-?[0-9]+$/) { ARGMSG = "--seed needs an integer"; return 0 }
            OPT_SEED = a + 0; SEEDED = 1
            continue
        }
        # --memsize N: the answer to MEMORY SIZE?, for a run that has no
        # prompt to answer.  Batch mode otherwise sees all 64K, and a period
        # program written on a 16K machine can depend on a smaller one: it
        # makes an address byte signed (IF H>127 THEN H=H-256) and POKEs it,
        # which is ?FC wherever string space sits above 32767.
        if (!nofl && (a == "--memsize" || a ~ /^--memsize=/)) {
            if (a == "--memsize") a = (++i < ARGC) ? ARGV[i] : ""
            else a = substr(a, 11)
            if (a !~ /^[0-9]+$/ || a + 0 < 17280 || a + 0 > 65535) {
                ARGMSG = "--memsize needs an address from 17280 to 65535"
                return 0
            }
            OPT_MEMSIZE = a + 0
            continue
        }
        if (!nofl && a == "--screen") { OPT_SCREEN = 1; continue }
        if (!nofl && (a == "-h" || a == "--help")) { OPT_HELP = 1; return 1 }
        if (!nofl && a ~ /^-./) { ARGMSG = "unknown option " a; return 0 }
        if (BATCHFILE != "") { ARGMSG = "only one program file may be given"; return 0 }
        BATCHFILE = a; BATCH = 1
    }
    return 1
}

# dest "" = stdout (--help), "/dev/stderr" = usage error (with the reason)
function usage(dest,   t) {
    t = "Usage: basic [options] [program.bas]\n" \
        "\n" \
        "With a program file, LOAD and RUN it non-interactively, then exit.\n" \
        "With no file, start the interactive READY prompt.\n" \
        "\n" \
        "  --seed N     seed RND for repeatable runs (RANDOM re-applies N)\n" \
        "  --memsize N  answer MEMORY SIZE? with N (17280-65535); 32767 is a\n" \
        "               16K machine, for programs that only ran on one\n" \
        "  --screen     keep the TRS-80 screen/cursor control codes\n" \
        "               (output is plain text by default without a tty)\n" \
        "  -h, --help   show this message\n" \
        "  --           end of options\n" \
        "\n" \
        "Exit status: 0 clean run, 1 BASIC runtime error, 2 bad invocation.\n" \
        "stdin feeds the program's own INPUT statements; BASIC errors go to\n" \
        "stderr as \"?SN ERROR IN 40\".  Use the shell's `timeout` to bound a\n" \
        "program that may not halt."
    if (dest == "") { printf "%s\n", t; return }
    if (ARGMSG != "") printf "basic: %s\n", ARGMSG > "/dev/stderr"
    printf "%s\n", t > "/dev/stderr"
}

# LOAD + RUN the batch program; returns the process exit status
function batch_main() {
    BATCHERR = 0
    if (!prog_load(BATCHFILE, 0)) {
        # /dev/stdin and the shell's <(...) (/dev/fd/N) are refused by name
        # (host_special, p90), and "cannot read" alone sent the user looking
        # for a missing file (the 2026-09-19 audit, M-23)
        if (host_special(BATCHFILE))
            diag_err("basic: cannot read '" BATCHFILE "': a device, descriptor or socket name is not taken for a program; give a file (stdin feeds the program's INPUT)")
        else diag_err("basic: cannot read '" BATCHFILE "'")
        return 2
    }
    if (LOADBAD) return 2                   # ?FD lines already on stderr
    exec_immediate("RUN")                   # the same path as typing RUN
    return (BATCHERR ? 1 : 0)
}

# an interpreter message (not program output): stderr in batch, the simulated
# screen when interactive
function diag(msg) {
    if (BATCH) diag_err(msg)
    else { s_puts(msg); s_nl() }
}

function diag_err(msg) {
    fflush()                                # keep stdout/stderr in order
    printf "%s\n", msg > "/dev/stderr"
    fflush("/dev/stderr")
}

# stdin ran dry while an INPUT was waiting: the fixture under-fed the program
function batch_ineof() {
    BATCHERR = 1
    diag_err("?BATCH: END OF INPUT" (CLN > 0 ? " AT LINE " CLN : ""))
}
# ===================== tokenizer ============================================
# Token types: n number, s string, i identifier/keyword (uppercase), o op,
#              d DATA payload, r REM payload, e end sentinel.

function tokline(key, text,   i, n, c, c2, k, s, j, q, two, t0) {
    if (key == "I") inval_cache_key("I")
    k = 0; i = 1; n = length(text)
    TSRC[key] = text                        # raw source + per-token offsets
    while (i <= n) {                        # (parse_fname reads paths verbatim)
        c = substr(text, i, 1)
        if (c == " " || c == "\t") { i++; continue }
        t0 = i
        if (c == "\"") {
            j = index(substr(text, i + 1), "\"")
            if (j == 0) { s = substr(text, i + 1); i = n + 1 }
            else { s = substr(text, i + 1, j - 1); i = i + j + 1 }
            k++; TK[key, k] = s; TY[key, k] = "s"
            continue
        }
        if (c ~ /[0-9]/ || (c == "." && substr(text, i + 1, 1) ~ /[0-9]/)) {
            match(substr(text, i), /^([0-9]+\.?[0-9]*|\.[0-9]+)([EeDd][-+]?[0-9]+)?/)
            s = substr(text, i, RLENGTH); i += RLENGTH
            sub(/[Dd]/, "E", s)             # D exponent: same value, E form for awk
            c = substr(text, i, 1)
            if (c == "!" || c == "#" || c == "%") i++
            k++; TK[key, k] = s; TY[key, k] = "n"; TPO[key, k] = t0
            continue
        }
        if (c ~ /[A-Za-z]/) {
            match(substr(text, i), /^[A-Za-z][A-Za-z0-9]*\$?/)
            s = toupper(substr(text, i, RLENGTH)); i += RLENGTH
            c = substr(text, i, 1)
            # "#" is a type suffix on variables (X#) but a channel marker
            # after PRINT/INPUT (PRINT#1), where it must stay an operator
            if (c == "!" || c == "%") i++
            else if (c == "#" && s != "PRINT" && s != "INPUT") i++
            if (s == "REM") {
                k++; TK[key, k] = "REM"; TY[key, k] = "i"
                k++; TK[key, k] = substr(text, i); TY[key, k] = "r"
                i = n + 1
                continue
            }
            if (s == "DATA") {
                k++; TK[key, k] = "DATA"; TY[key, k] = "i"
                q = 0; j = i
                while (j <= n) {
                    c2 = substr(text, j, 1)
                    if (c2 == "\"") q = !q
                    else if (c2 == ":" && !q) break
                    j++
                }
                k++; TK[key, k] = substr(text, i, j - i); TY[key, k] = "d"
                i = j
                continue
            }
            k++; TK[key, k] = s; TY[key, k] = "i"; TPO[key, k] = t0
            continue
        }
        if (c == "'") {
            k++; TK[key, k] = "REM"; TY[key, k] = "i"
            k++; TK[key, k] = substr(text, i + 1); TY[key, k] = "r"
            i = n + 1
            continue
        }
        if (c == "&" && toupper(substr(text, i + 1, 1)) ~ /^[HO]$/) {
            c2 = toupper(substr(text, i + 1, 1))    # &H/&O literal (Disk
            if (c2 == "H") match(substr(text, i + 2), /^[0-9A-Fa-f]+/)  # BASIC)
            else           match(substr(text, i + 2), /^[0-7]+/)
            if (RLENGTH > 0) {
                s = substr(text, i + 2, RLENGTH)
                j = (c2 == "H") ? strtonum("0x" s) : strtonum("0" s)
                i += 2 + RLENGTH
                k++; TY[key, k] = "n"; TPO[key, k] = t0
                # 16-bit two's complement per Microsoft (&HFFFF = -1);
                # more than 16 bits overflows -- a huge token makes eval
                # raise ?OV exactly like an out-of-range decimal literal
                TK[key, k] = (j > 65535) ? "1E99" : "" toS(j)
                continue
            }
        }
        two = substr(text, i, 2)
        if (two == "<=" || two == "=<") { k++; TK[key, k] = "<="; TY[key, k] = "o"; TPO[key, k] = t0; i += 2; continue }
        if (two == ">=" || two == "=>") { k++; TK[key, k] = ">="; TY[key, k] = "o"; TPO[key, k] = t0; i += 2; continue }
        if (two == "<>" || two == "><") { k++; TK[key, k] = "<>"; TY[key, k] = "o"; TPO[key, k] = t0; i += 2; continue }
        k++; TK[key, k] = c; TY[key, k] = "o"; TPO[key, k] = t0
        i++
    }
    k++; TK[key, k] = ""; TY[key, k] = "e"; TPO[key, k] = n + 1
    TCN[key] = k; TOKD[key] = 1
}

function inval_cache_key(k,   i) {
    if (k in TOKD) {
        for (i = 1; i <= TCN[k]; i++) { delete TK[k, i]; delete TY[k, i]; delete TPO[k, i] }
        delete TCN[k]; delete TOKD[k]; delete TSRC[k]
    }
}
# ===================== expression evaluator =================================
# Values: "N<number>" or "S<string>".  Precedence (LEVEL II):
#   ^  unary-  * /  + -  relational  NOT  AND  OR

function num(v) { return substr(v, 2) + 0 }
function vstr(v) { return substr(v, 2) }
function isN(v) { return substr(v, 1, 1) == "N" }

function e_or(   v, r) {
    v = e_and()
    while (!E && TY[CK, CP] == "i" && TK[CK, CP] == "OR") {
        CP++; r = e_and(); if (E) return v
        v = "N" bor16(v, r)
    }
    return v
}

function e_and(   v, r) {
    v = e_not()
    while (!E && TY[CK, CP] == "i" && TK[CK, CP] == "AND") {
        CP++; r = e_not(); if (E) return v
        v = "N" band16(v, r)
    }
    return v
}

function e_not(   v) {
    if (TY[CK, CP] == "i" && TK[CK, CP] == "NOT") {
        CP++
        v = e_not(); if (E) return v
        if (!isN(v)) { raise(13); return v }
        return "N" (-(to16(num(v)) + 1))
    }
    return e_rel()
}

function e_rel(   v, r, op, a, b, c) {
    v = e_add()
    while (!E && TY[CK, CP] == "o" && \
           (TK[CK, CP] == "=" || TK[CK, CP] == "<" || TK[CK, CP] == ">" || \
            TK[CK, CP] == "<=" || TK[CK, CP] == ">=" || TK[CK, CP] == "<>")) {
        op = TK[CK, CP]; CP++
        r = e_add(); if (E) return v
        if (isN(v) != isN(r)) { raise(13); return v }
        if (isN(v)) { a = num(v); b = num(r) } else { a = vstr(v); b = vstr(r) }
        if (op == "=") c = (a == b)
        else if (op == "<") c = (a < b)
        else if (op == ">") c = (a > b)
        else if (op == "<=") c = (a <= b)
        else if (op == ">=") c = (a >= b)
        else c = (a != b)
        v = "N" (c ? -1 : 0)
    }
    return v
}

function e_add(   v, r, op, x) {
    v = e_mul()
    while (!E && TY[CK, CP] == "o" && (TK[CK, CP] == "+" || TK[CK, CP] == "-")) {
        op = TK[CK, CP]; CP++
        r = e_mul(); if (E) return v
        if (op == "+") {
            if (!isN(v) && !isN(r)) { v = "S" vstr(v) vstr(r); continue }
            if (isN(v) != isN(r)) { raise(13); return v }
            x = num(v) + num(r)
        } else {
            if (!isN(v) || !isN(r)) { raise(13); return v }
            x = num(v) - num(r)
        }
        if (x > 1.7e38 || x < -1.7e38) { raise(6); return v }
        v = "N" x
    }
    return v
}

function e_mul(   v, r, op, x, d) {
    v = e_un()
    while (!E && TY[CK, CP] == "o" && (TK[CK, CP] == "*" || TK[CK, CP] == "/")) {
        op = TK[CK, CP]; CP++
        r = e_un(); if (E) return v
        if (!isN(v) || !isN(r)) { raise(13); return v }
        if (op == "*") x = num(v) * num(r)
        else {
            d = num(r)
            if (d == 0) { raise(11); return v }
            x = num(v) / d
        }
        if (x > 1.7e38 || x < -1.7e38) { raise(6); return v }
        v = "N" x
    }
    return v
}

function e_un(   v) {
    if (TY[CK, CP] == "o" && TK[CK, CP] == "-") {
        CP++
        v = e_un(); if (E) return v
        if (!isN(v)) { raise(13); return v }
        return "N" (-num(v))
    }
    if (TY[CK, CP] == "o" && TK[CK, CP] == "+") { CP++; return e_un() }
    return e_pow()
}

function e_pow(   v, r, a, b, x) {
    v = e_prim()
    while (!E && TY[CK, CP] == "o" && (TK[CK, CP] == "^" || TK[CK, CP] == "[")) {
        CP++
        r = e_powrhs(); if (E) return v
        if (!isN(v) || !isN(r)) { raise(13); return v }
        a = num(v); b = num(r)
        if (a < 0 && b != int(b)) { raise(5); return v }
        if (a == 0 && b < 0) { raise(11); return v }
        x = a ^ b
        if (x > 1.7e38 || x < -1.7e38) { raise(6); return v }
        v = "N" x
    }
    return v
}

# right-hand side of ^: allows unary sign but not another ^ (left-assoc)
function e_powrhs(   v) {
    if (TY[CK, CP] == "o" && TK[CK, CP] == "-") {
        CP++
        v = e_powrhs(); if (E) return v
        if (!isN(v)) { raise(13); return v }
        return "N" (-num(v))
    }
    if (TY[CK, CP] == "o" && TK[CK, CP] == "+") { CP++; return e_powrhs() }
    return e_prim()
}

function e_prim(   t, s, v, key) {
    t = TY[CK, CP]
    if (t == "n") {
        s = TK[CK, CP] + 0; CP++
        if (s > 1.7e38 || s < -1.7e38) { raise(6); return "N0" }   # 1E39 etc.
        return "N" s
    }
    if (t == "s") { v = "S" TK[CK, CP]; CP++; return v }
    if (t == "o" && TK[CK, CP] == "(") {
        CP++
        v = e_or(); if (E) return v
        if (TY[CK, CP] == "o" && TK[CK, CP] == ")") CP++
        else raise(2)
        return v
    }
    if (t == "i") {
        s = TK[CK, CP]
        # NOT where an operand is expected (5+NOT 0, -NOT 0, 2*NOT X): the
        # ROM meets the token in its operand reader and evaluates what
        # follows at NOT's own precedence (5AH: above AND and OR, below the
        # relationals and the arithmetic), so 5+NOT 0+1 is 5+(NOT 1).
        # It is never a variable named NOT.
        if (s == "NOT")    return e_not()
        if (s == "ERR")    { CP++; return "N" ERRV }
        if (s == "ERL")    { CP++; return "N" ERLV }
        if (s == "MEM")    { CP++; return "N" 15572 }
        if (s == "TIME$")  { CP++; return "S" strftime("%m/%d/%y %H:%M:%S") }
        if (s == "INKEY$") { CP++; return fn_inkey() }
        # USR: ML stub, never a variable.  When the spelling carries no
        # slot digit, one may follow as its own token -- real Level II
        # tokenizes past the space, so X=USR 0(n) is legal.  This is the
        # CALL-site twin of the DEF USR 0= fix (c61fdae5): that one
        # covered the definition only, and 134 rescued listings use the
        # spaced call form (Z80 sub-project FINDING 17).  The digit is
        # CARRIED into the name (USR 1( dispatches as USR1) so the slot
        # reaches usr_resolve -- until 2026-09-10 it was dropped here.
        if (s ~ /^USR[0-9]?$/) {
            if (s == "USR" && TY[CK, CP + 1] == "n" &&
                TK[CK, CP + 1] ~ /^[0-9]$/ &&
                TY[CK, CP + 2] == "o" && TK[CK, CP + 2] == "(") { CP++; s = s TK[CK, CP] }
            return fncall(s)
        }
        if (s == "VARPTR") { CP++; return fn_varptr() }   # p75, never a variable
        # user-defined functions, DEFINED-FIRST: an FN-prefixed identifier
        # is a call only when a DEF has executed for it -- otherwise it
        # stays a plain variable/array (three period listings in the
        # runnable corpus use FN* names as arrays; measured 2026-08-13)
        if (s ~ /^FN./ && (substr(s, 3) in FNPAR)) return fn_user(substr(s, 3))
        if (s == "FN" && TY[CK, CP + 1] == "i" && (TK[CK, CP + 1] in FNPAR)) {
            CP++                                  # spaced call: FN AB(1)
            return fn_user(TK[CK, CP])
        }
        if (index(FNLIST, " " s " ") > 0) return fncall(s)
        CP++
        if (TY[CK, CP] == "o" && TK[CK, CP] == "(") {
            key = aref(s); if (E) return "N0"
            if (ALN && (("A" key) in ALIAS)) return "S" al_read("A" key)   # finding 7 (p75)
            if (key in VA) return VA[key]
            return strname(s) ? "S" : "N0"
        }
        if (strname(s)) return "S" ((ALN && (("V" s) in ALIAS)) ? al_read("V" s) : SV[s])
        return "N" (NV[s] + 0)
    }
    raise(2)
    return "N0"
}

# ---- array reference: at "(", returns storage key; auto-DIM 10 -------------
function aref(name,   nd, i, v, idx, key, idxs) {
    CP++                                    # past "("
    nd = 0
    for (;;) {
        # idxs must be LOCAL: this e_or() can recurse into a nested aref
        # (A(B(1),C(1))), and a shared buffer would let the inner access
        # clobber the outer one's accumulated subscripts -- silently.
        v = e_or(); if (E) return ""
        if (!isN(v)) { raise(13); return "" }
        idx = bfloor(num(v))
        nd++; idxs[nd] = idx
        if (TY[CK, CP] == "o" && TK[CK, CP] == ",") { CP++; continue }
        break
    }
    if (TY[CK, CP] == "o" && TK[CK, CP] == ")") CP++
    else { raise(2); return "" }
    if (!(name in ADIM)) {
        ADIM[name] = nd
        for (i = 1; i <= nd; i++) ASZ[name, i] = 10
    }
    if (ADIM[name] != nd) { raise(9); return "" }
    key = name
    for (i = 1; i <= nd; i++) {
        if (idxs[i] < 0 || idxs[i] > ASZ[name, i]) { raise(9); return "" }
        key = key SUBSEP idxs[i]
    }
    return key
}

# ---- user-defined functions (DEF FN) ---------------------------------------
# Entered with CP at the FN name token.  Args are evaluated in the CALLER's
# scope first; parameters are plain global variables saved, bound, and
# restored around the body (MS BASIC shadowing -- recursion nests correctly
# because each frame saves the previous binding).  The body is evaluated by
# pointing CK/CP at the position st_deffn stored, then restoring them.
# Runaway recursion raises ?OM at depth 50; a body error unwinds every
# frame with bindings restored.
function fn_user(name,   n, i, p, v, r, sk, sp, av, osn, osv) {
    CP++
    n = FNPAR[name]
    if (n > 0) {
        if (!(TY[CK, CP] == "o" && TK[CK, CP] == "(")) { raise(2); return "N0" }
        CP++
        for (i = 1; i <= n; i++) {
            v = e_or(); if (E) return "N0"
            av[i] = v
            if (i < n) {
                if (!(TY[CK, CP] == "o" && TK[CK, CP] == ",")) { raise(2); return "N0" }
                CP++
            }
        }
        if (!(TY[CK, CP] == "o" && TK[CK, CP] == ")")) { raise(2); return "N0" }
        CP++
    }
    for (i = 1; i <= n; i++)                # type-check BEFORE binding, so
        if (strname(FNPARM[name, i]) != !isN(av[i])) { raise(13); return "N0" }
    if (++FNDEPTH > 50) { FNDEPTH--; raise(7); return "N0" }
    for (i = 1; i <= n; i++) {
        p = FNPARM[name, i]
        if (strname(p)) { osv[i] = SV[p]; SV[p] = substr(av[i], 2) }
        else            { osn[i] = NV[p]; NV[p] = num(av[i]) }
    }
    sk = CK; sp = CP
    CK = FNKEY[name]; CP = FNPOS[name]
    r = e_or()
    CK = sk; CP = sp
    for (i = n; i >= 1; i--) {
        p = FNPARM[name, i]
        if (strname(p)) SV[p] = osv[i]
        else            NV[p] = osn[i]
    }
    FNDEPTH--
    if (E) return "N0"
    if (strname(name) != !isN(r)) { raise(13); return "N0" }
    return r
}

# ---- built-in functions ----------------------------------------------------
function fncall(name,   v, a1, a2, a3, na, x, s, i, r) {
    CP++
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == "(")) { raise(2); return "N0" }
    CP++
    na = 0
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == ")")) {
        a1 = e_or(); if (E) return "N0"
        na = 1
        if (TY[CK, CP] == "o" && TK[CK, CP] == ",") {
            CP++; a2 = e_or(); if (E) return "N0"
            na = 2
            if (TY[CK, CP] == "o" && TK[CK, CP] == ",") {
                CP++; a3 = e_or(); if (E) return "N0"
                na = 3
            }
        }
    }
    if (TY[CK, CP] == "o" && TK[CK, CP] == ")") CP++
    else { raise(2); return "N0" }

    if (name == "ABS") { x = numarg(a1, na); if (E) return "N0"; return "N" (x < 0 ? -x : x) }
    if (name == "INT") { x = numarg(a1, na); if (E) return "N0"; return "N" bfloor(x) }
    if (name == "FIX") { x = numarg(a1, na); if (E) return "N0"; return "N" int(x) }
    if (name == "SGN") { x = numarg(a1, na); if (E) return "N0"; return "N" (x > 0 ? 1 : (x < 0 ? -1 : 0)) }
    if (name == "SQR") { x = numarg(a1, na); if (E) return "N0"; if (x < 0) { raise(5); return "N0" }; return "N" sqrt(x) }
    if (name == "SIN") { x = numarg(a1, na); if (E) return "N0"; return "N" sin(x) }
    if (name == "COS") { x = numarg(a1, na); if (E) return "N0"; return "N" cos(x) }
    if (name == "TAN") { x = numarg(a1, na); if (E) return "N0"; return "N" (sin(x) / cos(x)) }
    if (name == "ATN") { x = numarg(a1, na); if (E) return "N0"; return "N" atan2(x, 1) }
    if (name == "LOG") { x = numarg(a1, na); if (E) return "N0"; if (x <= 0) { raise(5); return "N0" }; return "N" log(x) }
    if (name == "EXP") {
        x = numarg(a1, na); if (E) return "N0"
        if (x > 87.3) { raise(6); return "N0" }
        return "N" exp(x)
    }
    if (name == "RND") {
        # authentic ROM sequence (rnd_next/sngl, p90): RND(0) = seed'/2^24,
        # RND(n) = INT(RND(0)*n + 1) with the multiply rounded to single
        # precision.  RND(neg) = ?FC (the ROM does NOT reseed on negative).
        x = numarg(a1, na); if (E) return "N0"
        i = int(x)
        if (x < 0) { raise(5); return "N0" }
        x = rnd_next()
        if (i == 0) return "N" x
        return "N" (int(sngl(x * i)) + 1)
    }
    if (name == "CINT") {
        x = numarg(a1, na); if (E) return "N0"
        x = to16(x); if (E) return "N0"           # rounds DOWN (p90 to16)
        return "N" x
    }
    if (name == "CSNG" || name == "CDBL") { x = numarg(a1, na); if (E) return "N0"; return "N" x }
    if (name == "PEEK") { x = numarg(a1, na); if (E) return "N0"; return "N" dopeek(x) }
    # INP(p): read Z80 port p (0-255, else ?FC).  Until 2026-09-11 INP had no
    # body, so INP(255) fell through to the array path and died with ?BS --
    # 96 corpus listings.  Port FFH is the Model I cassette/video-mode port
    # and the ONE port with state here: bit 6 reads 1 in 64-character mode
    # and 0 in CHR$(23)'s 32-character mode (127 / 63, the values period
    # listings test), bit 7 is the cassette input and stays 0 (no signal).
    # Every other port reads 255, the open bus, as unmapped memory does --
    # so RS-232 (232), floppy (240) and joystick probes take their
    # "not present" branch instead of erroring.  OUT (st_out, p80) is its
    # twin: only port 255 bit 3 does anything there.
    if (name == "INP") {
        x = numarg(a1, na); if (E) return "N0"
        x = bfloor(x)
        if (x < 0 || x > 255) { raise(5); return "N0" }
        return "N" ((x == 255) ? (LATCH ? 63 : 127) : 255)
    }
    # USR/USR0-9: with a core (TRS80_Z80, p77) the routine RUNS; without
    # one this is the STUB, which evaluates and returns its argument.
    # X=USR(V) identity keeps more rescued listings partially running than
    # ?FC would; routines whose RESULT is load-bearing still fail visibly.
    # The CALL FRAME is resolved even though nothing consumes it yet:
    # usr_resolve() fills USR_SLOT/USR_ENTRY/USR_ARG, which is what the p77
    # coprocess shim will hand to ../trs80_z80_core.
    # NOT SILENT (ruled 2026-09-11): 8 of the 11 trs-80.com string-packing
    # techniques are side-effect routines, and a stub that returns its
    # argument makes every one of them "succeed" with no effect, no error
    # and exit 0 -- the silent-wrong-output failure this project names as
    # the one that matters.  So the stub keeps stdout byte-identical (the
    # oracle role) and usr_stub_notice() prints ONE stderr line per run
    # naming every entry address that was called and not executed.
    # TRS80_USR=strict raises ?FC on the call instead, for a sweep that
    # wants the run to fail visibly.
    if (name ~ /^USR[0-9]?$/) {
        x = numarg(a1, na); if (E) return "N0"
        usr_resolve(name, x)
        x = z80_usr(x); if (E) return "N0"        # the core (p77), or the stub
        return "N" x
    }
    if (name == "POS") { x = numarg(a1, na); if (E) return "N0"; return "N" (CUR % 64) }
    if (name == "FRE") { if (na < 1) { raise(2); return "N0" }; return "N" 15572 }
    if (name == "LEN") { s = strarg(a1, na); if (E) return "N0"; return "N" length(s) }
    if (name == "ASC") {
        s = strarg(a1, na); if (E) return "N0"
        if (s == "") { raise(5); return "N0" }
        s = substr(s, 1, 1)
        return "N" ((s in ORD) ? ORD[s] : 63)
    }
    if (name == "VAL") { s = strarg(a1, na); if (E) return "N0"; x = valnum(s); if (E) return "N0"; return "N" x }
    if (name == "CHR$") {
        x = numarg(a1, na); if (E) return "N0"
        x = bfloor(x)
        if (x < 0 || x > 255) { raise(5); return "N0" }
        return "S" CHR[x]
    }
    if (name == "STR$") {
        x = numarg(a1, na); if (E) return "N0"
        s = fmtnum(x)
        sub(/ $/, "", s)
        return "S" s
    }
    if (name == "STRING$") {
        if (na < 2) { raise(2); return "N0" }
        if (!isN(a1)) { raise(13); return "N0" }
        x = bfloor(num(a1))
        if (x < 0 || x > 255) { raise(5); return "N0" }
        if (isN(a2)) {
            i = bfloor(num(a2))
            if (i < 0 || i > 255) { raise(5); return "N0" }
            s = CHR[i]
        } else {
            s = vstr(a2)
            if (s == "") { raise(5); return "N0" }
            s = substr(s, 1, 1)
        }
        r = ""
        for (i = 0; i < x; i++) r = r s
        return "S" r
    }
    if (name == "LEFT$") {
        s = strarg2(a1, na); x = intarg2(a2, na); if (E) return "N0"
        if (x < 0) { raise(5); return "N0" }
        return "S" substr(s, 1, x)
    }
    if (name == "RIGHT$") {
        s = strarg2(a1, na); x = intarg2(a2, na); if (E) return "N0"
        if (x < 0) { raise(5); return "N0" }
        if (x > length(s)) x = length(s)
        return "S" (x == 0 ? "" : substr(s, length(s) - x + 1))
    }
    if (name == "MID$") {
        s = strarg2(a1, na); x = intarg2(a2, na); if (E) return "N0"
        if (x < 1) { raise(5); return "N0" }
        if (na >= 3) {
            if (!isN(a3)) { raise(13); return "N0" }
            i = bfloor(num(a3))
            if (i < 0) { raise(5); return "N0" }
            return "S" substr(s, x, i)
        }
        return "S" substr(s, x)
    }
    if (name == "INSTR") {          # INSTR([n,]a$,b$) -- Disk BASIC
        if (na == 2) { x = 1; s = a1; r = a2 }
        else if (na == 3) {
            if (!isN(a1)) { raise(13); return "N0" }
            x = bfloor(num(a1)); s = a2; r = a3
        } else { raise(2); return "N0" }
        if (isN(s) || isN(r)) { raise(13); return "N0" }
        s = vstr(s); r = vstr(r)
        if (x < 1 || x > 255) { raise(5); return "N0" }
        if (x > length(s)) return "N0"
        if (r == "") return "N" x
        i = index(substr(s, x), r)
        return "N" (i ? i + x - 1 : 0)
    }
    if (name == "POINT") {
        if (na < 2) { raise(2); return "N0" }
        if (!isN(a1) || !isN(a2)) { raise(13); return "N0" }
        return "N" gpoint(bfloor(num(a1)), bfloor(num(a2)))
    }
    if (name == "EOF") {
        x = numarg(a1, na); if (E) return "N0"
        i = fio_fnchan(x); if (E) return "N0"
        if (FH_MODE[i] == "I") return "N" (FH_PENDHAS[i] ? 0 : (fio_fill(i) ? 0 : -1))
        if (FH_MODE[i] == "R") return "N" ((FH_LOC[i] >= FH_NREC[i]) ? -1 : 0)
        # "A": reports the reply buffer only -- never triggers a send
        if (FH_MODE[i] == "A") return "N" ((FH_PENDHAS[i] || AI_RHAS[i]) ? 0 : -1)
        raise(28); return "N0"
    }
    if (name == "LOF") {
        x = numarg(a1, na); if (E) return "N0"
        i = fio_fnchan(x); if (E) return "N0"
        if (FH_MODE[i] != "R") { raise(28); return "N0" }
        return "N" (FH_NREC[i] + 0)
    }
    if (name == "LOC") {
        x = numarg(a1, na); if (E) return "N0"
        i = fio_fnchan(x); if (E) return "N0"
        if (FH_MODE[i] == "A") return "N" (AI_NMSG[i] + 0)
        return "N" (FH_LOC[i] + 0)
    }
    if (name == "MKI$") { x = numarg(a1, na); if (E) return "N0"; s = fio_mki(x); if (E) return "N0"; return "S" s }
    if (name == "MKS$") { x = numarg(a1, na); if (E) return "N0"; s = fio_mkf(x, 4); if (E) return "N0"; return "S" s }
    if (name == "MKD$") { x = numarg(a1, na); if (E) return "N0"; s = fio_mkf(x, 8); if (E) return "N0"; return "S" s }
    if (name == "CVI") { s = strarg(a1, na); if (E) return "N0"; x = fio_cvi(s); if (E) return "N0"; return "N" x }
    if (name == "CVS") { s = strarg(a1, na); if (E) return "N0"; x = fio_cvf(s, 4); if (E) return "N0"; return "N" x }
    if (name == "CVD") { s = strarg(a1, na); if (E) return "N0"; x = fio_cvf(s, 8); if (E) return "N0"; return "N" x }
    if (name == "TAB") { raise(2); return "N0" }
    raise(2)
    return "N0"
}

function numarg(a, na) {
    if (na < 1) { raise(2); return 0 }
    if (!isN(a)) { raise(13); return 0 }
    return num(a)
}
function strarg(a, na) {
    if (na < 1) { raise(2); return "" }
    if (isN(a)) { raise(13); return "" }
    return vstr(a)
}
function strarg2(a, na) {
    if (na < 2) { raise(2); return "" }
    if (isN(a)) { raise(13); return "" }
    return vstr(a)
}
function intarg2(a, na) {
    if (na < 2) { raise(2); return 0 }
    if (!isN(a)) { raise(13); return 0 }
    return bfloor(num(a))
}

# ---- USR call frame ---------------------------------------------------------
# Two vectors exist on the real machines and this interpreter honours both:
#   408EH/408FH (16526/16527)  the Level II USR vector, set by POKE -- lives
#                              in MEM[] like any RAM (279 corpus listings)
#   DEF USRn=addr              the Disk BASIC ten-slot table, USRDEF[0..9]
#                              (481 listings; 212 use both, choosing by the
#                              PEEK(16396)=201 cassette/disk probe)
# PRECEDENCE, per slot: a DEF USRn executed this session wins; otherwise
# slot 0 -- which is what a bare USR( means -- falls back to the 408EH
# vector, and slots 1-9 are UNDEFINED (Disk BASIC's table entries point at
# the ?FC routine until defined; the core should raise ?FC there).  An
# unwritten 408EH vector is UNDEFINED too: on hardware the ROM seeds it
# with the ?FC routine's address, and this side never seeds it, so both
# bytes read 255.  USR_ENTRY is -1 for UNDEFINED.  The table is NOT cleared
# by CLEAR/RUN/NEW -- it is system RAM on hardware, like the POKEd vector.
function usr_slot(name) { return (length(name) == 4) ? substr(name, 4, 1) + 0 : 0 }

function usr_entry(slot,   lo, hi) {
    if (slot in USRDEF) return USRDEF[slot]
    if (slot != 0) return -1
    lo = (16526 in MEM) ? MEM[16526] : 255
    hi = (16527 in MEM) ? MEM[16527] : 255
    return (lo == 255 && hi == 255) ? -1 : lo + 256 * hi
}

# TRS80_USR_TRACE=1 prints one line per call to stderr: the frame the shim
# will send.  =2 also dumps the frame's memory image (p75 fr_build: full
# the first time, deltas after).  Diagnostic only; programs/tests/usr.sh
# asserts on both.
function usr_resolve(name, arg) {
    USR_SLOT = usr_slot(name); USR_ARG = arg
    USR_ENTRY = usr_entry(USR_SLOT)
    if (USR_TRACE == "") {
        USR_TRACE = ("TRS80_USR_TRACE" in ENVIRON && ENVIRON["TRS80_USR_TRACE"] != "") ? ENVIRON["TRS80_USR_TRACE"] + 0 : 0
        USR_STRICT = (ENVIRON["TRS80_USR"] == "strict")
    }
    if (USR_TRACE) printf "USR slot=%d entry=%s arg=%s\n", USR_SLOT, (USR_ENTRY < 0 ? "undefined" : USR_ENTRY), arg > "/dev/stderr"
    if (USR_TRACE >= 2) { fr_build(0); fr_dump() }   # the frame's memory image (p75 fr_*)
}

# the stub's per-run tally: distinct entry addresses in first-call order.
# Reset by exec_immediate (p70), which also prints the notice when the
# command or program that ran has finished.
function usr_stub_count(   k) {
    k = (USR_ENTRY < 0) ? "UNDEFINED" : sprintf("%04XH", USR_ENTRY)
    if (!(k in USR_SEEN)) USR_SEENORD[++USR_NSEEN] = k
    USR_SEEN[k]++; USR_NCALL++
}
function usr_stub_reset() { delete USR_SEEN; delete USR_SEENORD; USR_NSEEN = 0; USR_NCALL = 0 }
function usr_stub_notice(   i, s) {
    if (USR_NCALL == 0) return
    for (i = 1; i <= USR_NSEEN; i++)
        s = s (i > 1 ? ", " : "") USR_SEENORD[i] " x" USR_SEEN[USR_SEENORD[i]]
    diag_err("USR STUB: " USR_NCALL " CALL" (USR_NCALL == 1 ? "" : "S") " NOT EXECUTED (" s \
             "): no Z80 core, each returned its argument; TRS80_USR=strict raises ?FC instead")
    usr_stub_reset()
}

function fn_inkey(   c) {
    if (CK == "I" && !TTYIN) return "S"
    c = kb_poll1()
    if (c == 3) { if (brk_take()) PENDBRK = 1; return "S" }   # the BREAK vector (p30)
    if (c < 0) return "S"
    BRKFORCE = 0
    # at a terminal an arrow key is the Model I's one byte, not ESC [ A
    # (p30 kb_escseq); piped input is a byte stream and stays as sent
    if (c == 27 && TTYIN) { c = kb_escseq(); if (c < 0) return "S" }
    return "S" CHR[c]
}

# FNLIST is initialized in init_tables (single BEGIN block runs everything)
# ===================== execution engine and control flow ====================

function exec_immediate(line) {
    tokline("I", line)
    CK = "I"; CLI = 0; CLN = 0; CP = 1
    E = 0; HALT = 0; STOPPED = 0
    usr_stub_reset()
    execloop()
    if (E) report_err()
    usr_stub_notice()                       # one stderr line per run (p60)
}

function setline(i) {
    CLI = i; CLN = LNS[i]; CK = CLN ""
    if (!(CK in TOKD)) tokline(CK, prog[CLN])
    CP = 1
    if (TRACE) s_puts("<" CLN ">")
}

function jumpline(ln) {
    if (!(ln in LIDX)) { raise(8); return }
    setline(LIDX[ln])
}

function eolpos() { return TCN[CK] }

function execloop(   ty, tx) {
    for (;;) {
        ty = TY[CK, CP]
        if (ty == "" || ty == "e") {
            if (CK == "I") return
            if (CLI >= NL) return
            setline(CLI + 1)
            continue
        }
        tx = TK[CK, CP]
        if (ty == "o" && tx == ":") { CP++; continue }
        if (ty == "i" && tx == "ELSE") { CP = eolpos(); continue }
        if (++BRKCTR >= BRKEVERY) {
            BRKCTR = 0
            if (CK != "I" && pollbrk()) { dobreak(); return }
        }
        if (THROTTLE_D > 0) {           # emulate a slow clock (see set_speed)
            DACC += THROTTLE_D
            if (DACC >= 0.03) { system("sleep " DACC); DACC = 0 }
        }
        SK = CK; SLI = CLI; SCP = CP
        execstmt()
        if (E) {
            if (EHANDLER && !INHANDLER && CK != "I") {
                ERRV = (E - 1) * 2; ERLV = ERR_AT
                ERR_K = SK; ERR_LI = SLI; ERR_CP = SCP
                INHANDLER = 1; E = 0
                jumpline(EHANDLER)
                if (E) { report_err(); return }
                continue
            }
            report_err()
            return
        }
        if (HALT || STOPPED || EOFQUIT || QUITFLAG) return
    }
}

function dobreak() {
    if (BATCH) diag("BREAK IN " CLN)        # not program output: stderr
    else { s_nl(); s_puts("BREAK IN " CLN); s_nl() }
    CONT_K = SK; CONT_LI = SLI; CONT_P = SCP
    CONTOK = 1
    STOPPED = 1
    kb_flush()
}

# ---- statement dispatch ----------------------------------------------------
function execstmt(   ty, tx) {
    ty = TY[CK, CP]; tx = TK[CK, CP]
    if (ty == "i") {
        if (tx == "PRINT")   { CP++; st_print(); return }
        if (tx == "LET")     { CP++; st_let(); return }
        if (tx == "IF")      { CP++; st_if(); return }
        if (tx == "GOTO")    { CP++; st_goto(); return }
        if (tx == "GOSUB")   { CP++; st_gosub(); return }
        if (tx == "RETURN")  { CP++; st_return(); return }
        if (tx == "FOR")     { CP++; st_for(); return }
        if (tx == "NEXT")    { CP++; st_next(); return }
        if (tx == "INPUT")   { CP++; st_input(); return }
        if (tx == "READ")    { CP++; st_read(); return }
        if (tx == "DATA")    { CP++; if (TY[CK, CP] == "d") CP++; return }
        if (tx == "RESTORE") { CP++; st_restore(); return }
        if (tx == "REM")     { if (EXTON) rem_meta(); CP = eolpos(); return }
        if (tx == "END")     { CP++; st_end(); return }
        if (tx == "STOP")    { CP++; st_stop(); return }
        if (tx == "DIM")     { CP++; st_dim(); return }
        if (tx == "CLS")     { CP++; s_cls(); return }
        if (tx == "CLEAR")   { CP++; st_clear(); return }
        if (tx == "ON")      { CP++; st_on(); return }
        if (tx == "POKE")    { CP++; st_poke(); return }
        if (tx == "SET")     { CP++; st_setreset(1); return }
        if (tx == "RESET")   { CP++; st_setreset(0); return }
        if (tx == "RUN")     { CP++; st_run(); return }
        if (tx == "LIST")    { CP++; st_list(); return }
        if (tx == "NEW")     { CP++; st_new(); return }
        if (tx == "CONT")    { CP++; st_cont(); return }
        if (tx == "AUTO")    { CP++; st_auto(); return }
        if (tx == "DELETE")  { CP++; st_delete(); return }
        if (tx == "CLOAD")   { CP++; st_cload(); return }
        if (tx == "SYSTEM")  { CP++; st_system(); return }
        if (tx == "CSAVE")   { CP++; st_csave(); return }
        if (tx == "LOAD")    { CP++; st_load(); return }
        if (tx == "SAVE")    { CP++; st_save(); return }
        if (tx == "MERGE")   { CP++; st_merge(); return }
        if (tx == "NAME")    { CP++; st_name(); return }
        if (tx == "OPEN")    { CP++; st_open(); return }
        if (tx == "CLOSE")   { CP++; st_close(); return }
        if (tx == "FIELD")   { CP++; st_field(); return }
        if (tx == "GET")     { CP++; st_get(); return }
        if (tx == "PUT")     { CP++; st_put(); return }
        if (tx == "LSET")    { CP++; st_lset(1); return }
        if (tx == "RSET")    { CP++; st_lset(0); return }
        if (tx == "KILL")    { CP++; st_kill(); return }
        if (tx == "LINE")    { CP++; st_lineinput(); return }
        if (tx == "BYE")     { CP++; QUITFLAG = 1; HALT = 1; return }
        if (tx == "TRON")    { CP++; TRACE = 1; return }
        if (tx == "TROFF")   { CP++; TRACE = 0; return }
        if (tx == "RANDOM")  { CP++; rnd_setmid(int(rand() * 256)); return }
        if (tx == "ERROR")   { CP++; st_error(); return }
        if (tx == "RESUME")  { CP++; st_resume(); return }
        if (tx == "DEFINT" || tx == "DEFSNG" || tx == "DEFDBL" || tx == "DEFSTR") { CP++; st_deftype(tx == "DEFSTR"); return }
        if (tx == "DEF" || tx ~ /^DEFUSR[0-9]?$/ || tx ~ /^DEFFN./) { CP++; st_def(tx); return }
        if (tx == "LPRINT")  { CP++; st_lprint(); return }
        if (tx == "LLIST")   { CP++; st_llist(); return }
        if (tx == "OUT")     { CP++; st_out(); return }
        if (tx == "MID$")    { CP++; st_midset(); return }
        # CMD only when a string LITERAL follows, so `CMD A$` and a variable
        # named CMD keep their old meaning (see st_cmd, p80)
        if (tx == "CMD" && TY[CK, CP + 1] == "s") { CP++; st_cmd(); return }
        st_let()                       # implicit assignment
        return
    }
    if (ty == "o" && tx == "?") { CP++; st_print(); return }
    raise(2)
}

# is the token cursor at the end of the current statement?
function at_stmt_end(   ty, tx) {
    ty = TY[CK, CP]; tx = TK[CK, CP]
    return ty == "" || ty == "e" || (ty == "o" && tx == ":") || (ty == "i" && tx == "ELSE")
}

function skipstmt(   ty, tx) {
    for (;;) {
        ty = TY[CK, CP]
        if (ty == "" || ty == "e") return
        tx = TK[CK, CP]
        if (ty == "o" && tx == ":") return
        if (ty == "i" && tx == "ELSE") return
        CP++
    }
}

# ---- assignment ------------------------------------------------------------
function st_let(   name, key, v) {
    if (TY[CK, CP] != "i") { raise(2); return }
    name = TK[CK, CP]; CP++
    key = ""
    if (TY[CK, CP] == "o" && TK[CK, CP] == "(") {
        key = aref(name); if (E) return
    }
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == "=")) { raise(2); return }
    CP++
    v = e_or(); if (E) return
    assignv(name, key, v)
}

# DEFSTR/DEFINT/DEFSNG/DEFDBL letter[-letter][,...]: per-letter default type.
# Only the string/numeric split matters here -- numeric precision is a
# documented no-op -- so DEFINT/SNG/DBL clear the DEFSTR flag for the range.
# RUN/NEW/program load reset the table (clear_vars); CLEAR keeps it, so
# DEFSTR A: CLEAR 500: A="X" stays typed.
function st_deftype(isstr,   a, b, c) {
    for (;;) {
        if (TY[CK, CP] != "i" || TK[CK, CP] !~ /^[A-Z]$/) { raise(2); return }
        a = TK[CK, CP]; CP++
        b = a
        if (TY[CK, CP] == "o" && TK[CK, CP] == "-") {
            CP++
            if (TY[CK, CP] != "i" || TK[CK, CP] !~ /^[A-Z]$/) { raise(2); return }
            b = TK[CK, CP]; CP++
        }
        for (c = ORD[a]; c <= ORD[b]; c++) DEFS[CHR[c]] = isstr
        if (TY[CK, CP] == "o" && TK[CK, CP] == ",") { CP++; continue }
        return
    }
}

# DEF dispatch (Disk BASIC tier).  Three spellings arrive here:
#   DEF USR[n]=addr / DEFUSRn=addr   -- the address is evaluated and STORED
#     in the ten-slot table USRDEF[n] (p60 usr_entry reads it; until
#     2026-09-10 it was discarded).  USRn() calls still return their
#     argument (fncall) -- the stub ruling is unchanged, only the frame is
#     now resolved.
#   DEF FN name(...)=expr / DEF FNname(...)=expr / DEFFNname(...)=expr
#     -- real user-defined functions (st_deffn / fn_user).
# Any other DEF shape stays ?SN.
function st_def(tx,   v) {
    if (tx ~ /^DEFUSR[0-9]?$/) { st_defusr_tail(tx == "DEFUSR", substr(tx, 7)); return }
    if (tx ~ /^DEFFN./) { st_deffn(substr(tx, 6)); return }
    # tx == "DEF": look at the next identifier
    if (TY[CK, CP] != "i") { raise(2); return }
    tx = TK[CK, CP]
    if (tx ~ /^USR[0-9]?$/) { CP++; st_defusr_tail(tx == "USR", substr(tx, 4)); return }
    if (tx == "FN") {                       # spaced name: DEF FN AB(X)=...
        CP++
        if (TY[CK, CP] != "i") { raise(2); return }
        tx = TK[CK, CP]; CP++
        st_deffn(tx)
        return
    }
    if (tx ~ /^FN./) { CP++; st_deffn(substr(tx, 3)); return }
    raise(2)
}

function st_defusr_tail(baredigit, slot,   v, a) {
    # when the spelling carried no slot digit, one may follow as its own
    # token -- real Level II tokenizes past the space, so DEF USR 0=addr
    # is legal (measured on morsmstr/quest_2; Z80 sub-project FINDING 8)
    if (baredigit && TY[CK, CP] == "n" && TK[CK, CP] ~ /^[0-9]$/) { slot = TK[CK, CP]; CP++ }
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == "=")) { raise(2); return }
    CP++
    v = e_or(); if (E) return
    if (!isN(v)) { raise(13); return }
    a = addrconv(num(v)); if (E) return          # ?FC outside -65535..65535, negatives wrap
    USRDEF[(slot == "") ? 0 : slot + 0] = a
}

# DEF FN: record the parameter names and the token-cache POSITION of the
# body expression -- the body is skipped, never evaluated, at definition
# time (a DEF must not raise its body's errors).  fn_user (p60) evaluates
# it by pointing CK/CP at the stored position.  The name is stored WITHOUT
# its FN prefix so FNA(1), FN A(1) and a DEFFNA definition all meet in one
# table.  Definitions live in variable space: cleared by RUN/NEW/CLEAR
# like arrays (real MS BASIC behavior), so a program re-executes its DEFs.
# Immediate mode raises ?ID (MS "illegal direct") -- the immediate token
# cache is overwritten by every typed line, so a stored position there
# would dangle.
function st_deffn(name,   n, i) {
    if (CK == "I") { raise(12); return }
    n = 0
    if (TY[CK, CP] == "o" && TK[CK, CP] == "(") {
        CP++
        for (;;) {
            if (TY[CK, CP] != "i") { raise(2); return }
            FNTMP[++n] = TK[CK, CP]; CP++
            if (TY[CK, CP] == "o" && TK[CK, CP] == ",") { CP++; continue }
            break
        }
        if (!(TY[CK, CP] == "o" && TK[CK, CP] == ")")) { raise(2); return }
        CP++
    }
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == "=")) { raise(2); return }
    CP++
    FNPAR[name] = n
    for (i = 1; i <= n; i++) FNPARM[name, i] = FNTMP[i]
    FNKEY[name] = CK; FNPOS[name] = CP
    while (!at_stmt_end()) CP++             # skip the body, do not evaluate
}

# is this variable name a string?  An explicit $ suffix always; otherwise a
# bare name whose first letter is under DEFSTR.  Every type test in the
# interpreter goes through here so DEFSTR retypes arrays, INPUT, READ, FOR
# and file I/O consistently.
function strname(name) {
    return name ~ /\$$/ || DEFS[substr(name, 1, 1)]
}

function assignv(name, key, v) {
    if (strname(name)) {
        if (isN(v)) { raise(13); return }
        if (ALN) al_clear(name, key)            # the descriptor moves (p75, finding 7)
        if (key != "") VA[key] = v; else SV[name] = vstr(v)
        if (length(VPDATA)) sp_grown(name, key)  # a VARPTRed string that outgrew its cells (p75)
    } else {
        if (!isN(v)) { raise(13); return }
        if (key != "") VA[key] = "N" num(v); else NV[name] = num(v)
    }
}

# ---- control flow ----------------------------------------------------------
function st_goto(   ln) {
    if (TY[CK, CP] != "n") { raise(2); return }
    ln = TK[CK, CP] + 0; CP++
    jumpline(ln)
}

function st_gosub(   ln) {
    if (TY[CK, CP] != "n") { raise(2); return }
    ln = TK[CK, CP] + 0; CP++
    GSN++
    GS_K[GSN] = CK; GS_LI[GSN] = CLI; GS_P[GSN] = CP; GS_F[GSN] = FSN
    jumpline(ln)
    if (E) GSN--
}

function st_return() {
    if (GSN == 0) { raise(3); return }
    CK = GS_K[GSN]; CLI = GS_LI[GSN]; CP = GS_P[GSN]
    # discard FOR frames opened since the GOSUB (early RETURN out of a loop
    # is legal MS BASIC).  The subroutine cannot have touched a loop opened
    # before the call: FOR and NEXT stop their scan at this frame (for_floor)
    if (FSN > GS_F[GSN]) FSN = GS_F[GSN]
    GSN--
    CLN = (CK == "I") ? 0 : CK + 0
}

function st_for(   name, v0, v1, stp, j, v) {
    if (TY[CK, CP] != "i") { raise(2); return }
    name = TK[CK, CP]
    if (strname(name)) { raise(13); return }
    CP++
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == "=")) { raise(2); return }
    CP++
    v = e_or(); if (E) return
    if (!isN(v)) { raise(13); return }
    v0 = num(v)
    if (!(TY[CK, CP] == "i" && TK[CK, CP] == "TO")) { raise(2); return }
    CP++
    v = e_or(); if (E) return
    if (!isN(v)) { raise(13); return }
    v1 = num(v)
    stp = 1
    if (TY[CK, CP] == "i" && TK[CK, CP] == "STEP") {
        CP++
        v = e_or(); if (E) return
        if (!isN(v)) { raise(13); return }
        stp = num(v)
    }
    NV[name] = v0
    for (j = FSN; j > for_floor(); j--)
        if (FS_V[j] == name) { FSN = j - 1; break }
    FSN++
    FS_V[FSN] = name; FS_L[FSN] = v1; FS_S[FSN] = stp
    FS_K[FSN] = CK; FS_LI[FSN] = CLI; FS_P[FSN] = CP
}

function st_next(   name, looped) {
    for (;;) {
        name = ""
        if (TY[CK, CP] == "i") { name = TK[CK, CP]; CP++ }
        looped = do_next(name)
        if (E || looped) return
        if (TY[CK, CP] == "o" && TK[CK, CP] == ",") { CP++; continue }
        return
    }
}

# The ROM's scan of the stack for a FOR entry (1936H) gives up at the first
# entry that is not one -- the GOSUB frame.  So inside a subroutine the
# caller's loops do not exist: FOR I there opens a NEW loop and leaves the
# caller's FOR I alone (the delay-subroutine idiom), and a NEXT that names
# a loop opened before the GOSUB is ?NF.  The floor is the FOR depth the
# current GOSUB recorded.
function for_floor() { return (GSN > 0) ? GS_F[GSN] : 0 }

function do_next(name,   j, v, fl) {
    fl = for_floor()
    if (FSN <= fl) { raise(1); return 0 }
    if (name == "") j = FSN
    else {
        for (j = FSN; j > fl; j--)
            if (FS_V[j] == name) break
        if (j <= fl) { raise(1); return 0 }
    }
    FSN = j
    v = NV[FS_V[j]] + FS_S[j]
    NV[FS_V[j]] = v
    if (FS_S[j] >= 0 ? v <= FS_L[j] : v >= FS_L[j]) {
        CK = FS_K[j]; CLI = FS_LI[j]; CP = FS_P[j]
        CLN = (CK == "I") ? 0 : CK + 0
        return 1
    }
    FSN = j - 1
    return 0
}

function st_if(   v, truth, hadkw, d, p, ty, tx) {
    v = e_or(); if (E) return
    if (!isN(v)) { raise(13); return }
    truth = (num(v) != 0)
    # one comma after the expression is skipped, as the ROM does (203C-203F):
    # IF X=1,100   IF X=1,THEN 100   IF X=0,Y=1   are all Level II
    if (TY[CK, CP] == "o" && TK[CK, CP] == ",") CP++
    hadkw = ""
    if (TY[CK, CP] == "i" && (TK[CK, CP] == "THEN" || TK[CK, CP] == "GOTO")) {
        hadkw = TK[CK, CP]; CP++
    }
    if (truth) {
        if (TY[CK, CP] == "n") { jumpline(TK[CK, CP] + 0); return }
        if (hadkw == "GOTO") { raise(2); return }
        return                              # statements after THEN execute
    }
    # false: skip to matching ELSE (or end of line)
    d = 0; p = CP
    for (;;) {
        ty = TY[CK, p]
        if (ty == "" || ty == "e") { CP = p; return }
        tx = TK[CK, p]
        if (ty == "i" && tx == "IF") d++
        else if (ty == "i" && tx == "ELSE") {
            if (d == 0) {
                CP = p + 1
                if (TY[CK, CP] == "n") jumpline(TK[CK, CP] + 0)
                return
            }
            d--
        }
        p++
    }
}

function st_on(   v, n, mode, cnt, lst, retp) {
    if (TY[CK, CP] == "i" && TK[CK, CP] == "ERROR") {
        CP++
        if (!(TY[CK, CP] == "i" && TK[CK, CP] == "GOTO")) { raise(2); return }
        CP++
        if (TY[CK, CP] != "n") { raise(2); return }
        EHANDLER = TK[CK, CP] + 0; CP++
        # ON ERROR GOTO 0 inside the handler: "BASIC will handle the
        # current error normally" -- the ROM reloads the error's code and
        # joins the error routine past the point where it notes the line
        # (1F89-1F92 -> 19ABH), so the message names the line that failed
        if (EHANDLER == 0 && INHANDLER) { INHANDLER = 0; E = ERRV / 2 + 1; ERR_AT = ERLV }
        return
    }
    v = e_or(); if (E) return
    if (!isN(v)) { raise(13); return }
    n = bfloor(num(v))
    if (n < 0 || n > 255) { raise(5); return }
    if (TY[CK, CP] == "i" && (TK[CK, CP] == "GOTO" || TK[CK, CP] == "GOSUB")) {
        mode = TK[CK, CP]; CP++
    } else { raise(2); return }
    cnt = 0
    for (;;) {
        if (TY[CK, CP] != "n") { raise(2); return }
        cnt++; lst[cnt] = TK[CK, CP] + 0; CP++
        if (TY[CK, CP] == "o" && TK[CK, CP] == ",") { CP++; continue }
        break
    }
    if (n >= 1 && n <= cnt) {
        if (mode == "GOSUB") {
            GSN++
            GS_K[GSN] = CK; GS_LI[GSN] = CLI; GS_P[GSN] = CP; GS_F[GSN] = FSN
            jumpline(lst[n])
            if (E) GSN--
        } else jumpline(lst[n])
    }
}

function st_end() {
    if (CK != "I") {
        CONT_K = CK; CONT_LI = CLI; CONT_P = CP
        CONTOK = 1
    }
    fio_closeall()                          # END closes files (STOP does not)
    HALT = 1
}

function st_stop() {
    if (CK != "I") {
        diag("BREAK IN " CLN)
        CONT_K = CK; CONT_LI = CLI; CONT_P = CP
        CONTOK = 1
    }
    STOPPED = 1
}

function st_cont() {
    if (!CONTOK) { raise(17); return }
    CONTOK = 0
    CK = CONT_K; CLI = CONT_LI; CP = CONT_P
    CLN = (CK == "I") ? 0 : CK + 0
    if (CK != "I" && !(CK in TOKD)) tokline(CK, prog[CLN])
}

function st_run(   n, f, keep) {
    if (fname_is_expr()) {              # Disk BASIC RUN "file"[,R]; the name is an expression (p40)
        f = parse_fname(); if (E) return
        keep = 0
        if (TY[CK, CP] == "o" && TK[CK, CP] == ",") {
            CP++
            if (TY[CK, CP] == "i" && TK[CK, CP] == "R") { CP++; keep = 1 }
            else { raise(2); return }
        }
        if (!prog_load(f, 0, keep)) { raise(22); return }
        run_start(0, keep)
        return
    }
    n = 0
    if (TY[CK, CP] == "n") { n = TK[CK, CP] + 0; CP++ }
    run_start(n, 0)
}

# shared RUN startup (st_run, and LOAD "file",R)
function run_start(n, keepfiles) {
    clear_vars(keepfiles)
    if (DATADIRTY) datascan()
    DP = 1
    EHANDLER = 0; INHANDLER = 0; ERRV = 0; ERLV = 0
    CONTOK = 0
    if (NL == 0) { HALT = 1; return }
    if (n) jumpline(n)
    else setline(1)
}

function st_clear(   v, ty, tx) {
    # CLEAR takes a full numeric expression (CLEAR M, CLEAR FR!-8000 --
    # period listings prove the real ROM evaluated one; conformance fix
    # 2026-08-12, previously literal-or-parenthesized only)
    ty = TY[CK, CP]; tx = TK[CK, CP]
    if (!(ty == "" || ty == "e" || (ty == "o" && tx == ":") || (ty == "i" && tx == "ELSE"))) {
        v = e_or(); if (E) return
        if (!isN(v)) { raise(13); return }
    }
    # CLEAR is RUN's initializer without the jump (ROM 1B61-1B83): the
    # variables, the type table, the FOR/GOSUB stacks, the ON ERROR target
    # and the RESUME flag, CONT, and RESTORE.  ERR and ERL are not touched.
    run_reset()                     # p40: shared with line entry and DELETE
}

# RESTORE [n]: reset the DATA pointer -- to the first item at or after line
# n when given (Disk BASIC form; ?UL if the line does not exist)
function st_restore(   n, i) {
    if (DATADIRTY) datascan()
    if (TY[CK, CP] == "n") {
        n = TK[CK, CP] + 0; CP++
        if (!(n in LIDX)) { raise(8); return }
        DP = NDATA + 1
        for (i = 1; i <= NDATA; i++) if (DLINE[i] >= n) { DP = i; break }
        return
    }
    DP = 1
}

function st_error(   v, n) {
    v = e_or(); if (E) return
    if (!isN(v)) { raise(13); return }
    n = bfloor(num(v))
    if (n < 1 || n > NERRC) { raise(20); return }
    raise(n)
}

function st_resume(   p, ty, tx) {
    if (!INHANDLER) { raise(19); return }
    INHANDLER = 0
    if (TY[CK, CP] == "i" && TK[CK, CP] == "NEXT") {
        CP++
        CK = ERR_K; CLI = ERR_LI; CP = ERR_CP
        CLN = (CK == "I") ? 0 : CK + 0
        for (;;) {
            ty = TY[CK, CP]
            if (ty == "" || ty == "e") return
            tx = TK[CK, CP]
            if (ty == "o" && tx == ":") return
            if (ty == "i" && tx == "ELSE") return
            CP++
        }
    }
    if (TY[CK, CP] == "n") {
        p = TK[CK, CP] + 0; CP++
        if (p == 0) {
            CK = ERR_K; CLI = ERR_LI; CP = ERR_CP
            CLN = (CK == "I") ? 0 : CK + 0
            return
        }
        jumpline(p)
        return
    }
    CK = ERR_K; CLI = ERR_LI; CP = ERR_CP
    CLN = (CK == "I") ? 0 : CK + 0
}
# ===================== program-memory mapping + VARPTR string space =========
# Three related pieces of the real Level II memory model (STATUS roadmap:
# "Program-memory mapping", shipped 2026-08-14):
#
#  1. THE TOKENIZED PROGRAM IMAGE (writable since 2026-09-12): PEEK of 42E9H (17129) onward sees
#     the stored program in the authentic crunched cassette format -- per
#     line [next-addr lo][hi][line lo][hi][tokenized body][00], terminated
#     by 00 00 -- rebuilt lazily whenever the program changed (PROGDIRTY is
#     set in rebuild()).  System pointers served live: 40A4H (16548/9) =
#     program base 42E9H, 40F9H (16633/4) = first byte past the terminator
#     (start of variables), 40B1H (16561/2) = top of memory (the MEMORY
#     SIZE? answer).  POKEs into the region land in MEM and are never read
#     back -- the WRITABLE mapping (self-modifying code) stays unbuilt (see
#     STATUS).  Keyword bytes 80-FB embedded below = tools/level2_tokens.tsv;
#     serialization is validated byte-for-byte against tools/tok.py.
#     Deviations, documented: lowercase keywords in typed source stay text
#     bytes (real hardware uppercased on entry), and ELSE serializes without
#     the hidden ":" byte the real cruncher inserted.
#
#  2. MEMORY SIZE? enforcement: a numeric answer at boot becomes HIMEM,
#     which is a FENCE, not the top of RAM.  Two quantities, and the
#     distinction is the whole point of the prompt:
#       RAMTOP  the machine's physical top (FFFFH for the 48K Model I this
#               emulates).  Above it memory is ABSENT: PEEK reads 255,
#               POKE is discarded.
#       HIMEM   the MEMORY SIZE? answer, at or below RAMTOP.  The region
#               between them is PROTECTED RAM -- present, readable and
#               writable, simply never allocated by string space
#               (sp_materialize descends from HIMEM).  Reserving memory is
#               how a listing makes room for a machine-language routine, so
#               that region MUST accept POKEs; treating it as absent broke
#               the classic reserve-then-load idiom (fixed 2026-09-08,
#               reported by ../trs80_z80_core as its FINDING 22).
#     PEEK(16561/16562) reports HIMEM.  ENTER keeps HIMEM at 65535 so batch
#     mode and loaders see all of RAM.
#
#  3. VARPTR(var) + mem[]-backed string space (the string-packing idiom):
#     for a string, VARPTR returns the address of a live 3-byte descriptor
#     [len][addr lo][addr hi]; the string bytes are materialized just below
#     it and BOTH regions read and write through to the live value, so
#     locate-a-literal / POKE-semigraphics / PRINT-the-variable works.  For
#     a numeric, VARPTR returns the address of the value's 4 Microsoft-
#     single bytes (fio_mkf/fio_cvf), also live in both directions.  The
#     bytes a POKE (or a Z80 store) made are kept (NRAW, sp_nbytes) while
#     they still decode to the value, so a number written a byte at a
#     time into a variable holding 0 arrives whole.
#     Allocation grows down from HIMEM like real string space; CLEAR/RUN/
#     NEW reset it (sp_reset from clear_vars).  VARPTR IS STABLE: the
#     descriptor (or a numeric's 4 bytes) is allocated ONCE per variable per
#     run and every later VARPTR returns the same address, as on hardware
#     where it is the variable-table slot.  Only the string's DATA bytes ever
#     move, and only when the value outgrows the capacity they were given --
#     then a fresh data region is allocated and the descriptor's address
#     cells are repointed.  (Until 2026-09-10 EVERY call freed and
#     re-allocated the whole thing, so VARPTR(A$);VARPTR(A$) answered two
#     addresses, the two-call idiom PEEK(VARPTR(A$)+1)+256*PEEK(VARPTR(A$)+2)
#     composed a dead address, and VARPTR in a loop marched SSP down to ?OM --
#     162 corpus listings call VARPTR on the same string twice.)  Documented
#     deviations: the bytes are a mem[]-backed COPY (a literal's bytes are
#     not the program line, so pack-then-SAVE captures nothing), the data
#     region a string outgrew is unmapped rather than left as stale bytes,
#     and POKEing the descriptor's address cells is ignored.  POKE of the
#     length byte truncates or space-pads the live value.

# ---- THE ADDRESS-RESOLUTION CONTRACT --------------------------------------
# dopeek() (p80) resolves ONE byte per address from several stores.  The order
# below is the CONTRACT, not an implementation detail: ../trs80_z80_core must
# reproduce it byte-for-byte or the core will execute the wrong bytes with no
# error.  Requested by that project 2026-09-08; keep this list and dopeek in
# step.  Highest precedence first:
#
#   1. 3C00-3FFFH (15360-16383) -> SCR[], the simulated screen
#      3800-38FFH (14336-14591) -> kb_matrix(), the live keyboard matrix
#   2. 37E8/37E9H (14312/14313) -> constant 63, printer ready.  READ-ONLY
#      PROJECTION: POKEs land in MEM[] and are never read back.
#   3. 40AA-40ACH (16554-16556) -> the ROM RND seed (rnd_peek, p90)
#      40A4/40B1/40F9H pairs    -> pm_sysptr() below (program base, HIMEM,
#      start of variables).  40B1H is the one WRITABLE member: see
#      pm_sethimem().
#      THE SYSTEM VARIABLE WINDOW (sv_peek, below; the SVW set): 4020-4022H
#      cursor position and character, 4028H/4029H/409BH printer lines per
#      page, line counter and column, 4041-4046H the Model I clock,
#      40A2/40A3H the current line number, 40E1-40E5H AUTO's flag, line and
#      increment, 411BH the TRON flag -- each read from the live state it
#      names.  Added 2026-09-11; see the window's own comment for the write
#      side of each.
#   4. a in SPK -> VARPTR string space (sp_peek).  THIS DELIBERATELY OUTRANKS
#      RULE 5: a packed string inside the program-image range must win over
#      the image, which is what makes the string-packing idiom work at any
#      program size.  It is an invariant, not a consequence of statement
#      order -- do not reorder it under rule 5.
#   5. a >= 17129 and a < PMEND -> the tokenized program image.  WRITABLE
#      since 2026-09-12: a >= 17129 returns MEM[a] if that address was ever
#      stored (a POKE, or a USR write-set), else the original crunched byte
#      PMEM[a].  Image RAM is RAM, as on the machine -- a payload that keeps
#      a buffer inside its own loaded bytes (the Dancing Demon's score/dance
#      editor, at 6B9BH) reads back what it wrote.  RUN and LIST are never
#      affected: they work from prog[] (the source text), not PMEM, so a POKE
#      here cannot corrupt the running program the way it does on hardware.
#      A stored byte BELONGS TO THE LINE it landed in (pm_build, since
#      2026-09-20): a rebuild carries it to the line's new address, and
#      drops it when that line was re-entered, deleted or replaced by NEW
#      or a LOAD.  So after the program changes this rule still answers
#      from MEM[a], but MEM[] over the image has been re-keyed; the core
#      needs nothing new, because a rebuilt image is resent whole.
#      The bound is RAMTOP, not HIMEM.  a > RAMTOP -> 255 (unreachable today).
#   6. otherwise -> MEM[a] if it was ever written, else 255.
#
# TWO READ-ONLY PROJECTIONS, NOT ONE (rules 2 and 5): "POKE lands in MEM[] and
# is never read back" is a CLASS in this interpreter, not a program-image
# quirk.  A byte in either region is a byte the core will not see.
#
# 255 IS LIVE BEHAVIOUR, and it is reached by rule 6's fallthrough rather than
# by the RAMTOP test.  Unwritten RAM reads 255 -- what a machine with no chip
# at that address returns -- and the core models unwritten RAM the same way.

# ---- THE ADDRESS-RESOLUTION CONTRACT, WRITE SIDE --------------------------
# poke_byte() (p80) is dopeek's twin and its order is CONTRACT for the same
# reason: a Z80 store from ../trs80_z80_core must land exactly where a POKE of
# the same address lands, or the two disagree about memory with no error.
# Requested by that project 2026-09-08 (handoff REPLY 2).  They read the order
# off the code themselves and read it correctly; all six rules are theirs,
# re-verified against st_poke 2026-09-09.  Split 2026-09-11: st_poke is now
# only the statement parser, and poke_byte(a, b) is the single store
# primitive every write that must agree with POKE goes through -- the p77
# shim applying a Z80 write-set, and the string-alias write-through (finding
# 7).  Highest precedence first:
#
#   1. 3C00-3FFFH (15360-16383) -> s_poke() + sync_cursor()
#   2. 40AA-40ACH (16554-16556) -> rnd_poke(), the ROM RND seed
#   3. 40B1/40B2H (16561/16562) -> pm_sethimem(), the one writable pointer
#      the SYSTEM VARIABLE WINDOW (a in SVW) -> sv_poke(): cursor moves,
#      cursor character, printer counters, AUTO request, TRON flag; a
#      clock cell (4041-4046H) becomes plain RAM once written (MEM[a],
#      read back by sv_peek; on a cassette machine nothing updates those
#      bytes, and Space Chase parks its routine across them); the current
#      line number ignores writes (documented)
#   4. a in SPK                 -> sp_poke(), VARPTR string-space write-through
#   5. a > RAMTOP               -> DISCARDED (absent RAM)
#   6. otherwise                -> MEM[a] = b, after pm_sync() when the
#      program image is stale and a >= 17129: the store must be made against
#      the CURRENT image, because the next build decides by line what stays
#      (read rule 5).  Five cells there have a SIDE
#      EFFECT on write: 401E/401FH and 4026/4027H, the video and printer
#      driver vectors (dv_update, p80) -- the ROM's two driver addresses
#      re-route output, 0067H silences the printer; and 403DH (16445), the
#      ROM's image of the port-FF bits, whose bit 3 is its 32-column print
#      flag (the cursor step in s_putc, p20; CHR$(23) sets it and CLS
#      clears it through this same primitive, so the frame sees them).
#      The bytes themselves are ordinary MEM[] (seeded 88,4, 141,5 and 0
#      in init).
#
# FOUR ASYMMETRIES AGAINST THE READ SIDE.  Each is a range the read side
# projects from somewhere other than MEM[], so a write there lands in MEM[]
# and NOTHING CAN EVER OBSERVE IT:
#   * 3800-38FFH keyboard (read rule 1) -- no write branch.
#   * 37E8/37E9H printer  (read rule 2) -- no write branch.
#   * 40A4/40A5H and 40F9/40FAH (read rule 3) -- no write branch.  40B1/40B2H
#     is the ONLY writable member; rule 3 above is where that finally gets
#     said on the write side, having been stated only on the read side.
#   * the tokenized program image, a >= 17129 && a < PMEND -- rule 6 stores
#     MEM[a] and read rule 5 NOW READS IT BACK (writable since 2026-09-12,
#     superseding FINDING 23's read-only shadow: the Dancing Demon keeps its
#     score buffer inside its own image at 6B9BH and needs the write to
#     stick).  Not an asymmetry any more; no image-specific write branch is
#     needed because rule 6 already stores it and rule 5 reads it.
#
# THOSE BYTES ARE UNDEFINED -- not zero, not absent.  If this side and the
# core ever diff their memory images, the four ranges above are OUT OF SCOPE
# for the comparison: identical observable behaviour, deliberately different
# stores.  Do not "fix" either side to agree there, and do not turn rule 6
# into a discard for them -- the store is unobservable either way, and a
# discard would cost four address tests in the hot POKE path to buy nothing.
#
# NO ORDERING HAZARD MIRRORING READ RULES 4/5.  SPK outranks the program image
# on READ because a packed string inside the image range must win.  On write
# there is no image branch at all, so SPK merely precedes rule 6.  Nothing to
# keep in step here.
#
# RULE 5 IS UNREACHABLE TODAY, as dopeek's is (RAMTOP == 65535 == addrconv's
# bound), and the two stay equivalent for any RAMTOP: dopeek tests a > RAMTOP
# only inside its a >= 17129 branch and poke_byte tests it unconditionally,
# but RAMTOP >= 17129 always holds, so no address is judged differently.

# ---- keyword table (byte 128-251 <-> expansion), longest-match index -------
function pm_init_index(   tbl, pairs, np, i, j, v, w, ins) {
    tbl = "80 END 81 FOR 82 RESET 83 SET 84 CLS 85 CMD 86 RANDOM 87 NEXT " \
          "88 DATA 89 INPUT 8A DIM 8B READ 8C LET 8D GOTO 8E RUN 8F IF " \
          "90 RESTORE 91 GOSUB 92 RETURN 93 REM 94 STOP 95 ELSE 96 TRON " \
          "97 TROFF 98 DEFSTR 99 DEFINT 9A DEFSNG 9B DEFDBL 9C LINE 9D EDIT " \
          "9E ERROR 9F RESUME A0 OUT A1 ON A2 OPEN A3 FIELD A4 GET A5 PUT " \
          "A6 CLOSE A7 LOAD A8 MERGE A9 NAME AA KILL AB LSET AC RSET " \
          "AD SAVE AE SYSTEM AF LPRINT B0 DEF B1 POKE B2 PRINT B3 CONT " \
          "B4 LIST B5 LLIST B6 DELETE B7 AUTO B8 CLEAR B9 CLOAD BA CSAVE " \
          "BB NEW BC TAB( BD TO BE FN BF USING C0 VARPTR C1 USR C2 ERL " \
          "C3 ERR C4 STRING$ C5 INSTR C6 POINT C7 TIME$ C8 MEM C9 INKEY$ " \
          "CA THEN CB NOT CC STEP CD + CE - CF * D0 / D1 [ D1 ^ D2 AND " \
          "D3 OR D4 > D5 = D6 < D7 SGN D8 INT D9 ABS DA FRE DB INP DC POS " \
          "DD SQR DE RND DF LOG E0 EXP E1 COS E2 SIN E3 TAN E4 ATN E5 PEEK " \
          "E6 CVI E7 CVS E8 CVD E9 EOF EA LOC EB LOF EC MKI$ ED MKS$ " \
          "EE MKD$ EF CINT F0 CSNG F1 CDBL F2 FIX F3 LEN F4 STR$ F5 VAL " \
          "F6 ASC F7 CHR$ F8 LEFT$ F9 RIGHT$ FA MID$ FB '"
    np = split(tbl, pairs, " ")
    NTOKI = 0
    for (i = 1; i <= np; i += 2) {
        v = strtonum("0x" pairs[i]); w = pairs[i + 1]
        # insertion sort, longest expansion first (MID$ before MID etc.)
        ins = ++NTOKI
        for (j = NTOKI - 1; j >= 1 && length(TIW[j]) < length(w); j--) {
            TIV[j + 1] = TIV[j]; TIW[j + 1] = TIW[j]; ins = j
        }
        TIV[ins] = v; TIW[ins] = w
        if (!(v in TOKW)) TOKW[v] = w   # byte -> text for pm_detok; the first
                                        # spelling wins (D1H lists as [, and
                                        # both [ and ^ parse as the power op)
    }
    TOKIDX = 1
}

# detokenize one stored line body into the text prog[] holds (R1, p40).  The
# inverse of pm_crunch and a port of tools/detok.py's expand() with keyword
# spacing on: strings, DATA items up to a colon and everything after REM or
# ' stay literal; ' is stored as the three bytes :REM'; a keyword gets a
# space before it when the previous character would glue onto it (an
# alphanumeric, $, . or #) and one after it when an alphanumeric follows,
# because tokline lexes FORX as one identifier.  A CR or LF -- legal in a
# stored body, impossible in a text line -- becomes a space, or inside a
# non-DATA string the equivalent "+CHR$(n)+" splice.  Those rewrites touch
# only this text; the image is built from the escrowed bytes.
function pm_detok(body,   out, i, n, b, c, ins, ind, lit, kw, nxt) {
    if (!TOKIDX) pm_init_index()
    out = ""; i = 1; n = length(body); ins = 0; ind = 0; lit = 0
    while (i <= n) {
        c = substr(body, i, 1); b = ORD[c]
        if (lit) { out = out ((b == 10 || b == 13) ? " " : c); i++; continue }
        if (ins) {
            if (b == 10 || b == 13) { out = out (ind ? " " : "\"+CHR$(" b ")+\""); i++; continue }
            out = out c
            if (b == 34) ins = 0
            i++; continue
        }
        if (b == 34) { ins = 1; out = out c; i++; continue }
        if (ind) {
            if (b == 10 || b == 13) { out = out " "; i++; continue }
            if (b == 58) ind = 0
            out = out c; i++; continue
        }
        if (b == 58 && i + 2 <= n && ORD[substr(body, i + 1, 1)] == 147 && ORD[substr(body, i + 2, 1)] == 251) {
            out = out "'"; lit = 1; i += 3; continue
        }
        if (b == 10 || b == 13) { out = out " "; i++; continue }
        if (b >= 128) {
            if (!(b in TOKW)) { out = out c; i++; continue }
            kw = TOKW[b]
            if (kw ~ /^[A-Za-z]/ && out != "" && substr(out, length(out), 1) ~ /[A-Za-z0-9$.#]/) out = out " "
            out = out kw
            nxt = (i < n) ? substr(body, i + 1, 1) : ""
            if (kw ~ /[A-Za-z0-9]$/ && nxt ~ /^[A-Za-z0-9]$/) out = out " "
            if (b == 147 || b == 251) lit = 1
            else if (b == 136) ind = 1
            i++; continue
        }
        out = out c; i++
    }
    return out
}

# the bytes of one line for the image: the escrowed originals when the line
# came from a tokenized file (R1), else the crunched text
function pm_body(ln,   body, j) {
    if (ln in ESC) {
        body = ESC[ln]; PMBN = length(body)
        for (j = 1; j <= PMBN; j++) PMB[j] = ORD[substr(body, j, 1)]
    } else pm_crunch(prog[ln])
}

# crunch one line body into PMB[1..PMBN] (mirrors tools/tok.py: strings,
# DATA-to-colon, and REM/' payloads stay literal; ' stores as :REM')
function pm_crunch(text,   i, n, c, ins, ind, lit, j, w, matched) {
    PMBN = 0
    i = 1; n = length(text); ins = 0; ind = 0; lit = 0
    while (i <= n) {
        c = substr(text, i, 1)
        if (lit || ins) {
            PMB[++PMBN] = ORD[c]
            if (ins && c == "\"") ins = 0
            i++; continue
        }
        if (c == "\"") { ins = 1; PMB[++PMBN] = 34; i++; continue }
        if (ind) { if (c == ":") ind = 0; PMB[++PMBN] = ORD[c]; i++; continue }
        matched = 0
        for (j = 1; j <= NTOKI; j++) {
            w = TIW[j]
            if (substr(text, i, length(w)) == w) {
                if (TIV[j] == 251) { PMB[++PMBN] = 58; PMB[++PMBN] = 147; PMB[++PMBN] = 251 }
                else PMB[++PMBN] = TIV[j]
                if (TIV[j] == 147 || TIV[j] == 251) lit = 1
                else if (TIV[j] == 136) ind = 1
                i += length(w); matched = 1
                break
            }
        }
        if (!matched) { PMB[++PMBN] = (c in ORD) ? ORD[c] : 63; i++ }
    }
}

# (re)serialize prog[] into PMEM[17129..PMEND-1]
#
# THE WINDOW OVERFLOW POLICY (ruled 2026-09-11): TRUNCATE AT A WHOLE LINE.
# Program text is unbounded on this side, but the image lives in a 16-bit
# space, so a program can outgrow the window that shows it.  The image now
# stops before the first line whose record (plus the 00 00 terminator after
# it) would cross RAMTOP, and writes the terminator there, so any walker of
# the next-line chain -- a PEEK loop, or a Z80 dispatcher of the Dancing
# Demon kind, for which the chain IS its symbol table -- sees a well-formed,
# shorter program instead of a link into garbage.  40F9H reports the
# truncated end.  The other two options were rejected: REFUSING (?OM at
# RUN) would take back the unbounded-program generosity the interpreter
# chose deliberately, and a SLIDING window would change what 40A4H/40F9H
# mean mid-run.  Not silent: pm_truncnote() prints one stderr line per build
# the first time the truncated image is consulted (dopeek rule 5, 40F9H, or
# the USR frame), so a program that reads past its own cut is told, not
# fooled.  Until 2026-09-11 the next pointer wrapped modulo 65536 and PMEM
# went on being written above the address space, unreachable by any PEEK.
#
# WHAT A POKE INTO THE IMAGE BELONGS TO (the 2026-09-19 audit, M-8).  Read
# rule 5 serves MEM[a] over the crunched byte, and MEM[] is keyed by
# address, but on the machine a byte POKEd into a line is part of that
# LINE: it moves when an earlier line grows or goes, and it is gone when the
# line itself is re-entered, deleted, or replaced by NEW or a LOAD.  So each
# build lifts the stored bytes out of the old image, per line and offset
# (PMLA/PMLL, the old line table), and puts back only those whose line was
# not touched since (PMTOUCH, set by inval_cache in p40), at the line's new
# address.  Everything else stored inside the old or the new image range is
# dropped: the code-in-a-REM idiom keeps its bytes while the loader lines
# after it are deleted, and a payload loaded later is never read through
# the last program's POKEs.  poke_byte syncs the image before it stores
# into it, so a store is always judged against the image it was made in.
function pm_build(   i, ln, addr, nb, j, nxt, a, e, ov, novl, k, p) {
    if (!TOKIDX) pm_init_index()
    novl = 0
    for (ln in PMLA) {
        e = PMLA[ln] + PMLL[ln]
        for (a = PMLA[ln]; a < e; a++) if (a in MEM) {
            if (!(ln in PMTOUCH)) ov[++novl] = ln SUBSEP (a - PMLA[ln]) SUBSEP MEM[a]
            delete MEM[a]
        }
    }
    if (PMEND > 0) for (a = PMEND - 2; a < PMEND; a++) delete MEM[a]   # the old terminator
    e = PMEND
    delete PMLA; delete PMLL; delete PMTOUCH
    delete PMEM
    addr = 17129
    PMTRUNC = 0; PMTRUNCLN = 0; PMNOTED = 0
    for (i = 1; i <= NL; i++) {
        ln = LNS[i]
        pm_body(ln); nb = PMBN
        if (addr + 4 + nb + 1 + 2 - 1 > RAMTOP) { PMTRUNC = 1; PMTRUNCLN = ln; break }
        nxt = addr + 4 + nb + 1                   # always <= RAMTOP now
        PMEM[addr] = nxt % 256; PMEM[addr + 1] = int(nxt / 256)
        PMEM[addr + 2] = ln % 256; PMEM[addr + 3] = int(ln / 256)
        for (j = 1; j <= nb; j++) PMEM[addr + 4 + j - 1] = PMB[j]
        PMEM[addr + 4 + nb] = 0
        PMLA[ln] = addr; PMLL[ln] = 4 + nb + 1
        addr += 4 + nb + 1
    }
    PMEM[addr] = 0; PMEM[addr + 1] = 0
    PMEND = addr + 2
    for (a = (e > 17129 ? e : 17129); a < PMEND; a++) delete MEM[a]   # RAM the program grew over
    for (k = 1; k <= novl; k++) {
        split(ov[k], p, SUBSEP)
        if (p[1] in PMLA) MEM[PMLA[p[1]] + p[2]] = p[3] + 0
    }
    PROGDIRTY = 0
    FRPMDIRTY = 1                                 # the USR frame resends the image
}

function pm_sync() { if (PROGDIRTY || PMEND == 0) pm_build() }

# once per build, the first time a truncated image is consulted
function pm_truncnote() {
    if (!PMTRUNC || PMNOTED) return
    PMNOTED = 1
    diag_err("PROGRAM IMAGE TRUNCATED: LINE " PMTRUNCLN " AND AFTER DO NOT FIT BELOW " RAMTOP \
             "; PEEK AND MACHINE CODE SEE A CHAIN ENDING AT " (PMEND - 2))
}

# the six live system-pointer bytes (dopeek routes them here)
function pm_sysptr(a) {
    if (a == 16548) return 233                    # 40A4H: program base 42E9H
    if (a == 16549) return 66
    if (a == 16561) return HIMEM % 256            # 40B1H: top of memory
    if (a == 16562) return int(HIMEM / 256)
    pm_sync(); pm_truncnote()                     # 40F9H: start of variables
    # a PEEK returns a byte: mask the high half too, so a program image
    # larger than the address space cannot leak a >255 value (reported by
    # ../trs80_z80_core 2026-09-07; 1200 REM lines used to answer 381).
    # Since the truncation ruling PMEND <= RAMTOP + 1, so the mask is now
    # only a belt for the braces.
    return (a == 16633) ? PMEND % 256 : int(PMEND / 256) % 256
}

# 40B1H/40B2H is a WRITABLE pointer: lowering HIMEM with POKE 16561/16562
# (then CLEAR) is the PROGRAMMATIC half of the reserve-then-load idiom, the
# half that does not go through the MEMORY SIZE? prompt -- 91 corpus
# listings do it, e.g. wordsmth.bas reserving BF78H-BFFFH for a lowercase
# driver.  Writes move the live fence; string space allocated afterwards
# descends from the new value.  Existing VARPTR regions are left where they
# are, as on hardware, where the idiom requires the CLEAR to follow.
function pm_sethimem(a, b) {
    if (a == 16561) HIMEM = int(HIMEM / 256) * 256 + b
    else            HIMEM = HIMEM % 256 + b * 256
    if (SSP > HIMEM) SSP = HIMEM
}

# ---- VARPTR ---------------------------------------------------------------
# Storage maps, per materialized address a: SPK[a] = value locator ("V" name
# for a scalar, "A" storage-key for an array element), SPT[a] = role -- a
# 0-based byte offset for string bytes, "L" the live length byte, "C" a
# constant descriptor byte (SPV[a]), or "Nj" numeric byte j.  SSP grows down
# from HIMEM.  Per variable: VPDESC = its VARPTR (the descriptor address, or
# a numeric's first byte), permanent for the run; VPDATA/VPCAP = where its
# string bytes live and how many cells are mapped there.  sp_reset wipes
# everything (clear_vars).

function sp_reset(   a) {
    if (FRTRACK) for (a in SPK) FRDIRTY[a] = 1   # the frame resends what these read as now
    delete SPK; delete SPT; delete SPV; delete VPDESC; delete VPDATA; delete VPCAP
    delete ALIAS; ALN = 0
    delete NRAW
    SSP = HIMEM
}

# unmap a string's data cells (the descriptor stays where it is)
function sp_free_data(tgt,   a, e) {
    if (!(tgt in VPDATA)) return
    e = VPDATA[tgt] + VPCAP[tgt] - 1
    for (a = VPDATA[tgt]; a <= e; a++) { delete SPK[a]; delete SPT[a]; if (FRTRACK) FRDIRTY[a] = 1 }
}

# map len string cells for tgt at base
function sp_map_data(tgt, base, len,   j) {
    for (j = 0; j < len; j++) { SPK[base + j] = tgt; SPT[base + j] = j }
    VPDATA[tgt] = base; VPCAP[tgt] = len
}

# materialize var (locator tgt, string flag isstr) and return its VARPTR.
# Idempotent: a second call returns the first call's address.  A string's
# bytes are re-homed only when the live value is longer than the cells
# mapped for it -- which the assignment that grew it does at once (sp_grown)
# -- and shrinking never moves anything (sp_peek pads with 32 past the live
# length).
function sp_materialize(tgt, isstr,   len, need, base, j, dbase) {
    if (SSP == 0) SSP = HIMEM                     # first use this run
    if (!isstr) {
        if (tgt in VPDESC) return VPDESC[tgt]
        need = 4
        if (SSP - need < 17131) { raise(7); return 0 }
        base = SSP - need + 1; SSP -= need
        for (j = 0; j < 4; j++) { SPK[base + j] = tgt; SPT[base + j] = "N" j }
        VPDESC[tgt] = base
        return base
    }
    len = length(sp_gets(tgt))
    if (tgt in VPDESC) {
        dbase = VPDESC[tgt]
        if (len <= VPCAP[tgt]) return dbase       # still fits: nothing moves
        if (tgt in ALIAS) return dbase            # aliased: the cells are not what is read
        if (SSP - len < 17131) { raise(7); return 0 }
        base = SSP - len + 1; SSP -= len          # outgrown: fresh data region
        sp_free_data(tgt)
        sp_map_data(tgt, base, len)
        SPV[dbase + 1] = base % 256; SPV[dbase + 2] = int(base / 256)
        return dbase
    }
    need = len + 3                                # first VARPTR: bytes, then
    if (SSP - need < 17131) { raise(7); return 0 } # the descriptor just above
    base = SSP - need + 1; SSP -= need
    sp_map_data(tgt, base, len)
    dbase = base + len
    SPK[dbase] = tgt;     SPT[dbase] = "L"
    SPK[dbase + 1] = tgt; SPT[dbase + 1] = "C"; SPV[dbase + 1] = base % 256
    SPK[dbase + 2] = tgt; SPT[dbase + 2] = "C"; SPV[dbase + 2] = int(base / 256)
    VPDESC[tgt] = dbase
    return dbase
}

# An assignment gave a VARPTRed string a value longer than the cells mapped
# for it.  On the machine the assignment itself allocates the new string and
# rewrites the descriptor, so a program that kept V=VARPTR(A$) reads the new
# address at V+1/V+2 straight away.  Re-home NOW, not at the next VARPTR
# call: until 2026-09-20 the descriptor went on naming the old cells, a
# PEEK past them read the descriptor's own bytes (it sits just above), and
# a POKE there rewrote the length (the 2026-09-19 audit, M-13).
function sp_grown(name, key,   tgt) {
    tgt = (key != "") ? "A" key : "V" name
    if (tgt in VPDATA) sp_materialize(tgt, 1)
}

# live value read/write through the locator
function sp_gets(tgt,   key) {
    key = substr(tgt, 2)
    if (substr(tgt, 1, 1) == "A") return (key in VA) ? substr(VA[key], 2) : ""
    return SV[key]
}
function sp_sets(tgt, s,   key) {
    key = substr(tgt, 2)
    if (substr(tgt, 1, 1) == "A") VA[key] = "S" s
    else SV[key] = s
}
function sp_getn(tgt,   key) {
    key = substr(tgt, 2)
    if (substr(tgt, 1, 1) == "A") return (key in VA) ? substr(VA[key], 2) + 0 : 0
    return NV[key] + 0
}
function sp_setn(tgt, x,   key) {
    key = substr(tgt, 2)
    if (substr(tgt, 1, 1) == "A") VA[key] = "N" x
    else NV[key] = x
}

# The four MBF bytes of a numeric variable.  A variable here is a VALUE, not
# bytes, so they are normally encoded from it on demand.  That alone cannot
# hold a number being written one byte at a time: while the exponent byte
# (V+3) is still 0 the value is 0, and every mantissa byte stored before it
# was re-derived from that 0 and lost -- which broke the Level II MKS$/CVS
# substitute (copy four PEEKed bytes into a fresh variable) and any Z80
# routine storing a float through VARPTR, whose write-set arrives in
# ascending order, exponent last (the 2026-09-19 audit, H-11).  So a POKE
# keeps the bytes it made in NRAW, and they stay the truth for as long as
# they still decode to the variable's value; an assignment that changes
# the value outdates them, and the next read encodes afresh.
function sp_nbytes(tgt,   x) {
    x = sp_getn(tgt)
    if ((tgt in NRAW) && fio_cvf(NRAW[tgt], 4) == x) return NRAW[tgt]
    delete NRAW[tgt]
    return fio_mkf(x, 4)
}

function sp_peek(a,   t, tgt, v) {
    t = SPT[a]; tgt = SPK[a]
    if (t == "L") return length(sp_gets(tgt)) % 256
    if (t == "C") return SPV[a]
    if (substr(t, 1, 1) == "N") {
        v = sp_nbytes(tgt)
        return ORD[substr(v, substr(t, 2) + 1, 1)]
    }
    v = sp_gets(tgt)                              # string byte, live
    return (t + 1 <= length(v)) ? ORD[substr(v, t + 1, 1)] : 32
}

function sp_poke(a, b,   t, tgt, v, j) {
    t = SPT[a]; tgt = SPK[a]
    if (t == "C") { al_repoint(a, b, tgt); return } # descriptor address cell (finding 7)
    if (t == "L") {                               # truncate / space-pad
        v = sp_gets(tgt)
        while (length(v) < b) v = v " "
        sp_sets(tgt, substr(v, 1, b))
        return
    }
    if (substr(t, 1, 1) == "N") {
        v = sp_nbytes(tgt); j = substr(t, 2) + 1
        v = substr(v, 1, j - 1) CHR[b] substr(v, j + 1)
        NRAW[tgt] = v
        sp_setn(tgt, fio_cvf(v, 4))
        return
    }
    v = sp_gets(tgt); j = t + 1                   # string byte, write through
    while (length(v) < j) v = v " "
    sp_sets(tgt, substr(v, 1, j - 1) CHR[b] substr(v, j + 1))
}

# VARPTR(var) -- parse a variable REFERENCE (scalar or array element), not
# an expression; called from e_prim
function fn_varptr(   name, key, tgt) {
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == "(")) { raise(2); return "N0" }
    CP++
    if (TY[CK, CP] != "i") { raise(2); return "N0" }
    name = TK[CK, CP]; CP++
    key = ""
    if (TY[CK, CP] == "o" && TK[CK, CP] == "(") { key = aref(name); if (E) return "N0" }
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == ")")) { raise(2); return "N0" }
    CP++
    tgt = (key != "") ? "A" key : "V" name
    return "N" sp_materialize(tgt, strname(name))
}

# ===================== the SYSTEM VARIABLE WINDOW ============================
# ROM RAM cells that period listings PEEK and POKE, served from the live
# state they name instead of dead MEM[].  Proposed 2026-09-05 from the
# trs-80.com tips tally, MEASURED over the corpus before building (2026-09-11:
# the cursor cell has 92 readers and 26 writers, the printer line counter 27
# and 36, lines per page 13 and 21, the cursor character 26 and 43 -- eleven
# of them hiding the cursor; everything else under 3), built the same day.
# These are real Model I addresses, so EXT rule 1 is not in play.  Per cell:
#   4020/4021H (16416/7)  cursor position = 3C00H + CUR.  POKE moves the
#                         cursor once both bytes name a video address.
#   4022H (16418)         cursor character (CURCH).  POKE 0 hides the
#                         terminal cursor, anything else shows it; the glyph
#                         itself is the terminal's (documented).
#   4028H (16424)         lines per page + 1 (LPPAGE, 67).  POKE sets it.
#   4029H (16425)         lines printed on this page (LPLINES): lp_nl counts,
#                         wraps at LPPAGE-1.  POKE sets it (the "POKE
#                         16425,1 after a form feed" idiom, 36 listings).
#   409BH (16539)         printer column (LPCOL).  POKE sets it.  BASIC's
#                         count, kept before the driver is called, so it
#                         advances while the printer vector is routed too.
#   4041-4046H (16449-54) SS MN HH YY DD MM from the host clock, as TIME$
#                         reads it (documented deviation: Level II has no
#                         clock interrupt, so on the machine these bytes
#                         hold whatever was last stored).  A POKE makes the
#                         cell plain RAM from then on (SVWRIT): the byte
#                         reads back and reaches the USR frame.  Found by
#                         the 2026-09-15 corpus sweep: Space Chase (80
#                         Micro 5/1982) POKEs its routine at 403EH-405AH,
#                         and the frame carried the wall clock in place of
#                         six of its bytes -- 340 calls ran, the 341st
#                         crashed when the seconds byte became an opcode.
#   40A2/40A3H (16546/7)  the line number executing (CLN; 0 at READY).
#                         POKEs ignored.
#   40E1H (16609)         AUTO flag: 1 while AUTO is prompting.  POKE
#                         non-zero REQUESTS AUTO: it starts at the next
#                         READY prompt from 40E2/E3H by 40E4/E5H, as the ROM
#                         would (tip 70).  Batch mode has no prompt, so the
#                         request is inert there.
#   40E2/40E3H (16610/1)  AUTO's current line (AUTOLINE).  POKE sets it.
#   40E4/40E5H (16612/3)  AUTO's increment (AUTOINC).  POKE sets it (tip 71).
#   411BH (16667)         TRON flag: 175 on, 0 off.  POKE non-zero = TRON,
#                         0 = TROFF (tips 76/77).
# Every cell is also in the USR frame's always-sent set (fr_build).
function sv_init(   a) {
    SVW[16416] = 1; SVW[16417] = 1; SVW[16418] = 1
    SVW[16424] = 1; SVW[16425] = 1; SVW[16539] = 1
    for (a = 16449; a <= 16454; a++) SVW[a] = 1
    SVW[16546] = 1; SVW[16547] = 1
    for (a = 16609; a <= 16613; a++) SVW[a] = 1
    SVW[16667] = 1
}
function sv_peek(a,   v) {
    if (a == 16416) return (15360 + CUR) % 256
    if (a == 16417) return int((15360 + CUR) / 256)
    if (a == 16418) return CURCH
    if (a == 16424) return LPPAGE % 256
    if (a == 16425) return LPLINES % 256
    if (a == 16539) return LPCOL % 256
    if (a >= 16449 && a <= 16454) {
        if (a in SVWRIT) return MEM[a]
        v = strftime("%S %M %H %y %d %m")
        return substr(v, 3 * (a - 16449) + 1, 2) + 0
    }
    if (a == 16546) return CLN % 256
    if (a == 16547) return int(CLN / 256) % 256
    if (a == 16609) return AUTOON ? 1 : (AUTOREQ ? 1 : 0)
    if (a == 16610) return AUTOLINE % 256
    if (a == 16611) return int(AUTOLINE / 256) % 256
    if (a == 16612) return AUTOINC % 256
    if (a == 16613) return int(AUTOINC / 256) % 256
    if (a == 16667) return TRACE ? 175 : 0
    return 255
}
function sv_poke(a, b,   v) {
    if (a == 16416 || a == 16417) {
        v = 15360 + CUR
        v = (a == 16416) ? int(v / 256) * 256 + b : v % 256 + 256 * b
        if (v >= 15360 && v <= 16383) { CUR = v - 15360; sync_cursor() }
        return
    }
    if (a == 16418) {
        CURCH = b                    # 0 hides it; sync_cursor applies the rule
        sync_cursor()
        return
    }
    if (a == 16424) { LPPAGE = b; return }
    if (a == 16425) { LPLINES = b; return }
    if (a == 16539) { LPCOL = b; return }
    if (a == 16609) { AUTOREQ = (b != 0); return }
    if (a == 16610) { AUTOLINE = int(AUTOLINE / 256) * 256 + b; return }
    if (a == 16611) { AUTOLINE = AUTOLINE % 256 + 256 * b; return }
    if (a == 16612) { AUTOINC = int(AUTOINC / 256) * 256 + b; return }
    if (a == 16613) { AUTOINC = AUTOINC % 256 + 256 * b; return }
    if (a == 16667) { TRACE = (b != 0); return }
    if (a >= 16449 && a <= 16454) { MEM[a] = b; SVWRIT[a] = 1; return }
    # 16546/16547 (the current line): ignored
}

# ===================== string aliasing via the descriptor (finding 7) =======
# The period trick: POKE VARPTR(A$)+1 / +2 repoints a string's descriptor at
# video RAM (high byte 3CH) or system RAM (40H), and from then on ordinary
# string operations READ AND WRITE that region -- PRINT A$ shows the screen,
# LSET A$="..." paints it, MID$(A$,n,1) picks a cell.  Pure BASIC, no USR;
# ~23 corpus listings use the direct form (TAXMAN, VIDENTRY, INOUTPUT, the
# tax and screen editors) and more the indirect V=VARPTR(A$):POKE V+1 form.
# Until 2026-09-11 the descriptor cells ignored POKE, so every one of them
# ran to a clean END doing nothing (seam audit finding 7; built the same day
# after the user greenlit it).
#
# NOT a storage re-architecture: an ALIAS side-table (locator -> address),
# resolved through dopeek / poke_byte, so the aliased region obeys THE
# ADDRESS-RESOLUTION CONTRACT for free -- screen, keyboard, packed strings,
# system pointers, the program image, all of it.  The rules, each mirroring
# what the real descriptor does:
#   * POKE of an address cell STORES the byte (PEEK reads it back) and, when
#     the two cells no longer name the string's own data, sets ALIAS[tgt];
#     poking them back to the own data address clears it.
#   * READ of an aliased variable (e_prim scalar, aref element, and the
#     current value LSET/RSET/MID$= start from) assembles LEN bytes live from
#     dopeek(addr..); LEN is the live length, which POKE VARPTR(A$)+0 sets.
#   * an ASSIGNMENT (LET, READ, INPUT, FOR... -- assignv, p70) allocates a
#     new string on hardware and moves the descriptor, so it CLEARS the
#     alias and points the cells back at the own data.
#   * an IN-PLACE write (LSET/RSET p85, MID$= p80) writes THROUGH to the
#     aliased region via poke_byte, one byte per position, keeps the alias,
#     and leaves the string's own bytes as they were (repointing the cells
#     back shows the old value, as on hardware).
#   * VARPTR of an aliased string never re-homes its data cells (they are
#     not what is read), so the descriptor stays put.
#   * CLEAR/RUN/NEW drop every alias with the string space (sp_reset).
# Edges left alone, documented: an aliased string used as a DEF FN parameter
# reads the aliased bytes inside the body, not the bound argument (p60 binds
# SV[] directly); FIELDed strings are never aliased (their own path).  ALN
# counts live aliases so every check on an ordinary string is one integer
# test.  Addresses wrap at 65536 like the hardware's.
function al_repoint(a, b, tgt,   d, addr) {
    SPV[a] = b
    d = VPDESC[tgt]
    addr = SPV[d + 1] + 256 * SPV[d + 2]
    if (addr == VPDATA[tgt]) { if (tgt in ALIAS) { delete ALIAS[tgt]; ALN-- } }
    else { if (!(tgt in ALIAS)) ALN++; ALIAS[tgt] = addr }
}
function al_read(tgt,   addr, len, j, s, b) {
    addr = ALIAS[tgt]; len = length(sp_gets(tgt)); s = ""
    for (j = 0; j < len; j++) { b = dopeek((addr + j) % 65536); if (E) return ""; s = s CHR[b] }
    return s
}
# the current value of a string variable, alias-aware (name, array key)
function al_cur(name, key,   tgt) {
    tgt = (key != "") ? "A" key : "V" name
    if (ALN && (tgt in ALIAS)) return al_read(tgt)
    return (key != "") ? ((key in VA) ? vstr(VA[key]) : "") : SV[name]
}
# an in-place write: through to the alias when there is one (the string's
# own bytes stay as they were, as on hardware), else into the value
function al_setinplace(name, key, s,   tgt, addr, j) {
    tgt = (key != "") ? "A" key : "V" name
    if (!(ALN && (tgt in ALIAS))) { sp_sets(tgt, s); return }
    addr = ALIAS[tgt]
    for (j = 1; j <= length(s); j++) poke_byte((addr + j - 1) % 65536, ORD[substr(s, j, 1)])
}
# an assignment: the descriptor moves, so the alias is gone
function al_clear(name, key,   tgt, d) {
    tgt = (key != "") ? "A" key : "V" name
    if (!(tgt in ALIAS)) return
    delete ALIAS[tgt]; ALN--
    d = VPDESC[tgt]
    SPV[d + 1] = VPDATA[tgt] % 256; SPV[d + 2] = int(VPDATA[tgt] / 256)
}

# ===================== the USR frame's memory image ==========================
# What the p77 shim will hand ../trs80_z80_core as "the memory the routine
# can see".  RULED 2026-09-11 (seam audit finding 4 closed): MATERIALISE a
# SPARSE image in, STREAM video writes out, and the keyboard is the only live
# callback.  The arithmetic that decided it, measured on this machine: one
# gawk |& round trip is 12 us, so a callback per memory read caps a core at
# ~80,000 reads/s -- a quarter of Dancing Demon's 313,030 insn/s real-time
# bar before any Z80 work -- while a 45,000-pair sparse image round-trips in
# 14 ms.  Every defined address is enumerable (MEM[] keys, SPK keys, the
# image range, the screen, the constant and pointer bytes), every value is
# read through dopeek so the address-resolution contract holds by
# construction, and everything not listed is 255.  Video reads need no
# callback: the core is the only writer during the call and streams its own
# video writes back, so its copy stays coherent.  The keyboard changes
# underneath the core, and Dancing Demon polls it at ONE site, so a 12 us
# callback there is nothing.
#
# DELTA FRAMES from day one: the first frame is full and every later frame
# resends only what may have changed since the last one, so a listing that
# calls a scroll routine thousands of times does not pay 14 ms per call.
# What is resent and why:
#   * the screen (1K), the 11 constant/pointer bytes and the 20 system
#     variable window cells -- always; cheap, and written from many places
#     (PRINT, scroll, CLS) with no chokepoint.
#   * every SPK cell -- always; string VALUES change through ordinary
#     assignment (SV[]/VA[]), not through a chokepoint, and the region is
#     small (only what VARPTR materialised).
#   * the program image -- when pm_build has run since the last frame
#     (FRPMDIRTY), plus the range a SHRUNKEN image no longer covers, which
#     now reads as MEM[] or 255.
#   * MEM[] -- only the addresses poke_byte wrote since the last frame
#     (FRDIRTY), plus SPK cells that were UNMAPPED since (sp_free_data,
#     sp_reset), which now read as MEM[] or 255.  Tracking starts with the
#     first frame (FRTRACK), so a run that never calls USR pays nothing.
# A full frame is rebuilt whenever the coprocess (re)starts; the header
# carries the generation so the two sides cannot disagree about which they
# are on.  Wire framing is p77's; this builds the CONTENT.
#
# fr_build(full) fills FRHDR (one line: gen, full, slot, entry, arg, the
# initial SP = SSP, HIMEM, RAMTOP, run count) and FRRUN[1..FRN], one entry
# per run of consecutive addresses as "addr:b,b,b".  TRS80_USR_TRACE=2 dumps
# both to stderr on every USR call (programs/tests/usr.sh asserts on it).
function fr_build(full,   a, e, n, run, last, lo, hi) {
    delete FRSET
    if (!FRTRACK) { full = 1 }
    for (a = 15360; a <= 16383; a++) FRSET[a] = 1     # screen, always
    FRSET[14312] = 1; FRSET[14313] = 1                 # printer status (63)
    for (a = 16554; a <= 16556; a++) FRSET[a] = 1     # RND seed
    FRSET[16548] = 1; FRSET[16549] = 1; FRSET[16561] = 1; FRSET[16562] = 1
    FRSET[16633] = 1; FRSET[16634] = 1                 # the live pointers
    for (a in SVW) FRSET[a] = 1                        # the system variable window
    for (a in SPK) FRSET[a] = 1                        # packed strings, always
    pm_sync(); pm_truncnote()
    if (full || FRPMDIRTY) {
        for (a = 17129; a < PMEND; a++) FRSET[a] = 1
        hi = (FRPMHI > PMEND) ? FRPMHI : PMEND
        for (a = PMEND; a < hi; a++) FRSET[a] = 1      # a shrunken image's tail
    }
    if (full) { for (a in MEM) FRSET[a] = 1 }
    else       { for (a in FRDIRTY) FRSET[a] = 1 }
    delete FRRUN; FRN = 0; n = 0
    PROCINFO["sorted_in"] = "@ind_num_asc"
    last = -2; run = ""
    for (a in FRSET) {
        a = a + 0
        if (a > RAMTOP) continue
        # never the keyboard: a POKE (or a routine's store) at 3800-38FFH
        # sits in MEM[], but READING the address is the live matrix, which
        # takes a keystroke from the queue -- in batch a whole line of
        # stdin, and at its end a BREAK.  The core does not want the bytes
        # anyway: it asks for the matrix with K (PROTOCOL.md).
        if (a >= 14336 && a <= 14591) continue
        if (a != last + 1) { if (run != "") FRRUN[++FRN] = run; run = a ":" dopeek(a) }
        else run = run "," dopeek(a)
        last = a; n++
    }
    if (run != "") FRRUN[++FRN] = run
    delete PROCINFO["sorted_in"]
    FRGEN++; FRFULL = full ? 1 : 0
    FRHDR = "USR FRAME gen=" FRGEN " full=" FRFULL " slot=" USR_SLOT " entry=" USR_ENTRY \
            " arg=" USR_ARG " sp=" SSP " himem=" HIMEM " ramtop=" RAMTOP " bytes=" n " runs=" FRN
    delete FRDIRTY; FRPMDIRTY = 0; FRPMHI = PMEND; FRTRACK = 1
    delete FRSET
}

# the coprocess (re)started, or the shim wants a clean slate: next frame full
function fr_reset() { FRTRACK = 0; FRGEN = 0; delete FRDIRTY }

function fr_dump(   i) {
    printf "%s\n", FRHDR > "/dev/stderr"
    for (i = 1; i <= FRN; i++) printf "  %s\n", FRRUN[i] > "/dev/stderr"
    fflush("/dev/stderr")
}
# ===================== p77: the Z80 coprocess -- USR routines executed =====
# The companion engine ../trs80_z80_core executes machine code; this shim
# drives it over one persistent gawk |& coprocess per session.  PROTOCOL.md
# in the repo root is the contract (mirrored into the core's repository);
# programs/tests/z80_stub.py is its reference implementation on the core's
# side and programs/tests/z80.sh the conformance suite.  Nothing here
# executes an opcode.
#
# The rulings this implements (2026-09-11, STATUS "Machine-language" entry):
#   * frame OUT = fr_build's sparse, contract-resolved, delta-after-first
#     memory image (p75), plus slot/entry/arg and sp=SSP (the Z80 stack
#     seats where Level II's does, at the bottom of string space);
#   * video IN is streamed as V lines and drawn as it arrives; the keyboard
#     is the one live callback (K); T ticks let a long routine keep the
#     interpreter polling for BREAK and keep the timeout guard quiet;
#   * the write-set IN is applied in address order through poke_byte, so a
#     Z80 store lands exactly where a POKE would;
#   * GRACEFUL FALLBACK: no TRS80_Z80, a command that will not start, a
#     protocol mismatch or a timeout all leave USR as the shipped stub
#     (returns its argument, one tally line per run) with one notice, so
#     trs80basic.awk stays a complete single-file gawk program.
# Discovery: TRS80_Z80 is the COMMAND to run (e.g. "python3 /x/core.py");
# unset means no core.  TRS80_Z80_TIMEOUT is the per-line read guard in
# milliseconds (default 5000) -- gawk's PROCINFO[cmd, "READ_TIMEOUT"], so a
# hung core cannot hang the interpreter.  This is the first |& coprocess in
# the interpreter; both sides flush after every line or they deadlock.
#
# SOUND (EXT, 2026-09-14): machine-code sound lives in the core (its
# z80/sound.py): TRS80_SOUND names a player command, TRS80_SOUND_WAV a file,
# TRS80_SOUND_RATE the rate, all read from the core's environment when it
# starts, and the protocol does not change.  The `sound` metacommand (p40
# st_sound, the snd_* functions below) carries SWITCHES ONLY: the player
# command comes from the environment and never from a line of text, so the
# directive can one day join the REM META whitelist without a file ever
# naming a shell command.  A switch, like a changed `speed`, takes effect
# through z80_recycle(): BYE now, a fresh core with a full frame at the next
# USR call.  BASIC's own OUT 255 stays silent, by ruling.

function z80_init() {
    if (Z80INIT) return
    Z80INIT = 1
    Z80PROTO = 1
    Z80NAMED = ENVIRON["TRS80_Z80"]               # as the user wrote it, for notices
    # gawk runs a coprocess through `sh -c`.  Where sh keeps itself between us
    # and the core (Ubuntu's dash does; macOS's sh execs a simple command), the
    # kill in z80_close makes that shell print "Terminated" into our stderr.
    # `exec` makes the core the shell's own process on every platform, so the
    # pid the handshake reports is the only process, and nothing reports it.
    Z80CMD = (Z80NAMED == "") ? "" : "exec " Z80NAMED
    Z80TO = (ENVIRON["TRS80_Z80_TIMEOUT"] + 0 > 0) ? ENVIRON["TRS80_Z80_TIMEOUT"] + 0 : 5000
    Z80STATE = (Z80CMD == "") ? "none" : "cold"   # none | cold | up | dead
}

function z80_notice(msg) { diag_err("USR CORE: " msg) }

# one line from the core into Z80LINE; 0 on timeout or EOF.  Z80EOF tells
# the two apart: getline is 0 at end of file (the core has exited) and -1
# when READ_TIMEOUT ran out (it is there and silent).
function z80_recv(   r) {
    r = (Z80CMD |& getline Z80LINE)
    Z80EOF = (r == 0)
    if (r <= 0) { Z80LINE = ""; return 0 }
    sub(/\r$/, "", Z80LINE)
    return 1
}

# Every write to the core ends here.  A core that died BETWEEN calls is met
# on a write, and a failed write to a coprocess is a gawk fatal (the session,
# the unsaved program and the tty's cooked mode all go with it) unless the
# pipe is marked NONFATAL (z80_start).  With the mark the failure lands in
# ERRNO or in fflush's result; Z80WERR records it for the caller.
function z80_send(s) {
    ERRNO = ""
    print s |& Z80CMD
    if (fflush(Z80CMD) != 0 || ERRNO != "") Z80WERR = 1
}

# the core went away under us: same ending as a timeout (PROTOCOL.md)
# The write end goes FIRST: the line that failed is still in gawk's buffer,
# and every flush-everything after it (diag_err's, system()'s own) would
# print a gawk warning into the program's error channel.
function z80_gone() {
    close(Z80CMD, "to")
    z80_notice("the core has exited; it is dead for this session, USR is the stub")
    z80_close(); raise(5)
}

# value of key=... in Z80LINE ("" if absent)
function z80_field(key,   s) {
    if (match(Z80LINE, "(^|[ \t])" key "=[^ \t]*")) {
        s = substr(Z80LINE, RSTART, RLENGTH)
        sub(/^[ \t]/, "", s); sub(/^[^=]*=/, "", s)
        return s
    }
    return ""
}

# Give up on the core.  close() of a two-way pipe WAITS for the child, so a
# core that is hung (the timeout case) is killed first when it told us its
# pid in the handshake; gawk's own PROCINFO[cmd, "pid"] is empty on the gawk
# this was built with, which is why the protocol carries it.
function z80_close() {
    if (Z80PID > 0 && !WINNATIVE) system("kill " Z80PID " 2>/dev/null")
    close(Z80CMD)
    Z80STATE = "dead"; Z80PID = 0
}

# HELLO / Z80 handshake, once per session
function z80_start() {
    z80_init()
    if (Z80STATE != "cold") return
    Z80STATE = "dead"                             # until the handshake succeeds
    PROCINFO[Z80CMD, "READ_TIMEOUT"] = Z80TO
    PROCINFO[Z80CMD, "NONFATAL"] = 1              # a dead core is ours to report (z80_send)
    Z80WERR = 0
    z80_send("HELLO proto=" Z80PROTO " mhz=" (THROTTLE_MHZ + 0) " ramtop=" RAMTOP)
    if (!z80_recv()) {
        z80_notice("cannot start '" Z80NAMED "'; USR is the stub for this session")
        z80_close(); return
    }
    if (Z80LINE !~ /^Z80 / || z80_field("proto") != Z80PROTO) {
        z80_notice("'" Z80NAMED "' speaks protocol " (z80_field("proto") == "" ? "?" : z80_field("proto")) \
                   ", this interpreter speaks " Z80PROTO "; USR is the stub for this session")
        z80_close(); return
    }
    Z80NAME = z80_field("name"); Z80PID = z80_field("pid") + 0
    Z80STATE = "up"
    fr_reset()                                    # the first frame is full
}

function z80_stop() {
    if (Z80STATE == "up") { z80_send("BYE"); close(Z80CMD) }
    Z80STATE = "dead"; Z80PID = 0
}

# apply one run "addr:b,b,b": video straight to the screen, else poke_byte
function z80_apply(run, isvideo,   p, a, n, bs, j, b) {
    p = index(run, ":"); if (p == 0) return
    a = substr(run, 1, p - 1) + 0
    n = split(substr(run, p + 1), bs, ",")
    for (j = 1; j <= n; j++) {
        b = bs[j] + 0
        if (isvideo) { if (a >= 15360 && a <= 16383) s_poke(a - 15360, b) }
        else poke_byte(a, b)
        a++
    }
}

# USR(x) with the core: returns the value of the expression, or raises.
# Called from the USR branch of fncall (p60) after usr_resolve().
function z80_usr(x,   full, res) {
    z80_start()
    if (Z80STATE != "up") {                       # the shipped stub
        if (USR_STRICT) { raise(5); return 0 }
        usr_stub_count()
        return x
    }
    if (USR_ENTRY < 0) { raise(5); return 0 }     # undefined: ?FC, as the ROM vector does
    full = 0
    for (;;) {
        fr_build(full)
        z80_sendframe()
        if (Z80WERR) { z80_gone(); return 0 }
        res = z80_run(x)
        if (Z80STATE == "need") {                 # the core lost its RAM: once more, full
            Z80STATE = "up"; fr_reset(); full = 1
            continue
        }
        return res
    }
}

function z80_sendframe(   i) {
    ERRNO = ""
    print "CALL gen=" FRGEN " full=" FRFULL " slot=" USR_SLOT " entry=" USR_ENTRY \
          " arg=" USR_ARG " sp=" SSP " himem=" HIMEM " ramtop=" RAMTOP " runs=" FRN |& Z80CMD
    for (i = 1; i <= FRN; i++) print "M " FRRUN[i] |& Z80CMD
    if (ERRNO != "") Z80WERR = 1
    z80_send("GO")
}

# the message loop for one call
function z80_run(x,   hl, res, k, brk, i, vid, early) {
    vid = 0; early = 0
    for (;;) {
        if (!z80_recv()) {
            # a core that exited between calls is met on the write or on
            # this read, whichever the host's pipe notices first (macOS: the
            # write; Linux: usually the read) -- one ending for both
            if (Z80WERR || Z80EOF) { z80_gone(); return 0 }
            z80_notice("no reply within " Z80TO " ms; the core is dead for this session, USR is the stub")
            z80_close(); raise(5); return 0
        }
        if (Z80LINE ~ /^V /) { z80_apply(substr(Z80LINE, 3), 1); vid = 1; continue }
        if (Z80LINE ~ /^K /) { z80_send("K " kb_matrix(substr(Z80LINE, 3) + 0)); continue }
        if (Z80LINE ~ /^T /) {                # BREAK poll; the tty itself on every tick (p30 kb_fill_tty)
            z80_send(pollbrk() ? "BREAK" : "OK"); continue
        }
        if (Z80LINE ~ /^MODE /) { s_setwide(substr(Z80LINE, 6) + 0); continue }
        if (Z80LINE ~ /^NEED /) { Z80STATE = "need"; return 0 }
        # W ahead of an ERR: the stores the routine made before it failed.
        # The core keeps them, and the next frame is a delta of what THIS
        # side changed, so they are applied like a write-set or the two
        # memories disagree from here on (PROTOCOL.md, Errors).  W ahead of
        # a RET is not the protocol: it falls to "unexpected" below.
        if (Z80LINE ~ /^W /) { z80_apply(substr(Z80LINE, 3), 0); early = 1; continue }
        if (Z80LINE ~ /^RET / && !early) {
            hl = z80_field("hl") + 0; res = z80_field("result") + 0
            brk = z80_field("break") + 0; k = z80_field("writes") + 0
            for (i = 1; i <= k; i++) {
                if (!z80_recv() || Z80LINE !~ /^W /) {
                    z80_notice("write-set cut short; the core is dead for this session, USR is the stub")
                    z80_close(); raise(5); return 0
                }
                z80_apply(substr(Z80LINE, 3), 0)
            }
            if (vid) sync_cursor()
            if (brk) dobreak()                    # BREAK IN n; CONT resumes the statement
            if (hl > 32767) hl -= 65536           # HL to result: signed 16-bit
            return res ? hl : x
        }
        if (Z80LINE ~ /^ERR /) { z80_notice(substr(Z80LINE, 5)); raise(5); return 0 }
        z80_notice("unexpected '" Z80LINE "'; the core is dead for this session, USR is the stub")
        z80_close(); raise(5); return 0
    }
}

# Recycle the core: BYE now, a fresh start with a full frame at the next USR
# call.  The clock travels on HELLO and the sound variables in the
# environment, once per core, so `speed` and `sound` restart a running one.
# Nothing is lost -- the interpreter owns memory and every core write came
# back through poke_byte.  A core that died stays dead for the session.
function z80_recycle() {
    if (Z80STATE != "up") return
    z80_send("BYE"); close(Z80CMD)
    Z80STATE = "cold"; Z80PID = 0
}

# --- the `sound` metacommand's state (see the header) ----------------------
# gawk hands ENVIRON changes to a coprocess started afterwards, so a switch
# sets or deletes the variable and recycles a running core.  `sound on` with
# no TRS80_SOUND asks the core for its default player ("auto").
function snd_init() {
    if (SNDINIT) return
    SNDINIT = 1
    SNDCMD = ENVIRON["TRS80_SOUND"]           # the player command: never shown, never set here
    SNDON = (SNDCMD != "")
    SNDWAV = ENVIRON["TRS80_SOUND_WAV"]
}

function snd_apply() {
    if (SNDON) ENVIRON["TRS80_SOUND"] = (SNDCMD != "" ? SNDCMD : "auto")
    else delete ENVIRON["TRS80_SOUND"]
    if (SNDWAV != "") ENVIRON["TRS80_SOUND_WAV"] = SNDWAV
    else delete ENVIRON["TRS80_SOUND_WAV"]
    z80_recycle()
}

function snd_msg(   s) {
    snd_init()
    s = "SOUND " (SNDON ? "ON" : "OFF")
    if (SNDON) s = s ((SNDCMD != "" && SNDCMD != "auto") ? " (player from TRS80_SOUND)" : " (the core's default player)")
    s = s ", WAV " (SNDWAV != "" ? SNDWAV : "OFF")
    z80_init()
    if (Z80STATE == "none") s = s "\nNO CORE: sound is machine code, run by the Z80 core (TRS80_Z80)"
    return s
}

END { z80_stop() }
# ===================== PRINT, INPUT, READ/DATA, DIM, POKE, graphics =========

function st_print(   sep, ty, tx, v, tgt, col, t) {
    if (TY[CK, CP] == "o" && TK[CK, CP] == "#") { CP++; st_print_file(); return }
    if (TY[CK, CP] == "o" && TK[CK, CP] == "@") {
        CP++
        v = e_or(); if (E) return
        if (!isN(v)) { raise(13); return }
        tgt = bfloor(num(v))
        if (tgt < 0 || tgt > 1023) { raise(5); return }
        CUR = tgt
        if (TY[CK, CP] == "o" && (TK[CK, CP] == "," || TK[CK, CP] == ";")) CP++
    }
    if (TY[CK, CP] == "i" && TK[CK, CP] == "USING") { CP++; pr_using(); return }
    sep = 0
    for (;;) {
        ty = TY[CK, CP]
        if (ty == "" || ty == "e") break
        tx = TK[CK, CP]
        if (ty == "o" && tx == ":") break
        if (ty == "i" && (tx == "ELSE" || tx == "REM")) break
        if (ty == "i" && tx == "USING") { CP++; pr_using(); return }
        if (ty == "o" && tx == ";") { sep = 1; CP++; continue }
        if (ty == "o" && tx == ",") {
            sep = 1
            # the ROM PRINTS its way to the next zone (2123-2135 -> 215A-
            # 2162: blanks through the output routine), it does not move
            # the cursor: the gap overwrites what was there, reaches the
            # printer when video is routed to it, and is in the text stream.
            # From column 48 on there is no zone left: a carriage return.
            col = CUR % 64
            if (col >= 48) s_nl()
            else for (t = 16 - (col % 16); t > 0; t--) s_putc(32)
            CP++
            continue
        }
        if (ty == "i" && tx == "TAB") {
            CP++
            if (!(TY[CK, CP] == "o" && TK[CK, CP] == "(")) { raise(2); return }
            CP++
            v = e_or(); if (E) return
            if (!isN(v)) { raise(13); return }
            if (!(TY[CK, CP] == "o" && TK[CK, CP] == ")")) { raise(2); return }
            CP++
            t = bfloor(num(v))
            if (t < 0 || t > 255) { raise(5); return }
            t = t % 64
            col = CUR % 64
            while (col < t) { s_putc(32); col++ }
            sep = 0
            continue
        }
        v = e_or(); if (E) return
        if (isN(v)) {
            # a number is never split across two lines: the ROM adds its
            # length (sign and digits, not the blank that follows) to the
            # cursor's column and sends a carriage return first when that
            # reaches the line size (20DD-20E6 -> 20FEH).  Strings wrap.
            t = fmtnum(num(v))
            if (CUR % 64 + length(t) - 1 >= 64) s_nl()
            s_puts(t)
        }
        else s_puts(vstr(v))
        sep = 0
    }
    if (!sep) s_nl()
    sync_cursor()
}

# ---- PRINT USING tail (entered with CP just past USING) --------------------
# USING is legal at ANY item position, not only at the head of the list: the
# period idiom is PRINT TAB(57) USING X$;EC (Encyclopedia for the TRS-80
# vol. 3; DEMON.bas line 30 too).  It formats the rest of the statement, so
# whatever was already printed keeps its column and USING takes over here.
function pr_using(   sep, ty, tx, v, fmt) {
    v = e_or(); if (E) return
    if (isN(v)) { raise(13); return }
    fmt = vstr(v)
    if (TY[CK, CP] == "o" && (TK[CK, CP] == ";" || TK[CK, CP] == ",")) CP++
    else { raise(2); return }
    sep = 0; PUN = 0
    for (;;) {                              # , and ; are pure separators here
        ty = TY[CK, CP]
        if (ty == "" || ty == "e") break
        tx = TK[CK, CP]
        if (ty == "o" && tx == ":") break
        if (ty == "i" && (tx == "ELSE" || tx == "REM")) break
        if (ty == "o" && (tx == ";" || tx == ",")) { sep = 1; CP++; continue }
        v = e_or(); if (E) return
        PUV[++PUN] = v
        sep = 0
    }
    v = pu_output(fmt, PUN); if (E) return
    s_puts(v)
    if (!sep) s_nl()
    sync_cursor()
}

# ---- LPRINT / LLIST --------------------------------------------------------
# The line printer is a host stream: append to $TRS80_PRINTER, or discard
# when unset.  Same value formatting and USING support as PRINT; own column
# counter (LPCOL) for , zones and TAB; no @, no #, no screen wrap.
# The column (409BH) is BASIC's, not the driver's: the ROM counts the
# character at 03A0-03B7 -- CR, LF and FF zero the count, anything else
# bumps the byte -- and only THEN calls the driver through the vector
# (03BBH).  So it advances wherever the vector points; when it stood still
# while routed, LPRINT TAB(n) never reached its column and hung.  The page
# counter (4029H) is the driver's, so it moves only when the driver runs.
function lp_puts(s,   i, n, c) {
    n = length(s)
    for (i = 1; i <= n; i++) {
        c = ORD[substr(s, i, 1)]
        if (c == 10 || c == 12 || c == 13) LPCOL = 0
        else LPCOL = (LPCOL + 1) % 256
    }
    if (LPTOVID) { s_puts(s); return }        # printer vector -> the ROM video driver
    if (LPOFF) return                         # printer vector -> a RET
    if (index(s, CHR[12])) LPLINES = 0        # a form feed starts the page over
    if (LPFILE != "") printf "%s", s >> LPFILE
}

function lp_nl() {
    LPCOL = 0
    if (LPTOVID) { s_nl(); return }
    if (LPOFF) return
    if (++LPLINES >= LPPAGE - 1) LPLINES = 0   # 4029H: lines on this page, a page is LPPAGE-1
    if (LPFILE != "") { print "" >> LPFILE; fflush(LPFILE) }
}

function st_lprint(   sep, ty, tx, v, t) {
    if (TY[CK, CP] == "i" && TK[CK, CP] == "USING") { CP++; lp_using(); return }
    sep = 0
    for (;;) {
        ty = TY[CK, CP]
        if (ty == "" || ty == "e") break
        tx = TK[CK, CP]
        if (ty == "o" && tx == ":") break
        if (ty == "i" && (tx == "ELSE" || tx == "REM")) break
        if (ty == "i" && tx == "USING") { CP++; lp_using(); return }
        if (ty == "o" && tx == ";") { sep = 1; CP++; continue }
        if (ty == "o" && tx == ",") {
            sep = 1
            # past column 112 there is no zone left on the line: the ROM
            # skips to the next one instead (211B-212B)
            if (LPCOL >= 112) lp_nl()
            else lp_puts(substr("                ", 1, 16 - (LPCOL % 16)))
            CP++
            continue
        }
        if (ty == "i" && tx == "TAB") {
            CP++
            if (!(TY[CK, CP] == "o" && TK[CK, CP] == "(")) { raise(2); return }
            CP++
            v = e_or(); if (E) return
            if (!isN(v)) { raise(13); return }
            if (!(TY[CK, CP] == "o" && TK[CK, CP] == ")")) { raise(2); return }
            CP++
            t = bfloor(num(v))
            if (t < 0 || t > 255) { raise(5); return }
            t = t % 64                        # the ROM masks it, as PRINT's (213AH)
            while (LPCOL < t) lp_puts(" ")
            sep = 0
            continue
        }
        v = e_or(); if (E) return
        if (isN(v)) {
            # the printer's twin of PRINT's rule, against 132 columns
            # (20D5-20DB: column + length >= 84H)
            v = fmtnum(num(v))
            if (LPCOL + length(v) - 1 >= 132) lp_nl()
            lp_puts(v)
        }
        else lp_puts(vstr(v))
        sep = 0
    }
    if (!sep) lp_nl()
}

# LPRINT USING tail -- the printer twin of pr_using(), same any-position rule.
function lp_using(   sep, ty, tx, v, fmt) {
    v = e_or(); if (E) return
    if (isN(v)) { raise(13); return }
    fmt = vstr(v)
    if (TY[CK, CP] == "o" && (TK[CK, CP] == ";" || TK[CK, CP] == ",")) CP++
    else { raise(2); return }
    sep = 0; PUN = 0
    for (;;) {
        ty = TY[CK, CP]
        if (ty == "" || ty == "e") break
        tx = TK[CK, CP]
        if (ty == "o" && tx == ":") break
        if (ty == "i" && (tx == "ELSE" || tx == "REM")) break
        if (ty == "o" && (tx == ";" || tx == ",")) { sep = 1; CP++; continue }
        v = e_or(); if (E) return
        PUV[++PUN] = v
        sep = 0
    }
    v = pu_output(fmt, PUN); if (E) return
    lp_puts(v)
    if (!sep) lp_nl()
}

# OUT port,value -- accepted no-op (like DEFINT precision): both expressions
# are evaluated (errors still raise), the port write itself does nothing.
# OUT is a reserved word on hardware, so no period program uses it as a
# variable name.
# OUT p,v.  Port FFH is the Model I's four-bit output latch: bits 0-1 the
# cassette signal, bit 2 the cassette relay, bit 3 the 32-characters-per-line
# video mode -- the same latch bit CHR$(23) writes (Barden, Programming
# Techniques for Level II BASIC, 1981, figure 12-9).  OUT 255,8 selects 32
# columns and OUT 255,0 returns to 64; 81 corpus listings do so from BASIC,
# most of them to flash the screen, and until 2026-09-13 both were silent
# no-ops here.  Only the hardware changes: the ROM's print-size flag at
# 403DH, which sets the cursor step, is CHR$(23)'s and CLS's to change
# (s_setwide, p20).  Bits 0-2 stay silent by ruling (sound is machine code
# only; the core's port_out sees the same latch during a USR call), and
# every other port is open bus, as INP reads it.  Port and value are each a
# byte by the ROM's rule (byteconv): outside 0-255 is ?FC, as POKE's value.
function st_out(   v, p) {
    v = e_or(); if (E) return
    if (!isN(v)) { raise(13); return }
    p = byteconv(num(v)); if (E) return
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == ",")) { raise(2); return }
    CP++
    v = e_or(); if (E) return
    if (!isN(v)) { raise(13); return }
    v = byteconv(num(v)); if (E) return
    if (p == 255) s_setwide(int(v / 8) % 2)
}

# ---- MID$ statement --------------------------------------------------------
# MID$(v$,n[,m]) = expr : in-place replacement.  The target's length never
# changes -- the replacement is truncated to m (if given) and to what fits.
function st_midset(   name, key, n, m, v, s, r, cnt) {
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == "(")) { raise(2); return }
    CP++
    if (TY[CK, CP] != "i") { raise(2); return }
    name = TK[CK, CP]; CP++
    if (!strname(name)) { raise(13); return }
    key = ""
    if (TY[CK, CP] == "o" && TK[CK, CP] == "(") { key = aref(name); if (E) return }
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == ",")) { raise(2); return }
    CP++
    v = e_or(); if (E) return
    if (!isN(v)) { raise(13); return }
    n = bfloor(num(v))
    m = -1
    if (TY[CK, CP] == "o" && TK[CK, CP] == ",") {
        CP++
        v = e_or(); if (E) return
        if (!isN(v)) { raise(13); return }
        m = bfloor(num(v))
        if (m < 0 || m > 255) { raise(5); return }
    }
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == ")")) { raise(2); return }
    CP++
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == "=")) { raise(2); return }
    CP++
    v = e_or(); if (E) return
    if (isN(v)) { raise(13); return }
    r = vstr(v)
    s = al_cur(name, key); if (E) return
    if (n < 1 || n > 255 || n > length(s)) { raise(5); return }
    cnt = length(r)
    if (m >= 0 && m < cnt) cnt = m
    if (cnt > length(s) - n + 1) cnt = length(s) - n + 1
    s = substr(s, 1, n - 1) substr(r, 1, cnt) substr(s, n + cnt)
    # a FIELD variable's characters ARE the record buffer's (its descriptor
    # points into it), so the store lands there and PUT writes it (p85)
    if (fld_is(fld_tgt(name, key), s)) { fld_put(fld_tgt(name, key), s); return }
    # in place: the target keeps its length and its descriptor (p75 finding 7)
    al_setinplace(name, key, s)
}

# ---- PRINT USING formatter -------------------------------------------------
# Formats the tagged values PUV[1..nv] through the picture string.  Fields:
#   numeric: # digit positions, . decimal point, , grouping (counts as a
#     position), ** asterisk fill (+2 positions), $$ floating dollar (+2,
#     one being the $), **$ both (+3), leading + (extra sign position),
#     trailing - or + (sign after the number), ^^^^ exponent form.
#     A number too wide for its field prints as % followed by the plain
#     PRINT form.  Negative sign takes a digit position unless a sign
#     specifier is present.
#   string:  ! (first char), % spaces % (n+2 chars, left-justified).
# Anything else prints literally.  The picture is reused while values
# remain; a picture with no fields while values remain raises ?FC.
# A value of the wrong type for a field raises ?TM.
function pu_output(fmt, nv,   out, vi, i, n, c, j, r, consumed) {
    out = ""; vi = 1
    while (vi <= nv) {
        consumed = 0
        i = 1; n = length(fmt)
        while (i <= n) {
            c = substr(fmt, i, 1)
            if (c == "!") {
                if (vi > nv) return out
                out = out pu_str(PUV[vi++], 1); consumed = 1
                if (E) return ""
                i++; continue
            }
            if (c == "%") {
                j = index(substr(fmt, i + 1), "%")
                if (j > 0 && substr(fmt, i + 1, j - 1) ~ /^ *$/) {
                    if (vi > nv) return out
                    out = out pu_str(PUV[vi++], j + 1); consumed = 1
                    if (E) return ""
                    i += j + 1; continue
                }
            }
            r = pu_scan(fmt, i)
            if (r > 0) {
                if (vi > nv) return out
                out = out pu_num(PUV[vi++]); consumed = 1
                if (E) return ""
                i += r; continue
            }
            out = out c
            i++
        }
        if (!consumed && vi <= nv) { raise(5); return "" }
    }
    return out
}

# parse a numeric field at fmt[i]; returns its length, 0 if not a field.
# Sets PU_IP (integer positions incl fill/$/commas), PU_DP/PU_DOT, PU_AST,
# PU_DOL, PU_PLUS, PU_COMMA, PU_TS (trailing sign char), PU_EXP.
function pu_scan(fmt, i,   j, c, got) {
    PU_IP = 0; PU_DP = 0; PU_DOT = 0; PU_AST = 0; PU_DOL = 0
    PU_PLUS = 0; PU_COMMA = 0; PU_TS = ""; PU_EXP = 0
    j = i; got = 0
    if (substr(fmt, j, 1) == "+") { PU_PLUS = 1; j++ }
    if (substr(fmt, j, 2) == "**") {
        PU_AST = 1; PU_IP += 2; j += 2; got = 1
        if (substr(fmt, j, 1) == "$") { PU_DOL = 1; PU_IP++; j++ }
    } else if (substr(fmt, j, 2) == "$$") { PU_DOL = 1; PU_IP += 2; j += 2; got = 1 }
    for (;;) {
        c = substr(fmt, j, 1)
        if (c == "#") { PU_IP++; got = 1; j++; continue }
        if (c == "," && got) { PU_IP++; PU_COMMA = 1; j++; continue }
        break
    }
    if (substr(fmt, j, 1) == "." && (got || substr(fmt, j + 1, 1) == "#")) {
        PU_DOT = 1; j++
        while (substr(fmt, j, 1) == "#") { PU_DP++; j++ }
        if (PU_DP > 0) got = 1
    }
    if (!got) return 0
    if (substr(fmt, j, 4) == "^^^^") { PU_EXP = 1; j += 4 }
    c = substr(fmt, j, 1)
    if (c == "-" || c == "+") { PU_TS = c; j++ }
    return j - i
}

# format one numeric value into the field pu_scan just described.
# Digits come from an integer-scaled half-up round (the ROM rounds .5 up;
# C's printf rounds it to even), built back into int/decimal parts.
function pu_num(v,   x, ax, neg, digs, e2, es, ds, ist, dec, lead, core, w, fill, g, p, lim) {
    if (!isN(v)) { raise(13); return "" }
    x = num(v)
    neg = (x < 0)
    ax = neg ? -x : x
    lead = PU_PLUS ? (neg ? "-" : "+") : ((neg && PU_TS == "") ? "-" : "")
    if (PU_EXP) {
        # significant digits fill every integer position (exponent adjusted);
        # the sign, when shown on the left, takes one of them
        digs = PU_IP - (lead != "" && !PU_PLUS ? 1 : 0)
        if (digs < 1) return pu_ovf(x)
        if (ax == 0) { e2 = 0; ds = "0" }
        else {
            e2 = bfloor(log(ax) / log(10)) + 1 - digs
            lim = 10 ^ (digs + PU_DP)
            p = int(ax / (10 ^ e2) * (10 ^ PU_DP) + 0.5)
            if (p >= lim) { e2++; p = int(ax / (10 ^ e2) * (10 ^ PU_DP) + 0.5) }
            else if (p < lim / 10) { e2--; p = int(ax / (10 ^ e2) * (10 ^ PU_DP) + 0.5) }
            ds = sprintf("%.0f", p)
        }
        while (length(ds) < PU_DP + 1) ds = "0" ds
        ist = substr(ds, 1, length(ds) - PU_DP)
        dec = substr(ds, length(ds) - PU_DP + 1)
        es = sprintf("E%s%02d", (e2 < 0 ? "-" : "+"), (e2 < 0 ? -e2 : e2))
        core = lead ist (PU_DOT ? "." dec : "") es
        w = PU_IP + (PU_PLUS ? 1 : 0) + (PU_DOT ? 1 + PU_DP : 0) + 4
        while (length(core) < w) core = " " core
    } else {
        ds = sprintf("%.0f", int(ax * (10 ^ PU_DP) + 0.5))
        while (length(ds) < PU_DP + 1) ds = "0" ds
        ist = substr(ds, 1, length(ds) - PU_DP)
        dec = substr(ds, length(ds) - PU_DP + 1)
        if (ist == "0" && PU_IP == 0) ist = ""      # ".##" style field
        if (PU_COMMA) {
            g = ""; p = length(ist)
            while (p > 3) { g = "," substr(ist, p - 2, 3) g; p -= 3 }
            ist = substr(ist, 1, p) g
        }
        core = lead (PU_DOL ? "$" : "") ist (PU_DOT ? "." dec : "")
        w = PU_IP + (PU_PLUS ? 1 : 0) + (PU_DOT ? 1 + PU_DP : 0)
        if (length(core) > w) return pu_ovf(x)
        fill = PU_AST ? "*" : " "
        while (length(core) < w) core = fill core
    }
    if (PU_TS == "-") core = core (neg ? "-" : " ")
    else if (PU_TS == "+") core = core (neg ? "-" : "+")
    return core
}

# format one string value into a w-char field (truncate / pad right)
function pu_str(v, w,   s) {
    if (isN(v)) { raise(13); return "" }
    s = vstr(v)
    if (length(s) > w) s = substr(s, 1, w)
    while (length(s) < w) s = s " "
    return s
}

# field overflow: % then the number as plain PRINT would show it
function pu_ovf(x,   t) {
    t = fmtnum(x)
    gsub(/^ +| +$/, "", t)
    return "%" t
}

# ---- INPUT -----------------------------------------------------------------
function st_input(   prompt, pq, nlv, name, key, i, line, nib, idx, ok, x, d, endp) {
    # INPUT #n is legal in immediate mode, so check before the ID guard
    if (TY[CK, CP] == "o" && TK[CK, CP] == "#") { CP++; st_input_file(); return }
    if (CK == "I") { raise(12); return }
    prompt = ""; pq = 0
    if (TY[CK, CP] == "s") {
        if (TY[CK, CP + 1] == "o" && (TK[CK, CP + 1] == ";" || TK[CK, CP + 1] == ",")) {
            prompt = TK[CK, CP]; CP++
        } else {
            # Disk BASIC prompt expression: INPUT ""+CHR$(10)+"X";A.
            # e_prim reads the leading literal, so just evaluate from here.
            x = e_or(); if (E) return
            if (substr(x, 1, 1) != "S") { raise(13); return }
            prompt = substr(x, 2)
        }
        if (TY[CK, CP] == "o" && TK[CK, CP] == ";") { pq = 1; CP++ }
        else if (TY[CK, CP] == "o" && TK[CK, CP] == ",") { pq = 2; CP++ }
        else if (!(EXTON && at_stmt_end())) { raise(2); return }
    }
    if (EXTON && at_stmt_end()) {
        # EXT (gated): INPUT with no variable -- the pause idiom
        # (INPUT"PRESS ENTER";).  Prompt, read a line, discard it.
        if (prompt != "") s_puts(prompt)
        if (pq != 2) s_puts("? ")
        line = rl_read()
        if (RLCANCEL) { dobreak(); return }
        if (EOFQUIT) { if (BATCH) batch_ineof(); STOPPED = 1; return }
        return
    }
    # The targets are only LOCATED here.  Each one is resolved -- its
    # subscripts evaluated -- when its value is about to be stored, after
    # the assignments before it, as the ROM does and as READ does here:
    # INPUT I,A(I) answered 3,77 stores into A(3).  (Until 2026-09-20 every
    # subscript was evaluated before the prompt, so that went to A(0).)
    nlv = 0
    for (;;) {
        if (TY[CK, CP] != "i") { raise(2); return }
        nlv++; LV_P[nlv] = CP; CP++
        if (TY[CK, CP] == "o" && TK[CK, CP] == "(") {
            d = 0
            do {
                if (TY[CK, CP] == "" || TY[CK, CP] == "e") { raise(2); return }
                if (TY[CK, CP] == "o" && TK[CK, CP] == "(") d++
                else if (TY[CK, CP] == "o" && TK[CK, CP] == ")") d--
                CP++
            } while (d > 0)
        }
        if (TY[CK, CP] == "o" && TK[CK, CP] == ",") { CP++; continue }
        break
    }
    endp = CP
    for (;;) {                              # REDO loop
        if (prompt != "") s_puts(prompt)
        if (pq != 2) s_puts("? ")
        idx = 1; nib = 0
        ok = 1
        for (;;) {                          # fill loop
            line = rl_read()
            if (RLCANCEL) { dobreak(); return }
            if (EOFQUIT) { if (BATCH) batch_ineof(); STOPPED = 1; return }
            # ENTER alone ends the statement and assigns NOTHING: the ROM
            # tests the first byte of the buffer and skips to the end of
            # the INPUT (21E8H; the same at a ?? prompt, 2229H), so "the
            # variables will have the value they were previously assigned"
            # (manual p.3-9) -- the press-ENTER-to-keep-the-value prompt.
            # Values already taken from an earlier line of this INPUT stay.
            # A line of blanks is not empty: it still reads as 0 or "".
            if (line == "") return
            nib = parse_items(line, nib)
            while (idx <= nlv && idx <= nib) {
                CP = LV_P[idx]; name = TK[CK, CP]; CP++; key = ""
                if (TY[CK, CP] == "o" && TK[CK, CP] == "(") { key = aref(name); if (E) return }
                CP = endp
                if (strname(name)) assignv(name, key, "S" IB[idx])
                else {
                    x = IB[idx]
                    gsub(/^[ \t]+|[ \t]+$/, "", x)
                    if (x == "") x = "0"
                    if (!strictnum(x)) { ok = 0; break }
                    x = numconv(x); if (E) return           # ?OV, not ?REDO
                    assignv(name, key, "N" x)
                }
                idx++
            }
            if (!ok || idx > nlv) break
            s_puts("?? ")
        }
        if (ok) {
            if (nib > nlv) { s_puts("?EXTRA IGNORED"); s_nl() }
            return
        }
        s_puts("?REDO FROM START"); s_nl()
    }
}

# parse comma-separated items (quotes respected) from line into IB[base+1..]
function parse_items(line, base,   cnt, i, n, c, j, item) {
    cnt = base; i = 1; n = length(line)
    for (;;) {
        while (i <= n && substr(line, i, 1) == " ") i++
        if (i <= n && substr(line, i, 1) == "\"") {
            j = index(substr(line, i + 1), "\"")
            if (j == 0) { item = substr(line, i + 1); i = n + 1 }
            else { item = substr(line, i + 1, j - 1); i = i + j + 1 }
            while (i <= n && substr(line, i, 1) == " ") i++
        } else {
            j = i
            while (j <= n && substr(line, j, 1) != ",") j++
            item = substr(line, i, j - i)
            sub(/ +$/, "", item)
            i = j
        }
        cnt++; IB[cnt] = item
        if (i <= n && substr(line, i, 1) == ",") { i++; continue }
        break
    }
    return cnt
}

# ---- DATA / READ / RESTORE -------------------------------------------------
function datascan(   i, k, j) {
    NDATA = 0
    for (i = 1; i <= NL; i++) {
        k = LNS[i] ""
        if (!(k in TOKD)) tokline(k, prog[LNS[i]])
        for (j = 1; j <= TCN[k]; j++)
            if (TY[k, j] == "d") data_items(TK[k, j], LNS[i])
    }
    DATADIRTY = 0
}

function data_items(txt, ln,   ci, cn, c, j, item, wasq) {
    ci = 1; cn = length(txt)
    for (;;) {
        while (ci <= cn && substr(txt, ci, 1) == " ") ci++
        if (ci <= cn && substr(txt, ci, 1) == "\"") {
            j = index(substr(txt, ci + 1), "\"")
            if (j == 0) { item = substr(txt, ci + 1); ci = cn + 1 }
            else { item = substr(txt, ci + 1, j - 1); ci = ci + j + 1 }
            wasq = 1
            while (ci <= cn && substr(txt, ci, 1) == " ") ci++
        } else {
            j = ci
            while (j <= cn && substr(txt, j, 1) != ",") j++
            item = substr(txt, ci, j - ci)
            sub(/ +$/, "", item)
            ci = j
            wasq = 0
        }
        NDATA++; DITEM[NDATA] = item; DQ[NDATA] = wasq; DLINE[NDATA] = ln
        if (ci <= cn && substr(txt, ci, 1) == ",") { ci++; continue }
        break
    }
}

function st_read(   name, key, x) {
    if (DATADIRTY) datascan()
    for (;;) {
        if (TY[CK, CP] != "i") { raise(2); return }
        name = TK[CK, CP]; CP++
        key = ""
        if (TY[CK, CP] == "o" && TK[CK, CP] == "(") { key = aref(name); if (E) return }
        if (DP > NDATA) { raise(4); return }
        if (strname(name)) assignv(name, key, "S" DITEM[DP])
        else {
            x = DITEM[DP]
            gsub(/^[ \t]+|[ \t]+$/, "", x)
            if (x == "") x = "0"
            if (!strictnum(x)) {
                raise(2)
                ERR_AT = DLINE[DP]; ERLV = DLINE[DP]
                return
            }
            x = numconv(x); if (E) return
            assignv(name, key, "N" x)
        }
        DP++
        if (TY[CK, CP] == "o" && TK[CK, CP] == ",") { CP++; continue }
        return
    }
}

# ---- DIM -------------------------------------------------------------------
function st_dim(   name, nd, i, v, sz) {
    for (;;) {
        if (TY[CK, CP] != "i") { raise(2); return }
        name = TK[CK, CP]; CP++
        if (!(TY[CK, CP] == "o" && TK[CK, CP] == "(")) {
            # EXT (gated): DIM of a scalar (DIM Z!,V!,L$ declaration lists,
            # period habit for variable-lookup speed) -- accepted no-op
            if (EXTON && (at_stmt_end() || (TY[CK, CP] == "o" && TK[CK, CP] == ","))) {
                if (TY[CK, CP] == "o" && TK[CK, CP] == ",") { CP++; continue }
                return
            }
            raise(2); return
        }
        CP++
        nd = 0
        for (;;) {
            v = e_or(); if (E) return
            if (!isN(v)) { raise(13); return }
            sz = bfloor(num(v))
            if (sz < 0) { raise(9); return }
            nd++; DIMB[nd] = sz
            if (TY[CK, CP] == "o" && TK[CK, CP] == ",") { CP++; continue }
            break
        }
        if (!(TY[CK, CP] == "o" && TK[CK, CP] == ")")) { raise(2); return }
        CP++
        if (name in ADIM) { raise(10); return }
        ADIM[name] = nd
        for (i = 1; i <= nd; i++) ASZ[name, i] = DIMB[i]
        if (TY[CK, CP] == "o" && TK[CK, CP] == ",") { CP++; continue }
        return
    }
}

# ---- PEEK / POKE -----------------------------------------------------------
# Negative addresses wrap (the Microsoft convention: POKE -1 is 65535).
# NOTE the 65535 bound here is the SECOND place the machine size lives -- the
# first is RAMTOP (p10 init_tables).  They agree today, which is why dopeek's
# `a > RAMTOP` test is unreachable; if a 16K/32K machine is ever modelled,
# both have to change together.
# A byte argument, the way the ROM takes one (2B1C-2B22: the value of
# POKE, both arguments of OUT): convert to an integer, rounding down --
# ?OV outside -32768..32767 -- then ?FC unless the high byte is zero.
# POKE A,256 and POKE A,-1 store NOTHING on the machine.  Wrapping them to
# a byte, as this did until 2026-09-19, let a loader reading a damaged
# DATA item poke a wrong byte and carry on, where the machine stops at
# the bad line.
function byteconv(x) {
    x = bfloor(x)
    if (x < -32768 || x > 32767) { raise(6); return -1 }
    if (x < 0 || x > 255) { raise(5); return -1 }
    return x
}

function addrconv(x) {
    x = bfloor(x)
    if (x < 0) x += 65536
    if (x < 0 || x > 65535) { raise(5); return -1 }
    return x
}

# Resolution order is a CONTRACT the Z80 core must reproduce byte-for-byte --
# it is written out in full in p75's "THE ADDRESS-RESOLUTION CONTRACT" (read
# side; poke_byte below has its own).  Keep the two in step; in particular SPK
# (rule 4) must stay ABOVE the program image (rule 5).
function dopeek(x,   a) {
    a = addrconv(x)
    if (E) return 0
    if (a >= 15360 && a <= 16383) return SCR[a - 15360]
    if (a >= 14336 && a <= 14591) return kb_matrix(a - 14336)
    # 37E8H-37E9H printer status: 63 = attached and ready, matching the
    # always-ready LPRINT host stream (corpus idiom: IF PEEK(14312)<>63
    # waits; =255 means no printer; >127 means busy).  POKEs land in MEM
    # but are never read back -- on hardware these regions are not RAM.
    if (a == 14312 || a == 14313) return 63
    # 40AA-40ACH: the ROM RND seed, live and POKEable (rnd_* in p90)
    if (a >= 16554 && a <= 16556) return rnd_peek(a - 16554)
    # live system pointers + the read-only tokenized program image (p75)
    if (a == 16548 || a == 16549 || a == 16561 || a == 16562 || a == 16633 || a == 16634)
        return pm_sysptr(a)
    if (a >= 16416 && a <= 16667 && (a in SVW)) return sv_peek(a)   # system variable window (p75)
    if (a in SPK) return sp_peek(a)               # VARPTR string space (p75)
    if (a >= 17129) {
        if (a > RAMTOP) return 255                # absent RAM above the physical top
        pm_sync(); pm_truncnote()
        # THE PROGRAM IMAGE IS WRITABLE (2026-09-12).  A byte the program (or a
        # USR routine) stored into the image range reads back -- image RAM is
        # RAM, as on the machine -- so a payload that keeps a buffer inside its
        # own loaded bytes works (the Dancing Demon's score/dance editor does
        # exactly this at 6B9BH).  Unwritten image addresses still read the
        # original tokenized byte.  RUN and LIST are unaffected: they work from
        # prog[] (the source text), never from PMEM, so a stray POKE here can
        # never corrupt the running program the way it would on hardware.
        if (a < PMEND) return (a in MEM) ? MEM[a] : PMEM[a]
    }
    return (a in MEM) ? MEM[a] : 255
}

# POKE a,b: the statement half parses; poke_byte() below is the store.
function st_poke(   v, a, b) {
    v = e_or(); if (E) return
    if (!isN(v)) { raise(13); return }
    a = addrconv(num(v)); if (E) return
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == ",")) { raise(2); return }
    CP++
    v = e_or(); if (E) return
    if (!isN(v)) { raise(13); return }
    b = byteconv(num(v)); if (E) return
    poke_byte(a, b)
}

# The ONE store primitive: a resolved 16-bit address and a byte 0-255.  Its
# order is CONTRACT, dopeek's twin -- a Z80 write from ../trs80_z80_core must
# land where a POKE of the same address lands.  Written out in full in p75's
# "THE ADDRESS-RESOLUTION CONTRACT, WRITE SIDE", including the four ranges
# where a write is stored but can never be read back.  Keep the two in step.
# Every writer that must agree with POKE comes through here: the POKE
# statement, the p77 shim applying a Z80 write-set, and the string-alias
# write-through (seam audit finding 7).  Marks the address dirty for the USR
# frame's delta tracking (p75 fr_*).
function poke_byte(a, b) {
    if (a >= 15360 && a <= 16383) { s_poke(a - 15360, b); sync_cursor() }
    else if (a >= 16554 && a <= 16556) rnd_poke(a - 16554, b)
    else if (a == 16561 || a == 16562) pm_sethimem(a, b)   # move HIMEM (p75)
    else if (a >= 16416 && a <= 16667 && (a in SVW)) sv_poke(a, b)   # system variable window (p75)
    else if (a in SPK) sp_poke(a, b)              # VARPTR write-through (p75)
    else if (a > RAMTOP) { }                      # absent RAM: discarded
    else {
        # a store into a STALE image would be judged by the next build as one
        # made before the program changed, and dropped: bring the image up to
        # date first, so the byte belongs to the line it lands in (p75 pm_build)
        if (PROGDIRTY && a >= 17129) pm_sync()
        MEM[a] = b; if (FRTRACK) FRDIRTY[a] = 1
        if (a >= 16414 && a <= 16423) dv_update()   # the device vectors (side effect only)
        if (a == 16445) WIDE = int(b / 8) % 2       # 403DH: the ROM's 32-column print flag (side effect only)
    }
}

# ---- THE ROM DEVICE VECTORS (2026-09-11) ------------------------------------
# 401E/401FH (16414/5) is the video driver vector and 4026/4027H (16422/3)
# the printer driver vector; the ROM's drivers live at 0458H and 058DH.
# Period listings swap them: POKE 16414,141:POKE 16415,5 sends everything
# PRINTed to the printer (14 corpus files, the "print the whole report"
# mode), POKE 16422,88:POKE 16423,4 sends LPRINT to the screen (2 files,
# "no printer attached"), POKE 16422,103:POKE 16423,0 points the printer
# at a ROM RET so LLIST/LPRINT go nowhere (tip 74).  The cells are plain
# MEM[] (read rule 6, write rule 6) with this one side effect on write.
# ONLY the two ROM addresses and the RET re-route: any other value is a
# custom machine-language driver (32 corpus files install one at 16422/3),
# which cannot run without the core, and the closest honest behaviour is
# the driver it usually wraps -- the default.  Both vectors swapped at once
# would make the ROM loop; here the printer-to-video route wins and the
# video stays on the screen.
function dv_update(   v, l) {
    v = MEM[16414] + 256 * MEM[16415]; l = MEM[16422] + 256 * MEM[16423]
    LPTOVID = (l == 1112); LPOFF = (l == 103)
    VIDTOLP = (v == 1421 && !LPTOVID)
    if (VIDTOLP && LPFILE == "" && !DVNOTED) {
        DVNOTED = 1
        diag_err("VIDEO ROUTED TO THE PRINTER (POKE 16414/16415); set TRS80_PRINTER to see it, or POKE 16414,88:POKE 16415,4")
    }
}

# ---- SET / RESET / POINT ---------------------------------------------------
function st_setreset(on,   v, x, y, col) {
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == "(")) { raise(2); return }
    CP++
    v = e_or(); if (E) return
    if (!isN(v)) { raise(13); return }
    x = bfloor(num(v))
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == ",")) { raise(2); return }
    CP++
    v = e_or(); if (E) return
    if (!isN(v)) { raise(13); return }
    y = bfloor(num(v))
    col = -1                                # -1 = no color given (textbook)
    if (on && TY[CK, CP] == "o" && TK[CK, CP] == ",") {
        # EXT: SET(x,y,c) -- optional CoCo-style color 0-8.  Valid Level II
        # never writes a third argument, so period programs are unaffected;
        # RESET stays strictly two-argument.
        CP++
        v = e_or(); if (E) return
        if (!isN(v)) { raise(13); return }
        col = bfloor(num(v))
        if (col < 0 || col > 8) { raise(5); return }
    }
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == ")")) { raise(2); return }
    CP++
    if (x < 0 || x > 127 || y < 0 || y > 47) { raise(5); return }
    if (on) gset(x, y, col); else greset(x, y)
    sync_cursor()
}

function gcell(x, y) { return int(y / 3) * 64 + int(x / 2) }
function gbit(x, y) { return 2 ^ ((x % 2) + 2 * (y % 3)) }

function gset(x, y, col,   p, b) {
    p = gcell(x, y); b = SCR[p]
    if (b < 128 || b > 191) b = 128
    b = 128 + or(b - 128, gbit(x, y))
    # EXT: color is per character cell, last SET wins; a plain SET returns
    # the cell to default (B&W).  POINT is unaffected either way.
    if (col >= 0) CCOL[p] = col; else delete CCOL[p]
    s_poke(p, b)
}

function greset(x, y,   p, b) {
    p = gcell(x, y); b = SCR[p]
    if (b < 128 || b > 191) { s_poke(p, 128); return }
    b = 128 + and(b - 128, 63 - gbit(x, y))
    s_poke(p, b)
}

function gpoint(x, y,   p, b) {
    if (x < 0 || x > 127 || y < 0 || y > 47) { raise(5); return 0 }
    p = gcell(x, y); b = SCR[p]
    if (b < 128 || b > 191) return 0
    return and(b - 128, gbit(x, y)) ? -1 : 0
}

# ---- CMD -------------------------------------------------------------------
# CMD calls a TRSDOS service.  A cassette Level II machine has no DOS to call,
# so every form raises ?SN exactly as it always has -- except the one Model III
# TRSDOS 1.3 easter egg, CMD"&"&, which printed a hidden message from the
# people who wrote that DOS.  Ours says who wrote this one.
# EXT.  Safe as an always-on extension: the trigger is the literal three-token
# sequence CMD "&" & , which no Level II program can execute (CMD always
# errored on a cassette machine) and no OCR damage can plausibly spell.
# Dispatch (execstmt, p70) only routes here when a string LITERAL follows CMD,
# so `CMD A$` and CMD-as-a-variable-name keep the behavior they had.
function st_cmd(   s) {
    s = TK[CK, CP]; CP++                    # the string literal after CMD
    if (s != "&" || TY[CK, CP] != "o" || TK[CK, CP] != "&") { raise(2); return }
    CP++
    if (!at_stmt_end()) { raise(2); return }
    s_puts(egg_text()); s_nl()
}

# The message is not stored in the clear: it is xor-folded, byte by byte,
# against the incantation that summons it, so a passing eye -- or a grep over
# the source -- does not spoil the surprise.  Gentle, not secret; anyone who
# reads this function can unfold it, and that is the intended level of effort.
function egg_text(   h, k, i, n, s) {
    h = "17050D75630F05750A0E646F106D0A69176D07691314166F" \
        "04051063076D067F630905700A0964600C1F066F10616414" \
        "737F72"
    k = "CMD&"
    n = length(h) / 2
    for (i = 1; i <= n; i++)
        s = s CHR[xor(strtonum("0x" substr(h, i + i - 1, 2)), \
                      ORD[substr(k, (i - 1) % length(k) + 1, 1)])]
    return s
}
# ===================== Disk BASIC file I/O ==================================
# Channels 1..15; the BASIC filename is a literal host path (same simulation
# as CLOAD/CSAVE).  Sequential files are plain text lines via gawk's named
# getline/print streams.  Random files are slurped into memory at OPEN "R",
# GET/PUT operate in memory, and CLOSE rewrites the file one record per line
# (non-printable bytes escaped as \xNN so MK*$-packed fields survive).
#
# State (per channel n):
#   FH_MODE[n]  "I"/"O"/"E"/"R" ("" = closed)   FH_NAME[n]  host path
#   FH_LOC[n]   lines read/written (seq) or last record touched (R)
#   FH_PEND[n]/FH_PENDHAS[n]   unconsumed input line (INPUT# item stepping)
#   FH_EOF[n]   input stream exhausted
#   FH_OPEND[n]/FH_OPENDHAS[n] partial output line (PRINT# ended in ; or ,)
#   FH_RLEN[n]/FH_BUF[n]/FH_NREC[n]/FH_REC[n,r]/FH_DIRTY[n]  random access
# Field maps: FLDN[n], FLD_V/O/W[n,i] (channel order) and FVCH/FVOF/FVW[tgt]
# (per-variable; a re-FIELD of a variable moves it, last fielding wins).
# A variable is named here by its TARGET, p75's form: "V" name for a simple
# variable, "A" key for an array element -- the Disk manual's own example
# is FIELD 1,16 AS CLIENT$(1) (the 2026-09-19 audit, M-29).  Membership is
# always asked with `in`: a bare FVCH[tgt] creates the key, and a created
# key made LSET on a variable fielded away raise ?NO.
function fld_tgt(name, key) { return (key != "") ? "A" key : "V" name }

function fio_isopen(n) { return FH_MODE[n] != "" }

# parse [#] numexpr as a channel number; raise 24 (BN) outside 1..15
function fio_chan(withhash,   v, n) {
    if (withhash && TY[CK, CP] == "o" && TK[CK, CP] == "#") CP++
    v = e_or(); if (E) return 0
    if (!isN(v)) { raise(13); return 0 }
    n = bfloor(num(v))
    if (n < 1 || n > 15) { raise(24); return 0 }
    return n
}

# channel argument of EOF/LOF/LOC: validated + must be open
function fio_fnchan(x,   n) {
    n = bfloor(x)
    if (n < 1 || n > 15) { raise(24); return 0 }
    if (!fio_isopen(n)) { raise(25); return 0 }
    return n
}

function fio_pad(s, k) { return substr(s sprintf("%" k "s", ""), 1, k) }

# ---- OPEN / CLOSE / KILL ---------------------------------------------------
function st_open(   v, mode, n, f, rlen, r, l, i, cnt) {
    v = e_or(); if (E) return
    if (isN(v)) { raise(13); return }
    mode = toupper(substr(vstr(v), 1, 1))
    if (mode != "I" && mode != "O" && mode != "E" && mode != "R") { raise(28); return }
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == ",")) { raise(2); return }
    CP++
    n = fio_chan(1); if (E) return
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == ",")) { raise(2); return }
    CP++
    v = e_or(); if (E) return
    if (isN(v)) { raise(13); return }
    f = vstr(v)
    if (f == "") { raise(21); return }
    rlen = 256
    if (TY[CK, CP] == "o" && TK[CK, CP] == ",") {
        CP++
        v = e_or(); if (E) return
        if (!isN(v)) { raise(13); return }
        rlen = bfloor(num(v))
        if (rlen < 1 || rlen > 256) { raise(5); return }
    }
    if (fio_isopen(n)) { raise(26); return }
    for (i = 1; i <= 15; i++)
        if (fio_isopen(i) && FH_NAME[i] == f) { raise(26); return }
    if (toupper(f) ~ /^OLLAMA(:|$)/) { ai_open(n, f); return }
    if (host_special(f)) { raise(22); return }    # /inet/..., /dev/..., "-": not files (p90)
    if (mode != "I") {
        # probe writability now: a failed awk redirect later would be fatal
        if ((!WINNATIVE && f ~ /'/) || !host_writable(f)) { raise(22); return }
    }
    FH_LOC[n] = 0; FH_EOF[n] = 0
    FH_PEND[n] = ""; FH_PENDHAS[n] = 0
    FH_OPEND[n] = ""; FH_OPENDHAS[n] = 0
    if (mode == "I") {
        r = (getline l < f)
        if (r < 0) { raise(29); return }
        if (r > 0) { sub(/\r$/, "", l); FH_PEND[n] = l; FH_PENDHAS[n] = 1; FH_LOC[n] = 1 }
        else FH_EOF[n] = 1
    } else if (mode == "O") printf "" > f
    else if (mode == "E") printf "" >> f
    else {                                  # "R": slurp records into memory
        cnt = 0
        while ((getline l < f) > 0) { cnt++; FH_REC[n, cnt] = fio_pad(fio_unesc(l), rlen) }
        close(f)
        FH_NREC[n] = cnt
        FH_RLEN[n] = rlen
        FH_BUF[n] = fio_pad("", rlen)
        FH_DIRTY[n] = 0
    }
    FH_NAME[n] = f
    FH_MODE[n] = mode
}

function st_close(   n, ty, tx) {
    ty = TY[CK, CP]; tx = TK[CK, CP]
    if (ty == "" || ty == "e" || (ty == "o" && tx == ":") || (ty == "i" && tx == "ELSE")) {
        fio_closeall()
        return
    }
    for (;;) {
        n = fio_chan(1); if (E) return
        fio_close1(n)
        if (TY[CK, CP] == "o" && TK[CK, CP] == ",") { CP++; continue }
        break
    }
}

# closing an unopened channel is a silent no-op (Disk BASIC is forgiving)
function fio_close1(n,   f, r) {
    if (!fio_isopen(n)) return
    f = FH_NAME[n]
    if (FH_MODE[n] == "O" || FH_MODE[n] == "E") {
        if (FH_OPENDHAS[n]) print FH_OPEND[n] >> f
        close(f)
    } else if (FH_MODE[n] == "I") close(f)
    else if (FH_MODE[n] == "R") {
        # only a PUT makes the file worth writing: a file opened to GET from
        # is left byte for byte as it was (the rewrite re-pads every record
        # to this OPEN's length and re-escapes it)
        if (FH_DIRTY[n]) fio_flushR(n)
    }
    else ai_close(n)                        # "A": unsent prompt is discarded
    for (r = 1; r <= FH_NREC[n]; r++) delete FH_REC[n, r]
    for (r = 1; r <= FLDN[n]; r++) {
        if ((FLD_V[n, r] in FVCH) && FVCH[FLD_V[n, r]] == n) {
            delete FVCH[FLD_V[n, r]]; delete FVOF[FLD_V[n, r]]; delete FVW[FLD_V[n, r]]
        }
        delete FLD_V[n, r]; delete FLD_O[n, r]; delete FLD_W[n, r]
    }
    delete FLDN[n]
    delete FH_MODE[n]; delete FH_NAME[n]; delete FH_LOC[n]
    delete FH_PEND[n]; delete FH_PENDHAS[n]; delete FH_EOF[n]
    delete FH_OPEND[n]; delete FH_OPENDHAS[n]
    delete FH_RLEN[n]; delete FH_BUF[n]; delete FH_NREC[n]; delete FH_DIRTY[n]
}

function fio_flushR(n,   f, r) {
    f = FH_NAME[n]
    printf "" > f
    for (r = 1; r <= FH_NREC[n]; r++) print fio_esc(FH_REC[n, r]) >> f
    close(f)
}

function fio_closeall(   i) {
    for (i = 1; i <= 15; i++) fio_close1(i)
}

function st_kill(   v, f, i) {
    v = e_or(); if (E) return
    if (isN(v)) { raise(13); return }
    f = vstr(v)
    if (f == "") { raise(21); return }
    for (i = 1; i <= 15; i++)
        if (fio_isopen(i) && FH_NAME[i] == f) { raise(26); return }
    if (!WINNATIVE && f ~ /'/) { raise(22); return }
    if (!host_exists(f)) { raise(29); return }
    host_delete(f)
}

# ---- sequential input ------------------------------------------------------
# ensure FH_PEND holds a line; 0 at end of file
function fio_fill(n,   r, l) {
    if (FH_MODE[n] == "A") return ai_fill(n)
    if (FH_PENDHAS[n]) return 1
    if (FH_EOF[n]) return 0
    r = (getline l < FH_NAME[n])
    if (r <= 0) { FH_EOF[n] = 1; return 0 }
    sub(/\r$/, "", l)
    FH_PEND[n] = l; FH_PENDHAS[n] = 1; FH_LOC[n]++
    return 1
}

# extract one item (quotes respected) into FIO_IT, leaving the unconsumed
# remainder pending so one line can feed several INPUT#s.  A string item
# ends at a comma or the end of the line; a NUMERIC item (isnum) ends at a
# blank as well, and the blanks after it and one comma go with the
# terminator (Disk manual, INPUT#: the image " 1.234 -33 27" read by
# INPUT#1,A,B,C gives 1.234, -33 and 27) -- which is what lets the
# manual's own PRINT#1,A;B;C be read back.
function fio_next_item(n, isnum,   l, i, len, j, c, item) {
    if (!fio_fill(n)) return 0
    l = FH_PEND[n]
    i = 1; len = length(l)
    while (i <= len && substr(l, i, 1) == " ") i++
    if (i <= len && substr(l, i, 1) == "\"") {
        j = index(substr(l, i + 1), "\"")
        if (j == 0) { item = substr(l, i + 1); i = len + 1 }
        else { item = substr(l, i + 1, j - 1); i = i + j + 1 }
        while (i <= len && substr(l, i, 1) == " ") i++
    } else if (isnum) {
        j = i
        while (j <= len && (c = substr(l, j, 1)) != "," && c != " ") j++
        item = substr(l, i, j - i)
        i = j
        while (i <= len && substr(l, i, 1) == " ") i++
    } else {
        j = i
        while (j <= len && substr(l, j, 1) != ",") j++
        item = substr(l, i, j - i)
        sub(/ +$/, "", item)
        i = j
    }
    if (i <= len && substr(l, i, 1) == ",") i++
    if (i > len) FH_PENDHAS[n] = 0
    else FH_PEND[n] = substr(l, i)
    FIO_IT = item
    return 1
}

function st_input_file(   n, nlv, name, key, i, x) {
    n = fio_chan(0); if (E) return
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == ",")) { raise(2); return }
    CP++
    if (!fio_isopen(n)) { raise(25); return }
    if (FH_MODE[n] != "I" && FH_MODE[n] != "A") { raise(28); return }
    # each target is resolved when its item is stored, after the
    # assignments before it (INPUT#1,I,A(I)), as INPUT and READ do
    for (;;) {
        if (TY[CK, CP] != "i") { raise(2); return }
        name = TK[CK, CP]; CP++
        key = ""
        if (TY[CK, CP] == "o" && TK[CK, CP] == "(") { key = aref(name); if (E) return }
        if (!fio_next_item(n, !strname(name))) { raise(27); return }
        if (strname(name)) assignv(name, key, "S" FIO_IT)
        else {
            # the item is evaluated "by a routine just like the BASIC VAL
            # function" (Disk manual, INPUT#): A12 is 0, 5X is 5, never ?TM
            x = valnum(FIO_IT); if (E) return       # ?OV: nothing stored
            assignv(name, key, "N" x)
        }
        if (E) return
        if (TY[CK, CP] == "o" && TK[CK, CP] == ",") { CP++; continue }
        break
    }
}

# LINE INPUT [#n,] -- whole-line read, no comma splitting, no "? " prompt
function st_lineinput(   n, name, key, prompt, line, x) {
    if (!(TY[CK, CP] == "i" && TK[CK, CP] == "INPUT")) { raise(2); return }
    CP++
    if (TY[CK, CP] == "o" && TK[CK, CP] == "#") {
        CP++
        n = fio_chan(0); if (E) return
        if (!(TY[CK, CP] == "o" && TK[CK, CP] == ",")) { raise(2); return }
        CP++
        if (!fio_isopen(n)) { raise(25); return }
        if (FH_MODE[n] != "I" && FH_MODE[n] != "A") { raise(28); return }
        if (TY[CK, CP] != "i") { raise(2); return }
        name = TK[CK, CP]; CP++
        if (!strname(name)) { raise(13); return }
        key = ""
        if (TY[CK, CP] == "o" && TK[CK, CP] == "(") { key = aref(name); if (E) return }
        if (!fio_fill(n)) { raise(27); return }
        assignv(name, key, "S" FH_PEND[n])
        FH_PENDHAS[n] = 0
        return
    }
    if (CK == "I") { raise(12); return }
    prompt = ""
    if (TY[CK, CP] == "s") {
        if (TY[CK, CP + 1] == "o" && TK[CK, CP + 1] == ";") {
            prompt = TK[CK, CP]; CP++
        } else {
            # prompt expression, same as st_input
            x = e_or(); if (E) return
            if (substr(x, 1, 1) != "S") { raise(13); return }
            prompt = substr(x, 2)
        }
        if (TY[CK, CP] == "o" && TK[CK, CP] == ";") CP++
        else { raise(2); return }
    }
    if (TY[CK, CP] != "i") { raise(2); return }
    name = TK[CK, CP]; CP++
    if (!strname(name)) { raise(13); return }
    key = ""
    if (TY[CK, CP] == "o" && TK[CK, CP] == "(") { key = aref(name); if (E) return }
    if (prompt != "") s_puts(prompt)
    line = rl_read()
    if (RLCANCEL) { dobreak(); return }
    if (EOFQUIT) { if (BATCH) batch_ineof(); STOPPED = 1; return }
    assignv(name, key, "S" line)
}

# ---- sequential output -----------------------------------------------------
# PRINT #n, ... : "a disk image similar to what a PRINT to display creates
# on the screen" (Model III Disk manual, PRINT#).  ; joins; , writes blanks
# up to the next 16-column zone of the FILE's line, the manual's own case:
# PRINT#1,A,B with A=2300 "causes 10 extra spaces in the disk file".  The
# ROM's comma code leaves through the Disk BASIC exit at 41D3H (2108H), so
# the column is the file's, not the screen's.  The manual names no last
# zone for a file, so none is assumed: no carriage return is ever written
# for a comma.  A trailing separator holds the partial line in FH_OPEND
# until the next PRINT# or CLOSE.
function fio_col(s) {                       # the column the file's line is at
    if (match(s, /.*[\r\n]/)) return length(s) - RLENGTH
    return length(s)
}

function st_print_file(   n, s, sep, ty, tx, v, x) {
    n = fio_chan(0); if (E) return
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == ",")) { raise(2); return }
    CP++
    if (!fio_isopen(n)) { raise(25); return }
    if (FH_MODE[n] != "O" && FH_MODE[n] != "E" && FH_MODE[n] != "A") { raise(28); return }
    s = FH_OPENDHAS[n] ? FH_OPEND[n] : ""
    if (TY[CK, CP] == "i" && TK[CK, CP] == "USING") { CP++; fio_pr_using(n, s); return }
    sep = 0
    for (;;) {
        ty = TY[CK, CP]
        if (ty == "" || ty == "e") break
        tx = TK[CK, CP]
        if (ty == "o" && tx == ":") break
        if (ty == "i" && tx == "ELSE") break
        if (ty == "i" && tx == "USING") { CP++; fio_pr_using(n, s); return }
        if (ty == "o" && tx == ";") { sep = 1; CP++; continue }
        if (ty == "o" && tx == ",") {
            s = s substr("                ", 1, 16 - (fio_col(s) % 16))
            sep = 1; CP++
            continue
        }
        if (ty == "i" && tx == "TAB") {
            CP++
            if (!(TY[CK, CP] == "o" && TK[CK, CP] == "(")) { raise(2); return }
            CP++
            v = e_or(); if (E) return
            if (!isN(v)) { raise(13); return }
            x = bfloor(num(v))
            if (TY[CK, CP] == "o" && TK[CK, CP] == ")") CP++
            else { raise(2); return }
            while (length(s) < x) s = s " "
            sep = 1
            continue
        }
        v = e_or(); if (E) return
        s = s (isN(v) ? fmtnum(num(v)) : vstr(v))
        sep = 0
    }
    fio_pr_out(n, s, sep)
}

# PRINT# USING tail -- the file twin of pr_using(), same any-position rule;
# `s` carries whatever the item list built before USING took over.
function fio_pr_using(n, s,   sep, ty, tx, v, fmt) {
    v = e_or(); if (E) return
    if (isN(v)) { raise(13); return }
    fmt = vstr(v)
    if (TY[CK, CP] == "o" && (TK[CK, CP] == ";" || TK[CK, CP] == ",")) CP++
    else { raise(2); return }
    sep = 0; PUN = 0
    for (;;) {                              # , and ; are pure separators here
        ty = TY[CK, CP]
        if (ty == "" || ty == "e") break
        tx = TK[CK, CP]
        if (ty == "o" && tx == ":") break
        if (ty == "i" && tx == "ELSE") break
        if (ty == "o" && (tx == ";" || tx == ",")) { sep = 1; CP++; continue }
        v = e_or(); if (E) return
        PUV[++PUN] = v
        sep = 0
    }
    v = pu_output(fmt, PUN); if (E) return
    fio_pr_out(n, s v, sep)
}

# finish a PRINT# statement: hold the partial line on a trailing separator,
# else emit it (OLLAMA prompt buffer for mode "A", the file otherwise)
function fio_pr_out(n, s, sep) {
    if (sep) { FH_OPEND[n] = s; FH_OPENDHAS[n] = 1 }
    else if (FH_MODE[n] == "A") {           # completed prompt line, not sent yet
        AI_PROMPT[n] = AI_PROMPT[n] s "\n"
        FH_OPEND[n] = ""; FH_OPENDHAS[n] = 0
    }
    else {
        print s >> FH_NAME[n]
        FH_OPEND[n] = ""; FH_OPENDHAS[n] = 0
        FH_LOC[n]++
    }
}

# ---- random access ---------------------------------------------------------
function st_field(   n, off, w, v, name, key, tgt, i, found) {
    n = fio_chan(1); if (E) return
    if (!fio_isopen(n)) { raise(25); return }
    if (FH_MODE[n] != "R") { raise(28); return }
    off = 0
    for (;;) {
        if (!(TY[CK, CP] == "o" && TK[CK, CP] == ",")) { raise(2); return }
        CP++
        v = e_or(); if (E) return
        if (!isN(v)) { raise(13); return }
        w = bfloor(num(v))
        if (w < 0) { raise(5); return }
        if (!(TY[CK, CP] == "i" && TK[CK, CP] == "AS")) { raise(2); return }
        CP++
        if (TY[CK, CP] != "i") { raise(2); return }
        name = TK[CK, CP]; CP++
        key = ""
        if (TY[CK, CP] == "o" && TK[CK, CP] == "(") { key = aref(name); if (E) return }
        if (!strname(name)) { raise(13); return }
        if (off + w > FH_RLEN[n]) { raise(31); return }
        tgt = fld_tgt(name, key)
        found = 0
        for (i = 1; i <= FLDN[n]; i++)
            if (FLD_V[n, i] == tgt) { found = i; break }
        if (!found) { FLDN[n]++; found = FLDN[n]; FLD_V[n, found] = tgt }
        FLD_O[n, found] = off; FLD_W[n, found] = w
        FVCH[tgt] = n; FVOF[tgt] = off; FVW[tgt] = w
        sp_sets(tgt, substr(FH_BUF[n], off + 1, w))
        off += w
        if (!(TY[CK, CP] == "o" && TK[CK, CP] == ",")) break
    }
}

# refresh fielded vars from the channel buffer (skip vars re-FIELDed away)
function fld_sync(n,   i, v) {
    for (i = 1; i <= FLDN[n]; i++) {
        v = FLD_V[n, i]
        if ((v in FVCH) && FVCH[v] == n) sp_sets(v, substr(FH_BUF[n], FLD_O[n, i] + 1, FLD_W[n, i]))
    }
}

# is tgt a FIELD variable that s (a whole new value) fits?
function fld_is(tgt, s) {
    return (tgt in FVCH) && length(s) == FVW[tgt]
}

# store s, FVW[name] long, as a FIELD variable's slice of its record buffer.
# Every in-place string store reaches the buffer through here: LSET, RSET
# and MID$= (which wrote the variable only, so PUT wrote the old record:
# the 2026-09-19 audit, M-25).
function fld_put(tgt, s,   n) {
    n = FVCH[tgt]
    FH_BUF[n] = substr(FH_BUF[n], 1, FVOF[tgt]) s substr(FH_BUF[n], FVOF[tgt] + FVW[tgt] + 1)
    fld_sync(n)
}

function fio_just(s, w, left) {
    if (length(s) >= w) return substr(s, 1, w)
    if (left) return s fio_pad("", w - length(s))
    return fio_pad("", w - length(s)) s
}

# LSET (left=1) / RSET (left=0): justify into a fielded var's buffer slice;
# on a non-fielded string var, justify within its current length
function st_lset(left,   name, key, v, s, tgt, cur) {
    if (TY[CK, CP] != "i") { raise(2); return }
    name = TK[CK, CP]; CP++
    key = ""
    if (TY[CK, CP] == "o" && TK[CK, CP] == "(") { key = aref(name); if (E) return }
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == "=")) { raise(2); return }
    CP++
    v = e_or(); if (E) return
    if (!strname(name) || isN(v)) { raise(13); return }
    s = vstr(v)
    tgt = fld_tgt(name, key)
    if (tgt in FVCH) {
        fld_put(tgt, fio_just(s, FVW[tgt], left))
        return
    }
    cur = al_cur(name, key); if (E) return
    s = fio_just(s, length(cur), left)
    al_setinplace(name, key, s)                   # in place (p75 finding 7)
}

function st_get(   n, rec, v) {
    n = fio_chan(1); if (E) return
    if (!fio_isopen(n)) { raise(25); return }
    if (FH_MODE[n] != "R") { raise(28); return }
    rec = FH_LOC[n] + 1
    if (TY[CK, CP] == "o" && TK[CK, CP] == ",") {
        CP++
        v = e_or(); if (E) return
        if (!isN(v)) { raise(13); return }
        rec = bfloor(num(v))
    }
    if (rec < 1 || rec > 65535) { raise(30); return }
    # past the last record: "BASIC simply fills the buffer with hexadecimal
    # zeros, and no error is generated" (Disk manual, GET and LOF; the error
    # it speaks of is for variable-length records, which are not served).
    # This was ?IE while `man GET` promised spaces (the 2026-09-19 audit,
    # M-27).  EOF(n) is true afterwards, and LOF(n) is the test beforehand.
    if (rec > FH_NREC[n]) { FH_BUF[n] = ""; while (length(FH_BUF[n]) < FH_RLEN[n]) FH_BUF[n] = FH_BUF[n] CHR[0] }
    else FH_BUF[n] = fio_pad(FH_REC[n, rec], FH_RLEN[n])
    FH_LOC[n] = rec
    fld_sync(n)
}

function st_put(   n, rec, v, r) {
    n = fio_chan(1); if (E) return
    if (!fio_isopen(n)) { raise(25); return }
    if (FH_MODE[n] != "R") { raise(28); return }
    rec = FH_LOC[n] + 1
    if (TY[CK, CP] == "o" && TK[CK, CP] == ",") {
        CP++
        v = e_or(); if (E) return
        if (!isN(v)) { raise(13); return }
        rec = bfloor(num(v))
    }
    if (rec < 1 || rec > 65535) { raise(30); return }
    if (rec > FH_NREC[n]) {
        for (r = FH_NREC[n] + 1; r < rec; r++) FH_REC[n, r] = fio_pad("", FH_RLEN[n])
        FH_NREC[n] = rec
    }
    FH_REC[n, rec] = FH_BUF[n]
    FH_LOC[n] = rec
    FH_DIRTY[n] = 1
}

# ---- record serialization: one escaped line per record ---------------------
function fio_esc(s,   out, i, n, c, o) {
    out = ""; n = length(s)
    for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (c == "\\") { out = out "\\\\"; continue }
        o = (c in ORD) ? ORD[c] : 63
        if (o < 32 || o > 126) out = out sprintf("\\x%02X", o)
        else out = out c
    }
    return out
}

function fio_unesc(s,   out, i, n, c) {
    out = ""; i = 1; n = length(s)
    while (i <= n) {
        c = substr(s, i, 1)
        if (c == "\\" && i < n) {
            if (substr(s, i + 1, 1) == "\\") { out = out "\\"; i += 2; continue }
            if (substr(s, i + 1, 1) == "x" && i + 3 <= n) {
                out = out CHR[strtonum("0x" substr(s, i + 2, 2))]
                i += 4
                continue
            }
        }
        out = out c; i++
    }
    return out
}

# ---- MKI$/MKS$/MKD$ / CVI/CVS/CVD: Microsoft Binary Format -----------------
# 2-byte int, 4-byte single, 8-byte double, little-endian; float layout is
# mantissa LSB..MSB (sign replaces the implied leading 1 bit), exponent+128
function fio_mki(x,   v, u) {
    v = to16(x); if (E) return ""             # rounds DOWN, as CINT does
    u = (v < 0) ? v + 65536 : v
    return CHR[u % 256] CHR[int(u / 256)]
}

function fio_cvi(s,   u) {
    if (length(s) < 2) { raise(5); return 0 }
    u = ORD[substr(s, 1, 1)] + 256 * ORD[substr(s, 2, 1)]
    return (u >= 32768) ? u - 65536 : u
}

function fio_mkf(x, nb,   sgn, e, i, b, out) {
    if (x == 0) {
        out = ""
        for (i = 1; i <= nb; i++) out = out CHR[0]
        return out
    }
    sgn = 0
    if (x < 0) { sgn = 128; x = -x }
    if (x > 1.7e38) { raise(6); return "" }     # an infinity would never leave the loop
    e = 0
    while (x >= 1) { x /= 2; e++ }
    while (x < 0.5) { x *= 2; e-- }
    e += 128
    if (e > 255) { raise(6); return "" }
    if (e < 1) {                            # underflow -> zero
        out = ""
        for (i = 1; i <= nb; i++) out = out CHR[0]
        return out
    }
    for (i = 1; i <= nb - 1; i++) { x *= 256; b = int(x); x -= b; FIO_MB[i] = b }
    FIO_MB[1] = FIO_MB[1] - 128 + sgn       # implied leading 1 -> sign bit
    out = ""
    for (i = nb - 1; i >= 1; i--) out = out CHR[FIO_MB[i]]
    return out CHR[e]
}

function fio_cvf(s, nb,   e, sgn, m, i, dv, b) {
    if (length(s) < nb) { raise(5); return 0 }
    e = ORD[substr(s, nb, 1)]
    if (e == 0) return 0
    b = ORD[substr(s, nb - 1, 1)]
    sgn = (b >= 128) ? -1 : 1
    m = (b % 128 + 128) / 256               # restore implied leading 1
    dv = 65536
    for (i = nb - 2; i >= 1; i--) { m += ORD[substr(s, i, 1)] / dv; dv *= 256 }
    return sgn * m * 2 ^ (e - 128)
}
# ===================== OLLAMA device channel ================================
# OPEN mode$, [#]n, "OLLAMA[:model[:thread]]" turns channel n into a
# bidirectional link (internal mode "A") to a local Ollama server: PRINT#
# accumulates a prompt; the first INPUT#/LINE INPUT# sends it (blocking,
# full conversation history each call -- /api/chat is stateless) and the
# reply becomes pending input, read line by line.  EOF(n) = -1 once the
# reply is consumed; it never triggers a send.
#
# Named threads append every message to "<thread>.ollama" (one line per
# message: role char + space + fio_esc'd content) and reload it as context
# on OPEN.  KILL "<thread>.ollama" deletes a conversation.
#
# Env: TRS80_OLLAMA_MODEL (default model), TRS80_OLLAMA_HOST (default
# localhost:11434), TRS80_OLLAMA_TIMEOUT (seconds, default 300),
# TRS80_OLLAMA_THINK (0/1: send "think":false/true; unset = omit),
# TRS80_OLLAMA_KEEPALIVE (e.g. 30m: sent as keep_alive; unset = omit),
# TRS80_OLLAMA_CURL (test hook: replaces the whole curl command; the JSON
# request body file path is appended as the last argument).
#
# DIRECTIVES (added 2026-08-21 for structured replies).  A completed
# prompt line whose first character is "@" is an instruction to the
# channel, consumed at send time and never sent to the model:
#   @TOKENS A,B,C   this send only: ask Ollama for structured output
#                   (request "format" = a JSON schema {token: enum of
#                   the list, reply: string}); the reply is delivered
#                   as line 1 = the token, following lines = the reply.
#                   Constrained decoding means the token can only be
#                   one of the list.  If the model's JSON cannot be
#                   unpacked the raw content is delivered instead.
#   @THINK 0|1      sticky for the channel: "think":false/true in every
#                   request (thinking models otherwise spend seconds
#                   on hidden reasoning before a one-line answer).
#   @KEEPALIVE 30m  sticky: "keep_alive" in every request, so a game
#                   can hold its model resident across a session.
#   @@text          a literal prompt line beginning with "@".
# Unknown directives raise ?FC.  Directives are not logged to threads.
#
# State (per channel n): AI_MODEL[n], AI_TFILE[n] (transcript path or ""),
# AI_NMSG[n]/AI_ROLE[n,i]/AI_MSG[n,i] (history, roles "u"/"a"),
# AI_PROMPT[n] (accumulated unsent prompt), AI_REPLY[n]+AI_RHAS[n]
# (unread reply text).  FH_MODE[n]="A"; FH_NAME[n] = the OPEN string.

# name parse: OLLAMA | OLLAMA:model | OLLAMA:model:thread (last part is the
# thread; middle parts rejoin so tagged models like mistral:7b work --
# a tagged model with no thread needs a trailing colon: "OLLAMA:mistral:7b:")
function ai_open(n, f,   np, parts, model, thread, i, tf, l, role) {
    np = split(f, parts, ":")
    model = ""; thread = ""
    if (np == 2) model = parts[2]
    else if (np >= 3) {
        thread = parts[np]
        model = parts[2]
        for (i = 3; i < np; i++) model = model ":" parts[i]
    }
    if (model == "") model = ENVIRON["TRS80_OLLAMA_MODEL"]
    if (model == "") { raise(21); return }
    # the transcript is appended to after every exchange (ai_log), and a
    # failed awk redirect is fatal: probe it now, before any channel state
    # (a directory or read-only <thread>.ollama killed gawk -- the 2026-09-19 audit, C-1)
    if (thread != "" && !host_writable(thread ".ollama")) { raise(22); return }
    FH_LOC[n] = 0; FH_EOF[n] = 0
    FH_PEND[n] = ""; FH_PENDHAS[n] = 0
    FH_OPEND[n] = ""; FH_OPENDHAS[n] = 0
    AI_MODEL[n] = model
    AI_TFILE[n] = ""
    AI_NMSG[n] = 0
    AI_PROMPT[n] = ""; AI_REPLY[n] = ""; AI_RHAS[n] = 0
    AI_THINK[n] = ENVIRON["TRS80_OLLAMA_THINK"]
    AI_KEEP[n] = ENVIRON["TRS80_OLLAMA_KEEPALIVE"]
    AI_TOKENS[n] = ""
    if (thread != "") {
        tf = thread ".ollama"
        AI_TFILE[n] = tf
        while ((getline l < tf) > 0) {
            role = substr(l, 1, 1)
            if (role == "u" || role == "a") {
                AI_NMSG[n]++
                AI_ROLE[n, AI_NMSG[n]] = role
                AI_MSG[n, AI_NMSG[n]] = fio_unesc(substr(l, 3))
            }
        }
        close(tf)
    }
    FH_NAME[n] = f
    FH_MODE[n] = "A"
}

function ai_close(n,   i) {
    for (i = 1; i <= AI_NMSG[n]; i++) { delete AI_ROLE[n, i]; delete AI_MSG[n, i] }
    delete AI_MODEL[n]; delete AI_TFILE[n]; delete AI_NMSG[n]
    delete AI_PROMPT[n]; delete AI_REPLY[n]; delete AI_RHAS[n]
    delete AI_THINK[n]; delete AI_KEEP[n]; delete AI_TOKENS[n]
}

# strip "@" directive lines out of the assembled prompt, applying them;
# returns the prompt that remains.  "@@x" -> literal "@x".
function ai_directives(n, prompt,   nl, lines, i, l, out, kw, arg, sp) {
    out = ""
    nl = split(prompt, lines, "\n")
    for (i = 1; i <= nl; i++) {
        l = lines[i]
        if (substr(l, 1, 2) == "@@") { out = out substr(l, 2) "\n"; continue }
        if (substr(l, 1, 1) != "@") { out = out l "\n"; continue }
        sp = index(l, " ")
        if (sp) { kw = toupper(substr(l, 2, sp - 2)); arg = substr(l, sp + 1) }
        else { kw = toupper(substr(l, 2)); arg = "" }
        gsub(/^ +| +$/, "", arg)
        if (kw == "TOKENS") { gsub(/ /, "", arg); AI_TOKENS[n] = arg }
        else if (kw == "THINK") AI_THINK[n] = arg
        else if (kw == "KEEPALIVE") AI_KEEP[n] = arg
        else { raise(5); return "" }        # ?FC: unknown directive
    }
    sub(/\n$/, "", out)
    return out
}

# the fixed structured-output schema for @TOKENS
function ai_schema(list,   n, t, i, e) {
    n = split(list, t, ",")
    e = ""
    for (i = 1; i <= n; i++) {
        if (t[i] == "") continue
        e = e (e == "" ? "" : ",") "\"" ai_jesc(t[i]) "\""
    }
    return "{\"type\":\"object\",\"properties\":{\"token\":{\"type\":\"string\",\"enum\":[" e "]}," \
           "\"reply\":{\"type\":\"string\"}},\"required\":[\"token\",\"reply\"]}"
}

# value of string key k in a flat JSON object text, unescaped; "" + found=0 if absent
function ai_jstr(json, k,   p, i, len, c, out) {
    AI_JFOUND = 0
    p = index(json, "\"" k "\"")
    if (p == 0) return ""
    i = p + length(k) + 2
    len = length(json)
    while (i <= len && substr(json, i, 1) ~ /[ :\t\r\n]/) i++
    if (substr(json, i, 1) != "\"") return ""
    i++; out = ""
    while (i <= len) {
        c = substr(json, i, 1)
        if (c == "\"") { AI_JFOUND = 1; return ai_junesc(out) }
        if (c == "\\" && i < len) { out = out c substr(json, i + 1, 1); i += 2; continue }
        out = out c
        i++
    }
    return ""
}

# append one message to the thread transcript (durable: close every time)
function ai_log(n, role, msg) {
    if (AI_TFILE[n] == "") return
    print role " " fio_esc(msg) >> AI_TFILE[n]
    close(AI_TFILE[n])
}

# mode-"A" analog of fio_fill: pop the next reply line into FH_PEND,
# sending the accumulated prompt first.  A prompt that is waiting ALWAYS
# goes out at the next read ("the next LINE INPUT #n sends it"): whatever
# is left unread of the previous reply is dropped, or a program that reads
# only the first line of each answer -- the @TOKENS pattern -- would be
# handed line 2 of the old reply as the answer to its new question.
function ai_fill(n,   p) {
    if (FH_OPENDHAS[n] || AI_PROMPT[n] != "") {
        FH_PENDHAS[n] = 0; AI_REPLY[n] = ""; AI_RHAS[n] = 0
    }
    if (FH_PENDHAS[n]) return 1
    if (!AI_RHAS[n]) {
        if (!FH_OPENDHAS[n] && AI_PROMPT[n] == "") return 0
        ai_send(n)
        if (E) return 0
    }
    p = index(AI_REPLY[n], "\n")
    if (p) { FH_PEND[n] = substr(AI_REPLY[n], 1, p - 1); AI_REPLY[n] = substr(AI_REPLY[n], p + 1) }
    else { FH_PEND[n] = AI_REPLY[n]; AI_REPLY[n] = ""; AI_RHAS[n] = 0 }
    FH_PENDHAS[n] = 1
    FH_LOC[n]++
    return 1
}

function ai_send(n,   i, body, bf, cmd, host, tmo, resp, line, content, rc, tok, rep) {
    if (FH_OPENDHAS[n]) {                   # trailing-; partial completes the prompt
        AI_PROMPT[n] = AI_PROMPT[n] FH_OPEND[n] "\n"
        FH_OPEND[n] = ""; FH_OPENDHAS[n] = 0
    }
    sub(/\n$/, "", AI_PROMPT[n])
    AI_TOKENS[n] = ""
    AI_PROMPT[n] = ai_directives(n, AI_PROMPT[n])
    if (E) { AI_PROMPT[n] = ""; return }
    AI_NMSG[n]++
    AI_ROLE[n, AI_NMSG[n]] = "u"
    AI_MSG[n, AI_NMSG[n]] = AI_PROMPT[n]
    AI_PROMPT[n] = ""
    body = "{\"model\":\"" ai_jesc(AI_MODEL[n]) "\",\"stream\":false,\"messages\":["
    for (i = 1; i <= AI_NMSG[n]; i++) {
        if (i > 1) body = body ","
        body = body "{\"role\":\"" (AI_ROLE[n, i] == "u" ? "user" : "assistant") "\"," \
                    "\"content\":\"" ai_jesc(AI_MSG[n, i]) "\"}"
    }
    body = body "]"
    if (AI_THINK[n] == "0" || AI_THINK[n] == "1")
        body = body ",\"think\":" (AI_THINK[n] == "1" ? "true" : "false")
    if (AI_KEEP[n] != "") body = body ",\"keep_alive\":\"" ai_jesc(AI_KEEP[n]) "\""
    if (AI_TOKENS[n] != "") body = body ",\"format\":" ai_schema(AI_TOKENS[n])
    body = body "}"
    bf = host_mktemp("trs80_ollama")
    if (bf == "") { ai_unsend(n); raise(22); return }
    printf "%s", body > bf
    close(bf)
    if (ENVIRON["TRS80_OLLAMA_CURL"] != "")
        cmd = ENVIRON["TRS80_OLLAMA_CURL"] (WINNATIVE ? " \"" bf "\"" : " " shq(bf))
    else {
        host = ENVIRON["TRS80_OLLAMA_HOST"]
        if (host == "") host = "localhost:11434"
        tmo = ENVIRON["TRS80_OLLAMA_TIMEOUT"] + 0
        if (tmo <= 0) tmo = 300
        # cmd.exe passes single quotes through literally, so the native arm
        # must double-quote (curl.exe ships with Windows 10+)
        if (WINNATIVE)
            cmd = "curl -s --max-time " tmo " -X POST http://" host "/api/chat -d @\"" bf "\""
        else
            cmd = "curl -s --max-time " tmo " -X POST 'http://" host "/api/chat' -d @" shq(bf)
    }
    resp = ""
    while ((cmd | getline line) > 0) resp = resp line "\n"
    rc = close(cmd)
    host_delete(bf)
    if (rc != 0 || resp == "") { ai_unsend(n); raise(22); return }
    content = ai_extract(resp)
    if (E) { ai_unsend(n); return }
    if (AI_TOKENS[n] != "") {               # unpack {token, reply} into lines
        tok = ai_jstr(content, "token")
        if (AI_JFOUND) {
            rep = ai_jstr(content, "reply")
            content = tok "\n" rep
        }
        AI_TOKENS[n] = ""
    }
    sub(/\n+$/, "", content)                # models often pad with blank lines
    ai_log(n, "u", AI_MSG[n, AI_NMSG[n]])   # transcript only records completed exchanges
    AI_NMSG[n]++
    AI_ROLE[n, AI_NMSG[n]] = "a"
    AI_MSG[n, AI_NMSG[n]] = content
    ai_log(n, "a", content)
    AI_REPLY[n] = content
    AI_RHAS[n] = 1
}

# a failed send must not leave the unanswered user turn in the history
function ai_unsend(n) {
    delete AI_ROLE[n, AI_NMSG[n]]; delete AI_MSG[n, AI_NMSG[n]]
    AI_NMSG[n]--
}

# pull message.content out of a stream:false /api/chat response
function ai_extract(resp,   p, i, len, c, out) {
    p = index(resp, "\"content\":\"")
    if (p == 0) { raise(22); return "" }
    i = p + 11
    len = length(resp)
    out = ""
    while (i <= len) {
        c = substr(resp, i, 1)
        if (c == "\"") return ai_junesc(out)
        if (c == "\\" && i < len) { out = out c substr(resp, i + 1, 1); i += 2; continue }
        out = out c
        i++
    }
    raise(22)                               # unterminated string
    return ""
}

# JSON escape: backslash, quote, and ASCII control chars; UTF-8 passes through
function ai_jesc(s,   out, i, n, c, o) {
    out = ""; n = length(s)
    for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (c == "\\") { out = out "\\\\"; continue }
        if (c == "\"") { out = out "\\\""; continue }
        if (c in ORD) {
            o = ORD[c]
            if (o < 32) {
                if (o == 10) out = out "\\n"
                else if (o == 13) out = out "\\r"
                else if (o == 9) out = out "\\t"
                else out = out sprintf("\\u%04X", o)
                continue
            }
        }
        out = out c
    }
    return out
}

function ai_junesc(s,   out, i, n, c, e) {
    out = ""; i = 1; n = length(s)
    while (i <= n) {
        c = substr(s, i, 1)
        if (c != "\\" || i == n) { out = out c; i++; continue }
        e = substr(s, i + 1, 1)
        if (e == "n") out = out "\n"
        else if (e == "t") out = out "\t"
        else if (e == "r") out = out "\r"
        else if (e == "u" && i + 5 <= n) {
            out = out utf8(strtonum("0x" substr(s, i + 2, 4)))   # bytes (p10)
            i += 6
            continue
        }
        else out = out e                    # \" \\ \/ and anything unknown
        i += 2
    }
    return out
}
# ===================== errors and numeric utilities =========================

function raise(c) {
    if (E) return
    E = c
    ERR_AT = CLN
    ERRV = (c - 1) * 2
    ERLV = CLN
    # "." becomes the line with the error, trapped or not: the ROM notes it
    # with ERL, before it looks for an ON ERROR handler (19A5-19A8), so
    # LIST . and EDIT . go to the line that failed
    if (CLN > 0) LASTLN = CLN
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
# The sixth digit is rounded HALF UP on the magnitude: the ROM scales the
# value to six integer digits, adds .5 and truncates (12EA-12F0).  sprintf
# rounds an exact tie to even (100000.5 -> 100000, 1/512 -> .00195312), so
# a seventh digit of 5 is rounded here, on the decimal digits.
function fmtnum(x,   s, ax, t) {
    ax = (x < 0) ? -x : x
    if (x == int(x) && ax < 1e15) s = sprintf("%.0f", x)
    else {
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
    return system("test -f " shq(f)) == 0
}

function host_delete(f) {
    if (WINNATIVE) { if (f !~ /"/) system("del /f /q \"" f "\" 2>nul"); return }
    system("rm -f -- " shq(f))
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
