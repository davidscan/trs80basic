# ===================== program-memory mapping + VARPTR string space =========
# Three related pieces of the real Level II memory model (STATUS roadmap:
# "Program-memory mapping", shipped 2026-08-14):
#
#  1. READ-ONLY tokenized program image: PEEK of 42E9H (17129) onward sees
#     the stored program in the authentic crunched cassette format -- per
#     line [next-addr lo][hi][line lo][hi][tokenized body][00], terminated
#     by 00 00 -- rebuilt lazily whenever the program changed (PROGDIRTY is
#     set in rebuild()).  System pointers served live: 40A4H (16548/9) =
#     program base 42E9H, 40F9H (16633/4) = first byte past the terminator
#     (start of variables), 40B1H (16561/2) = top of memory (the MEMORY
#     SIZE? answer).  POKEs into the region land in MEM and are never read
#     back -- the WRITABLE mapping (self-modifying code) stays unbuilt (see
#     STATUS).  Keyword bytes 80-FB embedded below = tools/level2_tokens.tsv;
#     serialization is validated byte-for-byte against tools/tok.py.
#     Deviations, documented: lowercase keywords in typed source stay text
#     bytes (real hardware uppercased on entry), and ELSE serializes without
#     the hidden ":" byte the real cruncher inserted.
#
#  2. MEMORY SIZE? enforcement: a numeric answer at boot becomes HIMEM.
#     PEEK above it reads 255 and POKE above it is discarded (absent RAM);
#     ENTER keeps the full 65535 so batch mode and loaders see all of RAM.
#
#  3. VARPTR(var) + mem[]-backed string space (the string-packing idiom):
#     for a string, VARPTR returns the address of a live 3-byte descriptor
#     [len][addr lo][addr hi]; the string bytes are materialized just below
#     it and BOTH regions read and write through to the live value, so
#     locate-a-literal / POKE-semigraphics / PRINT-the-variable works.  For
#     a numeric, VARPTR returns the address of the value's 4 Microsoft-
#     single bytes (fio_mkf/fio_cvf), also live in both directions.
#     Allocation grows down from HIMEM like real string space; CLEAR/RUN/
#     NEW reset it (sp_reset from clear_vars).  Documented deviations: the
#     bytes are a mem[]-backed COPY (a literal's bytes are not the program
#     line, so pack-then-SAVE captures nothing), a re-VARPTR after the
#     value changed allocates a fresh region, and POKEing the descriptor's
#     address cells is ignored.  POKE of the length byte truncates or
#     space-pads the live value.

# ---- keyword table (byte 128-251 <-> expansion), longest-match index -------
function pm_init_index(   tbl, pairs, np, i, j, v, w, ins) {
    tbl = "80 END 81 FOR 82 RESET 83 SET 84 CLS 85 CMD 86 RANDOM 87 NEXT " \
          "88 DATA 89 INPUT 8A DIM 8B READ 8C LET 8D GOTO 8E RUN 8F IF " \
          "90 RESTORE 91 GOSUB 92 RETURN 93 REM 94 STOP 95 ELSE 96 TRON " \
          "97 TROFF 98 DEFSTR 99 DEFINT 9A DEFSNG 9B DEFDBL 9C LINE 9D EDIT " \
          "9E ERROR 9F RESUME A0 OUT A1 ON A2 OPEN A3 FIELD A4 GET A5 PUT " \
          "A6 CLOSE A7 LOAD A8 MERGE A9 NAME AA KILL AB LSET AC RSET " \
          "AD SAVE AE SYSTEM AF LPRINT B0 DEF B1 POKE B2 PRINT B3 CONT " \
          "B4 LIST B5 LLIST B6 DELETE B7 AUTO B8 CLEAR B9 CLOAD BA CSAVE " \
          "BB NEW BC TAB( BD TO BE FN BF USING C0 VARPTR C1 USR C2 ERL " \
          "C3 ERR C4 STRING$ C5 INSTR C6 POINT C7 TIME$ C8 MEM C9 INKEY$ " \
          "CA THEN CB NOT CC STEP CD + CE - CF * D0 / D1 [ D1 ^ D2 AND " \
          "D3 OR D4 > D5 = D6 < D7 SGN D8 INT D9 ABS DA FRE DB INP DC POS " \
          "DD SQR DE RND DF LOG E0 EXP E1 COS E2 SIN E3 TAN E4 ATN E5 PEEK " \
          "E6 CVI E7 CVS E8 CVD E9 EOF EA LOC EB LOF EC MKI$ ED MKS$ " \
          "EE MKD$ EF CINT F0 CSNG F1 CDBL F2 FIX F3 LEN F4 STR$ F5 VAL " \
          "F6 ASC F7 CHR$ F8 LEFT$ F9 RIGHT$ FA MID$ FB '"
    np = split(tbl, pairs, " ")
    NTOKI = 0
    for (i = 1; i <= np; i += 2) {
        v = strtonum("0x" pairs[i]); w = pairs[i + 1]
        # insertion sort, longest expansion first (MID$ before MID etc.)
        ins = ++NTOKI
        for (j = NTOKI - 1; j >= 1 && length(TIW[j]) < length(w); j--) {
            TIV[j + 1] = TIV[j]; TIW[j + 1] = TIW[j]; ins = j
        }
        TIV[ins] = v; TIW[ins] = w
    }
    TOKIDX = 1
}

# crunch one line body into PMB[1..PMBN] (mirrors tools/tok.py: strings,
# DATA-to-colon, and REM/' payloads stay literal; ' stores as :REM')
function pm_crunch(text,   i, n, c, ins, ind, lit, j, w, matched) {
    PMBN = 0
    i = 1; n = length(text); ins = 0; ind = 0; lit = 0
    while (i <= n) {
        c = substr(text, i, 1)
        if (lit || ins) {
            PMB[++PMBN] = ORD[c]
            if (ins && c == "\"") ins = 0
            i++; continue
        }
        if (c == "\"") { ins = 1; PMB[++PMBN] = 34; i++; continue }
        if (ind) { if (c == ":") ind = 0; PMB[++PMBN] = ORD[c]; i++; continue }
        matched = 0
        for (j = 1; j <= NTOKI; j++) {
            w = TIW[j]
            if (substr(text, i, length(w)) == w) {
                if (TIV[j] == 251) { PMB[++PMBN] = 58; PMB[++PMBN] = 147; PMB[++PMBN] = 251 }
                else PMB[++PMBN] = TIV[j]
                if (TIV[j] == 147 || TIV[j] == 251) lit = 1
                else if (TIV[j] == 136) ind = 1
                i += length(w); matched = 1
                break
            }
        }
        if (!matched) { PMB[++PMBN] = (c in ORD) ? ORD[c] : 63; i++ }
    }
}

# (re)serialize prog[] into PMEM[17129..PMEND-1]
function pm_build(   i, ln, addr, nb, j, nxt) {
    if (!TOKIDX) pm_init_index()
    delete PMEM
    addr = 17129
    for (i = 1; i <= NL; i++) {
        ln = LNS[i]
        pm_crunch(prog[ln]); nb = PMBN
        nxt = (addr + 4 + nb + 1) % 65536         # 16-bit pointer, wraps
        PMEM[addr] = nxt % 256; PMEM[addr + 1] = int(nxt / 256)
        PMEM[addr + 2] = ln % 256; PMEM[addr + 3] = int(ln / 256)
        for (j = 1; j <= nb; j++) PMEM[addr + 4 + j - 1] = PMB[j]
        PMEM[addr + 4 + nb] = 0
        addr += 4 + nb + 1
    }
    PMEM[addr] = 0; PMEM[addr + 1] = 0
    PMEND = addr + 2
    PROGDIRTY = 0
}

function pm_sync() { if (PROGDIRTY || PMEND == 0) pm_build() }

# the six live system-pointer bytes (dopeek routes them here)
function pm_sysptr(a) {
    if (a == 16548) return 233                    # 40A4H: program base 42E9H
    if (a == 16549) return 66
    if (a == 16561) return HIMEM % 256            # 40B1H: top of memory
    if (a == 16562) return int(HIMEM / 256)
    pm_sync()                                     # 40F9H: start of variables
    return (a == 16633) ? PMEND % 256 : int(PMEND / 256)
}

# ---- VARPTR ---------------------------------------------------------------
# Storage maps, per materialized address a: SPK[a] = value locator ("V" name
# for a scalar, "A" storage-key for an array element), SPT[a] = role -- a
# 0-based byte offset for string bytes, "L" the live length byte, "C" a
# constant descriptor byte (SPV[a]), or "Nj" numeric byte j.  SSP grows down
# from HIMEM; VPBASE/VPSIZE remember each variable's last allocation so a
# re-VARPTR frees it first.  sp_reset wipes everything (clear_vars).

function sp_reset(   a) {
    delete SPK; delete SPT; delete SPV; delete VPBASE; delete VPSIZE
    SSP = HIMEM
}

function sp_free(tgt,   a, e) {
    if (!(tgt in VPBASE)) return
    e = VPBASE[tgt] + VPSIZE[tgt] - 1
    for (a = VPBASE[tgt]; a <= e; a++) { delete SPK[a]; delete SPT[a]; delete SPV[a] }
    delete VPBASE[tgt]; delete VPSIZE[tgt]
}

# materialize var (locator tgt, string flag isstr) and return its VARPTR
function sp_materialize(tgt, isstr,   len, need, base, j, dbase) {
    if (SSP == 0) SSP = HIMEM                     # first use this run
    sp_free(tgt)
    if (isstr) {
        len = length(sp_gets(tgt))
        need = len + 3
    } else need = 4
    if (SSP - need < 17131) { raise(7); return 0 }
    base = SSP - need + 1; SSP -= need
    VPBASE[tgt] = base; VPSIZE[tgt] = need
    if (isstr) {
        for (j = 0; j < len; j++) { SPK[base + j] = tgt; SPT[base + j] = j }
        dbase = base + len
        SPK[dbase] = tgt;     SPT[dbase] = "L"
        SPK[dbase + 1] = tgt; SPT[dbase + 1] = "C"; SPV[dbase + 1] = base % 256
        SPK[dbase + 2] = tgt; SPT[dbase + 2] = "C"; SPV[dbase + 2] = int(base / 256)
        return dbase
    }
    for (j = 0; j < 4; j++) { SPK[base + j] = tgt; SPT[base + j] = "N" j }
    return base
}

# live value read/write through the locator
function sp_gets(tgt,   key) {
    key = substr(tgt, 2)
    if (substr(tgt, 1, 1) == "A") return (key in VA) ? substr(VA[key], 2) : ""
    return SV[key]
}
function sp_sets(tgt, s,   key) {
    key = substr(tgt, 2)
    if (substr(tgt, 1, 1) == "A") VA[key] = "S" s
    else SV[key] = s
}
function sp_getn(tgt,   key) {
    key = substr(tgt, 2)
    if (substr(tgt, 1, 1) == "A") return (key in VA) ? substr(VA[key], 2) + 0 : 0
    return NV[key] + 0
}
function sp_setn(tgt, x,   key) {
    key = substr(tgt, 2)
    if (substr(tgt, 1, 1) == "A") VA[key] = "N" x
    else NV[key] = x
}

function sp_peek(a,   t, tgt, v) {
    t = SPT[a]; tgt = SPK[a]
    if (t == "L") return length(sp_gets(tgt)) % 256
    if (t == "C") return SPV[a]
    if (substr(t, 1, 1) == "N") {
        v = fio_mkf(sp_getn(tgt), 4)
        return ORD[substr(v, substr(t, 2) + 1, 1)]
    }
    v = sp_gets(tgt)                              # string byte, live
    return (t + 1 <= length(v)) ? ORD[substr(v, t + 1, 1)] : 32
}

function sp_poke(a, b,   t, tgt, v, j) {
    t = SPT[a]; tgt = SPK[a]
    if (t == "C") return                          # can't relocate the bytes
    if (t == "L") {                               # truncate / space-pad
        v = sp_gets(tgt)
        while (length(v) < b) v = v " "
        sp_sets(tgt, substr(v, 1, b))
        return
    }
    if (substr(t, 1, 1) == "N") {
        v = fio_mkf(sp_getn(tgt), 4); j = substr(t, 2) + 1
        v = substr(v, 1, j - 1) CHR[b] substr(v, j + 1)
        sp_setn(tgt, fio_cvf(v, 4))
        return
    }
    v = sp_gets(tgt); j = t + 1                   # string byte, write through
    while (length(v) < j) v = v " "
    sp_sets(tgt, substr(v, 1, j - 1) CHR[b] substr(v, j + 1))
}

# VARPTR(var) -- parse a variable REFERENCE (scalar or array element), not
# an expression; called from e_prim
function fn_varptr(   name, key, tgt) {
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == "(")) { raise(2); return "N0" }
    CP++
    if (TY[CK, CP] != "i") { raise(2); return "N0" }
    name = TK[CK, CP]; CP++
    key = ""
    if (TY[CK, CP] == "o" && TK[CK, CP] == "(") { key = aref(name); if (E) return "N0" }
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == ")")) { raise(2); return "N0" }
    CP++
    tgt = (key != "") ? "A" key : "V" name
    return "N" sp_materialize(tgt, strname(name))
}
