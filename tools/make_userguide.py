#!/usr/bin/env python3
"""make_userguide.py -- regenerate the reference part of docs/USER_GUIDE.md.

The user guide is one hand-written file with a generated tail: everything
between the markers

    <!-- BEGIN GENERATED REFERENCE (make_userguide.py) -->
    <!-- END GENERATED REFERENCE -->

is rebuilt from support/manpages.txt (the same file the interpreter's `man`
and `help` commands read), so the guide cannot drift from what `man` says.
Run it after any manpages.txt edit:

    python3 tools/make_userguide.py          # rewrite docs/USER_GUIDE.md in place
    python3 tools/make_userguide.py --check  # exit 1 if the guide is stale
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANPAGES = ROOT / "support" / "manpages.txt"
GUIDE = ROOT / "docs" / "USER_GUIDE.md"
BEGIN = "<!-- BEGIN GENERATED REFERENCE (make_userguide.py) -->"
END = "<!-- END GENERATED REFERENCE -->"

# Display order and membership of the reference categories.  A keyword is
# filed under the first category listing any of its header's aliases;
# anything unlisted lands in "Everything else" with a warning, so a new
# manpage entry is never silently dropped.
CATEGORIES = [
    ("Statements", [
        "PRINT", "USING", "?", "LET", "IF", "THEN", "ELSE", "GOTO", "GOSUB",
        "RETURN", "FOR", "TO", "STEP", "NEXT", "INPUT", "READ", "DATA",
        "RESTORE", "REM", "END", "STOP", "DIM", "CLS", "CLEAR", "ON",
        "POKE", "OUT", "LPRINT", "LLIST", "TAB",
    ]),
    ("Command level", [
        "RUN", "LIST", "NEW", "CONT", "AUTO", "DELETE", "CLOAD", "CSAVE",
        "LOAD", "SAVE", "MERGE", "NAME", "BYE", "TRON", "TROFF", "RANDOM",
    ]),
    ("Graphics", ["SET", "RESET", "POINT"]),
    ("Error handling", ["ERROR", "RESUME", "ERR", "ERL"]),
    ("Types and definitions", [
        "DEFINT", "DEFSNG", "DEFDBL", "DEFSTR", "FN", "DEFFN", "USR",
        "DEFUSR", "VARPTR",
    ]),
    ("Files", [
        "OPEN", "CLOSE", "KILL", "PRINT#", "INPUT#", "LINE", "FIELD",
        "GET", "PUT", "LSET", "RSET", "EOF", "LOF", "LOC",
        "MKI$", "MKS$", "MKD$", "CVI", "CVS", "CVD",
    ]),
    ("The OLLAMA channel", ["OLLAMA"]),
    ("Numeric functions", [
        "ABS", "INT", "FIX", "SGN", "SQR", "SIN", "COS", "TAN", "ATN",
        "LOG", "EXP", "RND", "CINT", "CSNG", "CDBL", "&H", "&O",
    ]),
    ("String functions", [
        "LEN", "ASC", "VAL", "CHR$", "STR$", "STRING$", "LEFT$", "RIGHT$",
        "MID$", "INSTR",
    ]),
    ("System and screen", [
        "INKEY$", "POS", "FRE", "MEM", "TIME$",
    ]),
    # Not Level II BASIC -- host-side conveniences this interpreter adds.
    # Listed last so the reference reads as the language first.
    ("Metacommands", [
        "MAN", "HELP", "DIR", "CAT", "EXT", "FULLSCREEN", "SPEED",
        "HISTORY", "H", "@DUMP",
    ]),
]


def parse_manpages():
    """Return list of (header_keywords, body_lines) in file order."""
    entries, header, body = [], None, []
    for line in MANPAGES.read_text().split("\n"):
        if line.startswith(":"):
            if header is not None:
                entries.append((header, body))
            header = line[1:].replace(",", " ").split()
            body = []
        elif header is not None:
            body.append(line)
    if header is not None:
        entries.append((header, body))
    # trim trailing blank lines per entry
    return [(h, _trim(b)) for h, b in entries]


def _trim(lines):
    while lines and not lines[-1].strip():
        lines.pop()
    while lines and not lines[0].strip():
        lines.pop(0)
    return lines


def generate():
    entries = parse_manpages()
    filed = {}          # category -> [(header, body)]
    for header, body in entries:
        for cat, members in CATEGORIES:
            if any(k in members for k in header):
                filed.setdefault(cat, []).append((header, body))
                break
        else:
            filed.setdefault("Everything else", []).append((header, body))
            print(f"warning: {' '.join(header)} not in any category",
                  file=sys.stderr)

    out = [BEGIN, "", "*This part is generated from `support/manpages.txt` — "
           "the same text `man` shows inside the interpreter. Do not edit it "
           "here; edit the manpages and run `python3 tools/make_userguide.py`.*",
           ""]
    order = [c for c, _ in CATEGORIES] + ["Everything else"]
    for cat in order:
        if cat not in filed:
            continue
        out.append(f"### {cat}")
        out.append("")
        for header, body in filed[cat]:
            out.append(f"#### {' '.join(header)}")
            out.append("")
            out.append("```text")
            out.extend(body)
            out.append("```")
            out.append("")
    out.append(END)
    return "\n".join(out)


def main():
    check = "--check" in sys.argv
    guide = GUIDE.read_text()
    m = re.search(re.escape(BEGIN) + r".*?" + re.escape(END), guide, re.S)
    if not m:
        sys.exit(f"{GUIDE}: generated-reference markers not found")
    new = guide[: m.start()] + generate() + guide[m.end():]
    if check:
        if new != guide:
            sys.exit("USER_GUIDE.md is stale: run python3 tools/make_userguide.py")
        print("USER_GUIDE.md reference is current")
        return
    if new != guide:
        GUIDE.write_text(new)
        print(f"rewrote {GUIDE}")
    else:
        print("already current")


if __name__ == "__main__":
    main()
