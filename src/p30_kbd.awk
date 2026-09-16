# ============ keyboard: raw tty (gawk polls it; dd/od blocks), or piped stdin =

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
    if (r <= 0) return 0
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
function pollbrk(   i, c, j) {
    if (PENDBRK) { PENDBRK = 0; kb_flush(); return 1 }
    if (!TTYIN) return 0
    kb_mode("poll")
    if (KH >= KT) kb_fill()
    for (i = KH + 1; i <= KT; i++) {
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
    KMR_[32] = 6; KMB_[32] = 128                  # SPACE
    KMCLOCK = ("gettimeofday" in FUNCTAB) ? "gettimeofday" : ""
    KMHOLD = (ENVIRON["TRS80_KMHOLD"] + 0 > 0) ? ENVIRON["TRS80_KMHOLD"] + 0 : (KMCLOCK != "" ? 100 : 4)
    KMR = -1; KMSH = 0
}

# seconds, sub-millisecond, from the time extension; -1 without it.  The
# indirect call keeps the program loadable when the extension is absent
# (a direct gettimeofday() would be a parse error there).
function km_now(   f) {
    if (KMCLOCK == "") return -1
    f = KMCLOCK
    return @f()
}

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

# consume at most one pending byte into the latch; age the latch when idle
function km_pump(   c) {
    if (TTYIN) { kb_mode("poll"); if (KH >= KT) kb_fill() }
    else if (KH >= KT) {
        if (EOFQUIT || ++INKEYEOF > 200000) { kbe_diag(); PENDBRK = 1; KMR = -1; return }
        if (!kb_pipe_fill()) { kbe_diag(); KMR = -1; return }
    }
    if (KH >= KT) {
        if (KMR >= 0 && !km_held()) { KMR = -1; KMSH = 0 }
        return
    }
    c = KBQ[++KH]
    if (c == 3) { if (brk_take()) { PENDBRK = 1; kb_flush() }; km_latch(6, 4, 0); return }
    BRKFORCE = 0
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
    RLWAIT = 1                              # a waiting read shows the cursor
    sync_cursor()
    if (!TTYIN) {
        r = (getline s < "/dev/stdin")
        if (r <= 0) { EOFQUIT = 1; RLWAIT = 0; return "" }
        sub(/\r$/, "", s)
        if (length(s) > 255) s = substr(s, 1, 255)
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
