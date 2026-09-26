# ===================== command line and batch (non-interactive) mode ========
# With a filename argument the interpreter LOADs and RUNs the program, then
# exits.  stdin belongs entirely to the running program (INPUT/LINE INPUT/
# INKEY$ consume it in order); interpreter messages go to stderr so stdout
# carries only what the program PRINTs.  No timeout guard is built in --
# wrap the invocation in the shell's `timeout` if a program may not halt.
#
# Exit status:  0 clean halt (END, STOP, BYE, or falling off the end)
#               1 uncaught BASIC error, or stdin exhausted at an INPUT
#               2 bad arguments, unreadable file, or unloadable source

# parse ARGV; returns 0 on a usage error.  Sets BATCH/BATCHFILE, OPT_SCREEN,
# SEEDED/OPT_SEED, OPT_MEMSIZE, OPT_CLEAR, OPT_HELP.  gawk never reads the operands itself: the whole
# interpreter lives in BEGIN and exits there.
function parse_args(   i, a, nofl) {
    BATCH = 0; BATCHFILE = ""; OPT_SCREEN = 0; OPT_HELP = 0
    SEEDED = 0; OPT_SEED = 0; OPT_MEMSIZE = 0; OPT_CLEAR = -1; nofl = 0
    for (i = 1; i < ARGC; i++) {
        a = ARGV[i]
        if (!nofl && a == "--") { nofl = 1; continue }
        if (!nofl && a == "--seed") {
            if (++i >= ARGC || ARGV[i] !~ /^-?[0-9]+$/) {
                ARGMSG = "--seed needs an integer"
                return 0
            }
            OPT_SEED = ARGV[i] + 0; SEEDED = 1
            continue
        }
        if (!nofl && a ~ /^--seed=/) {
            a = substr(a, 8)
            if (a !~ /^-?[0-9]+$/) { ARGMSG = "--seed needs an integer"; return 0 }
            OPT_SEED = a + 0; SEEDED = 1
            continue
        }
        # --memsize N: the answer to MEM SIZE?, for a run that has no
        # prompt to answer.  Batch mode otherwise sees all 64K, and a period
        # program written on a 16K machine can depend on a smaller one: it
        # makes an address byte signed (IF H>127 THEN H=H-256) and POKEs it,
        # which is ?FC wherever string space sits above 32767.
        if (!nofl && (a == "--memsize" || a ~ /^--memsize=/)) {
            if (a == "--memsize") a = (++i < ARGC) ? ARGV[i] : ""
            else a = substr(a, 11)
            if (a !~ /^[0-9]+$/ || a + 0 < 17280 || a + 0 > 65535) {
                ARGMSG = "--memsize needs an address from 17280 to 65535"
                return 0
            }
            OPT_MEMSIZE = a + 0
            continue
        }
        # --clear N: the CLEAR N a period user typed at READY before RUN.
        # String space is 50 bytes at power-on and CLEAR n sets it (the
        # Level II manual: "the amount of string storage CLEARed must equal
        # or exceed the greatest number of characters stored in string
        # variables during execution; otherwise an Out of String Space
        # error will occur").  Many listings assumed the CLEAR was typed
        # first, outside the listing, and stop with ?OS here without it.
        # The option is that typed statement: in batch it runs after LOAD
        # and before RUN (CLOAD, CLEAR n, RUN); at the prompt it is entered
        # at the first READY, so no program can tell it from the keyboard.
        # N is CLEAR's own operand (an integer, 0-32767); its ?OM against
        # the program's size is CLEAR's, and stops the run.
        if (!nofl && (a == "--clear" || a ~ /^--clear=/)) {
            if (a == "--clear") a = (++i < ARGC) ? ARGV[i] : ""
            else a = substr(a, 9)
            if (a !~ /^[0-9]+$/ || a + 0 > 32767) {
                ARGMSG = "--clear needs a byte count from 0 to 32767"
                return 0
            }
            OPT_CLEAR = a + 0
            continue
        }
        if (!nofl && a == "--screen") { OPT_SCREEN = 1; continue }
        if (!nofl && (a == "-h" || a == "--help")) { OPT_HELP = 1; return 1 }
        if (!nofl && a ~ /^-./) { ARGMSG = "unknown option " a; return 0 }
        if (BATCHFILE != "") { ARGMSG = "only one program file may be given"; return 0 }
        BATCHFILE = a; BATCH = 1
    }
    return 1
}

# dest "" = stdout (--help), "/dev/stderr" = usage error (with the reason)
function usage(dest,   t) {
    t = "Usage: basic [options] [program.bas]\n" \
        "\n" \
        "With a program file, LOAD and RUN it non-interactively, then exit.\n" \
        "With no file, start the interactive READY prompt.\n" \
        "\n" \
        "  --seed N     seed RND for repeatable runs (RANDOM re-applies N)\n" \
        "  --memsize N  answer MEM SIZE? with N (17280-65535); 32767 is a\n" \
        "               16K machine, for programs that only ran on one\n" \
        "  --clear N    type CLEAR N before RUN: string space is 50 bytes\n" \
        "               until then, and a listing that assumed it stops ?OS\n" \
        "  --screen     keep the TRS-80 screen/cursor control codes\n" \
        "               (output is plain text by default without a tty)\n" \
        "  -h, --help   show this message\n" \
        "  --           end of options\n" \
        "\n" \
        "Exit status: 0 clean run, 1 BASIC runtime error, 2 bad invocation.\n" \
        "stdin feeds the program's own INPUT statements; BASIC errors go to\n" \
        "stderr as \"?SN ERROR IN 40\".  Use the shell's `timeout` to bound a\n" \
        "program that may not halt."
    if (dest == "") { printf "%s\n", t; return }
    if (ARGMSG != "") printf "basic: %s\n", ARGMSG > "/dev/stderr"
    printf "%s\n", t > "/dev/stderr"
}

# LOAD + RUN the batch program; returns the process exit status
function batch_main() {
    BATCHERR = 0
    if (!prog_load(BATCHFILE, 0)) {
        # /dev/stdin and the shell's <(...) (/dev/fd/N) are refused by name
        # (host_special, p90), and "cannot read" alone sent the user looking
        # for a missing file (the 2026-09-19 audit, M-23)
        if (host_special(BATCHFILE))
            diag_err("basic: cannot read '" BATCHFILE "': a device, descriptor or socket name is not taken for a program; give a file (stdin feeds the program's INPUT)")
        else diag_err("basic: cannot read '" BATCHFILE "'")
        return 2
    }
    if (LOADBAD) return 2                   # ?FD lines already on stderr
    if (OPT_CLEAR >= 0) {                   # --clear N: CLEAR N typed before RUN
        exec_immediate("CLEAR " OPT_CLEAR)
        if (BATCHERR) {                     # CLEAR's own ?OM: the space does not fit
            diag_err("basic: --clear " OPT_CLEAR " does not fit below the program on this memory map")
            return 2
        }
    }
    exec_immediate("RUN")                   # the same path as typing RUN
    return (BATCHERR ? 1 : 0)
}

# A note on stderr behind the ROM's error message, in batch mode only, for
# the two errors a period listing meets here because a keystroke that lived
# OUTSIDE the listing is missing: ?OS when string space was never CLEARed
# (the Level II manual has CLEAR n typed before RUN), and ?OV at CLEAR MEM-n
# on a map where MEM exceeds 32767 (a 16K/32K listing).  Not an extension
# of BASIC: the screen, the program's output, the error message and the
# exit status are what the machine gave, and no program can read stderr.
# At the prompt the ROM's message stands alone, as on the machine.
function batch_hint(c) {
    if (c == 14) {                                          # ?OS
        if (CLEARSRC == "")
            diag_err("basic: string space is 50 bytes until CLEAR n (Level II manual, CLEAR); the listing assumed one typed before RUN: try --clear 1000")
        else if (CLEARSRC == "I")
            diag_err("basic: --clear " CLEARN " is too small for this program's strings: raise it")
        else
            diag_err("basic: the program's own CLEAR " CLEARN " in line " CLEARSRC " is too small for its strings; --clear cannot help, the program's CLEAR wins")
    } else if (c == 6 && HIMEM > 32767 && TY[SK, SCP] == "i" && TK[SK, SCP] == "CLEAR")
        diag_err("basic: CLEAR's count is an integer (?OV past 32767) and MEM exceeds 32767 on this memory map: the listing was written for a 16K or 32K machine, try --memsize 32767")
}

# an interpreter message (not program output): stderr in batch, the simulated
# screen when interactive
function diag(msg) {
    if (BATCH) diag_err(msg)
    else { s_puts(msg); s_nl() }
}

function diag_err(msg) {
    fflush()                                # keep stdout/stderr in order
    printf "%s\n", msg > "/dev/stderr"
    fflush("/dev/stderr")
}

# stdin ran dry while an INPUT was waiting: the fixture under-fed the program
function batch_ineof() {
    BATCHERR = 1
    diag_err("?BATCH: END OF INPUT" (CLN == DIRECTLN ? "" : " AT LINE " CLN))
}
