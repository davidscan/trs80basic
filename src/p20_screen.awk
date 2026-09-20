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
