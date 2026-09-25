# ===================== tokenizer ============================================
# Token types: n number, s string, i identifier/keyword (uppercase), o op,
#              d DATA payload, r REM payload, e end sentinel.
# TKW[key, k] is 1 on a keyword the table matched (kw_at, p75), unset on a
# name: the parser needs it where the two spell alike (TAB( and the
# variable TAB).  TSX[key, k] is a name's type suffix (! % #), or on a
# number "%" and "%SN" (see tk_number).
#
# The line is read as the ROM's cruncher reads it (1BC0-1C8F), so that the
# tokens here are the tokens in the program image (pm_crunch, p75) and the
# program the machine would run: outside a string, a REM and DATA every
# letter is tried against the keyword table and a name is what lies
# between the keywords (TOTAL is TO TAL, SCORE is SC OR E, IFA=1THEN30 and
# FORI=1TO3 need no blanks).  The ROM stores digits and points as they
# stand and READS them at run time through RST 10H (0E6CH from 24A5H), so
# blanks inside a number are nothing (1 2 is 12) -- tk_number below.
# Until 2026-09-25 a whole identifier was read first and then looked up,
# and a number by a regex (the 2026-09-23 audit, M-2, and the keyword-
# crunching rule ruled 2026-09-23).

function tokline(key, text,   i, n, c, c2, k, s, j, q, two, t0, sx, up) {
    if (key == "I") inval_cache_key("I")
    k = 0; i = 1; n = length(text)
    up = toupper(text)                      # ASCII letters only under -b
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
            i = tk_number(text, up, i)
            k++; TK[key, k] = TKNUM; TY[key, k] = "n"; TPO[key, k] = t0; TSX[key, k] = TKSX
            continue
        }
        if (c ~ /[A-Za-z]/) {
            s = kw_at(up, i)                # the ROM's match at this letter (p75)
            if (s != "") {
                i += KWLEN
                if (s == "TAB(") {          # the token is TAB( ; the ( stays a token of its own for the parser
                    k++; TK[key, k] = "TAB"; TY[key, k] = "i"; TPO[key, k] = t0; TKW[key, k] = 1
                    k++; TK[key, k] = "("; TY[key, k] = "o"; TPO[key, k] = i - 1
                    continue
                }
                if (s == "REM") {
                    k++; TK[key, k] = "REM"; TY[key, k] = "i"; TPO[key, k] = t0; TKW[key, k] = 1
                    k++; TK[key, k] = substr(text, i); TY[key, k] = "r"; TPO[key, k] = i
                    i = n + 1
                    continue
                }
                if (s == "DATA") {
                    k++; TK[key, k] = "DATA"; TY[key, k] = "i"; TPO[key, k] = t0; TKW[key, k] = 1
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
                if (s == "FN") { j = i; while (substr(text, j, 1) ~ /^[ \t]$/) j++ }
                if (!(s == "FN" && substr(text, j, 1) ~ /^[A-Za-z]$/)) {
                    k++; TK[key, k] = s; TY[key, k] = "i"; TPO[key, k] = t0; TKW[key, k] = 1
                    continue
                }
                # FNAB: the name behind the FN token (read through RST 10H,
                # so FN AB and FN A B as well) is carried in ONE identifier,
                # FNAB, as before -- e_prim (p60) makes it a call only once
                # a DEF has run for it, else a variable (three period
                # listings use FN* names as arrays)
                i = tk_name(text, up, j); s = "FN" TKNAME
            } else {
                # a name: the letters and digits up to the next keyword
                i = tk_name(text, up, i); s = TKNAME
            }
            if (substr(text, i, 1) == "$") { s = s "$"; i++ }
            # the type suffix is dropped from the name (G% is G) but kept
            # beside the token in TSX: a store into a % name is an integer
            # store.  Behind a keyword # is never a suffix now (PRINT#1,
            # CLOSE#1): the keyword's token ended before it.
            sx = ""; c = substr(text, i, 1)
            if (c == "!" || c == "%" || c == "#") { sx = c; i++ }
            if (VARNAMES2 && length(s) > 2) s = vn_cut(s)
            k++; TK[key, k] = s; TY[key, k] = "i"; TPO[key, k] = t0; TSX[key, k] = sx
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

# A name that begins at i, as the ROM's name reader takes it (260DH):
# letters and digits, every one after the first fetched through RST 10H
# (261AH, 2623H), which skips blanks and tabs (1D78-1D88) -- so A B is
# AB, A 1 is A1, S UM is SUM -- and the type suffix is found past blanks
# too (2631H-2640H: A $ is A$).  A keyword ends the name wherever it
# begins, since the cruncher put a token there (1BF5-1C3C tries the table
# at every letter and stores a digit without a try, 1BEC-1BF2).  ONE
# GUARD: a name never joins onto AS, because Disk BASIC's FIELD looks for
# the letters AS before it reads the variable (FIELD 1,4 AS A$), and
# here the tokenizer runs first.  Until 2026-09-25 a blank ended a name
# (ruled the same day: follow the ROM).
# Sets TKNAME, the name in upper case with the blanks gone; returns the
# index of the first character behind it that is not a blank.
function tk_name(text, up, i,   c, j) {
    TKNAME = substr(up, i, 1)
    for (j = i + 1; ; j++) {
        c = substr(text, j, 1)
        if (c ~ /^[ \t]$/) { if (TKNAME == "AS") return j; continue }
        if (c !~ /^[A-Za-z0-9]$/) return j
        if (c ~ /^[A-Za-z]$/ && kw_at(up, j) != "") return j
        TKNAME = TKNAME toupper(c)
    }
}

# A number in a line, as 0E6CH reads it (24A5H: JP C,0E6CH at a digit or
# a point): every character after the first comes through RST 10H, which
# skips blanks and tabs (1D78-1D88), so 1 2 is 12, 12 34 is 1234 and a
# line number behind GOTO the same (1E5AH: GOTO 3 0 is GOTO 30); E or D is
# an exponent, of 0 when no digit follows (1E is 1); a second point ends
# the number (0EE4-0EE6); ! and # are taken (0EF5-0EF9); % is taken behind
# an integer up to 32767 and is ?SN otherwise (0EEE-0EEF, JP P,1997H),
# which e_prim raises when the number is evaluated.  The exponent letter
# is a letter the cruncher stored raw, so where a keyword begins the number
# ends: 1END is 1 then END, 100 ELSE 200 is two numbers.  valnum (p90) is
# the same reader for VAL, READ and INPUT, over text no cruncher has seen.
# Returns the index behind the number; TKNUM is its text in awk's form
# (the blanks gone, D as E), TKSX its suffix.
function tk_number(text, up, i,   c, m, dot, ex, exs, hasexp, isint) {
    m = ""; ex = ""; exs = ""; dot = 0; hasexp = 0; isint = 1; TKSX = ""
    for (;;) {
        while (substr(text, i, 1) ~ /^[ \t]$/) i++
        c = substr(text, i, 1)
        if (c ~ /^[0-9]$/) { m = m c; i++; continue }
        if (c == ".") {
            if (dot) break
            dot = 1; isint = 0; m = m c; i++; continue
        }
        if (c ~ /^[EeDd]$/ && kw_at(up, i) == "") {
            hasexp = 1; isint = 0; i++
            while (substr(text, i, 1) ~ /^[ \t]$/) i++
            c = substr(text, i, 1)
            if (c == "+" || c == "-") { exs = c; i++ }
            for (;;) {
                while (substr(text, i, 1) ~ /^[ \t]$/) i++
                c = substr(text, i, 1)
                if (c !~ /^[0-9]$/) break
                ex = ex c; i++
            }
            break
        }
        if (c == "%") { TKSX = (isint && m + 0 <= 32767) ? "%" : "%SN"; i++ }
        else if (c == "!" || c == "#") { TKSX = c; i++ }
        break
    }
    TKNUM = m (hasexp ? "E" exs (ex == "" ? "0" : ex) : "")
    return i
}

# TRS80_VARNAMES=2: a variable is named by its first two characters, as
# the ROM's variable table stores it, so ADDR and AD are one variable
# (gprixmc1.bas relies on it).  The tokenizer is the one place every name
# passes, so cutting here reaches variables, arrays, FOR/NEXT, INPUT/READ,
# DIM, VARPTR and the memory projection alike.  LIST shows the program's
# text, and the image cruncher and tools/tok.py crunch that text, so the
# full names stay in the program, as they do on the machine.  The ROM's
# reserved words never reach it (kw_at takes them first, since 2026-09-25,
# and a reserved word inside a name ends the name: TOTAL is TO TAL); BYE,
# the one statement word that is no token, is kept.  FNABC is FN plus a
# name, so FNAB.  The type suffix `$` is kept (AB$ and AB are two
# variables); % ! # are already dropped (G% is G).
function vn_cut(s,   d, b) {
    if (s == "BYE") return s
    d = (s ~ /\$$/) ? "$" : ""
    b = d ? substr(s, 1, length(s) - 1) : s
    if (b ~ /^FN./) return "FN" substr(b, 3, 2) d
    return substr(b, 1, 2) d
}

function inval_cache_key(k,   i) {
    if (k in TOKD) {
        for (i = 1; i <= TCN[k]; i++) { delete TK[k, i]; delete TY[k, i]; delete TPO[k, i]; delete TSX[k, i]; delete TKW[k, i] }
        delete TCN[k]; delete TOKD[k]; delete TSRC[k]
    }
}
