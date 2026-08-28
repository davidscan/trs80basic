# ===================== OLLAMA device channel ================================
# OPEN mode$, [#]n, "OLLAMA[:model[:thread]]" turns channel n into a
# bidirectional link (internal mode "A") to a local Ollama server: PRINT#
# accumulates a prompt; the first INPUT#/LINE INPUT# sends it (blocking,
# full conversation history each call -- /api/chat is stateless) and the
# reply becomes pending input, read line by line.  EOF(n) = -1 once the
# reply is consumed; it never triggers a send.
#
# Named threads append every message to "<thread>.ollama" (one line per
# message: role char + space + fio_esc'd content) and reload it as context
# on OPEN.  KILL "<thread>.ollama" deletes a conversation.
#
# Env: TRS80_OLLAMA_MODEL (default model), TRS80_OLLAMA_HOST (default
# localhost:11434), TRS80_OLLAMA_TIMEOUT (seconds, default 300),
# TRS80_OLLAMA_THINK (0/1: send "think":false/true; unset = omit),
# TRS80_OLLAMA_KEEPALIVE (e.g. 30m: sent as keep_alive; unset = omit),
# TRS80_OLLAMA_CURL (test hook: replaces the whole curl command; the JSON
# request body file path is appended as the last argument).
#
# DIRECTIVES (added 2026-08-21 for structured replies).  A completed
# prompt line whose first character is "@" is an instruction to the
# channel, consumed at send time and never sent to the model:
#   @TOKENS A,B,C   this send only: ask Ollama for structured output
#                   (request "format" = a JSON schema {token: enum of
#                   the list, reply: string}); the reply is delivered
#                   as line 1 = the token, following lines = the reply.
#                   Constrained decoding means the token can only be
#                   one of the list.  If the model's JSON cannot be
#                   unpacked the raw content is delivered instead.
#   @THINK 0|1      sticky for the channel: "think":false/true in every
#                   request (thinking models otherwise spend seconds
#                   on hidden reasoning before a one-line answer).
#   @KEEPALIVE 30m  sticky: "keep_alive" in every request, so a game
#                   can hold its model resident across a session.
#   @@text          a literal prompt line beginning with "@".
# Unknown directives raise ?FC.  Directives are not logged to threads.
#
# State (per channel n): AI_MODEL[n], AI_TFILE[n] (transcript path or ""),
# AI_NMSG[n]/AI_ROLE[n,i]/AI_MSG[n,i] (history, roles "u"/"a"),
# AI_PROMPT[n] (accumulated unsent prompt), AI_REPLY[n]+AI_RHAS[n]
# (unread reply text).  FH_MODE[n]="A"; FH_NAME[n] = the OPEN string.

# name parse: OLLAMA | OLLAMA:model | OLLAMA:model:thread (last part is the
# thread; middle parts rejoin so tagged models like mistral:7b work --
# a tagged model with no thread needs a trailing colon: "OLLAMA:mistral:7b:")
function ai_open(n, f,   np, parts, model, thread, i, tf, l, role) {
    np = split(f, parts, ":")
    model = ""; thread = ""
    if (np == 2) model = parts[2]
    else if (np >= 3) {
        thread = parts[np]
        model = parts[2]
        for (i = 3; i < np; i++) model = model ":" parts[i]
    }
    if (model == "") model = ENVIRON["TRS80_OLLAMA_MODEL"]
    if (model == "") { raise(21); return }
    FH_LOC[n] = 0; FH_EOF[n] = 0
    FH_PEND[n] = ""; FH_PENDHAS[n] = 0
    FH_OPEND[n] = ""; FH_OPENDHAS[n] = 0
    AI_MODEL[n] = model
    AI_TFILE[n] = ""
    AI_NMSG[n] = 0
    AI_PROMPT[n] = ""; AI_REPLY[n] = ""; AI_RHAS[n] = 0
    AI_THINK[n] = ENVIRON["TRS80_OLLAMA_THINK"]
    AI_KEEP[n] = ENVIRON["TRS80_OLLAMA_KEEPALIVE"]
    AI_TOKENS[n] = ""
    if (thread != "") {
        tf = thread ".ollama"
        AI_TFILE[n] = tf
        while ((getline l < tf) > 0) {
            role = substr(l, 1, 1)
            if (role == "u" || role == "a") {
                AI_NMSG[n]++
                AI_ROLE[n, AI_NMSG[n]] = role
                AI_MSG[n, AI_NMSG[n]] = fio_unesc(substr(l, 3))
            }
        }
        close(tf)
    }
    FH_NAME[n] = f
    FH_MODE[n] = "A"
}

function ai_close(n,   i) {
    for (i = 1; i <= AI_NMSG[n]; i++) { delete AI_ROLE[n, i]; delete AI_MSG[n, i] }
    delete AI_MODEL[n]; delete AI_TFILE[n]; delete AI_NMSG[n]
    delete AI_PROMPT[n]; delete AI_REPLY[n]; delete AI_RHAS[n]
    delete AI_THINK[n]; delete AI_KEEP[n]; delete AI_TOKENS[n]
}

# strip "@" directive lines out of the assembled prompt, applying them;
# returns the prompt that remains.  "@@x" -> literal "@x".
function ai_directives(n, prompt,   nl, lines, i, l, out, kw, arg, sp) {
    out = ""
    nl = split(prompt, lines, "\n")
    for (i = 1; i <= nl; i++) {
        l = lines[i]
        if (substr(l, 1, 2) == "@@") { out = out substr(l, 2) "\n"; continue }
        if (substr(l, 1, 1) != "@") { out = out l "\n"; continue }
        sp = index(l, " ")
        if (sp) { kw = toupper(substr(l, 2, sp - 2)); arg = substr(l, sp + 1) }
        else { kw = toupper(substr(l, 2)); arg = "" }
        gsub(/^ +| +$/, "", arg)
        if (kw == "TOKENS") { gsub(/ /, "", arg); AI_TOKENS[n] = arg }
        else if (kw == "THINK") AI_THINK[n] = arg
        else if (kw == "KEEPALIVE") AI_KEEP[n] = arg
        else { raise(5); return "" }        # ?FC: unknown directive
    }
    sub(/\n$/, "", out)
    return out
}

# the fixed structured-output schema for @TOKENS
function ai_schema(list,   n, t, i, e) {
    n = split(list, t, ",")
    e = ""
    for (i = 1; i <= n; i++) {
        if (t[i] == "") continue
        e = e (e == "" ? "" : ",") "\"" ai_jesc(t[i]) "\""
    }
    return "{\"type\":\"object\",\"properties\":{\"token\":{\"type\":\"string\",\"enum\":[" e "]}," \
           "\"reply\":{\"type\":\"string\"}},\"required\":[\"token\",\"reply\"]}"
}

# value of string key k in a flat JSON object text, unescaped; "" + found=0 if absent
function ai_jstr(json, k,   p, i, len, c, out) {
    AI_JFOUND = 0
    p = index(json, "\"" k "\"")
    if (p == 0) return ""
    i = p + length(k) + 2
    len = length(json)
    while (i <= len && substr(json, i, 1) ~ /[ :\t\r\n]/) i++
    if (substr(json, i, 1) != "\"") return ""
    i++; out = ""
    while (i <= len) {
        c = substr(json, i, 1)
        if (c == "\"") { AI_JFOUND = 1; return ai_junesc(out) }
        if (c == "\\" && i < len) { out = out c substr(json, i + 1, 1); i += 2; continue }
        out = out c
        i++
    }
    return ""
}

# append one message to the thread transcript (durable: close every time)
function ai_log(n, role, msg) {
    if (AI_TFILE[n] == "") return
    print role " " fio_esc(msg) >> AI_TFILE[n]
    close(AI_TFILE[n])
}

# mode-"A" analog of fio_fill: pop the next reply line into FH_PEND,
# sending the accumulated prompt first if the reply buffer is empty
function ai_fill(n,   p) {
    if (FH_PENDHAS[n]) return 1
    if (!AI_RHAS[n]) {
        if (!FH_OPENDHAS[n] && AI_PROMPT[n] == "") return 0
        ai_send(n)
        if (E) return 0
    }
    p = index(AI_REPLY[n], "\n")
    if (p) { FH_PEND[n] = substr(AI_REPLY[n], 1, p - 1); AI_REPLY[n] = substr(AI_REPLY[n], p + 1) }
    else { FH_PEND[n] = AI_REPLY[n]; AI_REPLY[n] = ""; AI_RHAS[n] = 0 }
    FH_PENDHAS[n] = 1
    FH_LOC[n]++
    return 1
}

function ai_send(n,   i, body, bf, cmd, host, tmo, resp, line, content, rc, tok, rep) {
    if (FH_OPENDHAS[n]) {                   # trailing-; partial completes the prompt
        AI_PROMPT[n] = AI_PROMPT[n] FH_OPEND[n] "\n"
        FH_OPEND[n] = ""; FH_OPENDHAS[n] = 0
    }
    sub(/\n$/, "", AI_PROMPT[n])
    AI_TOKENS[n] = ""
    AI_PROMPT[n] = ai_directives(n, AI_PROMPT[n])
    if (E) { AI_PROMPT[n] = ""; return }
    AI_NMSG[n]++
    AI_ROLE[n, AI_NMSG[n]] = "u"
    AI_MSG[n, AI_NMSG[n]] = AI_PROMPT[n]
    AI_PROMPT[n] = ""
    body = "{\"model\":\"" ai_jesc(AI_MODEL[n]) "\",\"stream\":false,\"messages\":["
    for (i = 1; i <= AI_NMSG[n]; i++) {
        if (i > 1) body = body ","
        body = body "{\"role\":\"" (AI_ROLE[n, i] == "u" ? "user" : "assistant") "\"," \
                    "\"content\":\"" ai_jesc(AI_MSG[n, i]) "\"}"
    }
    body = body "]"
    if (AI_THINK[n] == "0" || AI_THINK[n] == "1")
        body = body ",\"think\":" (AI_THINK[n] == "1" ? "true" : "false")
    if (AI_KEEP[n] != "") body = body ",\"keep_alive\":\"" ai_jesc(AI_KEEP[n]) "\""
    if (AI_TOKENS[n] != "") body = body ",\"format\":" ai_schema(AI_TOKENS[n])
    body = body "}"
    bf = host_tmpdir() "/trs80_ollama_" PROCINFO["pid"] ".json"
    printf "%s", body > bf
    close(bf)
    if (ENVIRON["TRS80_OLLAMA_CURL"] != "")
        cmd = ENVIRON["TRS80_OLLAMA_CURL"] (WINNATIVE ? " \"" bf "\"" : " '" bf "'")
    else {
        host = ENVIRON["TRS80_OLLAMA_HOST"]
        if (host == "") host = "localhost:11434"
        tmo = ENVIRON["TRS80_OLLAMA_TIMEOUT"] + 0
        if (tmo <= 0) tmo = 300
        # cmd.exe passes single quotes through literally, so the native arm
        # must double-quote (curl.exe ships with Windows 10+)
        if (WINNATIVE)
            cmd = "curl -s --max-time " tmo " -X POST http://" host "/api/chat -d @\"" bf "\""
        else
            cmd = "curl -s --max-time " tmo " -X POST 'http://" host "/api/chat' -d @'" bf "'"
    }
    resp = ""
    while ((cmd | getline line) > 0) resp = resp line "\n"
    rc = close(cmd)
    host_delete(bf)
    if (rc != 0 || resp == "") { ai_unsend(n); raise(22); return }
    content = ai_extract(resp)
    if (E) { ai_unsend(n); return }
    if (AI_TOKENS[n] != "") {               # unpack {token, reply} into lines
        tok = ai_jstr(content, "token")
        if (AI_JFOUND) {
            rep = ai_jstr(content, "reply")
            content = tok "\n" rep
        }
        AI_TOKENS[n] = ""
    }
    sub(/\n+$/, "", content)                # models often pad with blank lines
    ai_log(n, "u", AI_MSG[n, AI_NMSG[n]])   # transcript only records completed exchanges
    AI_NMSG[n]++
    AI_ROLE[n, AI_NMSG[n]] = "a"
    AI_MSG[n, AI_NMSG[n]] = content
    ai_log(n, "a", content)
    AI_REPLY[n] = content
    AI_RHAS[n] = 1
}

# a failed send must not leave the unanswered user turn in the history
function ai_unsend(n) {
    delete AI_ROLE[n, AI_NMSG[n]]; delete AI_MSG[n, AI_NMSG[n]]
    AI_NMSG[n]--
}

# pull message.content out of a stream:false /api/chat response
function ai_extract(resp,   p, i, len, c, out) {
    p = index(resp, "\"content\":\"")
    if (p == 0) { raise(22); return "" }
    i = p + 11
    len = length(resp)
    out = ""
    while (i <= len) {
        c = substr(resp, i, 1)
        if (c == "\"") return ai_junesc(out)
        if (c == "\\" && i < len) { out = out c substr(resp, i + 1, 1); i += 2; continue }
        out = out c
        i++
    }
    raise(22)                               # unterminated string
    return ""
}

# JSON escape: backslash, quote, and ASCII control chars; UTF-8 passes through
function ai_jesc(s,   out, i, n, c, o) {
    out = ""; n = length(s)
    for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (c == "\\") { out = out "\\\\"; continue }
        if (c == "\"") { out = out "\\\""; continue }
        if (c in ORD) {
            o = ORD[c]
            if (o < 32) {
                if (o == 10) out = out "\\n"
                else if (o == 13) out = out "\\r"
                else if (o == 9) out = out "\\t"
                else out = out sprintf("\\u%04X", o)
                continue
            }
        }
        out = out c
    }
    return out
}

function ai_junesc(s,   out, i, n, c, e) {
    out = ""; i = 1; n = length(s)
    while (i <= n) {
        c = substr(s, i, 1)
        if (c != "\\" || i == n) { out = out c; i++; continue }
        e = substr(s, i + 1, 1)
        if (e == "n") out = out "\n"
        else if (e == "t") out = out "\t"
        else if (e == "r") out = out "\r"
        else if (e == "u" && i + 5 <= n) {
            out = out sprintf("%c", strtonum("0x" substr(s, i + 2, 4)))
            i += 6
            continue
        }
        else out = out e                    # \" \\ \/ and anything unknown
        i += 2
    }
    return out
}
