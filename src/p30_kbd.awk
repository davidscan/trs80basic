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
    # there is a keyboard when STDIN is a terminal -- the launcher's own
    # `[ -t 0 ]` -- and /dev/tty opens for the readers below.  Testing
    # /dev/tty alone read the keyboard while a transcript sat unread on a
    # piped stdin, so `printf ... | gawk` and every transcript-fed suite
    # stalled at MEM SIZE? whenever a terminal existed (the 2026-09-19
    # audit, M-22; ruled 2026-09-21).  `stty -g` with no redirect reads
    # gawk's stdin.
    TTYIN = (system("( stty -g && stty -g < /dev/tty ) > /dev/null 2>&1") == 0)
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
#   Entering poll mode sends CSI ? u (the query, until answered) and CSI > 2 u (push
#   the flag); entering line mode and exiting send CSI < u (pop).  A
#   terminal without the protocol ignores all three and never answers
#   the query, so KBPROTO stays 0 and the timed latch above is used.
#   The reply CSI ? <flags> u, and every event CSI <code> ; <mods> : <ev> u
#   (or ... <ev> A-D for the arrows), is taken out of the byte stream by
#   kp_filter, in both tty readers: ev 2 = repeat (keeps the key fresh), ev 3 =
#   release.  The code is the unshifted key; the shift/ctrl bits are in
#   mods-1.  Pressed keys that never see a release (the window lost focus
#   mid-hold) are all released after KP_STUCK seconds with no event at
#   all, since the OS repeats the last held key while any key is down.
#   TRS80_KBPROTO: 0 = never; 1 = even in DUMB mode (the pty test); unset
#   = on at a terminal unless DUMB (a logged session stays plain).
# Why it cannot break a period program: presses are unchanged bytes; a
# program that read the matrix now reads what the machine's matrix read.
# One visible difference on such a terminal: INKEY$ no longer sees the
# terminal's auto-repeat -- which is what Level II did (no auto-repeat).
# An arrow's repeats are events; a plain key's are NOT: iTerm2 sends them
# as the plain byte again, and they reached INKEY$ as a stream (HAND_TEST
# 29, 27 `a`s for a three-second hold; ruled 2026-09-23: drop them).  So
# kp_repeat drops them in the poll reader.
function kp_on(   e) {
    e = ENVIRON["TRS80_KBPROTO"]
    return TTYIN && e != "0" && (e == "1" || !DUMB)
}

# The query goes out on every push until the terminal has answered.  It
# used to go out once: a reply that missed the first poll episode (a short
# RUN, a LIST, an arrow key at READY) was lost, and KBPROTO stayed 0 for
# the session with flag 2 still pushed (the 2026-09-19 audit, H-15).  A
# terminal without the protocol ignores the repeats as it ignored the first.
function kp_push() {
    if (!kp_on()) return
    if (!KBPROTO) printf "\033[?u"
    KPQUERIED = 1
    printf "\033[>2u"; fflush()
    KPPUSHED = 1
}

# Popping lets go of every key.  The down-set outlived the pop: the Ctrl-C
# that ended a run left BREAK down, and a key held across it stayed down
# too, until the stuck-key sweep KP_STUCK seconds after that last event --
# so a program that polled again at once (a RUN typed quickly, a menu
# loop, CONT) read BREAK as held for most of the window (the 2026-09-19
# audit, L-7; HAND_TEST 27).  Line mode takes no presses, and a key still
# held when poll mode returns is pressed again by its repeat bytes.
function kp_pop() {
    if (!KPPUSHED) return
    printf "\033[<u"; fflush()
    KPPUSHED = 0
    kp_release_all(); KPLAST = 0
}

# strip the protocol's replies and events from a record of tty bytes,
# applying them to the matrix; return the plain key bytes.  A sequence the
# read cut short is held in KPPART for the next read to complete.  `bare`
# (the poll reader) holds a trailing ESC or ESC [ too, once the terminal
# has answered: the cut can fall there as well, and the rest of the event
# arrived as keys (L-8 below).  The line reader blocks until the next
# keystroke, so a real Esc key there would wait on it; and a terminal
# without the protocol sends no events to cut: a bare ESC or ESC [ at the
# end of the read is keys for both.
function kp_filter(s, bare,   out, i, n, j, body, fin, had, cut) {
    if (!KPQUERIED) return s
    bare = bare && KBPROTO
    had = (KPPART != ""); s = KPPART s; KPPART = ""
    out = ""; n = length(s); i = 1
    while (i <= n) {
        if (substr(s, i, 2) != "\033[") {
            if (bare && i == n && substr(s, i, 1) == "\033") { KPPART = "\033"; cut = i; break }
            if (!bare || !kp_repeat(substr(s, i, 1))) out = out substr(s, i, 1)
            i++; continue
        }
        j = i + 2
        while (j <= n && index("0123456789;:?", substr(s, j, 1))) j++
        if (j > n) {
            if (bare || j > i + 2) { KPPART = substr(s, i); cut = i }   # a sequence cut by the read
            else out = out substr(s, i)                     # a bare ESC [ in line mode: keys
            break
        }
        body = substr(s, i + 2, j - i - 2); fin = substr(s, j, 1)
        if (fin == "u" && body ~ /^\?[0-9]*$/) KBPROTO = 1     # the terminal answered: it speaks it
        else if (index(body, ":") && (fin == "u" || fin ~ /^[A-D]$/)) kp_event(body, fin)
        else out = out substr(s, i, j - i + 1)                # an ordinary press sequence
        i = j + 1
    }
    if (KPPART != "" && !(had && cut == 1)) KPCUT = kp_now()   # a new cut starts the clock
    return out
}

# a plain byte that is its key's auto-repeat, not a press: the same PC key
# typed within KP_STUCK s with no release between (KPREP[key] = when it
# last typed).  A repeat keeps its key fresh, so a hold of any length is
# one press and the matrix keeps the key down; a key whose release was
# lost types again once it has been quiet for KP_STUCK s.  Never a repeat:
# Ctrl-C (BREAK must always get through), and ENTER, TAB, Backspace and
# Esc, which flag 2 gives no release (the protocol reports those only
# under flag 8), so a second tap could not be told from a repeat.
function kp_repeat(ch,   c, pk, now) {
    c = ORD[ch]
    if (c == 3 || c == 8 || c == 9 || c == 13 || c == 27 || c == 127) return 0
    if ((pk = kp_pckey(c)) < 0) return 0
    now = kp_now()
    if ((pk in KPREP) && now - KPREP[pk] <= KP_STUCK + KPSLACK) {
        KPREP[pk] = now; KPLAST = now
        return 1
    }
    KPREP[pk] = now
    return 0
}

# How long a cut sequence is held before it counts as keys.  It was
# flushed by the very next EMPTY poll, and a poll is 0.007 ms: the rest of
# the event, a write or two behind, came in after it as keys of its own --
# the release was never applied, and the fragment's scan (kb_escseq), ending
# on the next byte in 64-126, swallowed the next real keystroke (the
# 2026-09-19 audit, L-8; kbd_pty scenario 12).  A terminal writes one
# event whole, so the rest arrives within a millisecond; KP_CUTMS (100)
# is far beyond that and still below any human keystroke.  Only a real
# Esc key is ever kept that long, and only under the protocol.  Without
# the time extension the clock is systime(): 1-2 s.
function kp_cutstale() {
    if (KMCLOCK != "") return (km_now() - KPCUT) * 1000 >= KP_CUTMS
    return systime() - KPCUT >= 2
}

function kp_event(body, fin,   a, m, code, mods, ev, r, b, k) {
    split(body, a, ";"); split(a[2], m, ":")
    mods = m[1] + 0; ev = m[2] + 0
    if (mods < 1) mods = 1
    KPLAST = kp_now()
    if (fin == "u") {
        code = a[1] + 0
        if (ev == 3) delete KPREP[code]                       # the next byte of it is a press
        if (ev == 3 && code in KPKEY) {                       # what this PC key's press put down
            split(KPKEY[code], k, SUBSEP); delete KPKEY[code]
            kp_release(k[1] + 0, k[2] + 0)
            return
        }
        if (code == 127) code = 8                             # Delete: the left arrow, as its press byte is
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
    delete KPSH; KPSHIFT = 0; delete KPKEY; delete KPREP
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
    return (KBMODE == "poll") ? kb_fill_tty() : kb_fill_line()
}

function kb_fill_tty(   save, r, i, n, line) {
    save = RS; RS = "^$"
    r = (getline line < "/dev/tty")
    RS = save
    close("/dev/tty")
    if (r <= 0) {
        if (KPPART == "" || !kp_cutstale()) return 0
        line = KPPART; KPPART = ""          # a held partial that never completed: keys after all
    } else if (KPQUERIED) line = kp_filter(line, 1)
    n = length(line)
    for (i = 1; i <= n; i++) KBQ[++KT] = ORD[substr(line, i, 1)]
    return n
}

# The line-mode read goes through kp_filter as the poll does: the query's
# reply and a release event arrive whenever the terminal sends them, and
# one that lands here (the reply after a short RUN, a key let go after
# BREAK) was queued as typed bytes for rl_arrow to swallow -- the protocol
# never came on, the release was never applied (the 2026-09-19 audit,
# H-15 and L-7).  Returns the bytes READ, not the bytes queued: a read
# the filter emptied is not the end of input kb_get counts to three.
# Line mode at a TERMINAL: the editor's blocking read of /dev/tty (dd | od),
# which kb_fill_stdin below mirrors for piped stdin.  Until 2026-09-26 the
# two were kb_fill_pipe and kb_pipe_fill, one word apart, reading
# different devices (the 2026-09-23 audit's NIT).
function kb_fill_line(   cmd, ln, a, n, i, got, s) {
    cmd = "dd if=/dev/tty bs=256 count=1 2>/dev/null | od -A n -t u1 -v"
    got = 0; s = ""
    while ((cmd | getline ln) > 0) {
        n = split(ln, a, " ")
        for (i = 1; i <= n; i++) { s = s CHR[a[i] + 0]; got++ }
    }
    close(cmd)
    if (KPQUERIED) s = kp_filter(s, 0)
    n = length(s)
    for (i = 1; i <= n; i++) KBQ[++KT] = ORD[substr(s, i, 1)]
    return got
}

# pipe mode: pull the next stdin line into the queue as chars + CR
function kb_fill_stdin(   r, line, ch) {
    fflush()                    # prompt text must land before we block on stdin
    r = (getline line < "/dev/stdin")
    if (r <= 0) { EOFQUIT = 1; return 0 }
    sub(/\r$/, "", line)
    for (r = 1; r <= length(line); r++) {
        ch = substr(line, r, 1)
        KBQ[++KT] = (ch in ORD) ? ORD[ch] : 63
    }
    KBQ[++KT] = 13
    return 1
}

# blocking single byte (tty mode)
function kb_get(   tries) {
    if (!TTYIN) {
        if (KH >= KT && !kb_fill_stdin()) return -1
        return KBQ[++KH]
    }
    kb_mode("line")
    s_settle()                      # pending screen writes land before the wait
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
    diag_err("BATCH: END OF INPUT AT KEY POLL" (CLN == DIRECTLN ? "" : ", LINE " CLN))
}

# non-blocking single byte; -1 if none (used by INKEY$)
function kb_poll1() {
    if (!TTYIN) {
        if (KH >= KT) {
            if (EOFQUIT || ++INKEYEOF > 200000) { kbe_diag(); PENDBRK = 1; return -1 }
            if (!kb_fill_stdin()) { kbe_diag(); return -1 }
        }
        return KBQ[++KH]
    }
    kb_mode("poll")
    s_settle()                      # a program polling for a key is looking at the screen
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
    s_settle()                      # every BRKEVERY statements: pending screen writes land
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
    THR_SLICE = (KMCLOCK != "") ? 0.01 : 0.03      # the throttle's slice (thr_wait, p10)
    KMHOLD = (ENVIRON["TRS80_KMHOLD"] + 0 > 0) ? ENVIRON["TRS80_KMHOLD"] + 0 : (KMCLOCK != "" ? 100 : 4)
    KMR = -1; KMSH = 0
    KBPROTO = 0; KPQUERIED = 0; KPPUSHED = 0; KPPART = ""; KPSHIFT = 0; KPLAST = 0
    for (i = 0; i < 8; i++) KPDOWN[i] = 0
    # a shifted symbol's PC key, US layout: the code its release event names
    km_us("!@#$%^&*()_+{}|:\"<>?~", "1234567890-=[]\\;',./`")
    KP_CUTMS = 100                      # ms a sequence cut by the read is held (kp_cutstale)
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

function km_us(sh, un,   i) {
    for (i = 1; i <= length(sh); i++) KPUS_[ORD[substr(sh, i, 1)]] = ORD[substr(un, i, 1)]
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

# A byte consumed at a terminal, as the Model I key it meant: ESC starts a
# sequence (kb_escseq above), and 127 -- the Delete/Backspace key on a Mac
# or PC keyboard -- is the LEFT ARROW, byte 8, which IS the machine's
# backspace (row 6 bit 32).  No Model I key produces 127; the line editor
# had long taken 127 and 8 alike (readline below) while a program's INKEY$
# and the matrix saw 127 and no key, so `IF A$=CHR$(8)` never fired for the
# natural key (HAND_TEST 25, ruled 2026-09-21).  INKEY$, the timed latch
# and the release protocol's press path all come through here; a piped
# byte stream stays byte-exact and never does.
function kb_termkey(c) {
    if (c == 27) return kb_escseq()
    if (c == 127) return 8
    return c
}

# consume at most one pending byte into the latch; age the latch when idle.
# Under the release protocol (KBPROTO) every pending press byte goes into
# the down-set instead, and nothing ages: a key is up when its release
# arrives (kp_filter), or when no event at all has come for KP_STUCK s.
function km_pump(   c) {
    if (TTYIN) { kb_mode("poll"); s_settle(); if (KH >= KT) kb_fill() }
    else if (KH >= KT) {
        if (EOFQUIT || ++INKEYEOF > 200000) { kbe_diag(); PENDBRK = 1; KMR = -1; return }
        if (!kb_fill_stdin()) { kbe_diag(); KMR = -1; return }
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
    if (TTYIN) c = kb_termkey(c)                  # an arrow, Delete, or no TRS-80 key (-1)
    else if (c == 27) c = kb_escseq()             # a piped ESC [ A is still an arrow
    if (c in KMR_) km_latch(KMR_[c], KMB_[c], KMS_[c] + 0)
    else { KMR = -1; KMSH = 0 }                   # key with no matrix position
}

# one press byte under the release protocol: the key goes down and stays.
# The press is the TYPED byte and the release names the PC's UNSHIFTED key,
# and the two part company wherever the keyboards do: `:` is its own key on
# a Model I and Shift+; on a PC, so the press put down row 5 bit 4 and the
# release (code 59) let go of `;`, bit 8 -- the colon stayed down, SHIFT
# with it, until the stuck-key sweep (the 2026-09-19 audit, M-20: `: @ " &
# ( ) * +` and the Ctrl-H/J arrows).  So each press records, under the PC
# key that typed it (kp_pckey), the matrix key it put down, and the release
# lets go of exactly that -- whatever the modifiers are by then.
function kp_byte(c,   raw, pk) {
    raw = c
    if (c == 3) {
        if (brk_take()) { PENDBRK = 1; kb_flush() }
        kp_press(6, 4, 0); kp_owns(99, 6, 4); return
    }
    BRKFORCE = 0
    c = kb_termkey(c)                             # the protocol only runs at a terminal
    if (!(c in KMR_)) return
    kp_press(KMR_[c], KMB_[c], KMS_[c] + 0)
    if ((pk = kp_pckey(raw)) >= 0) kp_owns(pk, KMR_[c], KMB_[c])
}

# the PC key pk put down matrix key (r, b); a different key it held before
# (a repeat typed under another shift state) is let go first
function kp_owns(pk, r, b,   k) {
    if (pk in KPKEY && KPKEY[pk] != r SUBSEP b) {
        split(KPKEY[pk], k, SUBSEP); kp_release(k[1] + 0, k[2] + 0)
    }
    KPKEY[pk] = r SUBSEP b
}

# the kitty key code (the unshifted key) of the PC key that typed byte c,
# on the US layout the protocol's own codes assume; -1 for an escape
# sequence's byte (the arrows have their own release form, A-D)
function kp_pckey(c) {
    if (c >= 65 && c <= 90) return c + 32                          # A-Z: the letter key
    if (c >= 1 && c <= 26 && c != 9 && c != 13) return c + 96      # Ctrl-letter (TAB, ENTER are keys)
    if (c == 27) return -1
    if (c in KPUS_) return KPUS_[c]
    return c
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
    VCOL = 0                                # 0365H: the input routine zeroes 40A6H (p20)
    RLCANCEL = 0
    RLWAIT = 1                              # a waiting read shows the cursor
    sync_cursor()
    if (!TTYIN) {
        r = (getline s < "/dev/stdin")
        if (r <= 0) { EOFQUIT = 1; RLWAIT = 0; return "" }
        sub(/\r$/, "", s)
        # no cursor stops a piped line at the limit, so the cut is said out
        # loud, once: a transcript's long line must not lose its tail silently
        if (!HOSTMEM && length(s) > RLMAX) {    # whole under `memory host` (EXT); the editor keeps 240
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
                rl_draw(oldl, oldp, RLP)
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
            rl_draw(oldl, oldp, RLP - 1)
        }
    }
}

# repaint the input line after an edit, from character `from` (0-based; at
# or left of the old cursor, so the DUMB branch backspaces to it) -- the
# key just typed or deleted at the cursor, and nothing before it.  Until
# 2026-09-26 every keystroke repainted the whole line from its start, so
# a pasted line cost the square of its length in output (the 2026-09-23
# audit, L-14).  The other callers (Ctrl-A/E/U, the arrows, history,
# completion, Ctrl-L) pass nothing: from 0, the whole line, as before.
# Grid mode: repaint from the RLSTART anchor (tracking any scroll it
# causes).  Fullscreen tty mode: plain backspace/overprint -- fine up to
# the terminal width (240-char lines that wrap are a documented cosmetic
# limitation there).
function rl_draw(oldl, oldp, from,   i, nn, pre, top) {
    nn = length(RLS)
    if (DUMB) {
        for (i = oldp; i > from; i--) printf "\b"
        printf "%s", substr(RLS, from + 1)
        for (i = nn; i < oldl; i++) printf " "
        top = (nn > oldl) ? nn : oldl
        for (i = top; i > RLP; i--) printf "\b"
        fflush()
        return
    }
    pre = SCROLLS
    CUR = RLSTART + from
    s_puts(substr(RLS, from + 1))
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
# The line you see is the line that runs (the 2026-09-23 audit, L-9): a
# name holding a control byte is never offered, since on the screen it
# could hide the rest of the line; and on a cat or dir line, which the
# shell parses, a unique match the shell would take apart is inserted
# quoted (shq), so Enter runs cat on that one file.
function rl_complete(   i, c, word, cmd, line, nm, mt, lcp, j, add, oldl, oldp, out, bnd, name, q) {
    oldl = length(RLS); oldp = RLP
    nm = 0; bnd = 0
    for (i = 0; i <= RLP && nm == 0; i++) {
        if (i > 0) {
            c = substr(RLS, i, 1)
            if (!(c == " " || c == "\t" || c == "\"")) continue
        }
        word = substr(RLS, i + 1, RLP - i)
        if (word == "" || index(word, "\"") || word ~ /'/) continue
        cmd = "ls -1d -- " shq(word) "* 2>/dev/null"
        while ((cmd | getline line) > 0) {
            if (line ~ /[\001-\037\177]/) continue     # a control byte in the name: never offered
            if (nm < 100) mt[++nm] = line
        }
        close(cmd)
        if (nm) bnd = i                                # the boundary the word starts after
    }
    if (nm == 0) return
    lcp = mt[1]
    for (j = 2; j <= nm; j++)
        while (lcp != "" && substr(mt[j], 1, length(lcp)) != lcp) lcp = substr(lcp, 1, length(lcp) - 1)
    add = substr(lcp, length(word) + 1)
    # mt[1] is ls output, not typed text: the quote test above never saw
    # it, so it must be quoted for sh (a name with a ' ran as a command)
    if (nm == 1 && system("test -d " shq(mt[1])) == 0) add = add "/"
    # a unique match on a cat or dir line, after a blank (not inside a
    # "..." literal), that sh would take apart: the whole word becomes
    # one quoted sh word.  Only there: the raw name after LOAD or CLOAD
    # is not parsed by sh, so it stays as typed.
    name = word add
    if (nm == 1 && bnd > 0 && substr(RLS, bnd, 1) != "\"" && RLS ~ /^[ \t]*(cat|dir)[ \t]/ \
        && name ~ /[^A-Za-z0-9._\/+,:@%=-]/) {
        q = shq(name)
        if (oldl - length(word) + length(q) > RLMAX) return
        RLS = substr(RLS, 1, bnd) q substr(RLS, RLP + 1)
        RLP = bnd + length(q)
        rl_draw(oldl, oldp)
        return
    }
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
