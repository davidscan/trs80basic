# ===================== Disk BASIC file I/O ==================================
# Channels 1..15; the BASIC filename is a literal host path (same simulation
# as CLOAD/CSAVE).  Sequential files are plain text lines via gawk's named
# getline/print streams.  Random files are slurped into memory at OPEN "R",
# GET/PUT operate in memory, and CLOSE rewrites the file one record per line
# (non-printable bytes escaped as \xNN so MK*$-packed fields survive).
#
# State (per channel n):
#   FH_MODE[n]  "I"/"O"/"E"/"R" ("" = closed)   FH_NAME[n]  host path
#   FH_LOC[n]   lines read/written (seq) or last record touched (R)
#   FH_PEND[n]/FH_PENDHAS[n]   unconsumed input line (INPUT# item stepping)
#   FH_EOF[n]   input stream exhausted
#   FH_OPEND[n]/FH_OPENDHAS[n] partial output line (PRINT# ended in ; or ,)
#   FH_RLEN[n]/FH_BUF[n]/FH_NREC[n]/FH_REC[n,r]/FH_DIRTY[n]  random access
# Field maps: FLDN[n], FLD_V/O/W[n,i] (channel order) and FVCH/FVOF/FVW[tgt]
# (per-variable; a re-FIELD of a variable moves it, last fielding wins).
# A variable is named here by its TARGET, p75's form: "V" name for a simple
# variable, "A" key for an array element -- the Disk manual's own example
# is FIELD 1,16 AS CLIENT$(1) (the 2026-09-19 audit, M-29).  Membership is
# always asked with `in`: a bare FVCH[tgt] creates the key, and a created
# key made LSET on a variable fielded away raise ?NO.
function fld_tgt(name, key) { return (key != "") ? "A" key : "V" name }

function fio_isopen(n) { return FH_MODE[n] != "" }

# parse [#] numexpr as a channel number; raise 24 (BN) outside 1..15
function fio_chan(withhash,   v, n) {
    if (withhash && TY[CK, CP] == "o" && TK[CK, CP] == "#") CP++
    v = e_or(); if (E) return 0
    if (!isN(v)) { raise(13); return 0 }
    n = bfloor(num(v))
    if (n < 1 || n > 15) { raise(53); return 0 }
    return n
}

# channel argument of EOF/LOF/LOC: validated + must be open
function fio_fnchan(x,   n) {
    n = bfloor(x)
    if (n < 1 || n > 15) { raise(53); return 0 }
    if (!fio_isopen(n)) { raise(53); return 0 }
    return n
}

function fio_pad(s, k) { return substr(s sprintf("%" k "s", ""), 1, k) }

# ---- OPEN / CLOSE / KILL ---------------------------------------------------
function st_open(   v, mode, n, f, rlen, r, l, i, cnt, p) {
    v = e_or(); if (E) return
    if (isN(v)) { raise(13); return }
    mode = toupper(substr(vstr(v), 1, 1))
    if (mode != "I" && mode != "O" && mode != "E" && mode != "R") { raise(55); return }
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == ",")) { raise(2); return }
    CP++
    n = fio_chan(1); if (E) return
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == ",")) { raise(2); return }
    CP++
    v = e_or(); if (E) return
    if (isN(v)) { raise(13); return }
    f = vstr(v)
    if (f == "") { raise(21); return }
    rlen = 256
    if (TY[CK, CP] == "o" && TK[CK, CP] == ",") {
        CP++
        v = e_or(); if (E) return
        if (!isN(v)) { raise(13); return }
        rlen = bfloor(num(v))
        # Disk manual, OPEN: "record-length is a numeric expression from 0
        # to 256 specifying the logical record length.  0 is the same as
        # 256."  (TRSDOS keeps the LRL in one byte, +9 of the DCB, and
        # moves the whole 256-byte physical record when it is zero.)
        if (rlen < 0 || rlen > 256) { raise(5); return }
        if (rlen == 0) rlen = 256
    }
    if (fio_isopen(n)) { raise(70); return }
    for (i = 1; i <= 15; i++)
        if (fio_isopen(i) && FH_NAME[i] == f) { raise(70); return }
    if (toupper(f) ~ /^OLLAMA(:|$)/) { ai_open(n, f); return }
    if (host_special(f)) { raise(22); return }    # /inet/..., /dev/..., "-": not files (p90)
    # a device by another spelling, a directory, a FIFO: not a file either,
    # however it is written (the 2026-09-23 audit, H-3); "O", "E" and "R"
    # ask host_writable, which holds the same rule
    if (mode == "I" && host_kind(f) == "x") { raise(22); return }
    if (mode != "I") {
        # probe writability now: a failed awk redirect later would be fatal
        if ((!WINNATIVE && f ~ /'/) || !host_writable(f)) { raise(22); return }
    }
    FH_LOC[n] = 0; FH_EOF[n] = 0
    FH_PEND[n] = ""; FH_PENDHAS[n] = 0
    FH_RAW[n] = ""; FH_RAWHAS[n] = 0
    FH_OPEND[n] = ""; FH_OPENDHAS[n] = 0
    if (mode == "I") {
        r = (getline l < f)
        if (r < 0) { raise(54); return }
        if (r > 0) {
            sub(/\r$/, "", l)
            # a 0DH inside the line is a record end, as in fio_fill below
            p = index(l, CHR[13])
            if (p > 0) { FH_RAW[n] = substr(l, p + 1); FH_RAWHAS[n] = 1; l = substr(l, 1, p - 1) }
            FH_PEND[n] = l; FH_PENDHAS[n] = 1; FH_LOC[n] = 1
        }
        else FH_EOF[n] = 1
    } else if (mode == "O") printf "" > f
    else if (mode == "E") printf "" >> f
    else {                                  # "R": slurp records into memory
        cnt = 0
        while ((getline l < f) > 0) { cnt++; FH_REC[n, cnt] = fio_pad(fio_unesc(l), rlen) }
        close(f)
        FH_NREC[n] = cnt
        FH_RLEN[n] = rlen
        FH_BUF[n] = fio_pad("", rlen)
        FH_DIRTY[n] = 0
    }
    FH_NAME[n] = f
    FH_MODE[n] = mode
}

function st_close(   n, ty, tx) {
    ty = TY[CK, CP]; tx = TK[CK, CP]
    if (ty == "" || ty == "e" || (ty == "o" && tx == ":") || (ty == "i" && tx == "ELSE")) {
        fio_closeall()
        return
    }
    for (;;) {
        n = fio_chan(1); if (E) return
        fio_close1(n)
        if (TY[CK, CP] == "o" && TK[CK, CP] == ",") { CP++; continue }
        break
    }
}

# closing an unopened channel is a silent no-op (Disk BASIC is forgiving)
function fio_close1(n,   f, r) {
    if (!fio_isopen(n)) return
    f = FH_NAME[n]
    if (FH_MODE[n] == "O" || FH_MODE[n] == "E") {
        if (FH_OPENDHAS[n]) print FH_OPEND[n] >> f
        close(f)
    } else if (FH_MODE[n] == "I") close(f)
    else if (FH_MODE[n] == "R") {
        # only a PUT makes the file worth writing: a file opened to GET from
        # is left byte for byte as it was (the rewrite re-pads every record
        # to this OPEN's length and re-escapes it)
        if (FH_DIRTY[n]) fio_flushR(n)
    }
    else ai_close(n)                        # "A": unsent prompt is discarded
    for (r = 1; r <= FH_NREC[n]; r++) delete FH_REC[n, r]
    for (r = 1; r <= FLDN[n]; r++) {
        if ((FLD_V[n, r] in FVCH) && FVCH[FLD_V[n, r]] == n) {
            delete FVCH[FLD_V[n, r]]; delete FVOF[FLD_V[n, r]]; delete FVW[FLD_V[n, r]]
        }
        delete FLD_V[n, r]; delete FLD_O[n, r]; delete FLD_W[n, r]
    }
    delete FLDN[n]
    delete FH_MODE[n]; delete FH_NAME[n]; delete FH_LOC[n]
    delete FH_PEND[n]; delete FH_PENDHAS[n]; delete FH_EOF[n]
    delete FH_RAW[n]; delete FH_RAWHAS[n]
    delete FH_OPEND[n]; delete FH_OPENDHAS[n]
    delete FH_RLEN[n]; delete FH_BUF[n]; delete FH_NREC[n]; delete FH_DIRTY[n]
}

function fio_flushR(n,   f, r) {
    f = FH_NAME[n]
    printf "" > f
    for (r = 1; r <= FH_NREC[n]; r++) print fio_esc(FH_REC[n, r]) >> f
    close(f)
}

function fio_closeall(   i) {
    for (i = 1; i <= 15; i++) fio_close1(i)
}

function st_kill(   v, f, i) {
    v = e_or(); if (E) return
    if (isN(v)) { raise(13); return }
    f = vstr(v)
    if (f == "") { raise(21); return }
    for (i = 1; i <= 15; i++)
        if (fio_isopen(i) && FH_NAME[i] == f) { raise(70); return }
    if (!WINNATIVE && f ~ /'/) { raise(22); return }
    if (!host_exists(f)) { raise(54); return }
    # a delete the host refuses -- a read-only directory, say -- used to be
    # ignored: rm complained on the program's own error channel, the file
    # stayed, and the program carried on as though it had gone.  ?FD is what
    # every other host refusal here reports (the 2026-09-19 audit, L-5).
    if (!host_delete(f)) { raise(22); return }
}

# ---- sequential input ------------------------------------------------------
# ensure FH_PEND holds a line; 0 at end of file
# A CARRIAGE RETURN ENDS A RECORD, wherever it falls.  The Disk manual puts
# (ENTER) in every INPUT# terminator set, and LINE INPUT# reads up to "an
# (ENTER) character" -- on the machine the file is a byte stream and 0DH is
# what separates records, so a CHR$(13) a program PRINT#s is a record end
# like any other.  Here the reader knew only gawk's own line split, so an
# embedded 0DH stayed inside the item (the 2026-09-19 audit, L-35).  The text
# after it is held in FH_RAW and served as the next line, so a file whose
# records end in CR alone -- the machine's own form -- reads record by
# record instead of arriving as one enormous line.  A trailing CR (a CR LF
# pair) is still just the line end.
function fio_fill(n,   r, l, p) {
    if (FH_MODE[n] == "A") return ai_fill(n)
    if (FH_PENDHAS[n]) return 1
    if (FH_RAWHAS[n]) { l = FH_RAW[n]; FH_RAW[n] = ""; FH_RAWHAS[n] = 0 }
    else {
        if (FH_EOF[n]) return 0
        r = (getline l < FH_NAME[n])
        if (r <= 0) { FH_EOF[n] = 1; return 0 }
        sub(/\r$/, "", l)
    }
    p = index(l, CHR[13])
    if (p > 0) {
        FH_RAW[n] = substr(l, p + 1); FH_RAWHAS[n] = 1
        l = substr(l, 1, p - 1)
    }
    FH_PEND[n] = l; FH_PENDHAS[n] = 1; FH_LOC[n]++
    return 1
}

# extract one item (quotes respected) into FIO_IT, leaving the unconsumed
# remainder pending so one line can feed several INPUT#s.  A string item
# ends at a comma or the end of the line; a NUMERIC item (isnum) ends at a
# blank as well, and the blanks after it and one comma go with the
# terminator (Disk manual, INPUT#: the image " 1.234 -33 27" read by
# INPUT#1,A,B,C gives 1.234, -33 and 27) -- which is what lets the
# manual's own PRINT#1,A;B;C be read back.
function fio_next_item(n, isnum,   l, i, len, j, c, item, ist) {
    if (!fio_fill(n)) return 0
    l = FH_PEND[n]
    i = 1; len = length(l)
    while (i <= len && substr(l, i, 1) == " ") i++
    if (i <= len && substr(l, i, 1) == "\"") {
        ist = i + 1                             # where this item's data starts
        j = index(substr(l, i + 1), "\"")
        if (j == 0) { item = substr(l, i + 1); i = len + 1 }
        else { item = substr(l, i + 1, j - 1); i = i + j + 1 }
        while (i <= len && substr(l, i, 1) == " ") i++
    } else if (isnum) {
        ist = i
        j = i
        while (j <= len && (c = substr(l, j, 1)) != "," && c != " ") j++
        item = substr(l, i, j - i)
        i = j
        while (i <= len && substr(l, i, 1) == " ") i++
    } else {
        ist = i
        j = i
        while (j <= len && substr(l, j, 1) != ",") j++
        item = substr(l, i, j - i)
        sub(/ +$/, "", item)
        i = j
    }
    # Disk manual, INPUT#: EVERY one of the three terminator sets -- numeric,
    # quoted string, unquoted string -- lists "255th data character
    # encountered" beside the comma and the end of file.  An item longer
    # than that was returned whole here (the 2026-09-19 audit, L-41).  The
    # 255th character IS the terminator, so the next read resumes right
    # after it -- no comma is consumed, because none was reached.
    if (length(item) > 255) {
        item = substr(item, 1, 255)
        i = ist + 255
    } else if (i <= len && substr(l, i, 1) == ",") i++
    if (i > len) FH_PENDHAS[n] = 0
    else FH_PEND[n] = substr(l, i)
    FIO_IT = item
    return 1
}

function st_input_file(   n, nlv, name, key, i, x) {
    n = fio_chan(0); if (E) return
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == ",")) { raise(2); return }
    CP++
    if (!fio_isopen(n)) { raise(53); return }
    if (FH_MODE[n] != "I" && FH_MODE[n] != "A") { raise(55); return }
    # each target is resolved when its item is stored, after the
    # assignments before it (INPUT#1,I,A(I)), as INPUT and READ do
    for (;;) {
        if (TY[CK, CP] != "i") { raise(2); return }
        name = lvname()
        key = ""
        if (TY[CK, CP] == "o" && TK[CK, CP] == "(") { key = aref(name); if (E) return }
        if (!fio_next_item(n, !strname(name))) { raise(63); return }
        if (strname(name)) assignv(name, key, "S" FIO_IT)
        else {
            # the item is evaluated "by a routine just like the BASIC VAL
            # function" (Disk manual, INPUT#): A12 is 0, 5X is 5, never ?TM
            x = valnum(FIO_IT, 0); if (E) return   # ?OV: nothing stored
            assignv(name, key, "N" x)
        }
        if (E) return
        if (TY[CK, CP] == "o" && TK[CK, CP] == ",") { CP++; continue }
        break
    }
}

# LINE INPUT [#n,] -- whole-line read, no comma splitting, no "? " prompt
function st_lineinput(   n, name, key, prompt, line, x) {
    if (!(TY[CK, CP] == "i" && TK[CK, CP] == "INPUT")) { raise(2); return }
    CP++
    if (TY[CK, CP] == "o" && TK[CK, CP] == "#") {
        CP++
        n = fio_chan(0); if (E) return
        if (!(TY[CK, CP] == "o" && TK[CK, CP] == ",")) { raise(2); return }
        CP++
        if (!fio_isopen(n)) { raise(53); return }
        if (FH_MODE[n] != "I" && FH_MODE[n] != "A") { raise(55); return }
        if (TY[CK, CP] != "i") { raise(2); return }
        name = TK[CK, CP]; CP++
        if (!strname(name)) { raise(13); return }
        key = ""
        if (TY[CK, CP] == "o" && TK[CK, CP] == "(") { key = aref(name); if (E) return }
        if (!fio_fill(n)) { raise(63); return }
        # Disk manual, LINE INPUT#: it "reads everything from the first
        # character up to: 1. an (ENTER) character ... 2. the end of file
        # 3. the 255th data character (this 255 character is included in
        # the string)".  There was no limit here, so a long line came back
        # as a string longer than one can hold (the 2026-09-19 audit, L-41).
        # What is left stays for the next read, as a terminator would leave it.
        line = FH_PEND[n]
        if (length(line) > 255) {
            FH_PEND[n] = substr(line, 256)
            line = substr(line, 1, 255)
        } else FH_PENDHAS[n] = 0
        assignv(name, key, "S" line)
        return
    }
    if (CK == "I") { raise(12); return }
    prompt = ""
    if (TY[CK, CP] == "s") {
        if (TY[CK, CP + 1] == "o" && TK[CK, CP + 1] == ";") {
            prompt = TK[CK, CP]; CP++
        } else {
            # prompt expression, same as st_input
            x = e_or(); if (E) return
            if (substr(x, 1, 1) != "S") { raise(13); return }
            prompt = substr(x, 2)
        }
        if (TY[CK, CP] == "o" && TK[CK, CP] == ";") CP++
        else { raise(2); return }
    }
    if (TY[CK, CP] != "i") { raise(2); return }
    name = TK[CK, CP]; CP++
    if (!strname(name)) { raise(13); return }
    key = ""
    if (TY[CK, CP] == "o" && TK[CK, CP] == "(") { key = aref(name); if (E) return }
    if (prompt != "") s_puts(prompt)
    line = rl_read()
    if (RLCANCEL) { dobreak(); return }
    if (EOFQUIT) { if (BATCH) batch_ineof(); STOPPED = 1; return }
    assignv(name, key, "S" line)
}

# ---- sequential output -----------------------------------------------------
# PRINT #n, ... : "a disk image similar to what a PRINT to display creates
# on the screen" (Model III Disk manual, PRINT#).  ; joins; , writes blanks
# up to the next 16-column zone of the FILE's line, the manual's own case:
# PRINT#1,A,B with A=2300 "causes 10 extra spaces in the disk file".  The
# ROM's comma code leaves through the Disk BASIC exit at 41D3H (2108H), so
# the column is the file's, not the screen's.  The manual names no last
# zone for a file, so none is assumed: no carriage return is ever written
# for a comma.  A trailing separator holds the partial line in FH_OPEND
# until the next PRINT# or CLOSE.
function fio_col(s) {                       # the column the file's line is at
    if (match(s, /.*[\r\n]/)) return length(s) - RLENGTH
    return length(s)
}

function st_print_file(   n, s, sep, ty, tx, v, x) {
    n = fio_chan(0); if (E) return
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == ",")) { raise(2); return }
    CP++
    if (!fio_isopen(n)) { raise(53); return }
    if (FH_MODE[n] != "O" && FH_MODE[n] != "E" && FH_MODE[n] != "A") { raise(55); return }
    s = FH_OPENDHAS[n] ? FH_OPEND[n] : ""
    if (TY[CK, CP] == "i" && TK[CK, CP] == "USING") { CP++; fio_pr_using(n, s); return }
    sep = 0
    for (;;) {
        ty = TY[CK, CP]
        if (ty == "" || ty == "e") break
        tx = TK[CK, CP]
        if (ty == "o" && tx == ":") break
        if (ty == "i" && tx == "ELSE") break
        if (ty == "i" && tx == "USING") { CP++; fio_pr_using(n, s); return }
        if (ty == "o" && tx == ";") { sep = 1; CP++; continue }
        if (ty == "o" && tx == ",") {
            s = s substr("                ", 1, 16 - (fio_col(s) % 16))
            sep = 1; CP++
            continue
        }
        if (ty == "i" && tx == "TAB") {
            CP++
            if (!(TY[CK, CP] == "o" && TK[CK, CP] == "(")) { raise(2); return }
            CP++
            v = e_or(); if (E) return
            if (!isN(v)) { raise(13); return }
            x = bfloor(num(v))
            if (TY[CK, CP] == "o" && TK[CK, CP] == ")") CP++
            else { raise(2); return }
            while (length(s) < x) s = s " "
            sep = 1
            continue
        }
        v = e_or(); if (E) return
        s = s (isN(v) ? fmtnum(num(v)) : vstr(v))
        sep = 0
    }
    fio_pr_out(n, s, sep)
}

# PRINT# USING tail -- the file twin of pr_using(), same any-position rule;
# `s` carries whatever the item list built before USING took over.
function fio_pr_using(n, s,   sep, ty, tx, v, fmt) {
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
        if (ty == "i" && tx == "ELSE") break
        if (ty == "o" && (tx == ";" || tx == ",")) { sep = 1; CP++; continue }
        v = e_or(); if (E) return
        PUV[++PUN] = v
        sep = 0
    }
    v = pu_output(fmt, PUN); if (E) return
    fio_pr_out(n, s v, sep)
}

# finish a PRINT# statement: hold the partial line on a trailing separator,
# else emit it (OLLAMA prompt buffer for mode "A", the file otherwise)
function fio_pr_out(n, s, sep) {
    if (sep) { FH_OPEND[n] = s; FH_OPENDHAS[n] = 1 }
    else if (FH_MODE[n] == "A") {           # completed prompt line, not sent yet
        AI_PROMPT[n] = AI_PROMPT[n] s "\n"
        FH_OPEND[n] = ""; FH_OPENDHAS[n] = 0
    }
    else {
        print s >> FH_NAME[n]
        FH_OPEND[n] = ""; FH_OPENDHAS[n] = 0
        FH_LOC[n]++
    }
}

# ---- random access ---------------------------------------------------------
function st_field(   n, off, w, v, name, key, tgt, i, found) {
    n = fio_chan(1); if (E) return
    if (!fio_isopen(n)) { raise(53); return }
    if (FH_MODE[n] != "R") { raise(55); return }
    off = 0
    for (;;) {
        if (!(TY[CK, CP] == "o" && TK[CK, CP] == ",")) { raise(2); return }
        CP++
        v = e_or(); if (E) return
        if (!isN(v)) { raise(13); return }
        w = bfloor(num(v))
        if (w < 0) { raise(5); return }
        if (!(TY[CK, CP] == "i" && TK[CK, CP] == "AS")) { raise(2); return }
        CP++
        if (TY[CK, CP] != "i") { raise(2); return }
        name = TK[CK, CP]; CP++
        key = ""
        if (TY[CK, CP] == "o" && TK[CK, CP] == "(") { key = aref(name); if (E) return }
        if (!strname(name)) { raise(13); return }
        if (off + w > FH_RLEN[n]) { raise(51); return }
        tgt = fld_tgt(name, key)
        found = 0
        for (i = 1; i <= FLDN[n]; i++)
            if (FLD_V[n, i] == tgt) { found = i; break }
        if (!found) { FLDN[n]++; found = FLDN[n]; FLD_V[n, found] = tgt }
        FLD_O[n, found] = off; FLD_W[n, found] = w
        FVCH[tgt] = n; FVOF[tgt] = off; FVW[tgt] = w
        FLDANY = 1                          # assignv (p70) now looks for field variables
        sp_sets(tgt, substr(FH_BUF[n], off + 1, w))
        off += w
        if (!(TY[CK, CP] == "o" && TK[CK, CP] == ",")) break
    }
}

# refresh fielded vars from the channel buffer (skip vars re-FIELDed away)
function fld_sync(n,   i, v) {
    for (i = 1; i <= FLDN[n]; i++) {
        v = FLD_V[n, i]
        if ((v in FVCH) && FVCH[v] == n) sp_sets(v, substr(FH_BUF[n], FLD_O[n, i] + 1, FLD_W[n, i]))
    }
}

# is tgt a FIELD variable that s (a whole new value) fits?
function fld_is(tgt, s) {
    return (tgt in FVCH) && length(s) == FVW[tgt]
}

# store s, FVW[name] long, as a FIELD variable's slice of its record buffer.
# Every in-place string store reaches the buffer through here: LSET, RSET
# and MID$= (which wrote the variable only, so PUT wrote the old record:
# the 2026-09-19 audit, M-25).
function fld_put(tgt, s,   n) {
    n = FVCH[tgt]
    FH_BUF[n] = substr(FH_BUF[n], 1, FVOF[tgt]) s substr(FH_BUF[n], FVOF[tgt] + FVW[tgt] + 1)
    fld_sync(n)
}

# An ordinary assignment (LET, INPUT, READ: assignv, p70) gives the variable
# a new descriptor in string space, so it "will no longer point to the
# buffer field" (Disk manual, "More on field names": A$=B$ nullifies the
# FIELD).  GET no longer refills it and LSET works within its own length,
# until a FIELD names it again.  The channel's FLD_V list keeps the entry;
# fld_sync skips what is not in FVCH.  assignv asks only once a FIELD has
# run (FLDANY): it is the hottest store in the interpreter.
function fld_detach(name, key,   tgt) {
    tgt = fld_tgt(name, key)
    if (tgt in FVCH) { delete FVCH[tgt]; delete FVOF[tgt]; delete FVW[tgt] }
}

function fio_just(s, w, left) {
    if (length(s) >= w) return substr(s, 1, w)
    if (left) return s fio_pad("", w - length(s))
    return fio_pad("", w - length(s)) s
}

# LSET (left=1) / RSET (left=0): justify into a fielded var's buffer slice;
# on a non-fielded string var, justify within its current length
function st_lset(left,   name, key, v, s, tgt, cur) {
    if (TY[CK, CP] != "i") { raise(2); return }
    name = TK[CK, CP]; CP++
    key = ""
    if (TY[CK, CP] == "o" && TK[CK, CP] == "(") { key = aref(name); if (E) return }
    if (!(TY[CK, CP] == "o" && TK[CK, CP] == "=")) { raise(2); return }
    CP++
    v = e_or(); if (E) return
    if (!strname(name) || isN(v)) { raise(13); return }
    s = vstr(v)
    tgt = fld_tgt(name, key)
    if (tgt in FVCH) {
        fld_put(tgt, fio_just(s, FVW[tgt], left))
        return
    }
    cur = al_cur(name, key); if (E) return
    s = fio_just(s, length(cur), left)
    al_setinplace(name, key, s)                   # in place (p75 finding 7)
}

function st_get(   n, rec, v) {
    n = fio_chan(1); if (E) return
    if (!fio_isopen(n)) { raise(53); return }
    if (FH_MODE[n] != "R") { raise(55); return }
    rec = FH_LOC[n] + 1
    if (TY[CK, CP] == "o" && TK[CK, CP] == ",") {
        CP++
        v = e_or(); if (E) return
        if (!isN(v)) { raise(13); return }
        rec = bfloor(num(v))
    }
    if (rec < 1 || rec > 65535) { raise(64); return }
    # past the last record: "BASIC simply fills the buffer with hexadecimal
    # zeros, and no error is generated" (Disk manual, GET and LOF; the error
    # it speaks of is for variable-length records, which are not served).
    # This was ?IE while `man GET` promised spaces (the 2026-09-19 audit,
    # M-27).  EOF(n) is true afterwards, and LOF(n) is the test beforehand.
    if (rec > FH_NREC[n]) { FH_BUF[n] = ""; while (length(FH_BUF[n]) < FH_RLEN[n]) FH_BUF[n] = FH_BUF[n] CHR[0] }
    else FH_BUF[n] = fio_pad(FH_REC[n, rec], FH_RLEN[n])
    FH_LOC[n] = rec
    fld_sync(n)
}

function st_put(   n, rec, v, r) {
    n = fio_chan(1); if (E) return
    if (!fio_isopen(n)) { raise(53); return }
    if (FH_MODE[n] != "R") { raise(55); return }
    rec = FH_LOC[n] + 1
    if (TY[CK, CP] == "o" && TK[CK, CP] == ",") {
        CP++
        v = e_or(); if (E) return
        if (!isN(v)) { raise(13); return }
        rec = bfloor(num(v))
    }
    if (rec < 1 || rec > 65535) { raise(64); return }
    if (rec > FH_NREC[n]) {
        for (r = FH_NREC[n] + 1; r < rec; r++) FH_REC[n, r] = fio_pad("", FH_RLEN[n])
        FH_NREC[n] = rec
    }
    FH_REC[n, rec] = FH_BUF[n]
    FH_LOC[n] = rec
    FH_DIRTY[n] = 1
}

# ---- record serialization: one escaped line per record ---------------------
function fio_esc(s,   out, i, n, c, o) {
    out = ""; n = length(s)
    for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (c == "\\") { out = out "\\\\"; continue }
        o = (c in ORD) ? ORD[c] : 63
        if (o < 32 || o > 126) out = out sprintf("\\x%02X", o)
        else out = out c
    }
    return out
}

function fio_unesc(s,   out, i, n, c) {
    out = ""; i = 1; n = length(s)
    while (i <= n) {
        c = substr(s, i, 1)
        if (c == "\\" && i < n) {
            if (substr(s, i + 1, 1) == "\\") { out = out "\\"; i += 2; continue }
            if (substr(s, i + 1, 1) == "x" && i + 3 <= n) {
                out = out CHR[strtonum("0x" substr(s, i + 2, 2))]
                i += 4
                continue
            }
        }
        out = out c; i++
    }
    return out
}

# ---- MKI$/MKS$/MKD$ / CVI/CVS/CVD: Microsoft Binary Format -----------------
# 2-byte int, 4-byte single, 8-byte double, little-endian; float layout is
# mantissa LSB..MSB (sign replaces the implied leading 1 bit), exponent+128
function fio_mki(x,   v, u) {
    # Disk manual p.144: the argument "is evaluated as an integer, -32768
    # <= n <= 32767; if it exceeds this range, an ILLEGAL FUNCTION CALL
    # error" -- ?FC, where the plain integer conversion (to16, CINT's) says
    # ?OV.  The fraction goes the way CINT drops it: down (H-5).
    v = bfloor(x)
    if (v < -32768 || v > 32767) { raise(5); return "" }
    u = (v < 0) ? v + 65536 : v
    return CHR[u % 256] CHR[int(u / 256)]
}

function fio_cvi(s,   u) {
    if (length(s) < 2) { raise(5); return 0 }
    u = ORD[substr(s, 1, 1)] + 256 * ORD[substr(s, 2, 1)]
    return (u >= 32768) ? u - 65536 : u
}

function fio_mkf(x, nb,   sgn, e, i, b, out) {
    if (x == 0) {
        out = ""
        for (i = 1; i <= nb; i++) out = out CHR[0]
        return out
    }
    sgn = 0
    if (x < 0) { sgn = 128; x = -x }
    if (x > 1.7e38) { raise(6); return "" }     # an infinity would never leave the loop
    e = 0
    while (x >= 1) { x /= 2; e++ }
    while (x < 0.5) { x *= 2; e-- }
    e += 128
    if (e > 255) { raise(6); return "" }
    if (e < 1) {                            # underflow -> zero
        out = ""
        for (i = 1; i <= nb; i++) out = out CHR[0]
        return out
    }
    for (i = 1; i <= nb - 1; i++) { x *= 256; b = int(x); x -= b; FIO_MB[i] = b }
    # What is left of x is the guard byte.  The ROM rounds on it (0796H: top
    # bit set -> 07A8H bumps the mantissa, the carry going up through the
    # bytes and, from FFFFFFH, into the exponent with ?OV at 07B2H), so .1
    # is CDH CCH CCH 7DH on the machine.  Cutting it off gave CCH, and
    # INT(CVS(MKS$(.07))*100) was 6 (the 2026-09-19 audit, M-26).  Only a
    # single has anything left here: a double's 53 bits fit the 56.
    if (x >= 0.5) {
        for (i = nb - 1; i >= 1 && ++FIO_MB[i] > 255; i--) FIO_MB[i] = 0
        if (i < 1) { FIO_MB[1] = 128; if (++e > 255) { raise(6); return "" } }
    }
    FIO_MB[1] = FIO_MB[1] - 128 + sgn       # implied leading 1 -> sign bit
    out = ""
    for (i = nb - 1; i >= 1; i--) out = out CHR[FIO_MB[i]]
    return out CHR[e]
}

function fio_cvf(s, nb,   e, sgn, m, i, dv, b) {
    if (length(s) < nb) { raise(5); return 0 }
    e = ORD[substr(s, nb, 1)]
    if (e == 0) return 0
    b = ORD[substr(s, nb - 1, 1)]
    sgn = (b >= 128) ? -1 : 1
    m = (b % 128 + 128) / 256               # restore implied leading 1
    dv = 65536
    for (i = nb - 2; i >= 1; i--) { m += ORD[substr(s, i, 1)] / dv; dv *= 256 }
    return sgn * m * 2 ^ (e - 128)
}
