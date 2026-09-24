# ===================== PRINT, INPUT, READ/DATA, DIM, POKE, graphics =========

function st_print(   sep, ty, tx, v, tgt, col, t) {
    if (TY[CK, CP] == "o" && TK[CK, CP] == "#") { CP++; st_print_file(); return }
    if (TY[CK, CP] == "o" && TK[CK, CP] == "@") {
        CP++
        v = e_or(); if (E) return
        if (!isN(v)) { raise(13); return }
        tgt = bfloor(num(v))
        if (tgt < 0 || tgt > 1023) { raise(5); return }
        CUR = tgt
        if (TY[CK, CP] == "o" && (TK[CK, CP] == "," || TK[CK, CP] == ";")) CP++
    }
    if (TY[CK, CP] == "i" && TK[CK, CP] == "USING") { CP++; pr_using(); return }
    sep = 0
    for (;;) {
        ty = TY[CK, CP]
        if (ty == "" || ty == "e") break
        tx = TK[CK, CP]
        if (ty == "o" && tx == ":") break
        if (ty == "i" && (tx == "ELSE" || tx == "REM")) break
        if (ty == "i" && tx == "USING") { CP++; pr_using(); return }
        if (ty == "o" && tx == ";") { sep = 1; CP++; continue }
        if (ty == "o" && tx == ",") {
            sep = 1
            # the ROM PRINTS its way to the next zone (2123-2135 -> 215A-
            # 2162: blanks through the output routine), it does not move
            # the cursor: the gap overwrites what was there, reaches the
            # printer when video is routed to it, and is in the text stream.
            # From column 48 on there is no zone left: a carriage return.
            col = CUR % 64
            if (col >= 48) s_nl()
            else for (t = 16 - (col % 16); t > 0; t--) s_putc(32)
            CP++
            continue
        }
        if (ty == "i" && tx == "TAB") {
            CP++
            if (!(TY[CK, CP] == "o" && TK[CK, CP] == "(")) { raise(2); return }
            CP++
            v = e_or(); if (E) return
            if (!isN(v)) { raise(13); return }
            if (!(TY[CK, CP] == "o" && TK[CK, CP] == ")")) { raise(2); return }
            CP++
            t = bfloor(num(v))
            if (t < 0 || t > 255) { raise(5); return }
            t = t % 64
            col = CUR % 64
            while (col < t) { s_putc(32); col++ }
            sep = 0
            continue
        }
        v = e_or(); if (E) return
        if (isN(v)) {
            # a number is never split across two lines: the ROM adds its
            # length (sign and digits, not the blank that follows) to the
            # cursor's column and sends a carriage return first when that
            # reaches the line size (20DD-20E6 -> 20FEH).  Strings wrap.
            t = fmtnum(num(v))
            if (CUR % 64 + length(t) - 1 >= 64) s_nl()
            s_puts(t)
        }
        else s_puts(vstr(v))
        sep = 0
    }
    if (!sep) s_nl()
    sync_cursor()
}

# ---- PRINT USING tail (entered with CP just past USING) --------------------
# USING is legal at ANY item position, not only at the head of the list: the
# period idiom is PRINT TAB(57) USING X$;EC (Encyclopedia for the TRS-80
# vol. 3; DEMON.bas line 30 too).  It formats the rest of the statement, so
# whatever was already printed keeps its column and USING takes over here.
function pr_using(   sep, ty, tx, v, fmt) {
    v = e_or(); if (E) return
    if (isN(v)) { raise(13); return }
    fmt = vstr(v)
    if (TY[CK, CP] == "o" && (TK[CK, CP] == ";" || TK[CK, CP] == ",")) CP++
    else { raise(2); return }
    sep = 0; PUN = 0
    for (;;) {                              # , and ; are pure separators here
        ty = TY[CK, CP]
        if (ty == "" || ty == "e") break
        tx = TK[CK, CP]
        if (ty == "o" && tx == ":") break
        if (ty == "i" && (tx == "ELSE" || tx == "REM")) break
        if (ty == "o" && (tx == ";" || tx == ",")) { sep = 1; CP++; continue }
        v = e_or(); if (E) return
        PUV[++PUN] = v
        sep = 0
    }
    v = pu_output(fmt, PUN); if (E) return
    s_puts(v)
    if (!sep) s_nl()
    sync_cursor()
}

# ---- LPRINT / LLIST --------------------------------------------------------
# The line printer is a host stream: append to $TRS80_PRINTER, or discard
# when unset.  Same value formatting and USING support as PRINT; own column
# counter (LPCOL) for , zones and TAB; no @, no #, no screen wrap.
# The column (409BH) is BASIC's, not the driver's: the ROM counts the
# character at 03A0-03B7 -- CR, LF and FF zero the count, anything else
# bumps the byte -- and only THEN calls the driver through the vector
# (03BBH).  So it advances wherever the vector points; when it stood still
# while routed, LPRINT TAB(n) never reached its column and hung.  The page
# counter (4029H) is the driver's, so it moves only when the driver runs.
function lp_puts(s,   i, n, c) {
    n = length(s)
    for (i = 1; i <= n; i++) {
        c = ORD[substr(s, i, 1)]
        if (c == 10 || c == 12 || c == 13) LPCOL = 0
        else LPCOL = (LPCOL + 1) % 256
    }
    if (LPTOVID) { s_puts(s); return }        # printer vector -> the ROM video driver
    if (LPOFF) return                         # printer vector -> a RET
    if (index(s, CHR[12])) LPLINES = 0        # a form feed starts the page over
    if (LPFILE != "") printf "%s", s >> LPFILE
}

function lp_nl() {
    LPCOL = 0
    if (LPTOVID) { s_nl(); return }
    if (LPOFF) return
    if (++LPLINES >= LPPAGE - 1) LPLINES = 0   # 4029H: lines on this page, a page is LPPAGE-1
    if (LPFILE != "") { print "" >> LPFILE; fflush(LPFILE) }
}

function st_lprint(   sep, ty, tx, v, t) {
    if (TY[CK, CP] == "i" && TK[CK, CP] == "USING") { CP++; lp_using(); return }
    sep = 0
    for (;;) {
        ty = TY[CK, CP]
        if (ty == "" || ty == "e") break
        tx = TK[CK, CP]
        if (ty == "o" && tx == ":") break
        if (ty == "i" && (tx == "ELSE" || tx == "REM")) break
        if (ty == "i" && tx == "USING") { CP++; lp_using(); return }
        if (ty == "o" && tx == ";") { sep = 1; CP++; continue }
        if (ty == "o" && tx == ",") {
            sep = 1
            # past column 112 there is no zone left on the line: the ROM
            # skips to the next one instead (211B-212B)
            if (LPCOL >= 112) lp_nl()
            else lp_puts(substr("                ", 1, 16 - (LPCOL % 16)))
            CP++
            continue
        }
        if (ty == "i" && tx == "TAB") {
            CP++
            if (!(TY[CK, CP] == "o" && TK[CK, CP] == "(")) { raise(2); return }
            CP++
            v = e_or(); if (E) return
            if (!isN(v)) { raise(13); return }
            if (!(TY[CK, CP] == "o" && TK[CK, CP] == ")")) { raise(2); return }
            CP++
            t = bfloor(num(v))
            if (t < 0 || t > 255) { raise(5); return }
            t = t % 64                        # the ROM masks it, as PRINT's (213AH)
            while (LPCOL < t) lp_puts(" ")
            sep = 0
            continue
        }
        v = e_or(); if (E) return
        if (isN(v)) {
            # the printer's twin of PRINT's rule, against 132 columns
            # (20D5-20DB: column + length >= 84H)
            v = fmtnum(num(v))
            if (LPCOL + length(v) - 1 >= 132) lp_nl()
            lp_puts(v)
        }
        else lp_puts(vstr(v))
        sep = 0
    }
    if (!sep) lp_nl()
}

# LPRINT USING tail -- the printer twin of pr_using(), same any-position rule.
function lp_using(   sep, ty, tx, v, fmt) {
    v = e_or(); if (E) return
    if (isN(v)) { raise(13); return }
    fmt = vstr(v)
    if (TY[CK, CP] == "o" && (TK[CK, CP] == ";" || TK[CK, CP] == ",")) CP++
    else { raise(2); return }
    sep = 0; PUN = 0
    for (;;) {
        ty = TY[CK, CP]
        if (ty == "" || ty == "e") break
        tx = TK[CK, CP]
        if (ty == "o" && tx == ":") break
        if (ty == "i" && (tx == "ELSE" || tx == "REM")) break
        if (ty == "o" && (tx == ";" || tx == ",")) { sep = 1; CP++; continue }
        v = e_or(); if (E) return
        PUV[++PUN] = v
        sep = 0
    }
    v = pu_output(fmt, PUN); if (E) return
    lp_puts(v)
    if (!sep) lp_nl()
}

# OUT port,value -- accepted no-op (like DEFINT precision): both expressions
# are evaluated (errors still raise), the port write itself does nothing.
# OUT is a reserved word on hardware, so no period program uses it as a
# variable name.
# OUT p,v.  Port FFH is the Model I's four-bit output latch: bits 0-1 the
# cassette signal, bit 2 the cassette relay, bit 3 the 32-characters-per-line
# video mode -- the same latch bit CHR$(23) writes (Barden, Programming
# Techniques for Level II BASIC, 1981, figure 12-9).  OUT 255,8 selects 32
# columns and OUT 255,0 returns to 64; 81 corpus listings do so from BASIC,
# most of them to flash the screen, and until 2026-09-13 both were silent
# no-ops here.  Only the hardware changes: the ROM's print-size flag at
# 403DH, which sets the cursor step, is CHR$(23)'s and CLS's to change
# (s_setwide, p20).  Bits 0-2 stay silent by ruling (sound is machine code
# only; the core's port_out sees the same latch during a USR call), and
# every other port is open bus, as INP reads it.  Port and value are each a
# byte by the ROM's rule (byteconv): outside 0-255 is ?FC, as POKE's value.
function st_out(   v, p) {
    v = e_or(); if (E) return
    if (!isN(v)) { raise(13); return }
    p = byteconv(num(v)); if (E) return
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == ",")) { raise(2); return }
    CP++
    v = e_or(); if (E) return
    if (!isN(v)) { raise(13); return }
    v = byteconv(num(v)); if (E) return
    if (p == 255) s_setwide(int(v / 8) % 2)
}

# ---- MID$ statement --------------------------------------------------------
# MID$(v$,n[,m]) = expr : in-place replacement.  The target's length never
# changes -- the replacement is truncated to m (if given) and to what fits.
function st_midset(   name, key, n, m, v, s, r, cnt) {
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == "(")) { raise(2); return }
    CP++
    if (TY[CK, CP] != "i") { raise(2); return }
    name = TK[CK, CP]; CP++
    if (!strname(name)) { raise(13); return }
    key = ""
    if (TY[CK, CP] == "o" && TK[CK, CP] == "(") { key = aref(name); if (E) return }
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == ",")) { raise(2); return }
    CP++
    v = e_or(); if (E) return
    if (!isN(v)) { raise(13); return }
    n = bfloor(num(v))
    m = -1
    if (TY[CK, CP] == "o" && TK[CK, CP] == ",") {
        CP++
        v = e_or(); if (E) return
        if (!isN(v)) { raise(13); return }
        m = bfloor(num(v))
        if (m < 0 || m > 255) { raise(5); return }
    }
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == ")")) { raise(2); return }
    CP++
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == "=")) { raise(2); return }
    CP++
    v = e_or(); if (E) return
    if (isN(v)) { raise(13); return }
    r = vstr(v)
    s = al_cur(name, key); if (E) return
    if (n < 1 || n > 255 || n > length(s)) { raise(5); return }
    cnt = length(r)
    if (m >= 0 && m < cnt) cnt = m
    if (cnt > length(s) - n + 1) cnt = length(s) - n + 1
    s = substr(s, 1, n - 1) substr(r, 1, cnt) substr(s, n + cnt)
    # a FIELD variable's characters ARE the record buffer's (its descriptor
    # points into it), so the store lands there and PUT writes it (p85)
    if (fld_is(fld_tgt(name, key), s)) { fld_put(fld_tgt(name, key), s); return }
    # in place: the target keeps its length and its descriptor (p75 finding 7)
    al_setinplace(name, key, s)
}

# ---- PRINT USING formatter -------------------------------------------------
# Formats the tagged values PUV[1..nv] through the picture string.  Fields:
#   numeric: # digit positions, . decimal point, , grouping (counts as a
#     position), ** asterisk fill (+2 positions), $$ floating dollar (+2,
#     one being the $), **$ both (+3), leading + (extra sign position),
#     trailing - or + (sign after the number), ^^^^ exponent form.
#     A number too wide for its field prints as % followed by the plain
#     PRINT form.  Negative sign takes a digit position unless a sign
#     specifier is present.
#   string:  ! (first char), % spaces % (n+2 chars, left-justified).
# Anything else prints literally.  The picture is reused while values
# remain; a picture with no fields while values remain raises ?FC.
# A value of the wrong type for a field raises ?TM.
function pu_output(fmt, nv,   out, vi, i, n, c, j, r, consumed) {
    out = ""; vi = 1
    while (vi <= nv) {
        consumed = 0
        i = 1; n = length(fmt)
        while (i <= n) {
            c = substr(fmt, i, 1)
            if (c == "!") {
                if (vi > nv) return out
                out = out pu_str(PUV[vi++], 1); consumed = 1
                if (E) return ""
                i++; continue
            }
            if (c == "%") {
                j = index(substr(fmt, i + 1), "%")
                if (j > 0 && substr(fmt, i + 1, j - 1) ~ /^ *$/) {
                    if (vi > nv) return out
                    out = out pu_str(PUV[vi++], j + 1); consumed = 1
                    if (E) return ""
                    i += j + 1; continue
                }
            }
            r = pu_scan(fmt, i)
            if (r > 0) {
                if (vi > nv) return out
                out = out pu_num(PUV[vi++]); consumed = 1
                if (E) return ""
                i += r; continue
            }
            out = out c
            i++
        }
        if (!consumed && vi <= nv) { raise(5); return "" }
    }
    return out
}

# parse a numeric field at fmt[i]; returns its length, 0 if not a field.
# Sets PU_IP (integer positions incl fill/$/commas), PU_DP/PU_DOT, PU_AST,
# PU_DOL, PU_PLUS, PU_COMMA, PU_TS (trailing sign char), PU_EXP.
function pu_scan(fmt, i,   j, c, got) {
    PU_IP = 0; PU_DP = 0; PU_DOT = 0; PU_AST = 0; PU_DOL = 0
    PU_PLUS = 0; PU_COMMA = 0; PU_TS = ""; PU_EXP = 0
    j = i; got = 0
    if (substr(fmt, j, 1) == "+") { PU_PLUS = 1; j++ }
    if (substr(fmt, j, 2) == "**") {
        PU_AST = 1; PU_IP += 2; j += 2; got = 1
        if (substr(fmt, j, 1) == "$") { PU_DOL = 1; PU_IP++; j++ }
    } else if (substr(fmt, j, 2) == "$$") { PU_DOL = 1; PU_IP += 2; j += 2; got = 1 }
    for (;;) {
        c = substr(fmt, j, 1)
        if (c == "#") { PU_IP++; got = 1; j++; continue }
        if (c == "," && got) { PU_IP++; PU_COMMA = 1; j++; continue }
        break
    }
    if (substr(fmt, j, 1) == "." && (got || substr(fmt, j + 1, 1) == "#")) {
        PU_DOT = 1; j++
        while (substr(fmt, j, 1) == "#") { PU_DP++; j++ }
        if (PU_DP > 0) got = 1
    }
    if (!got) return 0
    # the machine's up-arrow is 5BH, which a period listing shows as "["
    # (the ROM compares with 5BH, 2D81H); a terminal types "^"
    if (substr(fmt, j, 4) == "^^^^" || substr(fmt, j, 4) == "[[[[") { PU_EXP = 1; j += 4 }
    c = substr(fmt, j, 1)
    if (c == "-" || c == "+") { PU_TS = c; j++ }
    return j - i
}

# format one numeric value into the field pu_scan just described.
# Digits come from an integer-scaled half-up round (the ROM rounds .5 up;
# C's printf rounds it to even), built back into int/decimal parts.
#
# The ROM formats the number into its buffer FIRST -- the field's decimals,
# its rounding, commas, $ and sign all in place -- and only then looks for
# the start of the field (10CA-1108).  What it finds in front of the field:
#   * a lone 0 before the point: dropped, the rest moves up (10EF-10FF).
#     #.## of -.5 is -.50, never an overflow
#   * anything else: a % goes in front of the FORMATTED number.  ##.## of
#     123.456 is %123.46 (not the plain %123.456), and a trailing sign
#     still follows
#   * only a value of 1E16 or more is handed to the plain formatter behind
#     its % (1110-1123)
# The exponent form (11AA-11FE) keeps ONE position for the sign unless the
# field says where the sign goes (a leading +, which is that position, or
# a trailing + or -): ##.##^^^^ of 234.56 is " 2.35E+02", one digit before
# the point, not two.  With no # before the point and no sign position the
# kept place falls BEHIND the point: .####^^^^ of 1234.5 is .0123E+05.
# The 0 the ROM writes before a bare point (1022-1023) shows when the field
# has room: #.##^^^^ of 123 is 0.12E+03, of -123 is -.12E+03.
# Microsoft's own examples for this code agree: " 2.35E+02",
# ".8889E+06 " for .####^^^^- and "+.12E+03" for +.##^^^^.
function pu_num(v,   x, ax, neg, id, nd, k, e2, es, ds, ist, dec, lead, body, core, w, fill, g, p) {
    if (!isN(v)) { raise(13); return "" }
    x = num(v)
    neg = (x < 0)
    ax = neg ? -x : x
    lead = PU_PLUS ? (neg ? "-" : "+") : ((neg && PU_TS == "") ? "-" : "")
    w = PU_IP + (PU_PLUS ? 1 : 0) + (PU_DOT ? 1 + PU_DP : 0)
    fill = " "
    if (PU_EXP) {
        w += 4
        id = PU_IP - ((PU_PLUS || PU_TS != "") ? 0 : 1)    # digits before the point
        nd = id + PU_DP                                     # significant digits
        if (nd < 1) return pu_ovf(x)
        if (ax == 0) { k = id; p = 0 }
        else {
            k = bfloor(log(ax) / log(10)) + 1               # digits in the integer part
            p = int(ax / (10 ^ (k - nd)) + 0.5)
            if (p >= 10 ^ nd) { k++; p = int(ax / (10 ^ (k - nd)) + 0.5) }
            else if (p < 10 ^ (nd - 1)) { k--; p = int(ax / (10 ^ (k - nd)) + 0.5) }
        }
        ds = sprintf("%.0f", p)
        while (length(ds) < nd) ds = "0" ds
        if (id < 0) { ist = ""; dec = "0" ds }              # the sign's place, behind the point
        else { ist = substr(ds, 1, id); dec = substr(ds, id + 1) }
        e2 = k - id
        es = sprintf("E%s%02d", (e2 < 0 ? "-" : "+"), (e2 < 0 ? -e2 : e2))
        body = (PU_DOT ? "." dec : "") es
        if (ist == "" && length(lead "0" body) <= w) ist = "0"
        core = lead ist body
    } else {
        if (ax >= 1e16) return pu_ovf(x) pu_tsign(neg)
        ds = sprintf("%.0f", int(ax * (10 ^ PU_DP) + 0.5))
        while (length(ds) < PU_DP + 1) ds = "0" ds
        ist = substr(ds, 1, length(ds) - PU_DP)
        dec = substr(ds, length(ds) - PU_DP + 1)
        if (PU_COMMA) {
            g = ""; p = length(ist)
            while (p > 3) { g = "," substr(ist, p - 2, 3) g; p -= 3 }
            ist = substr(ist, 1, p) g
        }
        body = (PU_DOT ? "." dec : "")
        core = lead (PU_DOL ? "$" : "") ist body
        if (length(core) > w && ist == "0" && PU_DP > 0)    # the lone 0 gives way
            core = lead (PU_DOL ? "$" : "") body
        if (PU_AST) fill = "*"
    }
    if (length(core) > w) core = "%" core
    while (length(core) < w) core = fill core
    return core pu_tsign(neg)
}

function pu_tsign(neg) {
    if (PU_TS == "-") return neg ? "-" : " "
    if (PU_TS == "+") return neg ? "-" : "+"
    return ""
}

# format one string value into a w-char field (truncate / pad right)
function pu_str(v, w,   s) {
    if (isN(v)) { raise(13); return "" }
    s = vstr(v)
    if (length(s) > w) s = substr(s, 1, w)
    while (length(s) < w) s = s " "
    return s
}

# field overflow: % then the number as plain PRINT would show it
function pu_ovf(x,   t) {
    t = fmtnum(x)
    gsub(/^ +| +$/, "", t)
    return "%" t
}

# ---- INPUT -----------------------------------------------------------------
function st_input(   prompt, pq, nlv, name, key, i, line, nib, idx, ok, x, d, endp) {
    # INPUT #n is legal in immediate mode, so check before the ID guard
    if (TY[CK, CP] == "o" && TK[CK, CP] == "#") { CP++; st_input_file(); return }
    if (CK == "I") { raise(12); return }
    prompt = ""; pq = 0
    if (TY[CK, CP] == "s") {
        if (TY[CK, CP + 1] == "o" && (TK[CK, CP + 1] == ";" || TK[CK, CP + 1] == ",")) {
            prompt = TK[CK, CP]; CP++
        } else {
            # Disk BASIC prompt expression: INPUT ""+CHR$(10)+"X";A.
            # e_prim reads the leading literal, so just evaluate from here.
            x = e_or(); if (E) return
            if (substr(x, 1, 1) != "S") { raise(13); return }
            prompt = substr(x, 2)
        }
        if (TY[CK, CP] == "o" && TK[CK, CP] == ";") { pq = 1; CP++ }
        else if (TY[CK, CP] == "o" && TK[CK, CP] == ",") { pq = 2; CP++ }
        else if (!(EXTON && at_stmt_end())) { raise(2); return }
    }
    if (EXTON && at_stmt_end()) {
        # EXT (gated): INPUT with no variable -- the pause idiom
        # (INPUT"PRESS ENTER";).  Prompt, read a line, discard it.
        if (prompt != "") s_puts(prompt)
        if (pq != 2) s_puts("? ")
        line = rl_read()
        if (RLCANCEL) { dobreak(); return }
        if (EOFQUIT) { if (BATCH) batch_ineof(); STOPPED = 1; return }
        return
    }
    # The targets are only LOCATED here.  Each one is resolved -- its
    # subscripts evaluated -- when its value is about to be stored, after
    # the assignments before it, as the ROM does and as READ does here:
    # INPUT I,A(I) answered 3,77 stores into A(3).  (Until 2026-09-20 every
    # subscript was evaluated before the prompt, so that went to A(0).)
    nlv = 0
    for (;;) {
        if (TY[CK, CP] != "i") { raise(2); return }
        nlv++; LV_P[nlv] = CP; CP++
        if (TY[CK, CP] == "o" && TK[CK, CP] == "(") {
            d = 0
            do {
                if (TY[CK, CP] == "" || TY[CK, CP] == "e") { raise(2); return }
                if (TY[CK, CP] == "o" && TK[CK, CP] == "(") d++
                else if (TY[CK, CP] == "o" && TK[CK, CP] == ")") d--
                CP++
            } while (d > 0)
        }
        if (TY[CK, CP] == "o" && TK[CK, CP] == ",") { CP++; continue }
        break
    }
    endp = CP
    for (;;) {                              # REDO loop
        if (prompt != "") s_puts(prompt)
        if (pq != 2) s_puts("? ")
        idx = 1; nib = 0
        ok = 1
        for (;;) {                          # fill loop
            line = rl_read()
            if (RLCANCEL) { dobreak(); return }
            if (EOFQUIT) { if (BATCH) batch_ineof(); STOPPED = 1; return }
            # ENTER alone ends the statement and assigns NOTHING: the ROM
            # tests the first byte of the buffer and skips to the end of
            # the INPUT (21E8H; the same at a ?? prompt, 2229H), so "the
            # variables will have the value they were previously assigned"
            # (manual p.3-9) -- the press-ENTER-to-keep-the-value prompt.
            # Values already taken from an earlier line of this INPUT stay.
            # A line of blanks is not empty: it still reads as 0 or "".
            if (line == "") return
            nib = parse_items(line, nib)
            while (idx <= nlv && idx <= nib) {
                CP = LV_P[idx]; name = lvname(); key = ""
                if (TY[CK, CP] == "o" && TK[CK, CP] == "(") { key = aref(name); if (E) return }
                CP = endp
                if (IBBAD[idx] || (IBQ[idx] && !strname(name))) { ok = 0; break }
                if (strname(name)) assignv(name, key, "S" IB[idx])
                else {
                    # the ROM's reader takes what it can (valnum, p90);
                    # anything but blanks left over is ?REDO (225A-2260)
                    x = IB[idx]
                    sub(/^[ \t\n]+/, "", x)
                    x = valnum(x, 0); if (E) return   # ?OV, or ?SN for a bad %: not ?REDO
                    if (!numrest()) { ok = 0; break }
                    assignv(name, key, "N" x)
                }
                # a store that fails (?OV into an integer, 1F33H -> 0A7FH)
                # ends the INPUT: the items behind it are not assigned
                if (E) return
                idx++
            }
            if (!ok || idx > nlv) break
            s_puts("?? ")
        }
        if (ok) {
            if (nib > nlv || IBREST) { s_puts("?EXTRA IGNORED"); s_nl() }
            return
        }
        # ROM 2178: the message is the five bytes 3F 52 45 44 4F -- "?REDO"
        # -- and a carriage return.  The Level II manual prints it twice,
        # in the INPUT section and in its worked example.  "?REDO FROM
        # START" is BASIC-80's wording, not this machine's.
        s_puts("?REDO"); s_nl()
    }
}

# parse comma-separated items (quotes respected) from line into IB[base+1..]
# The ROM reads a typed line with READ's own item reader (21EBH stores a
# comma in front of the buffer "to make READ think" it is in a DATA
# statement), so a typed line ends where a DATA statement would:
#   * an unquoted ":" ends the item AND the data (2869H stops a string at
#     ":" or ","; RST 10H calls ":" an end of statement, 225B-225C).  What
#     is behind it is never read: IBREST says so, and INPUT answers with
#     ?EXTRA IGNORED, or with ?? when variables are still waiting
#   * text between a closing quote and the comma ("AB"CD) is neither a
#     comma nor an end: IBBAD, ?REDO when INPUT reaches the item
#   * IBQ marks a quoted item; read into a number it is ?REDO (the reader
#     takes nothing and is left on the quote)
#   * the blanks skipped around an item are RST 10H's: blank, tab, line feed
function parse_items(line, base,   cnt, i, n, c, j, item, q, bad) {
    cnt = base; i = 1; n = length(line); IBREST = 0
    for (;;) {
        q = 0; bad = 0
        while (i <= n && substr(line, i, 1) ~ /^[ \t\n]$/) i++
        if (i <= n && substr(line, i, 1) == "\"") {
            j = index(substr(line, i + 1), "\"")
            if (j == 0) { item = substr(line, i + 1); i = n + 1 }
            else { item = substr(line, i + 1, j - 1); i = i + j + 1 }
            q = 1
            while (i <= n && substr(line, i, 1) ~ /^[ \t\n]$/) i++
            if (i <= n && substr(line, i, 1) !~ /^[,:]$/) {
                bad = 1
                while (i <= n && substr(line, i, 1) !~ /^[,:]$/) i++
            }
        } else {
            j = i
            while (j <= n && substr(line, j, 1) !~ /^[,:]$/) j++
            item = substr(line, i, j - i)
            sub(/ +$/, "", item)
            i = j
        }
        cnt++; IB[cnt] = item; IBQ[cnt] = q; IBBAD[cnt] = bad
        if (i <= n && substr(line, i, 1) == ",") { i++; continue }
        if (i <= n) IBREST = 1                  # stopped at a ":"
        break
    }
    return cnt
}

# ---- DATA / READ / RESTORE -------------------------------------------------
function datascan(   i, k, j, dn) {
    NDATA = 0
    for (i = 1; i <= NL; i++) {
        k = LNS[i] ""
        if (!(k in TOKD)) tokline(k, runtext(LNS[i]))
        dn = 0                          # which DATA of the line (p75 lit_addr)
        for (j = 1; j <= TCN[k]; j++)
            if (TY[k, j] == "d") data_items(TK[k, j], LNS[i], ++dn)
    }
    DATADIRTY = 0
}

# DBAD marks a quoted item with text between its closing quote and the
# comma (DATA "AB"CD,EF): the ROM reads the string, looks for a comma or
# the end of the statement, and finds neither (225A-2260).  That is ?SN
# when READ REACHES the item, not before; until 2026-09-21 the rest of the
# line was dropped silently and EF was never read.
function data_items(txt, ln, dn,   ci, cn, c, j, item, wasq, bad, off) {
    ci = 1; cn = length(txt)
    for (;;) {
        bad = 0
        while (ci <= cn && substr(txt, ci, 1) ~ /^[ \t\n]$/) ci++    # RST 10H: blank, tab, line feed
        off = ci
        if (ci <= cn && substr(txt, ci, 1) == "\"") {
            off = ci + 1
            j = index(substr(txt, ci + 1), "\"")
            if (j == 0) { item = substr(txt, ci + 1); ci = cn + 1 }
            else { item = substr(txt, ci + 1, j - 1); ci = ci + j + 1 }
            wasq = 1
            while (ci <= cn && substr(txt, ci, 1) ~ /^[ \t\n]$/) ci++
            if (ci <= cn && substr(txt, ci, 1) != ",") {
                bad = 1
                while (ci <= cn && substr(txt, ci, 1) != ",") ci++
            }
        } else {
            j = ci
            while (j <= cn && substr(txt, j, 1) != ",") j++
            item = substr(txt, ci, j - ci)
            sub(/ +$/, "", item)
            ci = j
            wasq = 0
        }
        NDATA++; DITEM[NDATA] = item; DQ[NDATA] = wasq; DBAD[NDATA] = bad; DLINE[NDATA] = ln
        DLIT[NDATA] = lit_spec(ln, "d", dn, off)   # where READ's string points (2240H)
        if (ci <= cn && substr(txt, ci, 1) == ",") { ci++; continue }
        break
    }
}

# The DATA pointer (40FFH) is committed only when the READ statement ENDS:
# the ROM carries it on the stack from 21F0H and stores it at 1D96H, reached
# from 2274H after the last item.  So an error inside a READ -- ?OV at the
# store (224AH -> 1F33H -> 0A7FH), ?SN in the DATA line (217FH), ?OD
# (22A2H), a bad subscript from 260DH -- leaves the pointer where the
# statement began, and RESUME re-reads the whole statement; the items stored
# before the error keep their values.  Until 2026-09-24 the pointer moved
# past every item as it was stored, so RESUME went on from the wrong item.
function st_read(   dp0) {
    if (DATADIRTY) datascan()
    dp0 = DP
    st_read_items()
    if (E) DP = dp0
}

function st_read_items(   name, key, x) {
    for (;;) {
        if (TY[CK, CP] != "i") { raise(2); return }
        name = lvname()
        key = ""
        if (TY[CK, CP] == "o" && TK[CK, CP] == "(") { key = aref(name); if (E) return }
        if (DP > NDATA) { raise(4); return }
        # text behind a closing quote, or a quoted item for a number (the
        # ROM's reader takes nothing from "12" and the quote is no comma):
        # ?SN in the DATA line, the pointer stays (225A-2260 -> 1991H)
        if (DBAD[DP] || (DQ[DP] && !strname(name))) {
            raise(2)
            ERR_AT = DLINE[DP]; ERLV = DLINE[DP]
            return
        }
        if (strname(name)) {
            assignv(name, key, "S" DITEM[DP])
            lit_note((key != "") ? "A" key : "V" name, DLIT[DP])
        } else {
            # the ROM's reader takes what it can (valnum, p90); anything
            # but blanks left over is ?SN in the DATA line (225A-2260 ->
            # 1991H).  A bad % is ?SN from inside the reader (1997H), which
            # names the READ's own line.
            x = DITEM[DP]
            sub(/^[ \t\n]+/, "", x)
            x = valnum(x, 0); if (E) return
            if (!numrest()) {
                raise(2)
                ERR_AT = DLINE[DP]; ERLV = DLINE[DP]
                return
            }
            assignv(name, key, "N" x)
        }
        if (E) return                       # ?OV at the store: nothing stored
        DP++
        if (TY[CK, CP] == "o" && TK[CK, CP] == ",") { CP++; continue }
        return
    }
}

# ---- DIM -------------------------------------------------------------------
function st_dim(   name, nd, i, v, sz) {
    for (;;) {
        if (TY[CK, CP] != "i") { raise(2); return }
        name = TK[CK, CP]; CP++
        if (!(TY[CK, CP] == "o" && TK[CK, CP] == "(")) {
            # EXT (gated): DIM of a scalar (DIM Z!,V!,L$ declaration lists,
            # period habit for variable-lookup speed) -- accepted no-op
            if (EXTON && (at_stmt_end() || (TY[CK, CP] == "o" && TK[CK, CP] == ","))) {
                if (TY[CK, CP] == "o" && TK[CK, CP] == ",") { CP++; continue }
                return
            }
            raise(2); return
        }
        CP++
        nd = 0
        for (;;) {
            v = e_or(); if (E) return
            if (!isN(v)) { raise(13); return }
            sz = bfloor(num(v))
            if (sz < 0) { raise(5); return }     # ROM 1E45-1E4C: ?FC, not ?BS
            nd++; DIMB[nd] = sz
            if (TY[CK, CP] == "o" && TK[CK, CP] == ",") { CP++; continue }
            break
        }
        if (!(TY[CK, CP] == "o" && TK[CK, CP] == ")")) { raise(2); return }
        CP++
        if (name in ADIM) { raise(10); return }
        ADIM[name] = nd
        for (i = 1; i <= nd; i++) ASZ[name, i] = DIMB[i]
        if (TY[CK, CP] == "o" && TK[CK, CP] == ",") { CP++; continue }
        return
    }
}

# ---- PEEK / POKE -----------------------------------------------------------
# Negative addresses wrap (the Microsoft convention: POKE -1 is 65535).
# NOTE the 65535 bound here is the SECOND place the machine size lives -- the
# first is RAMTOP (p10 init_tables).  They agree today, which is why dopeek's
# `a > RAMTOP` test is unreachable; if a 16K/32K machine is ever modelled,
# both have to change together.
# A byte argument, the way the ROM takes one (2B1C-2B22: the value of
# POKE, both arguments of OUT): convert to an integer, rounding down --
# ?OV outside -32768..32767 -- then ?FC unless the high byte is zero.
# POKE A,256 and POKE A,-1 store NOTHING on the machine.  Wrapping them to
# a byte, as this did until 2026-09-19, let a loader reading a damaged
# DATA item poke a wrong byte and carry on, where the machine stops at
# the bad line.
function byteconv(x) {
    x = bfloor(x)
    if (x < -32768 || x > 32767) { raise(6); return -1 }
    if (x < 0 || x > 255) { raise(5); return -1 }
    return x
}

function addrconv(x) {
    x = bfloor(x)
    if (x < 0) x += 65536
    if (x < 0 || x > 65535) { raise(5); return -1 }
    return x
}

# Resolution order is a CONTRACT the Z80 core must reproduce byte-for-byte --
# it is written out in full in p75's "THE ADDRESS-RESOLUTION CONTRACT" (read
# side; poke_byte below has its own).  Keep the two in step; in particular SPK
# (rule 4) must stay ABOVE the program image (rule 5).
function dopeek(x,   a) {
    a = addrconv(x)
    if (E) return 0
    if (a >= 15360 && a <= 16383) return SCR[a - 15360]
    if (a >= 14336 && a <= 14591) return kb_matrix(a - 14336)
    # 37E8H-37E9H printer status: 63 = attached and ready, matching the
    # always-ready LPRINT host stream (corpus idiom: IF PEEK(14312)<>63
    # waits; =255 means no printer; >127 means busy).  POKEs land in MEM
    # but are never read back -- on hardware these regions are not RAM.
    if (a == 14312 || a == 14313) return 63
    # 40AA-40ACH: the ROM RND seed, live and POKEable (rnd_* in p90)
    if (a >= 16554 && a <= 16556) return rnd_peek(a - 16554)
    # live system pointers + the read-only tokenized program image (p75)
    if (a == 16548 || a == 16549 || a == 16561 || a == 16562 || a == 16633 || a == 16634)
        return pm_sysptr(a)
    if (a >= 16416 && a <= 16667 && (a in SVW)) return sv_peek(a)   # system variable window (p75)
    if (a in SPK) return sp_peek(a)               # VARPTR string space (p75)
    if (a >= 17129) {
        if (a > RAMTOP) return 255                # absent RAM above the physical top
        pm_sync(); pm_truncnote()
        # THE PROGRAM IMAGE IS WRITABLE (2026-09-12).  A byte the program (or a
        # USR routine) stored into the image range reads back -- image RAM is
        # RAM, as on the machine -- so a payload that keeps a buffer inside its
        # own loaded bytes works (the Dancing Demon's score/dance editor does
        # exactly this at 6B9BH).  Unwritten image addresses still read the
        # original tokenized byte.  RUN and LIST are unaffected: they work from
        # prog[] (the source text), never from PMEM, so a stray POKE here can
        # never corrupt the running program the way it would on hardware.
        if (a < PMEND) return (a in MEM) ? MEM[a] : PMEM[a]
    }
    return (a in MEM) ? MEM[a] : 255
}

# POKE a,b: the statement half parses; poke_byte() below is the store.
function st_poke(   v, a, b) {
    v = e_or(); if (E) return
    if (!isN(v)) { raise(13); return }
    a = addrconv(num(v)); if (E) return
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == ",")) { raise(2); return }
    CP++
    v = e_or(); if (E) return
    if (!isN(v)) { raise(13); return }
    b = byteconv(num(v)); if (E) return
    poke_byte(a, b)
}

# The ONE store primitive: a resolved 16-bit address and a byte 0-255.  Its
# order is CONTRACT, dopeek's twin -- a Z80 write from ../trs80_z80_core must
# land where a POKE of the same address lands.  Written out in full in p75's
# "THE ADDRESS-RESOLUTION CONTRACT, WRITE SIDE", including the four ranges
# where a write is stored but can never be read back.  Keep the two in step.
# Every writer that must agree with POKE comes through here: the POKE
# statement, the p77 shim applying a Z80 write-set, and the string-alias
# write-through (seam audit finding 7).  Marks the address dirty for the USR
# frame's delta tracking (p75 fr_*).
function poke_byte(a, b) {
    if (a >= 15360 && a <= 16383) { s_poke(a - 15360, b); sync_cursor() }
    else if (a >= 16554 && a <= 16556) rnd_poke(a - 16554, b)
    else if (a == 16561 || a == 16562) pm_sethimem(a, b)   # move HIMEM (p75)
    else if (a >= 16416 && a <= 16667 && (a in SVW)) sv_poke(a, b)   # system variable window (p75)
    else if (a in SPK) sp_poke(a, b)              # VARPTR write-through (p75)
    else if (a > RAMTOP) { }                      # absent RAM: discarded
    # 0000-2FFFH is the ROM: a store there changes nothing on the machine,
    # and PROTOCOL.md has the range holding no bytes on either side.  It
    # used to land in MEM[] and read back, from POKE and from a Z80
    # write-set alike (the 2026-09-19 audit, L-45).
    else if (a < 12288) { }
    else {
        # a store into a STALE image would be judged by the next build as one
        # made before the program changed, and dropped: bring the image up to
        # date first, so the byte belongs to the line it lands in (p75 pm_build)
        if (PROGDIRTY && a >= 17129) pm_sync()
        MEM[a] = b; if (FRTRACK) FRDIRTY[a] = 1
        if (a >= 16414 && a <= 16423) dv_update()   # the device vectors (side effect only)
        if (a == 16445) WIDE = int(b / 8) % 2       # 403DH: the ROM's 32-column print flag (side effect only)
    }
}

# ---- THE ROM DEVICE VECTORS (2026-09-11) ------------------------------------
# 401E/401FH (16414/5) is the video driver vector and 4026/4027H (16422/3)
# the printer driver vector; the ROM's drivers live at 0458H and 058DH.
# Period listings swap them: POKE 16414,141:POKE 16415,5 sends everything
# PRINTed to the printer (14 corpus files, the "print the whole report"
# mode), POKE 16422,88:POKE 16423,4 sends LPRINT to the screen (2 files,
# "no printer attached"), POKE 16422,103:POKE 16423,0 points the printer
# at a ROM RET so LLIST/LPRINT go nowhere (tip 74).  The cells are plain
# MEM[] (read rule 6, write rule 6) with this one side effect on write.
# ONLY the two ROM addresses and the RET re-route: any other value is a
# custom machine-language driver (32 corpus files install one at 16422/3),
# which cannot run without the core, and the closest honest behaviour is
# the driver it usually wraps -- the default.  Both vectors swapped at once
# would make the ROM loop; here the printer-to-video route wins and the
# video stays on the screen.
function dv_update(   v, l) {
    v = MEM[16414] + 256 * MEM[16415]; l = MEM[16422] + 256 * MEM[16423]
    LPTOVID = (l == 1112); LPOFF = (l == 103)
    VIDTOLP = (v == 1421 && !LPTOVID)
    if (VIDTOLP && LPFILE == "" && !DVNOTED) {
        DVNOTED = 1
        diag_err("VIDEO ROUTED TO THE PRINTER (POKE 16414/16415); set TRS80_PRINTER to see it, or POKE 16414,88:POKE 16415,4")
    }
}

# ---- SET / RESET / POINT ---------------------------------------------------
function st_setreset(on,   v, x, y, col) {
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == "(")) { raise(2); return }
    CP++
    v = e_or(); if (E) return
    if (!isN(v)) { raise(13); return }
    x = bfloor(num(v))
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == ",")) { raise(2); return }
    CP++
    v = e_or(); if (E) return
    if (!isN(v)) { raise(13); return }
    y = bfloor(num(v))
    col = -1                                # -1 = no color given (textbook)
    if (on && TY[CK, CP] == "o" && TK[CK, CP] == ",") {
        # EXT: SET(x,y,c) -- optional CoCo-style color 0-8.  Valid Level II
        # never writes a third argument, so period programs are unaffected;
        # RESET stays strictly two-argument.
        CP++
        v = e_or(); if (E) return
        if (!isN(v)) { raise(13); return }
        col = bfloor(num(v))
        if (col < 0 || col > 8) { raise(5); return }
    }
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == ")")) { raise(2); return }
    CP++
    if (x < 0 || x > 127 || y < 0 || y > 47) { raise(5); return }
    if (on) gset(x, y, col); else greset(x, y)
    sync_cursor()
}

function gcell(x, y) { return int(y / 3) * 64 + int(x / 2) }
function gbit(x, y) { return 2 ^ ((x % 2) + 2 * (y % 3)) }

function gset(x, y, col,   p, b) {
    p = gcell(x, y); b = SCR[p]
    if (b < 128 || b > 191) b = 128
    b = 128 + or(b - 128, gbit(x, y))
    # EXT: color is per character cell, last SET wins; a plain SET returns
    # the cell to default (B&W).  POINT is unaffected either way.
    if (col >= 0) CCOL[p] = col; else delete CCOL[p]
    s_poke(p, b)
}

function greset(x, y,   p, b) {
    p = gcell(x, y); b = SCR[p]
    if (b < 128 || b > 191) { s_poke(p, 128); return }
    b = 128 + and(b - 128, 63 - gbit(x, y))
    s_poke(p, b)
}

function gpoint(x, y,   p, b) {
    if (x < 0 || x > 127 || y < 0 || y > 47) { raise(5); return 0 }
    p = gcell(x, y); b = SCR[p]
    if (b < 128 || b > 191) return 0
    return and(b - 128, gbit(x, y)) ? -1 : 0
}

# ---- CMD -------------------------------------------------------------------
# CMD calls a TRSDOS service.  A cassette Level II machine has no DOS to call,
# so every form raises ?SN exactly as it always has -- except the one Model III
# TRSDOS 1.3 easter egg, CMD"&"&, which printed a hidden message from the
# people who wrote that DOS.  Ours says who wrote this one.
# EXT.  Safe as an always-on extension: the trigger is the literal three-token
# sequence CMD "&" & , which no Level II program can execute (CMD always
# errored on a cassette machine) and no OCR damage can plausibly spell.
# Dispatch (execstmt, p70) only routes here when a string LITERAL follows CMD,
# so `CMD A$` and CMD-as-a-variable-name keep the behavior they had.
function st_cmd(   s) {
    s = TK[CK, CP]; CP++                    # the string literal after CMD
    if (s != "&" || TY[CK, CP] != "o" || TK[CK, CP] != "&") { raise(2); return }
    CP++
    if (!at_stmt_end()) { raise(2); return }
    s_puts(egg_text()); s_nl()
}

# The message is not stored in the clear: it is xor-folded, byte by byte,
# against the incantation that summons it, so a passing eye -- or a grep over
# the source -- does not spoil the surprise.  Gentle, not secret; anyone who
# reads this function can unfold it, and that is the intended level of effort.
function egg_text(   h, k, i, n, s) {
    h = "17050D75630F05750A0E646F106D0A69176D07691314166F" \
        "04051063076D067F630905700A0964600C1F066F10616414" \
        "737F72"
    k = "CMD&"
    n = length(h) / 2
    for (i = 1; i <= n; i++)
        s = s CHR[xor(strtonum("0x" substr(h, i + i - 1, 2)), \
                      ORD[substr(k, (i - 1) % length(k) + 1, 1)])]
    return s
}
