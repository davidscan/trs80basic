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
            if (!isN(v) && !isN(r)) {
                # ROM 299CH-29A5H adds the two lengths in a byte and takes
                # a carry to ?LS: a string is at most 255 characters, and
                # the store never happens.  Until 2026-09-24 strings grew
                # without bound, so the VARPTR length byte held the length
                # mod 256 and a handler written for ?LS never fired (H-2).
                if (length(v) + length(r) - 2 > 255) { raise(15); return v }
                v = "S" vstr(v) vstr(r); continue
            }
            if (isN(v) != isN(r)) { raise(13); return v }
            x = num(v) + num(r)
        } else {
            if (!isN(v) || !isN(r)) { raise(13); return v }
            x = num(v) - num(r)
        }
        if (x >= FMAX || x <= -FMAX) { raise(6); return v }
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
        if (x >= FMAX || x <= -FMAX) { raise(6); return v }
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
        if (x >= FMAX || x <= -FMAX) { raise(6); return v }
        v = "N" x
    }
    return v
}

# right-hand side of ^.  ^ itself is left-associative (2^3^2 is 64), but a
# MINUS where the operand should be is the ROM's unary minus (2532H): it
# evaluates what follows at precedence 7DH -- below ^ (7FH), above * and /
# (7CH) -- and negates that.  So 2^-3^2 is 2^-(3^2), and 2^-3*2 is
# (2^-3)*2.  e_un is that evaluation.  Until 2026-09-21 the minus bound
# to the 3 alone and 2^-3^2 was (2^-3)^2.  A plus is only skipped (24B0H):
# 2^+3^2 stays (2^3)^2.
function e_powrhs(   v) {
    if (TY[CK, CP] == "o" && TK[CK, CP] == "-") return e_un()
    if (TY[CK, CP] == "o" && TK[CK, CP] == "+") { CP++; return e_powrhs() }
    return e_prim()
}

function e_prim(   t, s, v, key) {
    t = TY[CK, CP]
    if (t == "n") {
        # 1.5% and 32768%: % is taken only behind an integer (tk_number,
        # p50; ROM 0EEE-0EEF, JP P,1997H)
        if (TSX[CK, CP] == "%SN") { raise(2); return "N0" }
        s = TK[CK, CP] + 0; CP++
        if (s >= FMAX || s <= -FMAX) { raise(6); return "N0" }   # 1.70142E38, 1E39 (p10 FMAX)
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
        # a REM token where an operand is expected is ?SN, as at 2337H:
        # PRINT A REM X used to print A and take the REM as the list's
        # end, and here REM would read as a variable (the 2026-09-23
        # audit, L-10).  ' is :REM, so a remark after a colon is untouched.
        # The other statement keywords as operands are the keyword-
        # crunching rule's business (M-2), not this line's.
        if (s == "REM")    { raise(2); return "N0" }
        if (s == "ERR")    { CP++; return "N" ERRV }
        if (s == "ERL")    { CP++; return "N" ERLV }
        if (s == "MEM")    { CP++; return "N" mem_free() }           # 27C9H (p75)
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
        # TAB is the token only as TAB( -- TAB (5) with a blank is the
        # variable TAB, an array here (trs-80.com's bug 7c; TKW, p50)
        if (index(FNLIST, " " s " ") > 0 && (s != "TAB" || TKW[CK, CP])) return fncall(s)
        # any other keyword token where an operand is expected is ?SN, as
        # at 2337H (PRINT 1END, X=END): a variable is never spelled like a
        # keyword, since the tokenizer takes the keyword out of the name
        # (TOTAL is TO TAL, p50).  It read as a variable of that name
        # before 2026-09-25 (the L-10 remainder).
        if (TKW[CK, CP]) { raise(2); return "N0" }
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
        # ROM 1E45-1E4C: the subscript evaluator returns only for a POSITIVE
        # value; a negative one is ?FC there and then, before the dimension
        # count or the bound is looked at.  (Seen, not followed: 2B02H
        # converts through CINT, so a subscript past 32767 is ?OV on the
        # machine where it is ?BS here.)
        if (idx < 0) { raise(5); return "" }
        nd++; idxs[nd] = idx
        if (TY[CK, CP] == "o" && TK[CK, CP] == ",") { CP++; continue }
        break
    }
    if (TY[CK, CP] == "o" && TK[CK, CP] == ")") CP++
    else { raise(2); return "" }
    if (!(name in ADIM)) {
        if (!mem_need(6 + 2 * nd + 11 ^ nd * (strname(name) ? 3 : mem_numsize(name)))) return ""   # ?OM (p75)
        ADIM[name] = nd
        for (i = 1; i <= nd; i++) ASZ[name, i] = 10
    }
    if (ADIM[name] != nd) { raise(9); return "" }
    key = name
    for (i = 1; i <= nd; i++) {
        if (idxs[i] > ASZ[name, i]) { raise(9); return "" }
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
function fncall(name,   v, a1, a2, a3, na, x, s, i, j, r) {
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
        # ROM 1439-1454.  EXP works on t = x * 1/ln 2 and overflows twice
        # over: at 144A when the exponent byte of that product has reached
        # 88H, which is |t| >= 128; and at 1454 when INT(t) has reached
        # 126, because the series is scaled by 2 ** (INT(t) + 1) and 2^127
        # is past the top of a single.  So the ceiling is 126*ln 2 =
        # 87.3365 -- the value itself is only 8.5E+37 there, half of what
        # a single holds, and EXP(88) IS ?OV on the machine (the audit's
        # L-24 read the ceiling off the float range instead).  Both exits
        # go to 0931H, which TESTS THE SIGN first (0931-093B: CALL 0955H,
        # CPL, OR A, JP P,0778H) -- a negative argument leaves through
        # 0778H with a result of zero, and only a positive one reaches the
        # ?OV at 07B2H.  So below -128*ln 2 = -88.7228 the answer is a
        # quiet 0.  (The L-24 fix made it ?OV for a day: it followed 144A
        # to 0931H and did not read what 0931H does.)
        r = x / 0.6931471805599453
        if (r <= -128) return "N0"
        if (bfloor(r) >= 126) { raise(6); return "N0" }
        return "N" exp(x)
    }
    if (name == "RND") {
        # authentic ROM sequence (rnd_next/sngl, p90): RND(0) = seed'/2^24,
        # RND(n) = INT(RND(0)*n + 1) with the multiply rounded to single
        # precision.  The argument goes through CINT first (14C9H -> 0A7FH:
        # rounded down, ?OV outside -32768..32767, so RND(32768) is ?OV);
        # then a negative one is ?FC at 14CEH (the ROM does NOT reseed on
        # negative).  Until 2026-09-25 RND(32768) returned a number.
        x = numarg(a1, na); if (E) return "N0"
        i = to16(x); if (E) return "N0"
        if (i < 0) { raise(5); return "N0" }
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
    if (name == "PEEK") { x = numarg(a1, na); if (E) return "N0"; x = addrarg(x); if (E) return "N0"; return "N" dopeek(x) }
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
    if (name == "POS") { x = numarg(a1, na); if (E) return "N0"; return "N" VCOL }   # 27F5H: 40A6H (p20)
    if (name == "FRE") {                    # 27D4H: a number asks about free memory, a string about the string area (p75)
        if (na < 1) { raise(2); return "N0" }
        return "N" (isN(a1) ? mem_free() : mem_strfree())
    }
    if (name == "LEN") { s = strarg(a1, na); if (E) return "N0"; return "N" length(s) }
    if (name == "ASC") {
        s = strarg(a1, na); if (E) return "N0"
        if (s == "") { raise(5); return "N0" }
        s = substr(s, 1, 1)
        return "N" ((s in ORD) ? ORD[s] : 63)
    }
    if (name == "VAL") { s = strarg(a1, na); if (E) return "N0"; x = valnum(s, 1); if (E) return "N0"; return "N" x }
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
    # LEFT$'s and RIGHT$'s count, MID$'s position and its count are bytes
    # by the ROM's rule (2568H and 2AADH -> 2B1CH): rounded down, ?OV
    # outside the integer range, then ?FC unless 0-255 (byteconv, p80).
    # Until 2026-09-25 any count was taken, so LEFT$(A$,256) was A$.
    if (name == "LEFT$") {
        s = strarg2(a1, na); x = bytearg2(a2, na); if (E) return "N0"
        return "S" substr(s, 1, x)
    }
    if (name == "RIGHT$") {
        s = strarg2(a1, na); x = bytearg2(a2, na); if (E) return "N0"
        if (x > length(s)) x = length(s)
        return "S" (x == 0 ? "" : substr(s, length(s) - x + 1))
    }
    if (name == "MID$") {
        s = strarg2(a1, na); x = bytearg2(a2, na); if (E) return "N0"
        if (x < 1) { raise(5); return "N0" }              # 2AA1H
        if (na >= 3) {
            if (!isN(a3)) { raise(13); return "N0" }
            i = byteconv(num(a3)); if (E) return "N0"
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
        raise(55); return "N0"
    }
    if (name == "LOF") {
        x = numarg(a1, na); if (E) return "N0"
        i = fio_fnchan(x); if (E) return "N0"
        if (FH_MODE[i] == "R") return "N" (FH_NREC[i] + 0)
        # Disk manual, LOF: "the number of the last, i.e., highest numbered,
        # record in a file.  It is useful for both sequential and random
        # access."  A sequential file's records are the 256-byte physical
        # ones (it has no logical record length of its own), so the answer
        # is its length rounded up.  It used to be ?BM on anything but "R".
        if (FH_MODE[i] == "I" || FH_MODE[i] == "O" || FH_MODE[i] == "E") {
            if (FH_MODE[i] != "I") fflush(FH_NAME[i])    # our own writes first
            j = host_size(FH_NAME[i])
            if (j < 0) { raise(55); return "N0" }
            return "N" int((j + 255) / 256)
        }
        raise(55); return "N0"                  # "A": the AI link has no records
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
function bytearg2(a, na) {
    if (na < 2) { raise(2); return 0 }
    if (!isN(a)) { raise(13); return 0 }
    return byteconv(num(a))
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
# the first time, deltas after) -- the frame the shim SENDS, dumped by
# z80_usr (p77) beside the send, or built for the dump alone when the
# stub answers.  Until 2026-09-25 the dump built a frame of its own here,
# ahead of the shim's: with a core that frame took a generation and the
# dirty sets, so the wire carried gen 1, 3, 5 and an empty delta, and the
# core answered NEED with a full frame every call.  Diagnostic only;
# programs/tests/usr.sh asserts on both.
# `entry`, when given, overrides the vector: SYSTEM's `/nnnnn` runs the
# address the monitor was given, not a DEFUSR vector, and the trace has to
# name what will actually run.  sys_exec used to resolve first and assign
# USR_ENTRY afterwards, so the line printed the 408EH vector's entry -- or
# "undefined" -- for a call that went somewhere else entirely (the
# 2026-09-19 audit, L-50).
function usr_resolve(name, arg, entry) {
    USR_SLOT = usr_slot(name); USR_ARG = arg
    USR_ENTRY = (entry == "") ? usr_entry(USR_SLOT) : entry + 0
    if (USR_TRACE == "") {
        USR_TRACE = ("TRS80_USR_TRACE" in ENVIRON && ENVIRON["TRS80_USR_TRACE"] != "") ? ENVIRON["TRS80_USR_TRACE"] + 0 : 0
        USR_STRICT = (ENVIRON["TRS80_USR"] == "strict")
    }
    if (USR_TRACE) printf "USR slot=%d entry=%s arg=%s\n", USR_SLOT, (USR_ENTRY < 0 ? "undefined" : USR_ENTRY), arg > "/dev/stderr"
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
    # at a terminal an arrow key is the Model I's one byte, not ESC [ A, and
    # Delete is the left arrow (p30 kb_termkey); piped input is a byte
    # stream and stays as sent
    if (TTYIN) { c = kb_termkey(c); if (c < 0) return "S" }
    return "S" CHR[c]
}

# FNLIST is initialized in init_tables (single BEGIN block runs everything)
