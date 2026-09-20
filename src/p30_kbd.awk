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
    KPLAST = km_now()
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
    KPLAST = km_now()
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
    KP_STUCK = 2                                  # seconds without any event: release everything
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
        if (KPLAST > 0 && km_now() - KPLAST > KP_STUCK) { kp_release_all(); KPLAST = 0 }
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
