# ===================== tokenizer ============================================
# Token types: n number, s string, i identifier/keyword (uppercase), o op,
#              d DATA payload, r REM payload, e end sentinel.

function tokline(key, text,   i, n, c, c2, k, s, j, q, two, t0) {
    if (key == "I") inval_cache_key("I")
    k = 0; i = 1; n = length(text)
    # TSRC + TPO give parse_fname (p40) the raw source from a token's own
    # position, so an unquoted file name is taken verbatim.  EVERY token
    # needs its TPO: a missing one made substr() start at "" and hand back
    # the WHOLE line, so `CSAVE DATA` saved to a file called "CSAVE DATA"
    # (the 2026-09-19 audit, L-15).  The string, REM, ' and DATA tokens had
    # none.
    TSRC[key] = text                        # raw source + per-token offsets
    while (i <= n) {                        # (parse_fname reads paths verbatim)
        c = substr(text, i, 1)
        if (c == " " || c == "\t") { i++; continue }
        t0 = i
        if (c == "\"") {
            j = index(substr(text, i + 1), "\"")
            if (j == 0) { s = substr(text, i + 1); i = n + 1 }
            else { s = substr(text, i + 1, j - 1); i = i + j + 1 }
            k++; TK[key, k] = s; TY[key, k] = "s"; TPO[key, k] = t0
            continue
        }
        if (c ~ /[0-9]/ || (c == "." && substr(text, i + 1, 1) ~ /[0-9]/)) {
            match(substr(text, i), /^([0-9]+\.?[0-9]*|\.[0-9]+)([EeDd][-+]?[0-9]+)?/)
            s = substr(text, i, RLENGTH); i += RLENGTH
            sub(/[Dd]/, "E", s)             # D exponent: same value, E form for awk
            c = substr(text, i, 1)
            if (c == "!" || c == "#" || c == "%") i++
            k++; TK[key, k] = s; TY[key, k] = "n"; TPO[key, k] = t0
            continue
        }
        if (c ~ /[A-Za-z]/) {
            match(substr(text, i), /^[A-Za-z][A-Za-z0-9]*\$?/)
            s = toupper(substr(text, i, RLENGTH)); i += RLENGTH
            c = substr(text, i, 1)
            # "#" is a type suffix on variables (X#) but a channel marker
            # after PRINT/INPUT (PRINT#1), where it must stay an operator
            if (c == "!" || c == "%") i++
            else if (c == "#" && s != "PRINT" && s != "INPUT") i++
            if (VARNAMES2 && length(s) > 2) s = vn_cut(s)
            if (s == "REM") {
                k++; TK[key, k] = "REM"; TY[key, k] = "i"; TPO[key, k] = t0
                k++; TK[key, k] = substr(text, i); TY[key, k] = "r"; TPO[key, k] = i
                i = n + 1
                continue
            }
            if (s == "DATA") {
                k++; TK[key, k] = "DATA"; TY[key, k] = "i"; TPO[key, k] = t0
                q = 0; j = i
                while (j <= n) {
                    c2 = substr(text, j, 1)
                    if (c2 == "\"") q = !q
                    else if (c2 == ":" && !q) break
                    j++
                }
                k++; TK[key, k] = substr(text, i, j - i); TY[key, k] = "d"; TPO[key, k] = i
                i = j
                continue
            }
            # ROM 1C24-1C2A: while the cruncher is matching token 8DH --
            # and ONLY that one -- it skips a blank in the input, so "GO TO"
            # crunches to GOTO.  It was ?SN here (the 2026-09-19 audit,
            # L-16).  GO SUB does NOT crunch: the ROM's skip is GOTO's alone.
            # The ROM matches byte by byte, so on the machine "GO TOTAL=5"
            # also becomes GOTO followed by TAL; this tokenizer reads a whole
            # identifier first, so only a standalone TO is taken.
            if (s == "GO") {
                j = i
                while (substr(text, j, 1) == " ") j++
                if (toupper(substr(text, j, 2)) == "TO" && substr(text, j + 2, 1) !~ /[A-Za-z0-9$]/) {
                    s = "GOTO"; i = j + 2
                }
            }
            k++; TK[key, k] = s; TY[key, k] = "i"; TPO[key, k] = t0
            continue
        }
        # ' is ":REM" -- the ROM's cruncher stores 3AH 93H FBH -- so a
        # statement boundary comes first.  It was a bare REM, which a
        # bare NEXT took for its loop variable: `NEXT 'POKE IN USR` was
        # ?NF (morseply, found by the core's oracle in its Phase A pass).
        if (c == "'") {
            k++; TK[key, k] = ":"; TY[key, k] = "o"; TPO[key, k] = t0
            k++; TK[key, k] = "REM"; TY[key, k] = "i"; TPO[key, k] = t0
            k++; TK[key, k] = substr(text, i + 1); TY[key, k] = "r"; TPO[key, k] = i + 1
            i = n + 1
            continue
        }
        if (c == "&" && toupper(substr(text, i + 1, 1)) ~ /^[HO]$/) {
            c2 = toupper(substr(text, i + 1, 1))    # &H/&O literal (Disk
            if (c2 == "H") match(substr(text, i + 2), /^[0-9A-Fa-f]+/)  # BASIC)
            else           match(substr(text, i + 2), /^[0-7]+/)
            if (RLENGTH > 0) {
                s = substr(text, i + 2, RLENGTH)
                j = (c2 == "H") ? strtonum("0x" s) : strtonum("0" s)
                i += 2 + RLENGTH
                k++; TY[key, k] = "n"; TPO[key, k] = t0
                # 16-bit two's complement per Microsoft (&HFFFF = -1);
                # more than 16 bits overflows -- a huge token makes eval
                # raise ?OV exactly like an out-of-range decimal literal
                TK[key, k] = (j > 65535) ? "1E99" : "" toS(j)
                continue
            }
        }
        two = substr(text, i, 2)
        if (two == "<=" || two == "=<") { k++; TK[key, k] = "<="; TY[key, k] = "o"; TPO[key, k] = t0; i += 2; continue }
        if (two == ">=" || two == "=>") { k++; TK[key, k] = ">="; TY[key, k] = "o"; TPO[key, k] = t0; i += 2; continue }
        if (two == "<>" || two == "><") { k++; TK[key, k] = "<>"; TY[key, k] = "o"; TPO[key, k] = t0; i += 2; continue }
        k++; TK[key, k] = c; TY[key, k] = "o"; TPO[key, k] = t0
        i++
    }
    k++; TK[key, k] = ""; TY[key, k] = "e"; TPO[key, k] = n + 1
    TCN[key] = k; TOKD[key] = 1
}

# TRS80_VARNAMES=2: a variable is named by its first two characters, as
# the ROM's variable table stores it, so ADDR and AD are one variable
# (gprixmc1.bas relies on it).  The tokenizer is the one place every name
# passes, so cutting here reaches variables, arrays, FOR/NEXT, INPUT/READ,
# DIM, VARPTR and the memory projection alike.  LIST shows the program's
# text, and the image cruncher and tools/tok.py crunch that text, so the
# full names stay in the program, as they do on the machine.  Not cut: the
# ROM's reserved words (pm_init_index's table), BYE, DEFUSR and USR0-USR9;
# FNABC is FN plus a name, so FNAB.  The type suffix `$` is kept (AB$ and AB
# are two variables); % ! # are already dropped (G% is G).  What this does
# NOT do: the ROM also takes a reserved word out of the middle of a name
# (TOTAL is TO TAL); this tokenizer reads a whole identifier first.
function vn_cut(s,   d, b) {
    if (!VNINIT) vn_init()
    if (s in VNKEEP || s ~ /^USR[0-9]$/) return s
    d = (s ~ /\$$/) ? "$" : ""
    b = d ? substr(s, 1, length(s) - 1) : s
    if (b ~ /^FN./) return "FN" substr(b, 3, 2) d
    return substr(b, 1, 2) d
}

function vn_init(   j, w) {
    if (!TOKIDX) pm_init_index()
    for (j = 1; j <= NTOKI; j++) { w = TIW[j]; sub(/\($/, "", w); VNKEEP[w] = 1 }
    VNKEEP["BYE"] = 1; VNKEEP["DEFUSR"] = 1
    VNINIT = 1
}

function inval_cache_key(k,   i) {
    if (k in TOKD) {
        for (i = 1; i <= TCN[k]; i++) { delete TK[k, i]; delete TY[k, i]; delete TPO[k, i] }
        delete TCN[k]; delete TOKD[k]; delete TSRC[k]
    }
}
