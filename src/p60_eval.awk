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
