# ===================== program-memory mapping + VARPTR string space =========
# Three related pieces of the real Level II memory model (STATUS roadmap:
# "Program-memory mapping", shipped 2026-08-14):
#
#  1. THE TOKENIZED PROGRAM IMAGE (writable since 2026-09-12): PEEK of 42E9H (17129) onward sees
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
#  2. MEMORY SIZE? enforcement: a numeric answer at boot becomes HIMEM,
#     which is a FENCE, not the top of RAM.  Two quantities, and the
#     distinction is the whole point of the prompt:
#       RAMTOP  the machine's physical top (FFFFH for the 48K Model I this
#               emulates).  Above it memory is ABSENT: PEEK reads 255,
#               POKE is discarded.
#       HIMEM   the MEMORY SIZE? answer, at or below RAMTOP.  The region
#               between them is PROTECTED RAM -- present, readable and
#               writable, simply never allocated by string space
#               (sp_materialize descends from HIMEM).  Reserving memory is
#               how a listing makes room for a machine-language routine, so
#               that region MUST accept POKEs; treating it as absent broke
#               the classic reserve-then-load idiom (fixed 2026-09-08,
#               reported by ../trs80_z80_core as its FINDING 22).
#     PEEK(16561/16562) reports HIMEM.  ENTER keeps HIMEM at 65535 so batch
#     mode and loaders see all of RAM.
#
#  3. VARPTR(var) + mem[]-backed string space (the string-packing idiom):
#     for a string, VARPTR returns the address of a live 3-byte descriptor
#     [len][addr lo][addr hi]; the string bytes are materialized just below
#     it and BOTH regions read and write through to the live value, so
#     locate-a-literal / POKE-semigraphics / PRINT-the-variable works.  For
#     a numeric, VARPTR returns the address of the value's 4 Microsoft-
#     single bytes (fio_mkf/fio_cvf), also live in both directions.  The
#     bytes a POKE (or a Z80 store) made are kept (NRAW, sp_nbytes) while
#     they still decode to the value, so a number written a byte at a
#     time into a variable holding 0 arrives whole.
#     Allocation grows down from HIMEM like real string space; CLEAR/RUN/
#     NEW reset it (sp_reset from clear_vars).  VARPTR IS STABLE: the
#     descriptor (or a numeric's 4 bytes) is allocated ONCE per variable per
#     run and every later VARPTR returns the same address, as on hardware
#     where it is the variable-table slot.  Only the string's DATA bytes ever
#     move, and only when the value outgrows the capacity they were given --
#     then a fresh data region is allocated and the descriptor's address
#     cells are repointed.  (Until 2026-09-10 EVERY call freed and
#     re-allocated the whole thing, so VARPTR(A$);VARPTR(A$) answered two
#     addresses, the two-call idiom PEEK(VARPTR(A$)+1)+256*PEEK(VARPTR(A$)+2)
#     composed a dead address, and VARPTR in a loop marched SSP down to ?OM --
#     162 corpus listings call VARPTR on the same string twice.)  Documented
#     deviations: the bytes are a mem[]-backed COPY (a literal's bytes are
#     not the program line, so pack-then-SAVE captures nothing), the data
#     region a string outgrew is unmapped rather than left as stale bytes,
#     and POKEing the descriptor's address cells is ignored.  POKE of the
#     length byte truncates or space-pads the live value.

# ---- THE ADDRESS-RESOLUTION CONTRACT --------------------------------------
# dopeek() (p80) resolves ONE byte per address from several stores.  The order
# below is the CONTRACT, not an implementation detail: ../trs80_z80_core must
# reproduce it byte-for-byte or the core will execute the wrong bytes with no
# error.  Requested by that project 2026-09-08; keep this list and dopeek in
# step.  Highest precedence first:
#
#   1. 3C00-3FFFH (15360-16383) -> SCR[], the simulated screen
#      3800-38FFH (14336-14591) -> kb_matrix(), the live keyboard matrix
#   2. 37E8/37E9H (14312/14313) -> constant 63, printer ready.  READ-ONLY
#      PROJECTION: POKEs land in MEM[] and are never read back.
#   3. 40AA-40ACH (16554-16556) -> the ROM RND seed (rnd_peek, p90)
#      40A4/40B1/40F9H pairs    -> pm_sysptr() below (program base, HIMEM,
#      start of variables).  40B1H is the one WRITABLE member: see
#      pm_sethimem().
#      THE SYSTEM VARIABLE WINDOW (sv_peek, below; the SVW set): 4020-4022H
#      cursor position and character, 4028H/4029H/409BH printer lines per
#      page, line counter and column, 4041-4046H the Model I clock,
#      40A2/40A3H the current line number, 40E1-40E5H AUTO's flag, line and
#      increment, 411BH the TRON flag -- each read from the live state it
#      names.  Added 2026-09-11; see the window's own comment for the write
#      side of each.
#   4. a in SPK -> VARPTR string space (sp_peek).  THIS DELIBERATELY OUTRANKS
#      RULE 5: a packed string inside the program-image range must win over
#      the image, which is what makes the string-packing idiom work at any
#      program size.  It is an invariant, not a consequence of statement
#      order -- do not reorder it under rule 5.
#   5. a >= 17129 and a < PMEND -> the tokenized program image.  WRITABLE
#      since 2026-09-12: a >= 17129 returns MEM[a] if that address was ever
#      stored (a POKE, or a USR write-set), else the original crunched byte
#      PMEM[a].  Image RAM is RAM, as on the machine -- a payload that keeps
#      a buffer inside its own loaded bytes (the Dancing Demon's score/dance
#      editor, at 6B9BH) reads back what it wrote.  RUN and LIST are never
#      affected: they work from prog[] (the source text), not PMEM, so a POKE
#      here cannot corrupt the running program the way it does on hardware.
#      A stored byte BELONGS TO THE LINE it landed in (pm_build, since
#      2026-09-20): a rebuild carries it to the line's new address, and
#      drops it when that line was re-entered, deleted or replaced by NEW
#      or a LOAD.  So after the program changes this rule still answers
#      from MEM[a], but MEM[] over the image has been re-keyed; the core
#      needs nothing new, because a rebuilt image is resent whole.
#      The bound is RAMTOP, not HIMEM.  a > RAMTOP -> 255 (unreachable today).
#   6. otherwise -> MEM[a] if it was ever written, else 255.
#
# TWO READ-ONLY PROJECTIONS, NOT ONE (rules 2 and 5): "POKE lands in MEM[] and
# is never read back" is a CLASS in this interpreter, not a program-image
# quirk.  A byte in either region is a byte the core will not see.
#
# 255 IS LIVE BEHAVIOUR, and it is reached by rule 6's fallthrough rather than
# by the RAMTOP test.  Unwritten RAM reads 255 -- what a machine with no chip
# at that address returns -- and the core models unwritten RAM the same way.

# ---- THE ADDRESS-RESOLUTION CONTRACT, WRITE SIDE --------------------------
# poke_byte() (p80) is dopeek's twin and its order is CONTRACT for the same
# reason: a Z80 store from ../trs80_z80_core must land exactly where a POKE of
# the same address lands, or the two disagree about memory with no error.
# Requested by that project 2026-09-08 (handoff REPLY 2).  They read the order
# off the code themselves and read it correctly; all six rules are theirs,
# re-verified against st_poke 2026-09-09.  Split 2026-09-11: st_poke is now
# only the statement parser, and poke_byte(a, b) is the single store
# primitive every write that must agree with POKE goes through -- the p77
# shim applying a Z80 write-set, and the string-alias write-through (finding
# 7).  Highest precedence first:
#
#   1. 3C00-3FFFH (15360-16383) -> s_poke() + sync_cursor()
#   2. 40AA-40ACH (16554-16556) -> rnd_poke(), the ROM RND seed
#   3. 40B1/40B2H (16561/16562) -> pm_sethimem(), the one writable pointer
#      the SYSTEM VARIABLE WINDOW (a in SVW) -> sv_poke(): cursor moves,
#      cursor character, printer counters, AUTO request, TRON flag; a
#      clock cell (4041-4046H) becomes plain RAM once written (MEM[a],
#      read back by sv_peek; on a cassette machine nothing updates those
#      bytes, and Space Chase parks its routine across them); the current
#      line number ignores writes (documented)
#   4. a in SPK                 -> sp_poke(), VARPTR string-space write-through
#   5. a > RAMTOP               -> DISCARDED (absent RAM)
#   6. otherwise                -> MEM[a] = b, after pm_sync() when the
#      program image is stale and a >= 17129: the store must be made against
#      the CURRENT image, because the next build decides by line what stays
#      (read rule 5).  Five cells there have a SIDE
#      EFFECT on write: 401E/401FH and 4026/4027H, the video and printer
#      driver vectors (dv_update, p80) -- the ROM's two driver addresses
#      re-route output, 0067H silences the printer; and 403DH (16445), the
#      ROM's image of the port-FF bits, whose bit 3 is its 32-column print
#      flag (the cursor step in s_putc, p20; CHR$(23) sets it and CLS
#      clears it through this same primitive, so the frame sees them).
#      The bytes themselves are ordinary MEM[] (seeded 88,4, 141,5 and 0
#      in init).
#
# FOUR ASYMMETRIES AGAINST THE READ SIDE.  Each is a range the read side
# projects from somewhere other than MEM[], so a write there lands in MEM[]
# and NOTHING CAN EVER OBSERVE IT:
#   * 3800-38FFH keyboard (read rule 1) -- no write branch.
#   * 37E8/37E9H printer  (read rule 2) -- no write branch.
#   * 40A4/40A5H and 40F9/40FAH (read rule 3) -- no write branch.  40B1/40B2H
#     is the ONLY writable member; rule 3 above is where that finally gets
#     said on the write side, having been stated only on the read side.
#   * the tokenized program image, a >= 17129 && a < PMEND -- rule 6 stores
#     MEM[a] and read rule 5 NOW READS IT BACK (writable since 2026-09-12,
#     superseding FINDING 23's read-only shadow: the Dancing Demon keeps its
#     score buffer inside its own image at 6B9BH and needs the write to
#     stick).  Not an asymmetry any more; no image-specific write branch is
#     needed because rule 6 already stores it and rule 5 reads it.
#
# THOSE BYTES ARE UNDEFINED -- not zero, not absent.  If this side and the
# core ever diff their memory images, the four ranges above are OUT OF SCOPE
# for the comparison: identical observable behaviour, deliberately different
# stores.  Do not "fix" either side to agree there, and do not turn rule 6
# into a discard for them -- the store is unobservable either way, and a
# discard would cost four address tests in the hot POKE path to buy nothing.
#
# NO ORDERING HAZARD MIRRORING READ RULES 4/5.  SPK outranks the program image
# on READ because a packed string inside the image range must win.  On write
# there is no image branch at all, so SPK merely precedes rule 6.  Nothing to
# keep in step here.
#
# RULE 5 IS UNREACHABLE TODAY, as dopeek's is (RAMTOP == 65535 == addrconv's
# bound), and the two stay equivalent for any RAMTOP: dopeek tests a > RAMTOP
# only inside its a >= 17129 branch and poke_byte tests it unconditionally,
# but RAMTOP >= 17129 always holds, so no address is judged differently.

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
        if (!(v in TOKW)) TOKW[v] = w   # byte -> text for pm_detok; the first
                                        # spelling wins (D1H lists as [, and
                                        # both [ and ^ parse as the power op)
    }
    TOKIDX = 1
}

# detokenize one stored line body into the text prog[] holds (R1, p40).  The
# inverse of pm_crunch and a port of tools/detok.py's expand() with keyword
# spacing on: strings, DATA items up to a colon and everything after REM or
# ' stay literal; ' is stored as the three bytes :REM'; a keyword gets a
# space before it when the previous character would glue onto it (an
# alphanumeric, $, . or #) and one after it when an alphanumeric follows,
# because tokline lexes FORX as one identifier.  A CR or LF -- legal in a
# stored body, impossible in a text line -- becomes a space, or inside a
# non-DATA string the equivalent "+CHR$(n)+" splice.  Those rewrites touch
# only this text; the image is built from the escrowed bytes.
function pm_detok(body,   out, i, n, b, c, ins, ind, lit, kw, nxt) {
    if (!TOKIDX) pm_init_index()
    out = ""; i = 1; n = length(body); ins = 0; ind = 0; lit = 0
    while (i <= n) {
        c = substr(body, i, 1); b = ORD[c]
        if (lit) { out = out ((b == 10 || b == 13) ? " " : c); i++; continue }
        if (ins) {
            if (b == 10 || b == 13) { out = out (ind ? " " : "\"+CHR$(" b ")+\""); i++; continue }
            out = out c
            if (b == 34) ins = 0
            i++; continue
        }
        if (b == 34) { ins = 1; out = out c; i++; continue }
        if (ind) {
            if (b == 10 || b == 13) { out = out " "; i++; continue }
            if (b == 58) ind = 0
            out = out c; i++; continue
        }
        if (b == 58 && i + 2 <= n && ORD[substr(body, i + 1, 1)] == 147 && ORD[substr(body, i + 2, 1)] == 251) {
            out = out "'"; lit = 1; i += 3; continue
        }
        if (b == 10 || b == 13) { out = out " "; i++; continue }
        if (b >= 128) {
            if (!(b in TOKW)) { out = out c; i++; continue }
            kw = TOKW[b]
            if (kw ~ /^[A-Za-z]/ && out != "" && substr(out, length(out), 1) ~ /[A-Za-z0-9$.#]/) out = out " "
            out = out kw
            nxt = (i < n) ? substr(body, i + 1, 1) : ""
            if (kw ~ /[A-Za-z0-9]$/ && nxt ~ /^[A-Za-z0-9]$/) out = out " "
            if (b == 147 || b == 251) lit = 1
            else if (b == 136) ind = 1
            i++; continue
        }
        out = out c; i++
    }
    return out
}

# the bytes of one line for the image: the escrowed originals when the line
# came from a tokenized file (R1), else the crunched text
function pm_body(ln,   body, j) {
    if (ln in ESC) {
        body = ESC[ln]; PMBN = length(body)
        for (j = 1; j <= PMBN; j++) PMB[j] = ORD[substr(body, j, 1)]
    } else pm_crunch(prog[ln])
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
#
# THE WINDOW OVERFLOW POLICY (ruled 2026-09-11): TRUNCATE AT A WHOLE LINE.
# Program text is unbounded on this side, but the image lives in a 16-bit
# space, so a program can outgrow the window that shows it.  The image now
# stops before the first line whose record (plus the 00 00 terminator after
# it) would cross RAMTOP, and writes the terminator there, so any walker of
# the next-line chain -- a PEEK loop, or a Z80 dispatcher of the Dancing
# Demon kind, for which the chain IS its symbol table -- sees a well-formed,
# shorter program instead of a link into garbage.  40F9H reports the
# truncated end.  The other two options were rejected: REFUSING (?OM at
# RUN) would take back the unbounded-program generosity the interpreter
# chose deliberately, and a SLIDING window would change what 40A4H/40F9H
# mean mid-run.  Not silent: pm_truncnote() prints one stderr line per build
# the first time the truncated image is consulted (dopeek rule 5, 40F9H, or
# the USR frame), so a program that reads past its own cut is told, not
# fooled.  Until 2026-09-11 the next pointer wrapped modulo 65536 and PMEM
# went on being written above the address space, unreachable by any PEEK.
#
# WHAT A POKE INTO THE IMAGE BELONGS TO (the 2026-09-19 audit, M-8).  Read
# rule 5 serves MEM[a] over the crunched byte, and MEM[] is keyed by
# address, but on the machine a byte POKEd into a line is part of that
# LINE: it moves when an earlier line grows or goes, and it is gone when the
# line itself is re-entered, deleted, or replaced by NEW or a LOAD.  So each
# build lifts the stored bytes out of the old image, per line and offset
# (PMLA/PMLL, the old line table), and puts back only those whose line was
# not touched since (PMTOUCH, set by inval_cache in p40), at the line's new
# address.  Everything else stored inside the old or the new image range is
# dropped: the code-in-a-REM idiom keeps its bytes while the loader lines
# after it are deleted, and a payload loaded later is never read through
# the last program's POKEs.  poke_byte syncs the image before it stores
# into it, so a store is always judged against the image it was made in.
function pm_build(   i, ln, addr, nb, j, nxt, a, e, ov, novl, k, p) {
    if (!TOKIDX) pm_init_index()
    novl = 0
    for (ln in PMLA) {
        e = PMLA[ln] + PMLL[ln]
        for (a = PMLA[ln]; a < e; a++) if (a in MEM) {
            if (!(ln in PMTOUCH)) ov[++novl] = ln SUBSEP (a - PMLA[ln]) SUBSEP MEM[a]
            delete MEM[a]
        }
    }
    if (PMEND > 0) for (a = PMEND - 2; a < PMEND; a++) delete MEM[a]   # the old terminator
    e = PMEND
    delete PMLA; delete PMLL; delete PMTOUCH
    delete PMEM
    addr = 17129
    PMTRUNC = 0; PMTRUNCLN = 0; PMNOTED = 0
    for (i = 1; i <= NL; i++) {
        ln = LNS[i]
        pm_body(ln); nb = PMBN
        if (addr + 4 + nb + 1 + 2 - 1 > RAMTOP) { PMTRUNC = 1; PMTRUNCLN = ln; break }
        nxt = addr + 4 + nb + 1                   # always <= RAMTOP now
        PMEM[addr] = nxt % 256; PMEM[addr + 1] = int(nxt / 256)
        PMEM[addr + 2] = ln % 256; PMEM[addr + 3] = int(ln / 256)
        for (j = 1; j <= nb; j++) PMEM[addr + 4 + j - 1] = PMB[j]
        PMEM[addr + 4 + nb] = 0
        PMLA[ln] = addr; PMLL[ln] = 4 + nb + 1
        addr += 4 + nb + 1
    }
    PMEM[addr] = 0; PMEM[addr + 1] = 0
    PMEND = addr + 2
    for (a = (e > 17129 ? e : 17129); a < PMEND; a++) delete MEM[a]   # RAM the program grew over
    for (k = 1; k <= novl; k++) {
        split(ov[k], p, SUBSEP)
        if (p[1] in PMLA) MEM[PMLA[p[1]] + p[2]] = p[3] + 0
    }
    PROGDIRTY = 0
    FRPMDIRTY = 1                                 # the USR frame resends the image
}

function pm_sync() { if (PROGDIRTY || PMEND == 0) pm_build() }

# once per build, the first time a truncated image is consulted
function pm_truncnote() {
    if (!PMTRUNC || PMNOTED) return
    PMNOTED = 1
    diag_err("PROGRAM IMAGE TRUNCATED: LINE " PMTRUNCLN " AND AFTER DO NOT FIT BELOW " RAMTOP \
             "; PEEK AND MACHINE CODE SEE A CHAIN ENDING AT " (PMEND - 2))
}

# the six live system-pointer bytes (dopeek routes them here)
function pm_sysptr(a) {
    if (a == 16548) return 233                    # 40A4H: program base 42E9H
    if (a == 16549) return 66
    if (a == 16561) return HIMEM % 256            # 40B1H: top of memory
    if (a == 16562) return int(HIMEM / 256)
    pm_sync(); pm_truncnote()                     # 40F9H: start of variables
    # a PEEK returns a byte: mask the high half too, so a program image
    # larger than the address space cannot leak a >255 value (reported by
    # ../trs80_z80_core 2026-09-07; 1200 REM lines used to answer 381).
    # Since the truncation ruling PMEND <= RAMTOP + 1, so the mask is now
    # only a belt for the braces.
    return (a == 16633) ? PMEND % 256 : int(PMEND / 256) % 256
}

# 40B1H/40B2H is a WRITABLE pointer: lowering HIMEM with POKE 16561/16562
# (then CLEAR) is the PROGRAMMATIC half of the reserve-then-load idiom, the
# half that does not go through the MEMORY SIZE? prompt -- 91 corpus
# listings do it, e.g. wordsmth.bas reserving BF78H-BFFFH for a lowercase
# driver.  Writes move the live fence; string space allocated afterwards
# descends from the new value.  Existing VARPTR regions are left where they
# are, as on hardware, where the idiom requires the CLEAR to follow.
function pm_sethimem(a, b) {
    if (a == 16561) HIMEM = int(HIMEM / 256) * 256 + b
    else            HIMEM = HIMEM % 256 + b * 256
    if (SSP > HIMEM) SSP = HIMEM
}

# ---- VARPTR ---------------------------------------------------------------
# Storage maps, per materialized address a: SPK[a] = value locator ("V" name
# for a scalar, "A" storage-key for an array element), SPT[a] = role -- a
# 0-based byte offset for string bytes, "L" the live length byte, "C" a
# constant descriptor byte (SPV[a]), or "Nj" numeric byte j.  SSP grows down
# from HIMEM.  Per variable: VPDESC = its VARPTR (the descriptor address, or
# a numeric's first byte), permanent for the run; VPDATA/VPCAP = where its
# string bytes live and how many cells are mapped there.  sp_reset wipes
# everything (clear_vars).

function sp_reset(   a) {
    if (FRTRACK) for (a in SPK) FRDIRTY[a] = 1   # the frame resends what these read as now
    delete SPK; delete SPT; delete SPV; delete VPDESC; delete VPDATA; delete VPCAP
    delete ALIAS; ALN = 0
    delete NRAW
    SSP = HIMEM
}

# unmap a string's data cells (the descriptor stays where it is)
function sp_free_data(tgt,   a, e) {
    if (!(tgt in VPDATA)) return
    e = VPDATA[tgt] + VPCAP[tgt] - 1
    for (a = VPDATA[tgt]; a <= e; a++) { delete SPK[a]; delete SPT[a]; if (FRTRACK) FRDIRTY[a] = 1 }
}

# map len string cells for tgt at base
function sp_map_data(tgt, base, len,   j) {
    for (j = 0; j < len; j++) { SPK[base + j] = tgt; SPT[base + j] = j }
    VPDATA[tgt] = base; VPCAP[tgt] = len
}

# materialize var (locator tgt, string flag isstr) and return its VARPTR.
# Idempotent: a second call returns the first call's address.  A string's
# bytes are re-homed only when the live value is longer than the cells
# mapped for it -- which the assignment that grew it does at once (sp_grown)
# -- and shrinking never moves anything (sp_peek pads with 32 past the live
# length).
function sp_materialize(tgt, isstr,   len, need, base, j, dbase) {
    if (SSP == 0) SSP = HIMEM                     # first use this run
    if (!isstr) {
        if (tgt in VPDESC) return VPDESC[tgt]
        need = 4
        if (SSP - need < 17131) { raise(7); return 0 }
        base = SSP - need + 1; SSP -= need
        for (j = 0; j < 4; j++) { SPK[base + j] = tgt; SPT[base + j] = "N" j }
        VPDESC[tgt] = base
        return base
    }
    len = length(sp_gets(tgt))
    if (tgt in VPDESC) {
        dbase = VPDESC[tgt]
        if (len <= VPCAP[tgt]) return dbase       # still fits: nothing moves
        if (tgt in ALIAS) return dbase            # aliased: the cells are not what is read
        if (SSP - len < 17131) { raise(7); return 0 }
        base = SSP - len + 1; SSP -= len          # outgrown: fresh data region
        sp_free_data(tgt)
        sp_map_data(tgt, base, len)
        SPV[dbase + 1] = base % 256; SPV[dbase + 2] = int(base / 256)
        return dbase
    }
    need = len + 3                                # first VARPTR: bytes, then
    if (SSP - need < 17131) { raise(7); return 0 } # the descriptor just above
    base = SSP - need + 1; SSP -= need
    sp_map_data(tgt, base, len)
    dbase = base + len
    SPK[dbase] = tgt;     SPT[dbase] = "L"
    SPK[dbase + 1] = tgt; SPT[dbase + 1] = "C"; SPV[dbase + 1] = base % 256
    SPK[dbase + 2] = tgt; SPT[dbase + 2] = "C"; SPV[dbase + 2] = int(base / 256)
    VPDESC[tgt] = dbase
    return dbase
}

# An assignment gave a VARPTRed string a value longer than the cells mapped
# for it.  On the machine the assignment itself allocates the new string and
# rewrites the descriptor, so a program that kept V=VARPTR(A$) reads the new
# address at V+1/V+2 straight away.  Re-home NOW, not at the next VARPTR
# call: until 2026-09-20 the descriptor went on naming the old cells, a
# PEEK past them read the descriptor's own bytes (it sits just above), and
# a POKE there rewrote the length (the 2026-09-19 audit, M-13).
function sp_grown(name, key,   tgt) {
    tgt = (key != "") ? "A" key : "V" name
    if (tgt in VPDATA) sp_materialize(tgt, 1)
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

# The four MBF bytes of a numeric variable.  A variable here is a VALUE, not
# bytes, so they are normally encoded from it on demand.  That alone cannot
# hold a number being written one byte at a time: while the exponent byte
# (V+3) is still 0 the value is 0, and every mantissa byte stored before it
# was re-derived from that 0 and lost -- which broke the Level II MKS$/CVS
# substitute (copy four PEEKed bytes into a fresh variable) and any Z80
# routine storing a float through VARPTR, whose write-set arrives in
# ascending order, exponent last (the 2026-09-19 audit, H-11).  So a POKE
# keeps the bytes it made in NRAW, and they stay the truth for as long as
# they still decode to the variable's value; an assignment that changes
# the value outdates them, and the next read encodes afresh.
function sp_nbytes(tgt,   x) {
    x = sp_getn(tgt)
    if ((tgt in NRAW) && fio_cvf(NRAW[tgt], 4) == x) return NRAW[tgt]
    delete NRAW[tgt]
    return fio_mkf(x, 4)
}

function sp_peek(a,   t, tgt, v) {
    t = SPT[a]; tgt = SPK[a]
    if (t == "L") return length(sp_gets(tgt)) % 256
    if (t == "C") return SPV[a]
    if (substr(t, 1, 1) == "N") {
        v = sp_nbytes(tgt)
        return ORD[substr(v, substr(t, 2) + 1, 1)]
    }
    v = sp_gets(tgt)                              # string byte, live
    return (t + 1 <= length(v)) ? ORD[substr(v, t + 1, 1)] : 32
}

function sp_poke(a, b,   t, tgt, v, j) {
    t = SPT[a]; tgt = SPK[a]
    if (t == "C") { al_repoint(a, b, tgt); return } # descriptor address cell (finding 7)
    if (t == "L") {                               # truncate / space-pad
        v = sp_gets(tgt)
        while (length(v) < b) v = v " "
        sp_sets(tgt, substr(v, 1, b))
        return
    }
    if (substr(t, 1, 1) == "N") {
        v = sp_nbytes(tgt); j = substr(t, 2) + 1
        v = substr(v, 1, j - 1) CHR[b] substr(v, j + 1)
        NRAW[tgt] = v
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

# ===================== the SYSTEM VARIABLE WINDOW ============================
# ROM RAM cells that period listings PEEK and POKE, served from the live
# state they name instead of dead MEM[].  Proposed 2026-09-05 from the
# trs-80.com tips tally, MEASURED over the corpus before building (2026-09-11:
# the cursor cell has 92 readers and 26 writers, the printer line counter 27
# and 36, lines per page 13 and 21, the cursor character 26 and 43 -- eleven
# of them hiding the cursor; everything else under 3), built the same day.
# These are real Model I addresses, so EXT rule 1 is not in play.  Per cell:
#   4020/4021H (16416/7)  cursor position = 3C00H + CUR.  POKE moves the
#                         cursor once both bytes name a video address.
#   4022H (16418)         cursor character (CURCH).  POKE 0 hides the
#                         terminal cursor, anything else shows it; the glyph
#                         itself is the terminal's (documented).
#   4028H (16424)         lines per page + 1 (LPPAGE, 67).  POKE sets it.
#   4029H (16425)         lines printed on this page (LPLINES): lp_nl counts,
#                         wraps at LPPAGE-1.  POKE sets it (the "POKE
#                         16425,1 after a form feed" idiom, 36 listings).
#   409BH (16539)         printer column (LPCOL).  POKE sets it.  BASIC's
#                         count, kept before the driver is called, so it
#                         advances while the printer vector is routed too.
#   4041-4046H (16449-54) SS MN HH YY DD MM from the host clock, as TIME$
#                         reads it (documented deviation: Level II has no
#                         clock interrupt, so on the machine these bytes
#                         hold whatever was last stored).  A POKE makes the
#                         cell plain RAM from then on (SVWRIT): the byte
#                         reads back and reaches the USR frame.  Found by
#                         the 2026-09-15 corpus sweep: Space Chase (80
#                         Micro 5/1982) POKEs its routine at 403EH-405AH,
#                         and the frame carried the wall clock in place of
#                         six of its bytes -- 340 calls ran, the 341st
#                         crashed when the seconds byte became an opcode.
#   40A2/40A3H (16546/7)  the line number executing (CLN; 0 at READY).
#                         POKEs ignored.
#   40E1H (16609)         AUTO flag: 1 while AUTO is prompting.  POKE
#                         non-zero REQUESTS AUTO: it starts at the next
#                         READY prompt from 40E2/E3H by 40E4/E5H, as the ROM
#                         would (tip 70).  Batch mode has no prompt, so the
#                         request is inert there.
#   40E2/40E3H (16610/1)  AUTO's current line (AUTOLINE).  POKE sets it.
#   40E4/40E5H (16612/3)  AUTO's increment (AUTOINC).  POKE sets it (tip 71).
#   411BH (16667)         TRON flag: 175 on, 0 off.  POKE non-zero = TRON,
#                         0 = TROFF (tips 76/77).
# Every cell is also in the USR frame's always-sent set (fr_build).
function sv_init(   a) {
    SVW[16416] = 1; SVW[16417] = 1; SVW[16418] = 1
    SVW[16424] = 1; SVW[16425] = 1; SVW[16539] = 1
    for (a = 16449; a <= 16454; a++) SVW[a] = 1
    SVW[16546] = 1; SVW[16547] = 1
    for (a = 16609; a <= 16613; a++) SVW[a] = 1
    SVW[16667] = 1
}
function sv_peek(a,   v) {
    if (a == 16416) return (15360 + CUR) % 256
    if (a == 16417) return int((15360 + CUR) / 256)
    if (a == 16418) return CURCH
    if (a == 16424) return LPPAGE % 256
    if (a == 16425) return LPLINES % 256
    if (a == 16539) return LPCOL % 256
    if (a >= 16449 && a <= 16454) {
        if (a in SVWRIT) return MEM[a]
        v = strftime("%S %M %H %y %d %m")
        return substr(v, 3 * (a - 16449) + 1, 2) + 0
    }
    if (a == 16546) return CLN % 256
    if (a == 16547) return int(CLN / 256) % 256
    if (a == 16609) return AUTOON ? 1 : (AUTOREQ ? 1 : 0)
    if (a == 16610) return AUTOLINE % 256
    if (a == 16611) return int(AUTOLINE / 256) % 256
    if (a == 16612) return AUTOINC % 256
    if (a == 16613) return int(AUTOINC / 256) % 256
    if (a == 16667) return TRACE ? 175 : 0
    return 255
}
function sv_poke(a, b,   v) {
    if (a == 16416 || a == 16417) {
        v = 15360 + CUR
        v = (a == 16416) ? int(v / 256) * 256 + b : v % 256 + 256 * b
        if (v >= 15360 && v <= 16383) { CUR = v - 15360; sync_cursor() }
        return
    }
    if (a == 16418) {
        CURCH = b                    # 0 hides it; sync_cursor applies the rule
        sync_cursor()
        return
    }
    if (a == 16424) { LPPAGE = b; return }
    if (a == 16425) { LPLINES = b; return }
    if (a == 16539) { LPCOL = b; return }
    if (a == 16609) { AUTOREQ = (b != 0); return }
    if (a == 16610) { AUTOLINE = int(AUTOLINE / 256) * 256 + b; return }
    if (a == 16611) { AUTOLINE = AUTOLINE % 256 + 256 * b; return }
    if (a == 16612) { AUTOINC = int(AUTOINC / 256) * 256 + b; return }
    if (a == 16613) { AUTOINC = AUTOINC % 256 + 256 * b; return }
    if (a == 16667) { TRACE = (b != 0); return }
    if (a >= 16449 && a <= 16454) { MEM[a] = b; SVWRIT[a] = 1; return }
    # 16546/16547 (the current line): ignored
}

# ===================== string aliasing via the descriptor (finding 7) =======
# The period trick: POKE VARPTR(A$)+1 / +2 repoints a string's descriptor at
# video RAM (high byte 3CH) or system RAM (40H), and from then on ordinary
# string operations READ AND WRITE that region -- PRINT A$ shows the screen,
# LSET A$="..." paints it, MID$(A$,n,1) picks a cell.  Pure BASIC, no USR;
# ~23 corpus listings use the direct form (TAXMAN, VIDENTRY, INOUTPUT, the
# tax and screen editors) and more the indirect V=VARPTR(A$):POKE V+1 form.
# Until 2026-09-11 the descriptor cells ignored POKE, so every one of them
# ran to a clean END doing nothing (seam audit finding 7; built the same day
# after the user greenlit it).
#
# NOT a storage re-architecture: an ALIAS side-table (locator -> address),
# resolved through dopeek / poke_byte, so the aliased region obeys THE
# ADDRESS-RESOLUTION CONTRACT for free -- screen, keyboard, packed strings,
# system pointers, the program image, all of it.  The rules, each mirroring
# what the real descriptor does:
#   * POKE of an address cell STORES the byte (PEEK reads it back) and, when
#     the two cells no longer name the string's own data, sets ALIAS[tgt];
#     poking them back to the own data address clears it.
#   * READ of an aliased variable (e_prim scalar, aref element, and the
#     current value LSET/RSET/MID$= start from) assembles LEN bytes live from
#     dopeek(addr..); LEN is the live length, which POKE VARPTR(A$)+0 sets.
#   * an ASSIGNMENT (LET, READ, INPUT, FOR... -- assignv, p70) allocates a
#     new string on hardware and moves the descriptor, so it CLEARS the
#     alias and points the cells back at the own data.
#   * an IN-PLACE write (LSET/RSET p85, MID$= p80) writes THROUGH to the
#     aliased region via poke_byte, one byte per position, keeps the alias,
#     and leaves the string's own bytes as they were (repointing the cells
#     back shows the old value, as on hardware).
#   * VARPTR of an aliased string never re-homes its data cells (they are
#     not what is read), so the descriptor stays put.
#   * CLEAR/RUN/NEW drop every alias with the string space (sp_reset).
# Edges left alone, documented: an aliased string used as a DEF FN parameter
# reads the aliased bytes inside the body, not the bound argument (p60 binds
# SV[] directly); FIELDed strings are never aliased (their own path).  ALN
# counts live aliases so every check on an ordinary string is one integer
# test.  Addresses wrap at 65536 like the hardware's.
function al_repoint(a, b, tgt,   d, addr) {
    SPV[a] = b
    d = VPDESC[tgt]
    addr = SPV[d + 1] + 256 * SPV[d + 2]
    if (addr == VPDATA[tgt]) { if (tgt in ALIAS) { delete ALIAS[tgt]; ALN-- } }
    else { if (!(tgt in ALIAS)) ALN++; ALIAS[tgt] = addr }
}
function al_read(tgt,   addr, len, j, s, b) {
    addr = ALIAS[tgt]; len = length(sp_gets(tgt)); s = ""
    for (j = 0; j < len; j++) { b = dopeek((addr + j) % 65536); if (E) return ""; s = s CHR[b] }
    return s
}
# the current value of a string variable, alias-aware (name, array key)
function al_cur(name, key,   tgt) {
    tgt = (key != "") ? "A" key : "V" name
    if (ALN && (tgt in ALIAS)) return al_read(tgt)
    return (key != "") ? ((key in VA) ? vstr(VA[key]) : "") : SV[name]
}
# an in-place write: through to the alias when there is one (the string's
# own bytes stay as they were, as on hardware), else into the value
function al_setinplace(name, key, s,   tgt, addr, j) {
    tgt = (key != "") ? "A" key : "V" name
    if (!(ALN && (tgt in ALIAS))) { sp_sets(tgt, s); return }
    addr = ALIAS[tgt]
    for (j = 1; j <= length(s); j++) poke_byte((addr + j - 1) % 65536, ORD[substr(s, j, 1)])
}
# an assignment: the descriptor moves, so the alias is gone
function al_clear(name, key,   tgt, d) {
    tgt = (key != "") ? "A" key : "V" name
    if (!(tgt in ALIAS)) return
    delete ALIAS[tgt]; ALN--
    d = VPDESC[tgt]
    SPV[d + 1] = VPDATA[tgt] % 256; SPV[d + 2] = int(VPDATA[tgt] / 256)
}

# ===================== the USR frame's memory image ==========================
# What the p77 shim will hand ../trs80_z80_core as "the memory the routine
# can see".  RULED 2026-09-11 (seam audit finding 4 closed): MATERIALISE a
# SPARSE image in, STREAM video writes out, and the keyboard is the only live
# callback.  The arithmetic that decided it, measured on this machine: one
# gawk |& round trip is 12 us, so a callback per memory read caps a core at
# ~80,000 reads/s -- a quarter of Dancing Demon's 313,030 insn/s real-time
# bar before any Z80 work -- while a 45,000-pair sparse image round-trips in
# 14 ms.  Every defined address is enumerable (MEM[] keys, SPK keys, the
# image range, the screen, the constant and pointer bytes), every value is
# read through dopeek so the address-resolution contract holds by
# construction, and everything not listed is 255.  Video reads need no
# callback: the core is the only writer during the call and streams its own
# video writes back, so its copy stays coherent.  The keyboard changes
# underneath the core, and Dancing Demon polls it at ONE site, so a 12 us
# callback there is nothing.
#
# DELTA FRAMES from day one: the first frame is full and every later frame
# resends only what may have changed since the last one, so a listing that
# calls a scroll routine thousands of times does not pay 14 ms per call.
# What is resent and why:
#   * the screen (1K), the 11 constant/pointer bytes and the 20 system
#     variable window cells -- always; cheap, and written from many places
#     (PRINT, scroll, CLS) with no chokepoint.
#   * every SPK cell -- always; string VALUES change through ordinary
#     assignment (SV[]/VA[]), not through a chokepoint, and the region is
#     small (only what VARPTR materialised).
#   * the program image -- when pm_build has run since the last frame
#     (FRPMDIRTY), plus the range a SHRUNKEN image no longer covers, which
#     now reads as MEM[] or 255.
#   * MEM[] -- only the addresses poke_byte wrote since the last frame
#     (FRDIRTY), plus SPK cells that were UNMAPPED since (sp_free_data,
#     sp_reset), which now read as MEM[] or 255.  Tracking starts with the
#     first frame (FRTRACK), so a run that never calls USR pays nothing.
# A full frame is rebuilt whenever the coprocess (re)starts; the header
# carries the generation so the two sides cannot disagree about which they
# are on.  Wire framing is p77's; this builds the CONTENT.
#
# fr_build(full) fills FRHDR (one line: gen, full, slot, entry, arg, the
# initial SP = SSP, HIMEM, RAMTOP, run count) and FRRUN[1..FRN], one entry
# per run of consecutive addresses as "addr:b,b,b".  TRS80_USR_TRACE=2 dumps
# both to stderr on every USR call (programs/tests/usr.sh asserts on it).
function fr_build(full,   a, e, n, run, last, lo, hi) {
    delete FRSET
    if (!FRTRACK) { full = 1 }
    for (a = 15360; a <= 16383; a++) FRSET[a] = 1     # screen, always
    FRSET[14312] = 1; FRSET[14313] = 1                 # printer status (63)
    for (a = 16554; a <= 16556; a++) FRSET[a] = 1     # RND seed
    FRSET[16548] = 1; FRSET[16549] = 1; FRSET[16561] = 1; FRSET[16562] = 1
    FRSET[16633] = 1; FRSET[16634] = 1                 # the live pointers
    for (a in SVW) FRSET[a] = 1                        # the system variable window
    for (a in SPK) FRSET[a] = 1                        # packed strings, always
    pm_sync(); pm_truncnote()
    if (full || FRPMDIRTY) {
        for (a = 17129; a < PMEND; a++) FRSET[a] = 1
        hi = (FRPMHI > PMEND) ? FRPMHI : PMEND
        for (a = PMEND; a < hi; a++) FRSET[a] = 1      # a shrunken image's tail
    }
    if (full) { for (a in MEM) FRSET[a] = 1 }
    else       { for (a in FRDIRTY) FRSET[a] = 1 }
    delete FRRUN; FRN = 0; n = 0
    PROCINFO["sorted_in"] = "@ind_num_asc"
    last = -2; run = ""
    for (a in FRSET) {
        a = a + 0
        if (a > RAMTOP) continue
        if (a != last + 1) { if (run != "") FRRUN[++FRN] = run; run = a ":" dopeek(a) }
        else run = run "," dopeek(a)
        last = a; n++
    }
    if (run != "") FRRUN[++FRN] = run
    delete PROCINFO["sorted_in"]
    FRGEN++; FRFULL = full ? 1 : 0
    FRHDR = "USR FRAME gen=" FRGEN " full=" FRFULL " slot=" USR_SLOT " entry=" USR_ENTRY \
            " arg=" USR_ARG " sp=" SSP " himem=" HIMEM " ramtop=" RAMTOP " bytes=" n " runs=" FRN
    delete FRDIRTY; FRPMDIRTY = 0; FRPMHI = PMEND; FRTRACK = 1
    delete FRSET
}

# the coprocess (re)started, or the shim wants a clean slate: next frame full
function fr_reset() { FRTRACK = 0; FRGEN = 0; delete FRDIRTY }

function fr_dump(   i) {
    printf "%s\n", FRHDR > "/dev/stderr"
    for (i = 1; i <= FRN; i++) printf "  %s\n", FRRUN[i] > "/dev/stderr"
    fflush("/dev/stderr")
}
