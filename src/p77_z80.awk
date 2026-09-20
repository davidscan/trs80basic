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
function z80_run(x,   hl, res, k, brk, i, vid) {
    vid = 0
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
        if (Z80LINE ~ /^RET /) {
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
