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
# SEEDED/OPT_SEED, OPT_HELP.  gawk never reads the operands itself: the whole
# interpreter lives in BEGIN and exits there.
function parse_args(   i, a, nofl) {
    BATCH = 0; BATCHFILE = ""; OPT_SCREEN = 0; OPT_HELP = 0
    SEEDED = 0; OPT_SEED = 0; nofl = 0
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
        diag_err("basic: cannot read '" BATCHFILE "'")
        return 2
    }
    if (LOADBAD) return 2                   # ?FD lines already on stderr
    exec_immediate("RUN")                   # the same path as typing RUN
    return (BATCHERR ? 1 : 0)
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
    diag_err("?BATCH: END OF INPUT" (CLN > 0 ? " AT LINE " CLN : ""))
}
