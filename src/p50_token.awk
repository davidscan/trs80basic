# ===================== tokenizer ============================================
# Token types: n number, s string, i identifier/keyword (uppercase), o op,
#              d DATA payload, r REM payload, e end sentinel.

function tokline(key, text,   i, n, c, c2, k, s, j, q, two, t0) {
    if (key == "I") inval_cache_key("I")
    k = 0; i = 1; n = length(text)
    TSRC[key] = text                        # raw source + per-token offsets
    while (i <= n) {                        # (parse_fname reads paths verbatim)
        c = substr(text, i, 1)
        if (c == " " || c == "\t") { i++; continue }
        t0 = i
        if (c == "\"") {
            j = index(substr(text, i + 1), "\"")
            if (j == 0) { s = substr(text, i + 1); i = n + 1 }
            else { s = substr(text, i + 1, j - 1); i = i + j + 1 }
            k++; TK[key, k] = s; TY[key, k] = "s"
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
            if (s == "REM") {
                k++; TK[key, k] = "REM"; TY[key, k] = "i"
                k++; TK[key, k] = substr(text, i); TY[key, k] = "r"
                i = n + 1
                continue
            }
            if (s == "DATA") {
                k++; TK[key, k] = "DATA"; TY[key, k] = "i"
                q = 0; j = i
                while (j <= n) {
                    c2 = substr(text, j, 1)
                    if (c2 == "\"") q = !q
                    else if (c2 == ":" && !q) break
                    j++
                }
                k++; TK[key, k] = substr(text, i, j - i); TY[key, k] = "d"
                i = j
                continue
            }
            k++; TK[key, k] = s; TY[key, k] = "i"; TPO[key, k] = t0
            continue
        }
        if (c == "'") {
            k++; TK[key, k] = "REM"; TY[key, k] = "i"
            k++; TK[key, k] = substr(text, i + 1); TY[key, k] = "r"
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

function inval_cache_key(k,   i) {
    if (k in TOKD) {
        for (i = 1; i <= TCN[k]; i++) { delete TK[k, i]; delete TY[k, i]; delete TPO[k, i] }
        delete TCN[k]; delete TOKD[k]; delete TSRC[k]
    }
}
