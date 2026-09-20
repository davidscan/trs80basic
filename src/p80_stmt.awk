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
        if (isN(v)) s_puts(fmtnum(num(v)))
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
        if (isN(v)) lp_puts(fmtnum(num(v)))
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
    # in place: the target keeps its length and its descriptor (p75 finding 7)
    al_setinplace(name, key, substr(s, 1, n - 1) substr(r, 1, cnt) substr(s, n + cnt))
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
    if (substr(fmt, j, 4) == "^^^^") { PU_EXP = 1; j += 4 }
    c = substr(fmt, j, 1)
    if (c == "-" || c == "+") { PU_TS = c; j++ }
    return j - i
}

# format one numeric value into the field pu_scan just described.
# Digits come from an integer-scaled half-up round (the ROM rounds .5 up;
# C's printf rounds it to even), built back into int/decimal parts.
function pu_num(v,   x, ax, neg, digs, e2, es, ds, ist, dec, lead, core, w, fill, g, p, lim) {
    if (!isN(v)) { raise(13); return "" }
    x = num(v)
    neg = (x < 0)
    ax = neg ? -x : x
    lead = PU_PLUS ? (neg ? "-" : "+") : ((neg && PU_TS == "") ? "-" : "")
    if (PU_EXP) {
        # significant digits fill every integer position (exponent adjusted);
        # the sign, when shown on the left, takes one of them
        digs = PU_IP - (lead != "" && !PU_PLUS ? 1 : 0)
        if (digs < 1) return pu_ovf(x)
        if (ax == 0) { e2 = 0; ds = "0" }
        else {
            e2 = bfloor(log(ax) / log(10)) + 1 - digs
            lim = 10 ^ (digs + PU_DP)
            p = int(ax / (10 ^ e2) * (10 ^ PU_DP) + 0.5)
            if (p >= lim) { e2++; p = int(ax / (10 ^ e2) * (10 ^ PU_DP) + 0.5) }
            else if (p < lim / 10) { e2--; p = int(ax / (10 ^ e2) * (10 ^ PU_DP) + 0.5) }
            ds = sprintf("%.0f", p)
        }
        while (length(ds) < PU_DP + 1) ds = "0" ds
        ist = substr(ds, 1, length(ds) - PU_DP)
        dec = substr(ds, length(ds) - PU_DP + 1)
        es = sprintf("E%s%02d", (e2 < 0 ? "-" : "+"), (e2 < 0 ? -e2 : e2))
        core = lead ist (PU_DOT ? "." dec : "") es
        w = PU_IP + (PU_PLUS ? 1 : 0) + (PU_DOT ? 1 + PU_DP : 0) + 4
        while (length(core) < w) core = " " core
    } else {
        ds = sprintf("%.0f", int(ax * (10 ^ PU_DP) + 0.5))
        while (length(ds) < PU_DP + 1) ds = "0" ds
        ist = substr(ds, 1, length(ds) - PU_DP)
        dec = substr(ds, length(ds) - PU_DP + 1)
        if (ist == "0" && PU_IP == 0) ist = ""      # ".##" style field
        if (PU_COMMA) {
            g = ""; p = length(ist)
            while (p > 3) { g = "," substr(ist, p - 2, 3) g; p -= 3 }
            ist = substr(ist, 1, p) g
        }
        core = lead (PU_DOL ? "$" : "") ist (PU_DOT ? "." dec : "")
        w = PU_IP + (PU_PLUS ? 1 : 0) + (PU_DOT ? 1 + PU_DP : 0)
        if (length(core) > w) return pu_ovf(x)
        fill = PU_AST ? "*" : " "
        while (length(core) < w) core = fill core
    }
    if (PU_TS == "-") core = core (neg ? "-" : " ")
    else if (PU_TS == "+") core = core (neg ? "-" : "+")
    return core
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
function st_input(   prompt, pq, nlv, name, key, i, line, nib, idx, ok, x) {
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
    nlv = 0
    for (;;) {
        if (TY[CK, CP] != "i") { raise(2); return }
        name = TK[CK, CP]; CP++
        key = ""
        if (TY[CK, CP] == "o" && TK[CK, CP] == "(") { key = aref(name); if (E) return }
        nlv++; LV_N[nlv] = name; LV_K[nlv] = key
        if (TY[CK, CP] == "o" && TK[CK, CP] == ",") { CP++; continue }
        break
    }
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
                if (strname(LV_N[idx])) assignv(LV_N[idx], LV_K[idx], "S" IB[idx])
                else {
                    x = IB[idx]
                    gsub(/^[ \t]+|[ \t]+$/, "", x)
                    if (x == "") x = "0"
                    if (!strictnum(x)) { ok = 0; break }
                    x = numconv(x); if (E) return           # ?OV, not ?REDO
                    assignv(LV_N[idx], LV_K[idx], "N" x)
                }
                idx++
            }
            if (!ok || idx > nlv) break
            s_puts("?? ")
        }
        if (ok) {
            if (nib > nlv) { s_puts("?EXTRA IGNORED"); s_nl() }
            return
        }
        s_puts("?REDO FROM START"); s_nl()
    }
}

# parse comma-separated items (quotes respected) from line into IB[base+1..]
function parse_items(line, base,   cnt, i, n, c, j, item) {
    cnt = base; i = 1; n = length(line)
    for (;;) {
        while (i <= n && substr(line, i, 1) == " ") i++
        if (i <= n && substr(line, i, 1) == "\"") {
            j = index(substr(line, i + 1), "\"")
            if (j == 0) { item = substr(line, i + 1); i = n + 1 }
            else { item = substr(line, i + 1, j - 1); i = i + j + 1 }
            while (i <= n && substr(line, i, 1) == " ") i++
        } else {
            j = i
            while (j <= n && substr(line, j, 1) != ",") j++
            item = substr(line, i, j - i)
            sub(/ +$/, "", item)
            i = j
        }
        cnt++; IB[cnt] = item
        if (i <= n && substr(line, i, 1) == ",") { i++; continue }
        break
    }
    return cnt
}

# ---- DATA / READ / RESTORE -------------------------------------------------
function datascan(   i, k, j) {
    NDATA = 0
    for (i = 1; i <= NL; i++) {
        k = LNS[i] ""
        if (!(k in TOKD)) tokline(k, prog[LNS[i]])
        for (j = 1; j <= TCN[k]; j++)
            if (TY[k, j] == "d") data_items(TK[k, j], LNS[i])
    }
    DATADIRTY = 0
}

function data_items(txt, ln,   ci, cn, c, j, item, wasq) {
    ci = 1; cn = length(txt)
    for (;;) {
        while (ci <= cn && substr(txt, ci, 1) == " ") ci++
        if (ci <= cn && substr(txt, ci, 1) == "\"") {
            j = index(substr(txt, ci + 1), "\"")
            if (j == 0) { item = substr(txt, ci + 1); ci = cn + 1 }
            else { item = substr(txt, ci + 1, j - 1); ci = ci + j + 1 }
            wasq = 1
            while (ci <= cn && substr(txt, ci, 1) == " ") ci++
        } else {
            j = ci
            while (j <= cn && substr(txt, j, 1) != ",") j++
            item = substr(txt, ci, j - ci)
            sub(/ +$/, "", item)
            ci = j
            wasq = 0
        }
        NDATA++; DITEM[NDATA] = item; DQ[NDATA] = wasq; DLINE[NDATA] = ln
        if (ci <= cn && substr(txt, ci, 1) == ",") { ci++; continue }
        break
    }
}

function st_read(   name, key, x) {
    if (DATADIRTY) datascan()
    for (;;) {
        if (TY[CK, CP] != "i") { raise(2); return }
        name = TK[CK, CP]; CP++
        key = ""
        if (TY[CK, CP] == "o" && TK[CK, CP] == "(") { key = aref(name); if (E) return }
        if (DP > NDATA) { raise(4); return }
        if (strname(name)) assignv(name, key, "S" DITEM[DP])
        else {
            x = DITEM[DP]
            gsub(/^[ \t]+|[ \t]+$/, "", x)
            if (x == "") x = "0"
            if (!strictnum(x)) {
                raise(2)
                ERR_AT = DLINE[DP]; ERLV = DLINE[DP]
                return
            }
            x = numconv(x); if (E) return
            assignv(name, key, "N" x)
        }
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
            if (sz < 0) { raise(9); return }
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
