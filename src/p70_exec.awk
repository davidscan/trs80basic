# ===================== execution engine and control flow ====================

function exec_immediate(line) {
    tokline("I", line)
    CK = "I"; CLI = 0; CLN = DIRECTLN; CP = 1
    E = 0; HALT = 0; STOPPED = 0
    usr_stub_reset()
    execloop()
    if (E) report_err()
    usr_stub_notice()                       # one stderr line per run (p60)
}

function setline(i) {
    CLI = i; CLN = LNS[i]; CK = CLN ""
    if (!(CK in TOKD)) tokline(CK, runtext(CLN))
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
            # ROM 19C9H-19CDH: before the handler test, the error routine
            # saves the line and the statement that failed in 40F5H/40F7H
            # -- the CONT point, the same cells STOP and END fill -- unless
            # the statement was typed at READY (19C7H: the line is FFFFH),
            # which leaves an earlier STOP's point alone.  So CONT after an
            # error re-runs the failing statement, trapped or not; until
            # 2026-09-24 a reported error made CONT ?CN (H-1).
            if (SK != "I") { CONT_K = SK; CONT_LI = SLI; CONT_P = SCP; CONTOK = 1 }
            # 19D0H-19E0H: a handler that is armed and not already running
            # takes the error, whether the statement is a program's or one
            # typed at READY (the ROM's test skips only the CONT save for
            # line FFFFH, and END does not disarm the trap); ERL is then
            # 65535, and RESUME goes on in the typed line.  Until
            # 2026-09-24 a typed statement's error was never trapped (M-6).
            if (EHANDLER && !INHANDLER) {
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
    if (BATCH) diag("BREAK" inln(CLN))      # not program output: stderr
    else { s_fresh(); s_puts("BREAK" inln(CLN)); s_nl() }   # ROM 1DD7H: no blank line from column 0
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
        if (tx == "DEFINT" || tx == "DEFSNG" || tx == "DEFDBL" || tx == "DEFSTR") { CP++; st_deftype(tx == "DEFINT" ? 2 : tx == "DEFSTR" ? 3 : tx == "DEFDBL" ? 8 : 4); return }
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
function st_let(   name, key, v, lp, src, j, n) {
    if (TY[CK, CP] != "i") { raise(2); return }
    name = lvname()
    key = ""
    if (TY[CK, CP] == "o" && TK[CK, CP] == "(") {
        key = aref(name); if (E) return
    }
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == "=")) { raise(2); return }
    CP++
    # a string literal, or a plain string variable, alone on the right in a
    # program line: the ROM leaves the string where it is (1F46H-1F57H)
    lp = 0
    if (CK != "I" && (TY[CK, CP] == "s" || TY[CK, CP] == "i") && strname(name)) {
        CP++; if (at_stmt_end()) lp = CP - 1; CP--
    }
    v = e_or(); if (E) return
    assignv(name, key, v)
    if (lp && !E) {
        if (TY[CK, lp] == "s") {
            for (j = 1; j <= lp; j++) if (TY[CK, j] == "s") n++
            src = lit_spec(CK + 0, "s", n, 0)
        } else src = lit_of("V" TK[CK, lp])
        if (src != "") lit_note((key != "") ? "A" key : "V" name, src)
    }
}

# DEFSTR/DEFINT/DEFSNG/DEFDBL letter[-letter][,...]: per-letter default type.
# The ROM keeps one type byte per letter at 4101H-411AH (2 integer, 3
# string, 4 single, 8 double; RUN and CLEAR set all 26 to 4).  DEFT holds
# those bytes (absent = 4) and PEEK/POKE reach them (sv_peek/sv_poke, p75);
# DEFS and DEFI are the two the interpreter acts on -- a string name, and an
# integer one whose stores round down (LET through 0A7FH).  Single and
# double precision are the same here.
# RUN/NEW/program load reset the table (clear_vars); CLEAR keeps it, so
# DEFSTR A: CLEAR 500: A="X" stays typed.
function deftype(l, code) {
    DEFT[l] = code; DEFS[l] = (code == 3); DEFI[l] = (code == 2)
}

function st_deftype(code,   a, b, c) {
    for (;;) {
        if (TY[CK, CP] != "i" || TK[CK, CP] !~ /^[A-Z]$/) { raise(2); return }
        a = TK[CK, CP]; CP++
        b = a
        if (TY[CK, CP] == "o" && TK[CK, CP] == "-") {
            CP++
            if (TY[CK, CP] != "i" || TK[CK, CP] !~ /^[A-Z]$/) { raise(2); return }
            b = TK[CK, CP]; CP++
        }
        for (c = ORD[a]; c <= ORD[b]; c++) deftype(CHR[c], code)
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

# The name a store is about to write, read at CP (which moves past it).
# LVI says whether the ROM would hold it as an INTEGER: a % suffix, or no
# suffix and a DEFINT letter (! and # override DEFINT, as on the machine).
# assignv reads LVI and clears it, so a store that did not come through
# here is never rounded.
function lvname(   s) {
    s = TK[CK, CP]
    LVI = intvar(s, TSX[CK, CP])
    CP++
    return s
}

function intvar(name, sx) {
    if (name ~ /\$$/ || sx == "!" || sx == "#") return 0
    return sx == "%" || DEFI[substr(name, 1, 1)]
}

# A value stored into an integer variable: LET converts through 0A7FH
# (2819H, table 18A5H), which rounds DOWN, so I=7/2 is 3 and I=-2.5 is -3,
# and a result outside -32768..32767 is ?OV there (0A8AH pushes 07B2H):
# nothing is stored.  READ and INPUT reach the same conversion (224AH ->
# 1F33H), so a typed 40000 is ?OV, not ?REDO.
function intstore(x,   r) {
    r = bfloor(x)
    if (r > 32767 || r < -32768) { raise(6); return 0 }
    return r
}

function assignv(name, key, v,   isint) {
    isint = LVI; LVI = 0
    if (strname(name)) {
        if (isN(v)) { raise(13); return }
        if (ALN) al_clear(name, key)            # the descriptor moves (p75, finding 7)
        delete LITA[(key != "") ? "A" key : "V" name]   # a literal it noted (p75)
        if (FLDANY) fld_detach(name, key)       # ... and out of a FIELD's buffer (p85)
        if (key != "") VA[key] = v; else SV[name] = vstr(v)
        if (length(VPDATA)) sp_grown(name, key)  # a VARPTRed string that outgrew its cells (p75)
    } else {
        if (!isN(v)) { raise(13); return }
        v = isint ? intstore(num(v)) : num(v)
        if (E) return
        if (key != "") VA[key] = "N" v; else NV[name] = v
    }
}

# ---- control flow ----------------------------------------------------------
# The line number behind GOTO, GOSUB, RUN n and IF's THEN/ELSE, as the
# ROM's one reader takes it (1E5AH; GOSUB and RUN n join the GOTO code at
# 1EC1H, IF jumps to 1EC2H from 2050H).  It starts at 0 and stops at the
# first byte that is not a digit, so a bare GOTO, or GOTO X, is GOTO 0;
# and a value that would pass 65529 is ?SN (1E62H-1E66H), so GOTO 70000
# is ?SN, never ?UL.  Until 2026-09-25 a bare GOTO was ?SN and GOTO 70000
# was ?UL (the 2026-09-23 audit, L-5).
function lineno_arg(   ln) {
    if (TY[CK, CP] != "n") return 0
    ln = TK[CK, CP] + 0; CP++
    if (ln > 65529) { raise(2); return 0 }
    return ln
}

function st_goto(   ln) {
    ln = lineno_arg(); if (E) return
    jumpline(ln)
}

function st_gosub(   ln) {
    ln = lineno_arg(); if (E) return
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
    CLN = (CK == "I") ? DIRECTLN : CK + 0
}

function st_for(   name, v0, v1, stp, j, v, isint) {
    if (TY[CK, CP] != "i") { raise(2); return }
    name = TK[CK, CP]
    if (strname(name)) { raise(13); return }
    isint = intvar(name, TSX[CK, CP])
    CP++
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == "=")) { raise(2); return }
    CP++
    v = e_or(); if (E) return
    if (!isN(v)) { raise(13); return }
    # an integer index runs an integer loop: the start through LET (1CA6H ->
    # 1F21H, stored before TO is read), TO through 0A7FH (1CD7H), STEP
    # through 2B01H -- each rounded down, each ?OV out of range
    v0 = num(v)
    if (isint) { v0 = intstore(v0); if (E) return }
    NV[name] = v0
    if (!(TY[CK, CP] == "i" && TK[CK, CP] == "TO")) { raise(2); return }
    CP++
    v = e_or(); if (E) return
    if (!isN(v)) { raise(13); return }
    v1 = num(v)
    if (isint) { v1 = intstore(v1); if (E) return }
    stp = 1
    if (TY[CK, CP] == "i" && TK[CK, CP] == "STEP") {
        CP++
        v = e_or(); if (E) return
        if (!isN(v)) { raise(13); return }
        stp = num(v)
        if (isint) { stp = intstore(stp); if (E) return }
    }
    for (j = FSN; j > for_floor(); j--)
        if (FS_V[j] == name) { FSN = j - 1; break }
    FSN++
    FS_V[FSN] = name; FS_L[FSN] = v1; FS_S[FSN] = stp; FS_I[FSN] = isint
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

function do_next(name,   j, v, fl, d) {
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
    # an integer index steps by integer addition (22F9H); a sum past
    # -32768..32767 is ?OV and the index keeps its value (2301H), so
    # FOR I%=32760 TO 32767 stops at the NEXT after 32767, as on the machine
    if (FS_I[j] && (v > 32767 || v < -32768)) { raise(6); return 0 }
    NV[FS_V[j]] = v
    # the loop goes on unless the sign of (index - limit) is the STEP's
    # sign: 2310H compares the new index with the limit, 2315H subtracts
    # the sign flag FOR pushed (1D11H: +1 or -1 from 0955H/099EH, 0 for a
    # zero step) and 2319H leaves on zero.  So a STEP 0 loop ends when the
    # index EQUALS the limit: FOR I=5 TO 5 STEP 0 runs once and FOR I=7
    # TO 5 STEP 0 never ends.  Until 2026-09-25 STEP 0 counted as positive.
    d = v - FS_L[j]
    if (((d > 0) - (d < 0)) != ((FS_S[j] > 0) - (FS_S[j] < 0))) {
        CK = FS_K[j]; CLI = FS_LI[j]; CP = FS_P[j]
        CLN = (CK == "I") ? DIRECTLN : CK + 0
        return 1
    }
    FSN = j - 1
    return 0
}

function st_if(   v, truth, hadkw, d, p, ty, tx, ln) {
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
        if (TY[CK, CP] == "n") { ln = lineno_arg(); if (!E) jumpline(ln); return }
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
                if (TY[CK, CP] == "n") { ln = lineno_arg(); if (!E) jumpline(ln) }
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
        n = TK[CK, CP] + 0; CP++
        # ROM 1F7A-1F80: a target other than 0 is looked up at 1B2AH WHEN
        # THE STATEMENT RUNS, and a line that is not there is ?UL then --
        # not later, when an error finally fires and the handler is wanted.
        if (n != 0 && !(n in LIDX)) { raise(8); return }
        EHANDLER = n
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

# ROM 1DD4-1DDE: a new line if the cursor is not at the start of one
# (20F9H), then BREAK, then " IN n" unless the line is 65535 -- so a STOP
# typed at the prompt prints a bare BREAK (until 2026-09-21: nothing).
function st_stop() {
    if (BATCH) diag_err("BREAK" inln(CLN))  # not program output: stderr
    else { s_fresh(); s_puts("BREAK" inln(CLN)); s_nl() }
    if (CK != "I") {
        CONT_K = CK; CONT_LI = CLI; CONT_P = CP
        CONTOK = 1
    }
    STOPPED = 1
}

function st_cont() {
    if (!CONTOK) { raise(17); return }
    CONTOK = 0
    CK = CONT_K; CLI = CONT_LI; CP = CONT_P
    CLN = (CK == "I") ? DIRECTLN : CK + 0
    if (CK != "I" && !(CK in TOKD)) tokline(CK, runtext(CLN))
}

function st_run(   n, f, keep, given) {
    if (fname_is_expr()) {              # Disk BASIC RUN "file"[,R]; the name is an expression (p40)
        f = parse_fname(); if (E) return
        keep = 0
        if (TY[CK, CP] == "o" && TK[CK, CP] == ",") {
            CP++
            if (TY[CK, CP] == "i" && TK[CK, CP] == "R") { CP++; keep = 1 }
            else { raise(2); return }
        }
        if (!host_found(f)) return            # 54, File not found (p40)
        if (!prog_load(f, 0, keep)) { raise(22); return }
        run_start(0, keep)
        return
    }
    n = 0; given = 0
    if (TY[CK, CP] == "n") { given = 1; n = lineno_arg(); if (E) return }
    run_start(n, 0, given)
}

# shared RUN startup (st_run, and LOAD "file",R).  given: RUN n was typed
# with its number, which then goes through the GOTO code after the
# variables are cleared (1EA9H -> 1EC1H), so a line that is not there is
# ?UL from 1ED9H -- RUN 0 with no line 0, or RUN 10 in an empty program
# (until 2026-09-25 the first ran from the lowest line and the second was
# silent).  Plain RUN in an empty program is READY (1B5DH).
function run_start(n, keepfiles, given) {
    clear_vars(keepfiles)
    if (DATADIRTY) datascan()
    DP = 1
    EHANDLER = 0; INHANDLER = 0; ERRV = 0; ERLV = 0
    CONTOK = 0
    if (given) { jumpline(n); return }
    if (NL == 0) { HALT = 1; return }
    setline(1)
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
    # ROM 1FF4-2005.  The code goes through the byte evaluator at 2B1CH --
    # the same one POKE's value uses -- so anything outside 0-255 is ?FC
    # (?OV outside the integer range, as byteconv has it since ruling 7);
    # then 0 is ?FC at 1FF9, and a code past the table is ?UE at 2003.
    # The ROM's table ends at 23 (2(n-1) < 45 at 1FFF).  The file errors
    # sit at Disk BASIC's 51-70 (p10) but ERROR cannot raise them: "Disk
    # errors cannot be simulated via the ERROR statement" (Model III Disk
    # System manual p.156), so past 23 -- the gaps and 51-70 alike -- is
    # ?UE.  Until 2026-09-21 they were 24-31 and ERROR 24-31 named them.
    n = byteconv(num(v)); if (E) return
    if (n == 0) { raise(5); return }
    if (n > NERRC) { raise(20); return }
    raise(n)
}

function st_resume(   p, ty, tx) {
    if (!INHANDLER) { raise(19); return }
    INHANDLER = 0
    if (TY[CK, CP] == "i" && TK[CK, CP] == "NEXT") {
        CP++
        CK = ERR_K; CLI = ERR_LI; CP = ERR_CP
        CLN = (CK == "I") ? DIRECTLN : CK + 0
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
            CLN = (CK == "I") ? DIRECTLN : CK + 0
            return
        }
        jumpline(p)
        return
    }
    CK = ERR_K; CLI = ERR_LI; CP = ERR_CP
    CLN = (CK == "I") ? DIRECTLN : CK + 0
}
