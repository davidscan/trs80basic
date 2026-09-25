#!/bin/sh
# special.sh -- gawk's special file names never reach getline or a redirect.
# /inet/tcp/... is a socket, /dev/fd/N and "-" are the interpreter's own
# descriptors, /dev/zero never ends; a BASIC program picks its file names,
# so each of these must be ?FD from every statement that takes a name
# (the 2026-09-19 audit, H-1; host_special in p90).  With python3 a loopback
# listener proves that no connection was even attempted.  Self-checking:
# exits 1 on any mismatch.  Run from the repo root:
#   sh programs/tests/special.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
d=$(mktemp -d) || exit 2
cd "$d" || exit 2
lpid=
cleanup() { [ -n "$lpid" ] && { kill "$lpid"; wait "$lpid"; } 2>/dev/null; cd /; rm -rf "$d"; }
fail() { echo "SPECIAL FAILED: $1"; printf '%s\n' "$2"; cleanup; exit 1; }
run() { TRS80_DUMB=1 TRS80_Z80= "$here/basic" "$@" 2>&1 </dev/null; }

port=9
if command -v python3 >/dev/null 2>&1; then
    python3 - "$d/port" "$d/hits" <<'PY' &
import socket, sys
s = socket.socket(); s.bind(('127.0.0.1', 0)); s.listen(8)
open(sys.argv[1], 'w').write(str(s.getsockname()[1]))
while True:
    c, _ = s.accept()
    open(sys.argv[2], 'a').write('hit\n')
    c.sendall(b'10 PRINT "FETCHED FROM THE NETWORK"\n'); c.close()
PY
    lpid=$!
    i=0; while [ ! -s "$d/port" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
    [ -s "$d/port" ] && port=$(cat "$d/port")
fi
net="/inet/tcp/0/127.0.0.1/$port"

# every statement that takes a name, against the socket name: ?FD (22), trapped
cat > t.bas <<BAS
10 ON ERROR GOTO 900:N\$="$net":K=0
20 S=1:OPEN "I",1,N\$
30 S=2:OPEN "O",1,N\$
40 S=3:OPEN "E",1,N\$
50 S=4:OPEN "R",1,N\$
60 S=5:OPEN "I",1,"-"
70 S=6:OPEN "I",1,"/dev/stdin"
80 S=7:OPEN "I",1,"/dev/fd/0"
90 S=8:OPEN "O",1,"/dev/stdout"
100 S=9:OPEN "I",1,"/inet4/tcp/0/127.0.0.1/$port"
110 S=10:OPEN "I",1,"/dev/zero"
120 S=11:KILL "/dev/null"
130 IF K=11 THEN PRINT "ALL REFUSED" ELSE PRINT "REFUSED ONLY";K
140 END
900 IF ERR/2+1=22 OR (S=11 AND ERR/2+1=54) THEN K=K+1 ELSE PRINT "STEP";S;"GAVE ERROR";ERR/2+1
910 RESUME NEXT
BAS
out=$(run t.bas)
[ "$out" = "ALL REFUSED" ] || fail "OPEN/KILL on a special name" "$out"

# LOAD, RUN "f", MERGE, CLOAD, SAVE and SYSTEM, at the prompt: the program in memory survives
out=$(printf '\n10 PRINT "MINE"\nLOAD "%s"\nRUN "%s"\nMERGE "%s"\nCLOAD "%s"\nSAVE "%s"\nCSAVE "/dev/stdout"\nRUN\n' \
      "$net" "$net" "$net" "$net" "$net" | TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" 2>&1)
n=$(printf '%s\n' "$out" | grep -c '?FD ERROR')
[ "$n" -eq 6 ] || fail "LOAD/RUN/MERGE/CLOAD/SAVE/CSAVE: $n of 6 were ?FD" "$out"
case $out in *FETCHED*) fail "a program came in from the network" "$out" ;; esac
case $out in *MINE*) ;; *) fail "the program in memory did not survive" "$out" ;; esac
out=$(printf '\nSYSTEM\n%s\n' "$net" | TRS80_DUMB=1 TRS80_Z80= gawk -b -f "$here/trs80basic.awk" 2>&1)
case $out in *"?FD ERROR"*) ;; *) fail "SYSTEM took a special name" "$out" ;; esac

# the batch program file itself
out=$(run "$net"); rc=$?
[ $rc -eq 2 ] || fail "a socket as the batch program (rc=$rc)" "$out"
out=$(printf '10 PRINT "FROM STDIN"\n' | TRS80_Z80= "$here/basic" /dev/stdin 2>&1); rc=$?
[ $rc -eq 2 ] || fail "/dev/stdin as the batch program (rc=$rc)" "$out"
# ... and the message says why: the file is there, the NAME is refused
# (the 2026-09-19 audit, M-23)
case $out in *"not taken for a program"*) ;; *) fail "/dev/stdin: the message must say why" "$out" ;; esac
case $out in *"FROM STDIN"*) fail "/dev/stdin ran as the batch program" "$out" ;; esac
# a FIFO is an ordinary name and can be read only ONCE: the loader used to
# open the file twice (header sniff, then the text lines), which ran an
# empty program or hung
if mkfifo "$d/ff" 2>/dev/null; then
    (printf '10 PRINT "FROM FIFO"\n' > "$d/ff" &)
    TRS80_DUMB=1 TRS80_Z80= "$here/basic" "$d/ff" > "$d/ff.out" 2>&1 </dev/null &
    bp=$!
    (sleep 20; kill "$bp" 2>/dev/null) >/dev/null 2>&1 &
    wp=$!
    wait "$bp"; rc=$?
    kill "$wp" 2>/dev/null; wait "$wp" 2>/dev/null
    out=$(cat "$d/ff.out")
    [ $rc -eq 0 ] && [ "$out" = "FROM FIFO" ] || fail "a FIFO as the batch program (rc=$rc)" "$out"
fi

# the SAME devices spelled another way.  gawk matches its own names as
# literal prefixes, so //dev/zero, /./dev/zero and (on a case-insensitive
# filesystem) /Dev/zero are handed to the OS, which resolves them to the
# device: the slurp never ended, the write went raw to the terminal (the
# 2026-09-23 audit, H-3).  The rule is now the file's KIND, not its
# spelling: a program reads a regular file, and writes a regular file or a
# name that does not exist yet -- a device, a directory or a FIFO is ?FD.
# A run that hangs on a device is killed after 20 s and counts as a failure.
# (//dev/stdout is not in the list: it IS whatever stdout is, and here that
# is a regular file, which a program may write; at a terminal or a pipe it
# is a device and is refused like the rest.)
runto() {   # $1 = stdin file, $2... = arguments; output on stdout, rc 124 on the kill
    inp=$1; shift
    TRS80_DUMB=1 TRS80_Z80= "$here/basic" "$@" < "$inp" > "$d/to.out" 2>&1 &
    bp=$!
    (sleep 20; kill "$bp" 2>/dev/null) >/dev/null 2>&1 &
    wp=$!
    wait "$bp"; rc=$?
    kill "$wp" 2>/dev/null; wait "$wp" 2>/dev/null
    cat "$d/to.out"; return $rc
}
mkdir adir
mkfifo "$d/ff" 2>/dev/null || touch "$d/ff"      # no FIFO: a plain file, refused nowhere, counted below
fifo=$([ -p "$d/ff" ] && echo 1 || echo 0)
cat > k.bas <<BAS
10 ON ERROR GOTO 900:K=0:F=$fifo
20 S=1:OPEN "I",1,"//dev/zero"
30 S=2:OPEN "O",1,"/./dev/tty"
40 S=3:OPEN "E",1,"//dev/null"
50 S=4:OPEN "R",1,"//dev/zero"
60 S=5:OPEN "O",1,"//dev/zero"
70 S=6:OPEN "I",1,"adir"
80 S=7:OPEN "I",1,"$d/ff":IF F=0 THEN CLOSE:K=K+1
90 S=8:OPEN "R",1,"$d/ff":IF F=0 THEN CLOSE:K=K+1
100 S=9:KILL "//dev/null"
110 IF K=9 THEN PRINT "ALL REFUSED" ELSE PRINT "REFUSED ONLY";K
120 END
900 IF ERR/2+1=22 OR (S=9 AND ERR/2+1=54) THEN K=K+1 ELSE PRINT "STEP";S;"GAVE ERROR";ERR/2+1
910 RESUME NEXT
BAS
out=$(runto /dev/null k.bas)
[ "$out" = "ALL REFUSED" ] || fail "OPEN/KILL on a device, a directory or a FIFO by another spelling" "$out"
# LOAD, RUN "f", MERGE, CLOAD, SAVE and SYSTEM, at the prompt: ?FD each, the program survives
printf '\n10 PRINT "MINE"\nLOAD "//dev/zero"\nRUN "/./dev/zero"\nMERGE "adir"\nCLOAD "%s"\nSAVE "//dev/null"\nCSAVE "adir"\nRUN\n' "$d/ff" > in.txt
out=$(runto in.txt)
n=$(printf '%s\n' "$out" | grep -c '?FD ERROR')
[ "$n" -eq 6 ] || fail "LOAD/RUN/MERGE/CLOAD/SAVE/CSAVE by another spelling: $n of 6 were ?FD" "$out"
case $out in *MINE*) ;; *) fail "the program in memory did not survive the other spellings" "$out" ;; esac
printf '\nSYSTEM\n//dev/zero\n' > in.txt
out=$(runto in.txt)
case $out in *"?FD ERROR"*) ;; *) fail "SYSTEM took a device by another spelling" "$out" ;; esac
# a symbolic link to a regular file is that file
printf '10 PRINT "THROUGH THE LINK"\n' > real.bas
ln -s real.bas link.bas
printf '\nLOAD "link.bas"\nRUN\n' > in.txt
out=$(runto in.txt)
case $out in *"THROUGH THE LINK"*) ;; *) fail "a symlink to a regular file must load" "$out" ;; esac

# nothing connected
[ -s "$d/hits" ] && fail "the listener saw $(wc -l < "$d/hits") connection(s)" ""

# ordinary names that merely LOOK close are still files
cat > ok.bas <<'BAS'
10 OPEN "O",1,"inet":PRINT#1,"A":CLOSE
20 OPEN "O",1,"dev-null":PRINT#1,"B":CLOSE
30 OPEN "I",1,"inet":LINE INPUT#1,A$:CLOSE:OPEN "I",1,"dev-null":LINE INPUT#1,B$:CLOSE
40 PRINT A$;B$:KILL "inet":KILL "dev-null"
BAS
out=$(run ok.bas)
[ "$out" = "AB" ] || fail "ordinary file names" "$out"

cleanup
echo "SPECIAL OK"
