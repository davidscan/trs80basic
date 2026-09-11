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
# Uses stty/dd/od for raw keyboard input (permitted external utilities).
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
        RC = batch_main()
        fio_closeall()
        t_done()
        exit RC
    }
    s_cls()
    s_puts("MEMORY SIZE? "); sync_cursor()
    BOOTMS = rl_read()
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
    M3MODE = 0; M3KANA = 0; WIDE = 0
    DUMB = (ENVIRON["TRS80_DUMB"] != "")
    # misc state
    CUR = 0; NL = 0; LASTLN = 0; DATADIRTY = 1; NDATA = 0; DP = 1
    FSN = 0; GSN = 0; CONTOK = 0; TRACE = 0
    EHANDLER = 0; INHANDLER = 0; ERRV = 0; ERLV = 0
    E = 0; RLCANCEL = 0; EOFQUIT = 0; PENDBRK = 0
    BRKCTR = 0; BRKEVERY = 400
    FNLIST = " ABS INT FIX SGN SQR SIN COS TAN ATN LOG EXP RND CINT CSNG CDBL PEEK POS FRE LEN ASC VAL CHR$ STR$ STRING$ LEFT$ RIGHT$ MID$ INSTR POINT TAB EOF LOF LOC MKI$ MKS$ MKD$ CVI CVS CVD "
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
    init_man()
}

# recompute the per-statement throttle delay from a target clock in MHz
function set_speed(mhz) {
    if (WINNATIVE) mhz = 0      # cmd.exe has no sub-second sleep: throttle off
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

function drawcell(p) {
    if (DUMB) return
    if (WIDE) {
        # CHR$(23) 32-column mode: only even display bytes are visible,
        # each rendered double wide (glyph + trailing space); a write to
        # an odd byte repaints its even partner (no visible change)
        p -= p % 2
        if (p in CCOL)
            printf "\033[%d;%dH\033[38;5;%dm%s \033[39m", int(p / 64) + 1, p % 64 + 1, GCANSI[CCOL[p]], GL[SCR[p]]
        else
            printf "\033[%d;%dH%s ", int(p / 64) + 1, p % 64 + 1, GL[SCR[p]]
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

function sync_cursor() {
    if (!DUMB) printf "\033[%d;%dH", int(CUR / 64) + 1, CUR % 64 + 1
    fflush()
}

function redraw_all(   r, c, s, p, g) {
    if (DUMB) return
    for (r = 0; r < 16; r++) {
        s = ""
        for (c = 0; c < 64; c += (WIDE ? 2 : 1)) {
            p = r * 64 + c
            g = GL[SCR[p]] (WIDE ? " " : "")
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
    WIDE = 0                                # CLS returns to 64 chars per line
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

function s_nl() {
    # On a real tty we hold the line in `stty raw` for our own key handling,
    # so LF alone won't return the carriage -- emit CR+LF when streaming.
    if (DUMB) printf (TTYIN ? "\r\n" : "\n")
    CUR = int(CUR / 64) * 64 + 64
    if (CUR > 1023) { s_scroll(); CUR = 960 }
}

# output one byte with LEVEL II display-control semantics
function s_putc(b,   n, r) {
    # printable: 32-191 always; 192-255 too when the Model III special/
    # Katakana mode is on (CHR$(21)) -- then they are characters, not
    # space-compression codes
    if (b >= 32 && (b < 192 || M3MODE)) {
        if (WIDE) {
            # CHR$(23) 32-column mode: characters land on even display
            # bytes (the ROM masks the low cursor bit) and advance by 2
            CUR -= CUR % 2
            if (DUMB) printf "%s ", GL[b]
            setcell(CUR, b); CUR += 2
        } else {
            if (DUMB) printf "%s", GL[b]
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
    # Model III: 21 toggles codes 192-255 between space compression and
    # character display; 22 picks which set that shows (special/Katakana)
    if (b == 21) { M3MODE = !M3MODE; m3_rebuild(); return }
    if (b == 22) { M3KANA = !M3KANA; if (M3MODE) m3_rebuild(); return }
    # LEVEL II: 23 shifts to 32 characters per line (CLS returns to 64)
    if (b == 23) { if (!WIDE) { WIDE = 1; if (!DUMB) { redraw_all(); sync_cursor() } } return }
    if (b == 24) { if (CUR > 0) CUR--; return }
    if (b == 25) { if (CUR < 1023) CUR++; return }
    if (b == 26) { if (CUR < 960) CUR += 64; else { s_scroll(); } return }
    if (b == 27) { if (CUR >= 64) CUR -= 64; return }
    if (b == 28) { CUR = 0; return }
    if (b == 29) { CUR = int(CUR / 64) * 64; return }
    if (b == 30) { r = int(CUR / 64) * 64 + 63; for (n = CUR; n <= r; n++) setcell(n, 32); return }
    if (b == 31) { for (n = CUR; n < 1024; n++) setcell(n, 32); return }
    # 0-7, 9, 11, 12, 14-20: ignored
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
# ===================== keyboard: raw tty via dd/od, or piped stdin ==========

function kb_init() {
    KH = 0; KT = 0; KBMODE = ""
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
    if (TTYIN && STTY0 != "") system("stty " STTY0 " < /dev/tty 2>/dev/null")
    else if (TTYIN) system("stty sane < /dev/tty 2>/dev/null")
}

function kb_mode(m) {
    if (!TTYIN || KBMODE == m) return
    if (m == "line") system("stty raw -echo min 1 time 0 < /dev/tty")
    else             system("stty raw -echo min 0 time 0 < /dev/tty")
    KBMODE = m
}

# read whatever is available from the tty into the queue (>=1 byte if "line")
function kb_fill(   cmd, ln, a, n, i, got) {
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

# check for BREAK (Ctrl-C, byte 3) without consuming other typed-ahead input.
# Ctrl-S (byte 19) = the real SHIFT-@ pause: block until a key; Ctrl-C breaks.
function pollbrk(   i, c) {
    if (PENDBRK) { PENDBRK = 0; kb_flush(); return 1 }
    if (!TTYIN) return 0
    kb_mode("poll")
    if (KH >= KT) kb_fill()
    for (i = KH + 1; i <= KT; i++) {
        if (KBQ[i] == 3) { kb_flush(); return 1 }
        if (KBQ[i] == 19) {
            KH = i                          # consume through the Ctrl-S only:
            c = kb_get()                    # typed-ahead after it must survive
            if (c == 3) { kb_flush(); return 1 }
            return 0
        }
    }
    if (KT - KH > 4096) kb_flush()
    return 0
}

function kb_flush() { KH = 0; KT = 0 }

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
# consumes at most one pending byte and "presses" its key for KMHOLD polls
# (TRS80_KMHOLD, default 4).  A terminal sends no key-up events, so a tap
# reads as a short press and a held key rides the terminal's auto-repeat.
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
    KMR_[32] = 6; KMB_[32] = 128                  # SPACE
    KMHOLD = (ENVIRON["TRS80_KMHOLD"] + 0 > 0) ? ENVIRON["TRS80_KMHOLD"] + 0 : 4
    KMR = -1; KMSH = 0
}

function km_row(s, row, sh, fb,   i, c) {
    for (i = 1; i <= length(s); i++) {
        c = ORD[substr(s, i, 1)]
        KMR_[c] = row; KMB_[c] = 2 ^ (fb + i - 1); KMS_[c] = sh
    }
}

function km_latch(r, b, sh) { KMR = r; KMB = b; KMSH = sh; KMTTL = KMHOLD }

# next byte of an ESC sequence: already queued in pipe mode, short poll on tty
function km_next(   i) {
    if (!TTYIN) return (KH < KT) ? KBQ[++KH] : -1
    for (i = 0; i < 30; i++) if (KH < KT || kb_fill() > 0) return KBQ[++KH]
    return -1
}

# consume at most one pending byte into the latch; age the latch when idle
function km_pump(   c) {
    if (TTYIN) { kb_mode("poll"); if (KH >= KT) kb_fill() }
    else if (KH >= KT) {
        if (EOFQUIT || ++INKEYEOF > 200000) { kbe_diag(); PENDBRK = 1; KMR = -1; return }
        if (!kb_pipe_fill()) { kbe_diag(); KMR = -1; return }
    }
    if (KH >= KT) {
        if (KMR >= 0 && --KMTTL <= 0) { KMR = -1; KMSH = 0 }
        return
    }
    c = KBQ[++KH]
    if (c == 3) { PENDBRK = 1; kb_flush(); km_latch(6, 4, 0); return }
    if (c == 27) {
        c = km_next()
        if (c == 91 || c == 79) {
            c = km_next()
            if      (c == 65) { km_latch(6, 8, 0);  return }   # up
            else if (c == 66) { km_latch(6, 16, 0); return }   # down
            else if (c == 67) { km_latch(6, 64, 0); return }   # right
            else if (c == 68) { km_latch(6, 32, 0); return }   # left
        }
        KMR = -1; KMSH = 0                        # lone/unknown ESC: no key
        return
    }
    if (c in KMR_) km_latch(KMR_[c], KMB_[c], KMS_[c] + 0)
    else { KMR = -1; KMSH = 0 }                   # key with no matrix position
}

function kb_matrix(sel,   out) {
    km_pump()
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
    sync_cursor()
    if (!TTYIN) {
        r = (getline s < "/dev/stdin")
        if (r <= 0) { EOFQUIT = 1; return "" }
        sub(/\r$/, "", s)
        if (length(s) > 255) s = substr(s, 1, 255)
        s_puts(s); s_nl()
        return s
    }
    RLS = ""; RLP = 0
    RLSTART = CUR
    HIX = 0; RLDRAFT = ""
    for (;;) {
        c = kb_get()
        if (c < 0) return RLS
        if (c == 13 || c == 10) {
            if (!DUMB) { CUR = RLSTART + length(RLS); if (CUR > 1023) CUR = 1023 }
            s_nl(); sync_cursor()
            return RLS
        }
        if (c == 3) { RLCANCEL = 1; s_nl(); sync_cursor(); return "" }
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
        if (c >= 32 && c < 127 && oldl < 255) {
            RLS = substr(RLS, 1, RLP) CHR[c] substr(RLS, RLP + 1)
            RLP++
            rl_draw(oldl, oldp)
        }
    }
}

# repaint the input line after an edit.  Grid mode: repaint from the RLSTART
# anchor (tracking any scroll it causes).  Fullscreen tty mode: plain
# backspace/overprint -- fine up to the terminal width (255-char lines that
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
        cmd = "ls -1d -- '" word "'* 2>/dev/null"
        while ((cmd | getline line) > 0) { if (nm < 100) mt[++nm] = line }
        close(cmd)
    }
    if (nm == 0) return
    lcp = mt[1]
    for (j = 2; j <= nm; j++)
        while (lcp != "" && substr(mt[j], 1, length(lcp)) != lcp) lcp = substr(lcp, 1, length(lcp) - 1)
    add = substr(lcp, length(word) + 1)
    if (nm == 1 && system("test -d '" mt[1] "'") == 0) add = add "/"
    if (add != "") {
        if (oldl + length(add) > 255) return
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
    LASTLN = ln
    inval_cache(ln)
    rebuild()
    DATADIRTY = 1; CONTOK = 0
}

function delline(ln) {
    delete prog[ln]
    inval_cache(ln)
    rebuild()
    DATADIRTY = 1; CONTOK = 0
}

function inval_cache(ln) { inval_cache_key(ln "") }

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

function st_list(   i, ln) {
    parse_range()
    for (i = 1; i <= NL; i++) {
        ln = LNS[i]
        if (ln < RA) continue
        if (ln > RB) break
        s_puts(ln " " prog[ln]); s_nl()
        if (pollbrk()) break
    }
}

# LLIST: LIST to the printer stream (all the same range forms)
function st_llist(   i, ln) {
    parse_range()
    for (i = 1; i <= NL; i++) {
        ln = LNS[i]
        if (ln < RA) continue
        if (ln > RB) break
        lp_puts(ln " " prog[ln]); lp_nl()
    }
}

function st_delete(   i, ln, n, hits) {
    if (!parse_range()) { raise(2); return }
    n = 0
    for (i = 1; i <= NL; i++) {
        ln = LNS[i]
        if (ln >= RA && ln <= RB) { hits[++n] = ln }
    }
    if (n == 0) { raise(8); return }
    for (i = 1; i <= n; i++) { delete prog[hits[i]]; inval_cache(hits[i]) }
    rebuild()
    DATADIRTY = 1; CONTOK = 0
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
    while (start <= 65529) {
        kb_mode("line")
        k = (start in prog)
        s_puts(start (k ? "*" : " "))
        line = rl_read()
        if (EOFQUIT || RLCANCEL) break
        if (line == "") { if (!k) break }
        else storeline(start, line)
        start += inc
    }
}

function st_new(   x) {
    for (x in prog) { inval_cache(x); delete prog[x] }
    rebuild()
    clear_vars()
    FSN = 0; GSN = 0; NDATA = 0; DP = 1; DATADIRTY = 1
    CONTOK = 0; LASTLN = 0; EHANDLER = 0; INHANDLER = 0; ERRV = 0; ERLV = 0
    HALT = 1
}

# keepfiles=1 (LOAD/RUN "file",R) skips the channel close; every existing
# caller omits it, so plain clear_vars() still closes everything
function clear_vars(keepfiles, keeptypes) {
    if (!keepfiles) fio_closeall()
    delete NV; delete SV; delete VA; delete ADIM; delete ASZ
    # DEF FN definitions live in variable space (MS BASIC): RUN/NEW/CLEAR
    # all wipe them and the program re-executes its DEFs
    delete FNPAR; delete FNPARM; delete FNKEY; delete FNPOS
    FNDEPTH = 0
    # DEF-type table survives the CLEAR statement (DEFSTR A: CLEAR 500: A="X"
    # stays typed) but resets on RUN/NEW/program load
    if (!keeptypes) delete DEFS
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
# quoted string token -> as-is.  Anything else: the filename is the RAW
# source text from here to end of line (case preserved, "/" and "." intact;
# no ":"-statement may follow an unquoted name -- documented).
function parse_fname(   t, f) {
    t = TY[CK, CP]
    if (t == "s") { f = TK[CK, CP]; CP++; return f }
    if (t == "" || t == "e") return ""
    f = substr(TSRC[CK], TPO[CK, CP])
    gsub(/^[ \t]+|[ \t]+$/, "", f)
    while (!(TY[CK, CP] == "" || TY[CK, CP] == "e")) CP++
    return f
}

function st_csave(   f) {
    f = parse_fname()
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
    f = parse_fname()
    if (f == "") { raise(21); return }
    if (!prog_load(f, verify)) { raise(22); return }
}

# Disk BASIC LOAD "file"[,R]: host-file CLOAD.  ,R = run after loading,
# keeping open file channels (the manual's chaining device).  The flag is
# only reachable after a QUOTED name -- an unquoted name runs to end of
# line, same as CLOAD.
function st_load(   f, keep) {
    f = parse_fname()
    if (f == "") { raise(21); return }
    keep = 0
    if (TY[CK, CP] == "o" && TK[CK, CP] == ",") {
        CP++
        if (TY[CK, CP] == "i" && TK[CK, CP] == "R") { CP++; keep = 1 }
        else { raise(2); return }
    }
    if (!prog_load(f, 0, keep)) { raise(22); return }
    if (keep) run_start(0, 1)
}

# Disk BASIC MERGE "file": read a listing into the CURRENT program -- no
# implicit NEW.  File lines overwrite same-numbered lines and interleave
# with the rest.  Variables clear and BASIC returns to command level (the
# TRSDOS behavior), so a MERGE issued by a running program stops it --
# which also sidesteps executing from a shifted line table.
function st_merge(   f) {
    f = parse_fname()
    if (f == "") { raise(21); return }
    if (!prog_load(f, 0, 0, 1)) { raise(22); return }
    HALT = 1
}

# Disk BASIC SAVE "file"[,V]: host-file CSAVE.  ,V (verify) is accepted and
# ignored -- host writes don't need a cassette verify pass.
function st_save(   f) {
    f = parse_fname()
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
function prog_load(f, verify, keepfiles, merge,   l, r, ln, rest, bad, x, nseen, ok, pln, rpt, ra, ri, nn) {
    LOADBAD = 0
    r = (getline l < f); pln = 1
    if (r < 0) return 0
    if (!verify) {
        if (!merge) for (x in prog) { inval_cache(x); delete prog[x] }
        clear_vars(keepfiles)
        NDATA = 0; DP = 1; CONTOK = 0
    }
    ok = 1; nseen = 0
    while (r > 0) {
        sub(/\r$/, "", l)
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
                } else { prog[ln] = rest; inval_cache(ln); LASTLN = ln }
            } else { bad = 1; rpt = rpt "?FD ERROR - FILE LINE " pln " (NO LINE NUMBER)\n" }
        }
        r = (getline l < f); pln++
    }
    close(f)
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
# SEEDED/OPT_SEED, OPT_HELP.  gawk never reads the operands itself: the whole
# interpreter lives in BEGIN and exits there.
function parse_args(   i, a, nofl) {
    BATCH = 0; BATCHFILE = ""; OPT_SCREEN = 0; OPT_HELP = 0
    SEEDED = 0; OPT_SEED = 0; nofl = 0
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
        diag_err("basic: cannot read '" BATCHFILE "'")
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
        # spaced call form (Z80 sub-project FINDING 17).
        if (s ~ /^USR[0-9]?$/) {
            if (s == "USR" && TY[CK, CP + 1] == "n" &&
                TK[CK, CP + 1] ~ /^[0-9]$/ &&
                TY[CK, CP + 2] == "o" && TK[CK, CP + 2] == "(") CP++
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
            if (key in VA) return VA[key]
            return strname(s) ? "S" : "N0"
        }
        if (strname(s)) return "S" SV[s]
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
        if (x > 32767.5 || x < -32768.5) { raise(6); return "N0" }
        return "N" bfloor(x + 0.5)
    }
    if (name == "CSNG" || name == "CDBL") { x = numarg(a1, na); if (E) return "N0"; return "N" x }
    if (name == "PEEK") { x = numarg(a1, na); if (E) return "N0"; return "N" dopeek(x) }
    # USR/USR0-9 machine-language call STUB: evaluates and returns its
    # argument -- there is no Z80 to run the routine (see STATUS roadmap).
    # X=USR(V) identity keeps more rescued listings partially running than
    # ?FC would; routines whose RESULT is load-bearing still fail visibly.
    if (name ~ /^USR[0-9]?$/) { x = numarg(a1, na); if (E) return "N0"; return "N" x }
    if (name == "POS") { x = numarg(a1, na); if (E) return "N0"; return "N" (CUR % 64) }
    if (name == "FRE") { if (na < 1) { raise(2); return "N0" }; return "N" 15572 }
    if (name == "LEN") { s = strarg(a1, na); if (E) return "N0"; return "N" length(s) }
    if (name == "ASC") {
        s = strarg(a1, na); if (E) return "N0"
        if (s == "") { raise(5); return "N0" }
        s = substr(s, 1, 1)
        return "N" ((s in ORD) ? ORD[s] : 63)
    }
    if (name == "VAL") { s = strarg(a1, na); if (E) return "N0"; return "N" valnum(s) }
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

function fn_inkey(   c) {
    if (CK == "I" && !TTYIN) return "S"
    c = kb_poll1()
    if (c == 3) { PENDBRK = 1; return "S" }
    if (c < 0) return "S"
    return "S" CHR[c]
}

# FNLIST is initialized in init_tables (single BEGIN block runs everything)
# ===================== execution engine and control flow ====================

function exec_immediate(line) {
    tokline("I", line)
    CK = "I"; CLI = 0; CLN = 0; CP = 1
    E = 0; HALT = 0; STOPPED = 0
    execloop()
    if (E) report_err()
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
#   DEF USR[n]=addr / DEFUSRn=addr   -- accepted no-op stub: the address
#     expression is evaluated for syntax honesty (like OUT) and discarded;
#     USRn() calls return their argument (fncall).
#   DEF FN name(...)=expr / DEF FNname(...)=expr / DEFFNname(...)=expr
#     -- real user-defined functions (st_deffn / fn_user).
# Any other DEF shape stays ?SN.
function st_def(tx,   v) {
    if (tx ~ /^DEFUSR[0-9]?$/) { st_defusr_tail(tx == "DEFUSR"); return }
    if (tx ~ /^DEFFN./) { st_deffn(substr(tx, 6)); return }
    # tx == "DEF": look at the next identifier
    if (TY[CK, CP] != "i") { raise(2); return }
    tx = TK[CK, CP]
    if (tx ~ /^USR[0-9]?$/) { CP++; st_defusr_tail(tx == "USR"); return }
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

function st_defusr_tail(baredigit,   v) {
    # when the spelling carried no slot digit, one may follow as its own
    # token -- real Level II tokenizes past the space, so DEF USR 0=addr
    # is legal (measured on morsmstr/quest_2; Z80 sub-project FINDING 8)
    if (baredigit && TY[CK, CP] == "n" && TK[CK, CP] ~ /^[0-9]$/) CP++
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == "=")) { raise(2); return }
    CP++
    v = e_or(); if (E) return
    if (!isN(v)) { raise(13); return }
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
        if (key != "") VA[key] = v; else SV[name] = vstr(v)
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
    # is legal MS BASIC) -- truncate only, never restore: the subroutine may
    # legitimately have NEXT'd a loop opened before the call to completion
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
    for (j = FSN; j >= 1; j--)
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

function do_next(name,   j, v) {
    if (FSN == 0) { raise(1); return 0 }
    if (name == "") j = FSN
    else {
        for (j = FSN; j >= 1; j--)
            if (FS_V[j] == name) break
        if (j < 1) { raise(1); return 0 }
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
        if (EHANDLER == 0) INHANDLER = 0
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
    if (TY[CK, CP] == "s") {            # Disk BASIC RUN "file"[,R]
        f = TK[CK, CP]; CP++
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
    clear_vars(0, 1)
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
#  1. READ-ONLY tokenized program image: PEEK of 42E9H (17129) onward sees
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
#     single bytes (fio_mkf/fio_cvf), also live in both directions.
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
#   4. a in SPK -> VARPTR string space (sp_peek).  THIS DELIBERATELY OUTRANKS
#      RULE 5: a packed string inside the program-image range must win over
#      the image, which is what makes the string-packing idiom work at any
#      program size.  It is an invariant, not a consequence of statement
#      order -- do not reorder it under rule 5.
#   5. a >= 17129 and a < PMEND -> PMEM[], the READ-ONLY tokenized program
#      image (rule 2's shape again: POKEs land in MEM[] and vanish).  The
#      bound is RAMTOP, not HIMEM -- lowering HIMEM does NOT shrink the
#      shadowed range.  a > RAMTOP -> 255, currently unreachable (see below).
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
# st_poke() (p80) is dopeek's twin and its order is CONTRACT for the same
# reason: a Z80 store from ../trs80_z80_core must land exactly where a POKE of
# the same address lands, or the two disagree about memory with no error.
# Requested by that project 2026-09-08 (handoff REPLY 2).  They read the order
# off the code themselves and read it correctly; all six rules are theirs,
# re-verified against st_poke 2026-09-09.  Highest precedence first:
#
#   1. 3C00-3FFFH (15360-16383) -> s_poke() + sync_cursor()
#   2. 40AA-40ACH (16554-16556) -> rnd_poke(), the ROM RND seed
#   3. 40B1/40B2H (16561/16562) -> pm_sethimem(), the one writable pointer
#   4. a in SPK                 -> sp_poke(), VARPTR string-space write-through
#   5. a > RAMTOP               -> DISCARDED (absent RAM)
#   6. otherwise                -> MEM[a] = b
#
# FOUR ASYMMETRIES AGAINST THE READ SIDE.  Each is a range the read side
# projects from somewhere other than MEM[], so a write there lands in MEM[]
# and NOTHING CAN EVER OBSERVE IT:
#   * 3800-38FFH keyboard (read rule 1) -- no write branch.
#   * 37E8/37E9H printer  (read rule 2) -- no write branch.
#   * 40A4/40A5H and 40F9/40FAH (read rule 3) -- no write branch.  40B1/40B2H
#     is the ONLY writable member; rule 3 above is where that finally gets
#     said on the write side, having been stated only on the read side.
#   * the tokenized program image, a >= 17129 && a < PMEND (read rule 5) --
#     no write branch.  THIS ASYMMETRY IS THE SHADOW of FINDING 23: a byte
#     POKEd into the image is stored and invisible.  Measured at zero across
#     4,339 corpus files, so it stays exactly as it is.
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
# only inside its a >= 17129 branch and st_poke tests it unconditionally, but
# RAMTOP >= 17129 always holds, so no address is judged differently.

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
    }
    TOKIDX = 1
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
function pm_build(   i, ln, addr, nb, j, nxt) {
    if (!TOKIDX) pm_init_index()
    delete PMEM
    addr = 17129
    for (i = 1; i <= NL; i++) {
        ln = LNS[i]
        pm_crunch(prog[ln]); nb = PMBN
        nxt = (addr + 4 + nb + 1) % 65536         # 16-bit pointer, wraps
        PMEM[addr] = nxt % 256; PMEM[addr + 1] = int(nxt / 256)
        PMEM[addr + 2] = ln % 256; PMEM[addr + 3] = int(ln / 256)
        for (j = 1; j <= nb; j++) PMEM[addr + 4 + j - 1] = PMB[j]
        PMEM[addr + 4 + nb] = 0
        addr += 4 + nb + 1
    }
    PMEM[addr] = 0; PMEM[addr + 1] = 0
    PMEND = addr + 2
    PROGDIRTY = 0
}

function pm_sync() { if (PROGDIRTY || PMEND == 0) pm_build() }

# the six live system-pointer bytes (dopeek routes them here)
function pm_sysptr(a) {
    if (a == 16548) return 233                    # 40A4H: program base 42E9H
    if (a == 16549) return 66
    if (a == 16561) return HIMEM % 256            # 40B1H: top of memory
    if (a == 16562) return int(HIMEM / 256)
    pm_sync()                                     # 40F9H: start of variables
    # a PEEK returns a byte: mask the high half too, so a program image
    # larger than the address space cannot leak a >255 value (reported by
    # ../trs80_z80_core 2026-09-07; 1200 REM lines used to answer 381)
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
    delete SPK; delete SPT; delete SPV; delete VPDESC; delete VPDATA; delete VPCAP
    SSP = HIMEM
}

# unmap a string's data cells (the descriptor stays where it is)
function sp_free_data(tgt,   a, e) {
    if (!(tgt in VPDATA)) return
    e = VPDATA[tgt] + VPCAP[tgt] - 1
    for (a = VPDATA[tgt]; a <= e; a++) { delete SPK[a]; delete SPT[a] }
}

# map len string cells for tgt at base
function sp_map_data(tgt, base, len,   j) {
    for (j = 0; j < len; j++) { SPK[base + j] = tgt; SPT[base + j] = j }
    VPDATA[tgt] = base; VPCAP[tgt] = len
}

# materialize var (locator tgt, string flag isstr) and return its VARPTR.
# Idempotent: a second call returns the first call's address.  A string's
# bytes are re-homed only when the live value is longer than the cells
# mapped for it; shrinking never moves anything (sp_peek pads with 32 past
# the live length).
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

function sp_peek(a,   t, tgt, v) {
    t = SPT[a]; tgt = SPK[a]
    if (t == "L") return length(sp_gets(tgt)) % 256
    if (t == "C") return SPV[a]
    if (substr(t, 1, 1) == "N") {
        v = fio_mkf(sp_getn(tgt), 4)
        return ORD[substr(v, substr(t, 2) + 1, 1)]
    }
    v = sp_gets(tgt)                              # string byte, live
    return (t + 1 <= length(v)) ? ORD[substr(v, t + 1, 1)] : 32
}

function sp_poke(a, b,   t, tgt, v, j) {
    t = SPT[a]; tgt = SPK[a]
    if (t == "C") return                          # can't relocate the bytes
    if (t == "L") {                               # truncate / space-pad
        v = sp_gets(tgt)
        while (length(v) < b) v = v " "
        sp_sets(tgt, substr(v, 1, b))
        return
    }
    if (substr(t, 1, 1) == "N") {
        v = fio_mkf(sp_getn(tgt), 4); j = substr(t, 2) + 1
        v = substr(v, 1, j - 1) CHR[b] substr(v, j + 1)
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
            col = CUR % 64
            if (int(col / 16) >= 3) s_nl()
            else CUR += 16 - (col % 16)
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
        if (isN(v)) s_puts(fmtnum(num(v)))
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
function lp_puts(s) {
    LPCOL += length(s)
    if (LPFILE != "") printf "%s", s >> LPFILE
}

function lp_nl() {
    LPCOL = 0
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
            lp_puts(substr("                ", 1, 16 - (LPCOL % 16)))
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
            while (LPCOL < t) lp_puts(" ")
            sep = 0
            continue
        }
        v = e_or(); if (E) return
        if (isN(v)) lp_puts(fmtnum(num(v)))
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
function st_out(   v) {
    v = e_or(); if (E) return
    if (!isN(v)) { raise(13); return }
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == ",")) { raise(2); return }
    CP++
    v = e_or(); if (E) return
    if (!isN(v)) { raise(13); return }
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
    s = (key != "") ? ((key in VA) ? vstr(VA[key]) : "") : SV[name]
    if (n < 1 || n > 255 || n > length(s)) { raise(5); return }
    cnt = length(r)
    if (m >= 0 && m < cnt) cnt = m
    if (cnt > length(s) - n + 1) cnt = length(s) - n + 1
    assignv(name, key, "S" substr(s, 1, n - 1) substr(r, 1, cnt) substr(s, n + cnt))
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
function st_input(   prompt, pq, nlv, name, key, i, line, nib, idx, ok, x) {
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
    nlv = 0
    for (;;) {
        if (TY[CK, CP] != "i") { raise(2); return }
        name = TK[CK, CP]; CP++
        key = ""
        if (TY[CK, CP] == "o" && TK[CK, CP] == "(") { key = aref(name); if (E) return }
        nlv++; LV_N[nlv] = name; LV_K[nlv] = key
        if (TY[CK, CP] == "o" && TK[CK, CP] == ",") { CP++; continue }
        break
    }
    for (;;) {                              # REDO loop
        if (prompt != "") s_puts(prompt)
        if (pq != 2) s_puts("? ")
        idx = 1; nib = 0
        ok = 1
        for (;;) {                          # fill loop
            line = rl_read()
            if (RLCANCEL) { dobreak(); return }
            if (EOFQUIT) { if (BATCH) batch_ineof(); STOPPED = 1; return }
            nib = parse_items(line, nib)
            while (idx <= nlv && idx <= nib) {
                if (strname(LV_N[idx])) assignv(LV_N[idx], LV_K[idx], "S" IB[idx])
                else {
                    x = IB[idx]
                    gsub(/^[ \t]+|[ \t]+$/, "", x)
                    if (x == "") x = "0"
                    if (!strictnum(x)) { ok = 0; break }
                    assignv(LV_N[idx], LV_K[idx], "N" numconv(x))
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
            assignv(name, key, "N" numconv(x))
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
function addrconv(x) {
    x = bfloor(x)
    if (x < 0) x += 65536
    if (x < 0 || x > 65535) { raise(5); return -1 }
    return x
}

# Resolution order is a CONTRACT the Z80 core must reproduce byte-for-byte --
# it is written out in full in p75's "THE ADDRESS-RESOLUTION CONTRACT" (read
# side; st_poke below has its own).  Keep the two in step; in particular SPK
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
    if (a in SPK) return sp_peek(a)               # VARPTR string space (p75)
    if (a >= 17129) {
        if (a > RAMTOP) return 255                # absent RAM above the physical top
        pm_sync()
        if (a < PMEND) return PMEM[a]
    }
    return (a in MEM) ? MEM[a] : 255
}

# The store order is CONTRACT too -- a Z80 write must land where a POKE of the
# same address lands.  Written out in full in p75's "THE ADDRESS-RESOLUTION
# CONTRACT, WRITE SIDE", including the four ranges where a write is stored but
# can never be read back.  Keep the two in step.
function st_poke(   v, a, b) {
    v = e_or(); if (E) return
    if (!isN(v)) { raise(13); return }
    a = addrconv(num(v)); if (E) return
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == ",")) { raise(2); return }
    CP++
    v = e_or(); if (E) return
    if (!isN(v)) { raise(13); return }
    b = bfloor(num(v)) % 256
    if (b < 0) b += 256
    if (a >= 15360 && a <= 16383) { s_poke(a - 15360, b); sync_cursor() }
    else if (a >= 16554 && a <= 16556) rnd_poke(a - 16554, b)
    else if (a == 16561 || a == 16562) pm_sethimem(a, b)   # move HIMEM (p75)
    else if (a in SPK) sp_poke(a, b)              # VARPTR write-through (p75)
    else if (a > RAMTOP) { }                      # absent RAM: discarded
    else MEM[a] = b
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
# Field maps: FLDN[n], FLD_V/O/W[n,i] (channel order) and FVCH/FVOF/FVW[name]
# (per-variable; a re-FIELD of a name moves it, last fielding wins).

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
    else if (FH_MODE[n] == "R") fio_flushR(n)
    else ai_close(n)                        # "A": unsent prompt is discarded
    for (r = 1; r <= FH_NREC[n]; r++) delete FH_REC[n, r]
    for (r = 1; r <= FLDN[n]; r++) {
        if (FVCH[FLD_V[n, r]] == n) {
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

# extract one comma-delimited item (quotes respected) into FIO_IT, leaving
# the unconsumed remainder pending so one line can feed several INPUT#s
function fio_next_item(n,   l, i, len, j, item) {
    if (!fio_fill(n)) return 0
    l = FH_PEND[n]
    i = 1; len = length(l)
    while (i <= len && substr(l, i, 1) == " ") i++
    if (i <= len && substr(l, i, 1) == "\"") {
        j = index(substr(l, i + 1), "\"")
        if (j == 0) { item = substr(l, i + 1); i = len + 1 }
        else { item = substr(l, i + 1, j - 1); i = i + j + 1 }
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
    nlv = 0
    for (;;) {
        if (TY[CK, CP] != "i") { raise(2); return }
        name = TK[CK, CP]; CP++
        key = ""
        if (TY[CK, CP] == "o" && TK[CK, CP] == "(") { key = aref(name); if (E) return }
        nlv++; LV_N[nlv] = name; LV_K[nlv] = key
        if (TY[CK, CP] == "o" && TK[CK, CP] == ",") { CP++; continue }
        break
    }
    for (i = 1; i <= nlv; i++) {
        if (!fio_next_item(n)) { raise(27); return }
        if (strname(LV_N[i])) assignv(LV_N[i], LV_K[i], "S" FIO_IT)
        else {
            x = FIO_IT
            gsub(/^[ \t]+|[ \t]+$/, "", x)
            if (x == "") x = "0"
            if (!strictnum(x)) { raise(13); return }
            assignv(LV_N[i], LV_K[i], "N" numconv(x))
        }
        if (E) return
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
# PRINT #n, ... : ; and , are pure separators (no display zone padding --
# zone spaces would corrupt comma-delimited re-reading); a trailing separator
# holds the partial line in FH_OPEND until the next PRINT# or CLOSE
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
        if (ty == "o" && (tx == ";" || tx == ",")) { sep = 1; CP++; continue }
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
function st_field(   n, off, w, v, name, i, found) {
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
        if (!strname(name)) { raise(13); return }
        if (off + w > FH_RLEN[n]) { raise(31); return }
        found = 0
        for (i = 1; i <= FLDN[n]; i++)
            if (FLD_V[n, i] == name) { found = i; break }
        if (!found) { FLDN[n]++; found = FLDN[n]; FLD_V[n, found] = name }
        FLD_O[n, found] = off; FLD_W[n, found] = w
        FVCH[name] = n; FVOF[name] = off; FVW[name] = w
        SV[name] = substr(FH_BUF[n], off + 1, w)
        off += w
        if (!(TY[CK, CP] == "o" && TK[CK, CP] == ",")) break
    }
}

# refresh fielded vars from the channel buffer (skip vars re-FIELDed away)
function fld_sync(n,   i, v) {
    for (i = 1; i <= FLDN[n]; i++) {
        v = FLD_V[n, i]
        if (FVCH[v] == n) SV[v] = substr(FH_BUF[n], FLD_O[n, i] + 1, FLD_W[n, i])
    }
}

function fio_just(s, w, left) {
    if (length(s) >= w) return substr(s, 1, w)
    if (left) return s fio_pad("", w - length(s))
    return fio_pad("", w - length(s)) s
}

# LSET (left=1) / RSET (left=0): justify into a fielded var's buffer slice;
# on a non-fielded string var, justify within its current length
function st_lset(left,   name, key, v, s, n, w, cur) {
    if (TY[CK, CP] != "i") { raise(2); return }
    name = TK[CK, CP]; CP++
    key = ""
    if (TY[CK, CP] == "o" && TK[CK, CP] == "(") { key = aref(name); if (E) return }
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == "=")) { raise(2); return }
    CP++
    v = e_or(); if (E) return
    if (!strname(name) || isN(v)) { raise(13); return }
    s = vstr(v)
    if (key == "" && (name in FVCH)) {
        n = FVCH[name]
        if (FH_MODE[n] != "R") { raise(25); return }
        w = FVW[name]
        s = fio_just(s, w, left)
        FH_BUF[n] = substr(FH_BUF[n], 1, FVOF[name]) s substr(FH_BUF[n], FVOF[name] + w + 1)
        fld_sync(n)
        return
    }
    cur = (key != "") ? ((key in VA) ? vstr(VA[key]) : "") : SV[name]
    s = fio_just(s, length(cur), left)
    if (key != "") VA[key] = "S" s
    else SV[name] = s
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
    if (rec > FH_NREC[n]) { raise(27); return }
    FH_BUF[n] = fio_pad(FH_REC[n, rec], FH_RLEN[n])
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
    if (x > 32767.5 || x < -32768.5) { raise(6); return "" }
    v = bfloor(x + 0.5)
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
# sending the accumulated prompt first if the reply buffer is empty
function ai_fill(n,   p) {
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
    bf = host_tmpdir() "/trs80_ollama_" PROCINFO["pid"] ".json"
    printf "%s", body > bf
    close(bf)
    if (ENVIRON["TRS80_OLLAMA_CURL"] != "")
        cmd = ENVIRON["TRS80_OLLAMA_CURL"] (WINNATIVE ? " \"" bf "\"" : " '" bf "'")
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
            cmd = "curl -s --max-time " tmo " -X POST 'http://" host "/api/chat' -d @'" bf "'"
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
# awk's own conversion would stop at ("1D3" + 0 == 1)
function numconv(s) {
    sub(/[Dd]/, "E", s)
    return s + 0
}

# BASIC INT(): floor
function bfloor(x,   f) {
    f = int(x)
    if (x < 0 && f != x) f--
    return f
}

# ---- 16-bit logical operators (operands rounded, two's complement) ---------
function to16(x,   r) {
    r = bfloor(x + 0.5)
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
# POKEable -- dopeek/st_poke map it):
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
# failures are fatal in gawk (that is why this stays a shell-out)
function host_writable(f) {
    if (WINNATIVE)
        return f !~ /"/ && system("type nul >> \"" f "\" 2>nul") == 0
    return system("touch -- '" f "' 2>/dev/null") == 0
}

function host_exists(f) {
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
