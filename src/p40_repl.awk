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
    DATADIRTY = 1; CONTOK = 0
}

function delline(ln) {
    delete prog[ln]; delete ESC[ln]
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
function sys_load(name,   f, data, i, c) {
    f = sys_find(name)
    if (f == "") return ""
    data = SLURPED; SLURPED = ""
    i = index(data, CHR[165])                     # A5H: the tape's sync byte
    if (i > 0 && substr(data, i + 1, 1) == CHR[85]) return sys_load_cas(data, i + 8)
    c = ORD[substr(data, 1, 1)]
    if (c == 1 || c == 2 || c == 5 || c == 7 || c == 31) return sys_load_cmd(data)
    return "F"
}

function sys_load_cas(data, i,   n, c, cnt, a, sum, j, b, got) {
    n = length(data); got = 0
    while (i <= n) {
        c = ORD[substr(data, i, 1)]
        if (c == 60) {                            # 3CH: a data block
            cnt = ORD[substr(data, i + 1, 1)]; if (cnt == 0) cnt = 256
            if (i + 4 + cnt > n) return "C"
            a = ORD[substr(data, i + 2, 1)] + 256 * ORD[substr(data, i + 3, 1)]
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
    return got ? 1 : "C"
}

function sys_load_cmd(data,   n, i, t, ln, a, j, got) {
    n = length(data); i = 1; got = 0
    while (i + 1 <= n) {
        t = ORD[substr(data, i, 1)]; ln = ORD[substr(data, i + 1, 1)]
        if (t == 1 && ln <= 2) ln += 256
        if (i + 1 + ln > n) return "F"
        if (t == 1) {
            a = ORD[substr(data, i + 2, 1)] + 256 * ORD[substr(data, i + 3, 1)]
            for (j = 0; j < ln - 2; j++) { poke_byte((a + j) % 65536, ORD[substr(data, i + 4 + j, 1)]); got++ }
        } else if (t == 2) {
            if (ln < 2) return "F"
            SYSENTRY = ORD[substr(data, i + 2, 1)] + 256 * ORD[substr(data, i + 3, 1)]
            return got ? 1 : "F"
        } else if (!(t == 5 || t == 7 || t == 16 || t == 26 || t == 31)) return "F"
        i += 2 + ln
    }
    return got ? 1 : "F"
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
    else to_ready()
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
function prog_load(f, verify, keepfiles, merge,   l, r, ln, rest, bad, x, nseen, ok, pln, rpt, ra, ri, nn, data) {
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
    SLURPED = ""
    r = (getline l < f); pln = 1
    if (r < 0) return 0
    if (!verify) {
        if (!merge) { for (x in prog) { inval_cache(x); delete prog[x] }; delete ESC }
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
                } else { prog[ln] = rest; delete ESC[ln]; inval_cache(ln); LASTLN = ln }
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
