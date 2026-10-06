# ===================== expression evaluator =================================
# Values: "N<t><number>" or "S<string>", where t is the number's TYPE as
# the ROM holds it: I integer (16 bits), S single (24-bit mantissa), D
# double (56 bits, held as a payload: p91).    Since 2026-09-26
# (the 2026-09-23 audit, M-15 and L-16: printing and arithmetic go by
# type).  A literal is typed by the ROM's reader (tk_number, p50); a
# variable by its NAME at the reference (ntype, p70: the suffix, else the
# DEF table, else single); an operation by the wider operand, I < S < D
# (ptype), except that / and ^ are never integer.  NV[] and VA[] hold raw
# numbers: the type is the name's.  Precedence (LEVEL II):
#   ^  unary-  * /  + -  relational  NOT  AND  OR

function num(v) { return substr(v, 3) + 0 }
# what fmtnum takes: a double's payload (p91), else the number
function fnum(v) { return (substr(v, 2, 1) == "D") ? substr(v, 3) : substr(v, 3) + 0 }
function vtype(v) { return substr(v, 2, 1) }
function ptype(a, b,   ta, tb) {
    ta = substr(a, 2, 1); tb = substr(b, 2, 1)
    return (ta == "D" || tb == "D") ? "D" : (ta == "S" || tb == "S") ? "S" : "I"
}
function vstr(v) { return substr(v, 2) }
function isN(v) { return substr(v, 1, 1) == "N" }

# The "b" token (p50): a blank behind a # ! % literal, where the ROM's
# evaluator stops.  The verbs that read a value through 2B1CH (a byte:
# ON, POKE's value, OUT, SET, RESET, TAB(, the counts of STRING$, LEFT$,
# RIGHT$ and MID$) and CLEAR's count go on past it; every other reader
# meets it where it wanted ")", THEN, TO, "," or the end: ?SN.  The PRINT
# list takes what follows as a new item.
function skipblank() { if (TY[CK, CP] == "b") CP++ }

function e_or(   v, r) {
    v = e_and()
    while (!E && TY[CK, CP] == "i" && TK[CK, CP] == "OR") {
        CP++; r = e_and(); if (E) return v
        v = "NI" bor16(v, r)
    }
    return v
}

function e_and(   v, r) {
    v = e_not()
    while (!E && TY[CK, CP] == "i" && TK[CK, CP] == "AND") {
        CP++; r = e_not(); if (E) return v
        v = "NI" band16(v, r)
    }
    return v
}

function e_not(   v) {
    if (TY[CK, CP] == "i" && TK[CK, CP] == "NOT") {
        CP++
        v = e_not(); if (E) return v
        if (!isN(v)) { raise(13); return v }
        return "NI" (-(to16(num(v)) + 1))
    }
    return e_rel()
}

# The ROM collects EVERY consecutive relational character into one flag
# (234DH-2362H): 1 for >, 2 for =, 4 for <, XORed in one at a time with
# blanks between them skipped by RST 10H -- so 1 < = > 2 is legal (flag 7,
# true whatever the compare says) and only a REPEATED character (<<, ==,
# >>, <=<) reaches ?SN at 1997H.  The tokenizer folds the common pairs
# (<= =< >= => <> ><) into one token; any longer run is merged here.
function e_rel(   v, r, op, a, b, c, f, nb) {
    v = e_add()
    while (!E && TY[CK, CP] == "o" && TK[CK, CP] ~ /^(=|<|>|<=|>=|<>)$/) {
        f = 0
        while (TY[CK, CP] == "o" && (op = TK[CK, CP]) ~ /^(=|<|>|<=|>=|<>)$/) {
            nb = (op == ">") ? 1 : (op == "=") ? 2 : (op == "<") ? 4 : \
                 (op == "<=") ? 6 : (op == ">=") ? 3 : 5
            if (and(f, nb)) { raise(2); return v }
            f = or(f, nb); CP++
        }
        r = e_add(); if (E) return v
        if (isN(v) != isN(r)) { raise(13); return v }
        if (isN(v) && (vtype(v) == "D" || vtype(r) == "D")) { a = dcmp(substr(v, 3), substr(r, 3)); b = 0 }   # a double's 56 bits (p91)
        else if (isN(v)) { a = num(v); b = num(r) } else { a = vstr(v); b = vstr(r) }
        c = (and(f, 1) && a > b) || (and(f, 2) && a == b) || (and(f, 4) && a < b)
        v = "NI" (c ? -1 : 0)
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
                if (!HOSTMEM && length(v) + length(r) - 2 > 255) { raise_host(15); return v }   # unbounded under `memory host` (EXT)
                v = "S" vstr(v) vstr(r); continue
            }
            if (isN(v) != isN(r)) { raise(13); return v }
            if (ptype(v, r) == "D") { x = dadd(substr(v, 3), substr(r, 3)); if (E) return v; v = "ND" x; continue }   # the double add (0C77H; p91)
            x = (ptype(v, r) == "S") ? sadd(num(v), num(r)) : num(v) + num(r)
        } else {
            if (!isN(v) || !isN(r)) { raise(13); return v }
            if (ptype(v, r) == "D") { x = dadd(substr(v, 3), dneg(substr(r, 3))); if (E) return v; v = "ND" x; continue }   # 0C70H: the sign turned, then the add
            x = (ptype(v, r) == "S") ? sadd(num(v), -num(r)) : num(v) - num(r)
        }
        v = "N" tresult(ptype(v, r), x); if (E) return v
    }
    return v
}

# The typed result of + - * (and unary minus): an INTEGER result that
# leaves 16 bits is silently converted to single (0BD0H-0BDDH: "underflows
# convert to SP"), never ?OV; a SINGLE result is rounded to 24 bits
# (sround); a single or double result past its type's limit (FMAX/DMAX,
# p10) is ?OV and below 2^-128 is 0 (frange).  Returns "<t><x>" behind
# the caller's "N".
function tresult(t, x) {
    if (t == "I") {
        if (x <= 32767 && x >= -32768) return "I" x
        t = "S"
    }
    x = frange(x, t); if (E) return "I0"
    if (t == "S") x = sround(x)
    return t x
}

# INT as the ROM's 0B37H: an integer is returned as it is; below 32768
# in magnitude the value goes through the 16-bit conversion (0B3DH for a
# single, 0B5FH JP C,0A7FH for a double) and comes back an INTEGER --
# for a double that conversion is CSNG first (0A87H -> 0AB9H -> 0796H),
# so INT(2.9999999#) is 3 and INT(32767.9999999#), which rounds to
# 32768, is ?OV (0AA3H -> 07B2H; only a rounded -32768 is taken, 0AACH):
# ROM bug 5a's mechanism.  From 32768 up the integer part is taken in
# the value's own type (0B40H's 24-bit conversion for a single, 0B78H
# for a double), exactly.  Until 2026-09-27 INT floored the raw value
# and kept its type (the 2026-09-26 audit, L-8).  FIX (0B26H) is INT of
# the magnitude, negated back (097BH: an integer -32768 overflows into
# a single at 0C5BH).
function fn_int(v,   t, x) {
    t = vtype(v); if (t == "I") return v
    x = num(v)
    if (x < 32768 && x >= -32768) {
        x = sround(x)
        if (x >= 32768) { raise(6); return "NI0" }
        return "NI" bfloor(x)
    }
    if (t == "D") return "ND" dint(substr(v, 3))
    return "N" t bfloor(x)
}

function fn_fix(v,   t, x, r) {
    t = vtype(v); if (t == "I") return v
    x = num(v)
    if (x >= 0) return fn_int(v)
    r = fn_int("N" t ((t == "D") ? dneg(substr(v, 3)) : -x)); if (E) return "NI0"
    if (vtype(r) == "D") return "ND" dneg(substr(r, 3))
    t = vtype(r); x = -num(r)
    if (t == "I" && x < -32768) t = "S"
    return "N" t x
}

function e_mul(   v, r, op, x, d, t) {
    v = e_un()
    while (!E && TY[CK, CP] == "o" && (TK[CK, CP] == "*" || TK[CK, CP] == "/")) {
        op = TK[CK, CP]; CP++
        r = e_un(); if (E) return v
        if (!isN(v) || !isN(r)) { raise(13); return v }
        t = ptype(v, r)
        if (op == "/" && t == "I") t = "S"      # division is never integer: both are converted to single (0BD2H's family)
        if (op == "*") {
            if (t == "D") { x = dmul(substr(v, 3), substr(r, 3)); if (E) return v; v = "ND" x; continue }   # the double multiply (0DA1H; p91)
            x = (t == "S") ? smul(num(v), num(r)) : num(v) * num(r)   # the single multiply (0847H; p90)
        } else {
            d = num(r)
            if (d == 0) { raise(11); return v }
            if (t == "D") { x = ddiv(substr(v, 3), substr(r, 3)); if (E) return v; v = "ND" x; continue }   # the double divide (0DE5H; p91)
            x = (t == "S") ? sdiv(num(v), d) : num(v) / d              # the single divide (08A2H; p90)
        }
        if (E) return v
        v = "N" tresult(t, x); if (E) return v
    }
    return v
}

function e_un(   v) {
    if (TY[CK, CP] == "o" && TK[CK, CP] == "-") {
        CP++
        v = e_un(); if (E) return v
        if (!isN(v)) { raise(13); return v }
        if (vtype(v) == "D") return "ND" dneg(substr(v, 3))
        return "N" tresult(vtype(v), -num(v))   # -(-32768) leaves 16 bits: a single
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
        a = frange(num(v), "S"); if (E) return v
        b = frange(num(r), "S"); if (E) return v
        x = rom_pow(sround(a), sround(b)); if (E) return v   # ^ works in single (13F2H converts an integer base): EXP(y * LOG(x)), p90
        v = "NS" x
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

function e_prim(   t, s, v, key, sx) {
    t = TY[CK, CP]
    # a lone "." in operand position enters the number reader (24B2H ->
    # 0E6CH), which takes the point and no digits as 0 -- a single, as a
    # pointed literal is (the 2026-09-26 audit, N-5).  ".5" and "1." were
    # folded into number tokens by tk_number already; only the bare dot
    # reaches here.
    if (t == "o" && TK[CK, CP] == ".") { CP++; return "NS0" }
    if (t == "n") {
        # 1.5% and 32768%: % is taken only behind an integer (tk_number,
        # p50; ROM 0EEE-0EEF, JP P,1997H)
        if (TSX[CK, CP] == "%SN") { raise(2); return "NI0" }
        s = TK[CK, CP] + 0; t = TSX[CK, CP]; CP++    # t: the literal's type, as 0E6CH read it (tk_number)
        if (t == "I") return "NI" s
        if (t == "S") s = rdsng(TK[CK, CP - 1])  # scaled as the reader scales it: .29 is 29/10/10 (p90)
        if (t == "D") { s = dread(TK[CK, CP - 1]); if (E) return "NI0"; return "ND" s }   # the reader's 56-bit steps (p91)
        s = frange(s, t); if (E) return "NI0"    # 1.70142E38, 1E39 ?OV (p10 FMAX; a double literal at DMAX, L-24); 1E-40 is 0
        return "N" t s
    }
    if (t == "s") {
        # a literal longer than 255 characters: the machine's line buffer
        # (240) cannot hold one, so the ROM has no case; a LOADed text
        # line here can (linelen.sh), and the value is refused as ?LS,
        # the error every string past 255 gets (29A2H), never stored
        # (the 2026-09-19 audit's H-2 named it; the 2026-09-26 audit,
        # L-23).  Unbounded under `memory host` (EXT, p10).
        if (!HOSTMEM && length(TK[CK, CP]) > 255) { raise_host(15); return "NI0" }
        v = "S" TK[CK, CP]; CP++; return v
    }
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
        if (s == "REM")    { raise(2); return "NI0" }
        if (s == "ERR")    { CP++; return "NI" ERRV }
        if (s == "ERL")    { CP++; return "NS" ERLV }     # 24DFH-24E2H: the line number through 0C66H, a SINGLE (it can be 65535)
        if (s == "MEM")    { CP++; return "NS" mem_free() }           # 27C9H -> 27F2H: through 0C66H, a SINGLE (p75)
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
            return fn_usr(s)
        }
        if (s == "VARPTR") { CP++; return fn_varptr() }   # p75, never a variable
        # user-defined functions, DEFINED-FIRST: an FN-prefixed identifier
        # is a call only when a DEF has executed for it -- otherwise it
        # stays a plain variable/array (three period listings in the
        # runnable corpus use FN* names as arrays; measured 2026-08-13)
        if (s ~ /^FN./ && (substr(s, 3) in FNPAR)) return fn_user(substr(s, 3))
        if (s == "FN" && TY[CK, CP + 1] == "i" && !((CK, CP + 1) in TKW) && (TK[CK, CP + 1] in FNPAR)) {
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
        if (TKW[CK, CP]) { raise(2); return "NI0" }
        sx = TSX[CK, CP]; CP++                    # the name's suffix types the value read (ntype, p70)
        if (TY[CK, CP] == "o" && TK[CK, CP] == "(") {
            key = aref(s); if (E) return "NI0"
            if (ALN && (("A" key) in ALIAS)) return "S" al_read("A" key)   # finding 7 (p75)
            if (strname(s, sx)) return (key in VA) ? VA[key] : "S"
            return "N" ntype(s, sx) ((key in VA) ? VA[key] : 0)
        }
        # a variable read in an expression is NEVER created: the ROM's
        # lookup, called from the evaluator, answers a name it cannot find
        # with a zero of the type and allocates nothing (269CH -> 26D5H),
        # so PRINT Y;Z;Y$ leaves MEM where it was.  Only a store (LET at
        # 1F21H, READ, INPUT, FOR, DIM) makes the entry.  A bare SV[s] or
        # NV[s] here is awk's bare-read trap (reading an element creates
        # it) reaching the memory accounting (mem_varbytes counts the
        # entries): until 2026-09-27
        # every read cost 7 or 6 bytes of MEM (the 2026-09-26 audit, M-8).
        if (strname(s, sx)) return "S" ((ALN && (("V" s) in ALIAS)) ? al_read("V" s) : (s in SV) ? SV[s] : "")
        t = ntype(s, sx)
        return "N" t ((s in NV) ? ((t == "D") ? NV[s] : NV[s] + 0) : 0)   # a double's payload as it is (p91)
    }
    raise(2)
    return "NI0"
}

# ---- array reference: at "(", returns storage key; auto-DIM 10 -------------
function aref(name,   nd, i, v, idx, key, idxs, vz) {
    vz = vt_size(name, TSX[CK, CP - 1])     # every caller stands on "(" just past the name
    CP++                                    # past "("
    nd = 0
    for (;;) {
        # idxs must be LOCAL: this e_or() can recurse into a nested aref
        # (A(B(1),C(1))), and a shared buffer would let the inner access
        # clobber the outer one's accumulated subscripts -- silently.
        v = e_or(); if (E) return ""
        if (!isN(v)) { raise(13); return "" }
        # ROM 1E45-1E4C: the subscript goes through 2B02H, which converts
        # through CINT (0A7FH: rounded down, ?OV outside -32768..32767),
        # and the evaluator returns only for a POSITIVE value; a negative
        # one is ?FC there and then, before the dimension count or the
        # bound is looked at.  So A(40000) is ?OV, never ?BS (the 2026-09-23
        # audit's NIT; until 2026-09-26 it was ?BS).
        idx = bigint(num(v)); if (E) return ""    # any integer under `memory host` (EXT, p70)
        if (idx < 0) { raise(5); return "" }
        nd++; idxs[nd] = idx
        if (TY[CK, CP] == "o" && TK[CK, CP] == ",") { CP++; continue }
        break
    }
    if (TY[CK, CP] == "o" && TK[CK, CP] == ")") CP++
    else { raise(2); return "" }
    if (!(name in ADIM)) {
        if (!mem_need(6 + 2 * nd + 11 ^ nd * vz)) return ""   # ?OM (p75)
        ADIM[name] = nd; AVZ[name] = vz
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
        if (!(TY[CK, CP] == "o" && TK[CK, CP] == "(")) { raise(2); return "NI0" }
        CP++
        for (i = 1; i <= n; i++) {
            v = e_or(); if (E) return "NI0"
            av[i] = v
            if (i < n) {
                if (!(TY[CK, CP] == "o" && TK[CK, CP] == ",")) { raise(2); return "NI0" }
                CP++
            }
        }
        if (!(TY[CK, CP] == "o" && TK[CK, CP] == ")")) { raise(2); return "NI0" }
        CP++
    }
    for (i = 1; i <= n; i++)                # type-check BEFORE binding, so
        if (strname(FNPARM[name, i]) != !isN(av[i])) { raise(13); return "NI0" }
    if (++FNDEPTH > 50) { FNDEPTH--; raise(7); return "NI0" }
    for (i = 1; i <= n; i++) {
        p = FNPARM[name, i]
        if (strname(p)) { osv[i] = SV[p]; SV[p] = substr(av[i], 2) }
        else            { osn[i] = NV[p]; NV[p] = (vtype(av[i]) == "D") ? substr(av[i], 3) : num(av[i]) }
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
    if (E) return "NI0"
    if (strname(name) != !isN(r)) { raise(13); return "NI0" }
    return r
}

# ---- built-in functions ----------------------------------------------------
function fncall(name,   v, a1, a2, a3, na, x, s, i, j, r) {
    CP++
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == "(")) { raise(2); return "NI0" }
    CP++
    na = 0
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == ")")) {
        a1 = e_or(); if (E) return "NI0"
        if (name == "STRING$") skipblank()                      # the count is a byte (2B1CH): a "b" token is passed
        na = 1
        if (TY[CK, CP] == "o" && TK[CK, CP] == ",") {
            CP++; a2 = e_or(); if (E) return "NI0"
            if (name ~ /^(LEFT|RIGHT|MID)\$$/) skipblank()       # the counts of the string functions too
            na = 2
            if (TY[CK, CP] == "o" && TK[CK, CP] == ",") {
                CP++; a3 = e_or(); if (E) return "NI0"
                if (name == "MID$") skipblank()
                na = 3
            }
        }
    }
    if (TY[CK, CP] == "o" && TK[CK, CP] == ")") CP++
    else { raise(2); return "NI0" }

    if (name == "ABS") { x = numarg(a1, na); if (E) return "NI0"; if (vtype(a1) == "D") return "ND" (x < 0 ? dneg(substr(a1, 3)) : substr(a1, 3)); return "N" vtype(a1) (x < 0 ? -x : x) }
    if (name == "INT") { x = numarg(a1, na); if (E) return "NI0"; return fn_int(a1) }
    if (name == "FIX") { x = numarg(a1, na); if (E) return "NI0"; return fn_fix(a1) }
    if (name == "SGN") { x = numarg(a1, na); if (E) return "NI0"; return "NI" (x > 0 ? 1 : (x < 0 ? -1 : 0)) }
    if (name == "SQR") { x = numarg(a1, na); if (E) return "NI0"; x = rom_pow(csng(x), 0.5); if (E) return "NI0"; return "NS" x }   # x ^ .5 (13E7H; p90)
    if (name == "SIN") { x = numarg(a1, na); if (E) return "NI0"; x = csng(x); if (E) return "NI0"; return "NS" rom_sin(x) }   # the ROM's series, step for step (p90)
    if (name == "COS") { x = numarg(a1, na); if (E) return "NI0"; x = csng(x); if (E) return "NI0"; return "NS" rom_cos(x) }
    if (name == "TAN") { x = numarg(a1, na); if (E) return "NI0"; x = csng(x); if (E) return "NI0"; x = rom_tan(x); if (E) return "NI0"; return "NS" x }
    if (name == "ATN") { x = numarg(a1, na); if (E) return "NI0"; x = csng(x); if (E) return "NI0"; return "NS" rom_atn(x) }
    if (name == "LOG") { x = numarg(a1, na); if (E) return "NI0"; x = csng(x); if (E) return "NI0"; x = rom_log(x); if (E) return "NI0"; return "NS" x }
    if (name == "EXP") {
        x = numarg(a1, na); if (E) return "NI0"
        # the ROM's routine (1439H; rom_exp, p90): EXP(88) is ?OV, and
        # below -128 ln 2 the answer is a quiet 0 (0931H tests the sign)
        x = csng(x); if (E) return "NI0"
        x = rom_exp(x); if (E) return "NI0"
        return "NS" x
    }
    if (name == "RND") {
        # authentic ROM sequence (rnd_next, p90): RND(0) = seed'/2^24,
        # RND(n) = INT(RND(0)*n + 1), the multiply and the add of 1 both
        # single operations (14E7H-14EAH: 070BH -> 0716H -> 0796H).  The
        # add rounds: for the one seed whose RND(0) is .99999994 the sum
        # reaches n+1, so RND(1) is 2 and RND(2) is 3 once in 16,777,216
        # draws (the ROM bug list's RND entry).  Until 2026-10-05 the 1
        # was added after INT and that draw gave n.  The argument goes through CINT first (14C9H -> 0A7FH:
        # rounded down, ?OV outside -32768..32767, so RND(32768) is ?OV);
        # then a negative one is ?FC at 14CEH (the ROM does NOT reseed on
        # negative).  Until 2026-09-25 RND(32768) returned a number.
        x = numarg(a1, na); if (E) return "NI0"
        i = to16(x); if (E) return "NI0"
        if (i < 0) { raise(5); return "NI0" }
        x = rnd_next()
        if (i == 0) return "NS" x
        return "NS" bfloor(sadd(smul(x, i), 1))
    }
    if (name == "CINT") {
        x = numarg(a1, na); if (E) return "NI0"
        x = to16(x); if (E) return "NI0"           # rounds DOWN (p90 to16)
        return "NI" x
    }
    if (name == "CSNG") { x = numarg(a1, na); if (E) return "NI0"; x = csng(x); if (E) return "NI0"; return "NS" x }
    if (name == "CDBL") { x = numarg(a1, na); if (E) return "NI0"; return "ND" substr(a1, 3) }   # a double as it is; a single or an integer is exact in one
    if (name == "PEEK") { x = numarg(a1, na); if (E) return "NI0"; x = addrarg(x); if (E) return "NI0"; return "NI" dopeek(x) }
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
        x = numarg(a1, na); if (E) return "NI0"
        x = byteconv(x); if (E) return "NI0"   # 2B1CH: ?OV past 16 bits (0A7FH), then ?FC outside 0-255 (L-7)
        return "NI" ((x == 255) ? (LATCH ? 63 : 127) : 255)
    }
    # 27F5H reads 40A6H and never looks at WRA1: the argument is a dummy of
    # ANY type -- the dispatch (2574H-257BH) type-checks only SQR-ATN, so
    # POS("A") is legal on the ROM (the 2026-09-26 audit, N-5)
    if (name == "POS") { if (na != 1) { raise(2); return "NI0" }; return "NI" VCOL }
    if (name == "FRE") {                    # 27D4H: a number asks about free memory, a string about the string area (p75)
        if (na < 1) { raise(2); return "NI0" }
        return "NS" (isN(a1) ? mem_free() : mem_strfree())   # 27F2H: a single, as MEM
    }
    if (name == "LEN") { s = strarg(a1, na); if (E) return "NI0"; return "NI" length(s) }
    if (name == "ASC") {
        s = strarg(a1, na); if (E) return "NI0"
        if (s == "") { raise(5); return "NI0" }
        s = substr(s, 1, 1)
        return "NI" ((s in ORD) ? ORD[s] : 63)
    }
    if (name == "VAL") { s = strarg(a1, na); if (E) return "NI0"; x = valnum(s, 1); if (E) return "NI0"; return "N" VALTYPE ((VALTYPE == "S") ? sround(x) : x) }   # a double comes back as its payload (valnum)
    if (name == "CHR$") {
        x = numarg(a1, na); if (E) return "NI0"
        x = byteconv(x); if (E) return "NI0"   # 2B1CH: ?OV past 16 bits, ?FC outside 0-255 (L-7)
        return "S" CHR[x]
    }
    if (name == "STR$") {
        x = numarg(a1, na); if (E) return "NI0"
        s = fmtnum(fnum(a1), vtype(a1))
        sub(/ $/, "", s)
        return "S" s
    }
    if (name == "STRING$") {
        if (na < 2) { raise(2); return "NI0" }
        if (!isN(a1)) { raise(13); return "NI0" }
        x = to16(num(a1)); if (E) return "NI0"   # 2B1CH: ?OV past 16 bits first (L-7)
        if (x < 0 || (!HOSTMEM && x > 255)) { raise_host(5); return "NI0" }   # any count under `memory host` (EXT)
        if (isN(a2)) {
            i = byteconv(num(a2)); if (E) return "NI0"
            s = CHR[i]
        } else {
            s = vstr(a2)
            if (s == "") { raise(5); return "NI0" }
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
        s = strarg2(a1, na); x = bytearg2(a2, na); if (E) return "NI0"
        return "S" substr(s, 1, x)
    }
    if (name == "RIGHT$") {
        s = strarg2(a1, na); x = bytearg2(a2, na); if (E) return "NI0"
        if (x > length(s)) x = length(s)
        return "S" (x == 0 ? "" : substr(s, length(s) - x + 1))
    }
    if (name == "MID$") {
        s = strarg2(a1, na); x = bytearg2(a2, na); if (E) return "NI0"
        if (x < 1) { raise(5); return "NI0" }              # 2AA1H
        if (na >= 3) {
            if (!isN(a3)) { raise(13); return "NI0" }
            i = lenconv(num(a3)); if (E) return "NI0"   # a byte, or any count under `memory host` (p80)
            return "S" substr(s, x, i)
        }
        return "S" substr(s, x)
    }
    if (name == "INSTR") {          # INSTR([n,]a$,b$) -- Disk BASIC
        if (na == 2) { x = 1; s = a1; r = a2 }
        else if (na == 3) {
            if (!isN(a1)) { raise(13); return "NI0" }
            x = bfloor(num(a1)); s = a2; r = a3
        } else { raise(2); return "NI0" }
        if (isN(s) || isN(r)) { raise(13); return "NI0" }
        s = vstr(s); r = vstr(r)
        if (x < 1 || (!HOSTMEM && x > 255)) { raise_host(5); return "NI0" }   # any start under `memory host` (EXT)
        if (x > length(s)) return "NI0"
        if (r == "") return "NI" x
        i = index(substr(s, x), r)
        return "NI" (i ? i + x - 1 : 0)
    }
    if (name == "POINT") {
        if (na < 2) { raise(2); return "NI0" }
        if (!isN(a1) || !isN(a2)) { raise(13); return "NI0" }
        # 0132H-014DH, shared with SET and RESET: each coordinate a byte
        # (2B1CH: ?OV, then ?FC), x tested against 128 before y is read,
        # y against 48 (L-7)
        x = byteconv(num(a1)); if (E) return "NI0"
        if (x > 127) { raise(5); return "NI0" }
        i = byteconv(num(a2)); if (E) return "NI0"
        if (i > 47) { raise(5); return "NI0" }
        return "NI" gpoint(x, i)
    }
    if (name == "EOF") {
        x = numarg(a1, na); if (E) return "NI0"
        i = fio_fnchan(x); if (E) return "NI0"
        if (FH_MODE[i] == "I") return "NI" (FH_PENDHAS[i] ? 0 : (fio_fill(i) ? 0 : -1))
        if (FH_MODE[i] == "R") return "NI" ((FH_LOC[i] >= FH_NREC[i]) ? -1 : 0)
        # "A": reports the reply buffer only -- never triggers a send
        if (FH_MODE[i] == "A") return "NI" ((FH_PENDHAS[i] || AI_RHAS[i]) ? 0 : -1)
        raise(55); return "NI0"
    }
    if (name == "LOF") {
        x = numarg(a1, na); if (E) return "NI0"
        i = fio_fnchan(x); if (E) return "NI0"
        if (FH_MODE[i] == "R") return "NI" (FH_NREC[i] + 0)
        # Disk manual, LOF: "the number of the last, i.e., highest numbered,
        # record in a file.  It is useful for both sequential and random
        # access."  A sequential file's records are the 256-byte physical
        # ones (it has no logical record length of its own), so the answer
        # is its length rounded up.  It used to be ?BM on anything but "R".
        if (FH_MODE[i] == "I" || FH_MODE[i] == "O" || FH_MODE[i] == "E") {
            if (FH_MODE[i] != "I") fflush(FH_NAME[i])    # our own writes first
            j = host_size(FH_NAME[i])
            if (j < 0) { raise(55); return "NI0" }
            return "NI" int((j + 255) / 256)
        }
        raise(55); return "NI0"                  # "A": the AI link has no records
    }
    if (name == "LOC") {
        x = numarg(a1, na); if (E) return "NI0"
        i = fio_fnchan(x); if (E) return "NI0"
        if (FH_MODE[i] == "A") return "NI" (AI_NMSG[i] + 0)
        return "NI" (FH_LOC[i] + 0)
    }
    if (name == "MKI$") { x = numarg(a1, na); if (E) return "NI0"; s = fio_mki(x); if (E) return "NI0"; return "S" s }
    if (name == "MKS$") { x = numarg(a1, na); if (E) return "NI0"; s = fio_mkf(x, 4); if (E) return "NI0"; return "S" s }
    if (name == "MKD$") { x = numarg(a1, na); if (E) return "NI0"; s = dbytes((vtype(a1) == "D") ? substr(a1, 3) : x); if (E) return "NI0"; return "S" s }
    if (name == "CVI") { s = strarg(a1, na); if (E) return "NI0"; x = fio_cvi(s); if (E) return "NI0"; return "NI" x }
    if (name == "CVS") { s = strarg(a1, na); if (E) return "NI0"; x = fio_cvf(s, 4); if (E) return "NI0"; return "NS" x }
    if (name == "CVD") { s = strarg(a1, na); if (E) return "NI0"; if (length(s) < 8) { raise(5); return "NI0" }; x = dfrombytes(s); if (E) return "NI0"; return "ND" x }
    if (name == "TAB") { raise(2); return "NI0" }
    raise(2)
    return "NI0"
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
function bytearg2(a, na) {                # a string count or position (LEFT$, RIGHT$, MID$)
    if (na < 2) { raise(2); return 0 }
    if (!isN(a)) { raise(13); return 0 }
    return lenconv(num(a))                  # a byte, or any count under `memory host` (p80)
}

# ---- USR call frame ---------------------------------------------------------
# USR/USR0-9: with a core (TRS80_Z80, p77) the routine RUNS; without
# one this is the STUB, which evaluates and returns its argument.
# X=USR(V) identity keeps more rescued listings partially running than
# ?FC would; routines whose RESULT is load-bearing still fail visibly.
# NOT SILENT (ruled 2026-09-11): 8 of the 11 trs-80.com string-packing
# techniques are side-effect routines, and a stub that returns its
# argument makes every one of them "succeed" with no effect, no error
# and exit 0 -- the silent-wrong-output failure this project names as
# the one that matters.  So the stub keeps stdout byte-identical (the
# oracle role) and usr_stub_notice() prints ONE stderr line per run
# naming every entry address that was called and not executed.
# TRS80_USR=strict raises ?FC on the call instead, for a sweep that
# wants the run to fail visibly.
#
# THE CALL PARSE is the ROM's own (27FE-2818, M-17): RST 10H, then 252CH
# evaluates ONE expression of ANY type -- so `USR(1,2)` is ?SN at the
# comma, where the generic function parser used to read a second argument
# and drop it, and a string argument is legal, where numarg made it ?TM.
# The routine enters with A = the type (40AFH: 2 I, 3 $, 4 S, 8 D), DE =
# the string's descriptor address when it is a string (2810: CALL 29DAH,
# 2814: EX DE,HL), HL = the entry, and the argument's bytes in WRA1
# (4121H) -- usr_setnum/usr_setstr build that image and the p77 shim sends
# it in the CALL header (proto 3); the core makes the ROM's stores and
# they come back in the write-set, so PEEK sees what the routine saw.
# A bare string VARIABLE (or array element) keeps its identity: the
# descriptor sent is the variable's own (sp_materialize), so a routine
# that rewrites the bytes rewrites A$ in place, as on the machine -- the
# X$=USR(Z$(N)) print-driver idiom.  Any other string expression is
# packed under the hidden name usr_strtmp() serves (a temporary on the
# machine; excluded from mem_varbytes so MEM does not move).  The trial
# parse re-reads a reference that turns out to be mid-expression
# (USR(A$(I)+B$)) from the saved position, so a subscript expression is
# evaluated twice there; BASIC subscripts have no side effects.
function fn_usr(name,   a1, x, r, tgt, cp0, nm, key) {
    if (name ~ /^USR[0-9]?$/) {
        CP++
        if (!(TY[CK, CP] == "o" && TK[CK, CP] == "(")) { raise(2); return "NI0" }
        CP++
        tgt = ""
        if (TY[CK, CP] == "i" && !TKW[CK, CP] && strname(TK[CK, CP]) &&
            !(TK[CK, CP] ~ /^FN./ && (substr(TK[CK, CP], 3) in FNPAR))) {
            cp0 = CP
            nm = TK[CK, CP]; CP++
            if (TY[CK, CP] == "o" && TK[CK, CP] == "(") {
                key = aref(nm); if (E) return "NI0"
                if (TY[CK, CP] == "o" && TK[CK, CP] == ")") tgt = "A" key
            } else if (TY[CK, CP] == "o" && TK[CK, CP] == ")") tgt = "V" nm
            if (tgt == "") CP = cp0
        }
        if (tgt != "") {
            # the reference's value, read as e_prim reads it (alias-aware)
            a1 = "S" ((ALN && (tgt in ALIAS)) ? al_read(tgt) : sp_gets(tgt))
        } else { a1 = e_or(); if (E) return "NI0" }
        if (!(TY[CK, CP] == "o" && TK[CK, CP] == ")")) { raise(2); return "NI0" }
        CP++
        if (isN(a1)) { x = num(a1); usr_setnum(vtype(a1), fnum(a1)) }
        else {
            if (tgt == "") tgt = usr_strtmp(substr(a1, 2))
            key = sp_materialize(tgt, 1); if (E) return "NI0"
            x = 0; usr_setstr(key)
        }
        if (E) return "NI0"
        usr_resolve(name, USR_ARG)
        r = z80_usr(x); if (E) return "NI0"        # the core (p77), or the stub
        # result=0 and the stub mean the argument UNCHANGED -- its value and
        # its type (PROTOCOL.md "The return"); only an HL reply is the
        # 16-bit integer (M-13: NI on every path was a 6fe3814 regression).
        # A rewritten string variable is re-read: the routine's write-set
        # went through the descriptor's cells into the variable itself.
        if (Z80RES) return "NI" r
        if (isN(a1)) return a1
        return "S" ((ALN && (tgt in ALIAS)) ? al_read(tgt) : sp_gets(tgt))
    }
    raise(2); return "NI0"
}

# The argument image the ROM's evaluator leaves behind (27FE: 252CH), as
# the CALL header carries it (p77, proto 3): USR_TYPE is 40AFH's flag,
# USR_ARG the number (or the string's descriptor address), USR_MBF the
# eight bytes 411DH-4124H -- an integer in 4121/4122H, a single in
# 4121-4124H (MBF, fio_mkf), a double filling all eight, a string's
# descriptor address in 4121/4122H.  The core stores them and they return
# in the write-set, like the 0A9AH trap's own stores.
function usr_setnum(t, v,   i, s, off, w) {
    USR_ARG = v + 0
    if (t == "I") {
        USR_TYPE = 2
        i = (v < 0) ? v + 65536 : v
        USR_MBF = "0,0,0,0," (i % 256) "," int(i / 256) ",0,0"
        return
    }
    USR_TYPE = (t == "D") ? 8 : 4
    s = (USR_TYPE == 8) ? dbytes(v) : fio_mkf(v, 4); if (E) return   # a double's own 56 bits (p91)
    off = 8 - USR_TYPE
    USR_MBF = ""
    for (i = 0; i < 8; i++) {
        w = (i >= off) ? ORD[substr(s, i - off + 1, 1)] : 0
        USR_MBF = (i == 0) ? w : USR_MBF "," w
    }
}
function usr_setstr(dbase) {
    USR_TYPE = 3; USR_ARG = dbase
    USR_MBF = "0,0,0,0," (dbase % 256) "," (int(dbase / 256) % 256) ",0,0"
}
# a string temporary's home: a hidden variable no listing can name (the
# tokenizer upper-cases every name, so a lower-case key never collides).
# One slot, reused: the machine's temp descriptor is transient too.
function usr_strtmp(s) {
    SV["usr$"] = s
    return "Vusr$"
}

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
