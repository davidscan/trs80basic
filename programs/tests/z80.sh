#!/bin/sh
# z80.sh -- the USR coprocess protocol (PROTOCOL.md, src/p77_z80.awk) against
# its reference stub, programs/tests/z80_stub.py.  Self-checking: exits 1 on
# any mismatch.  Run from the repo root:  sh programs/tests/z80.sh
# A real core is conformant when this passes with TRS80_Z80 pointing at it:
#   TRS80_Z80="python3 ../trs80_z80_core/core.py --fixture" sh programs/tests/z80.sh
here=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 2
core="python3 $here/programs/tests/z80_stub.py"
[ -n "$TRS80_Z80" ] && core="$TRS80_Z80"
tmp=$(mktemp) || exit 2
fail() { echo "Z80 FIXTURE FAILED: $1"; [ -n "$2" ] && printf '%s\n' "$2"; rm -f "$tmp" "$tmp.err"; exit 1; }

# --- the main program: every entry with a batch-visible effect
cat > "$tmp" <<'EOF'
10 DIM Z(1):F=0
20 DEFUSR0=&H7000:X=USR0(0):IF PEEK(15360)<>72 OR PEEK(15361)<>73 THEN PRINT "FAIL video streamed";PEEK(15360);PEEK(15361):F=1
30 DEFUSR1=&H7003:IF USR1(21)<>42 THEN PRINT "FAIL HL result";USR1(21):F=1
40 IF USR1(-5)<>-10 THEN PRINT "FAIL signed result";USR1(-5):F=1
50 IF USR1(1.9)<>2 THEN PRINT "FAIL arg converted to integer";USR1(1.9):F=1
52 IF USR1(-1.5)<>-4 THEN PRINT "FAIL 0A7FH floors, -1.5 is -2";USR1(-1.5):F=1
53 IF USR1(-32768)<>0 THEN PRINT "FAIL -32768 passes 0A7FH";USR1(-32768):F=1
54 ON ERROR GOTO 56:X=USR1(40000):PRINT "FAIL no ?OV for 40000":F=1:GOTO 58
56 IF ERR/2+1<>6 THEN PRINT "FAIL 40000 at 0A7FH is not ?OV but";ERR/2+1:F=1
57 RESUME 58
58 ON ERROR GOTO 0
60 A$="HELLO":V=VARPTR(A$):D=PEEK(V+1)+256*PEEK(V+2)
62 IF V>=0 THEN PRINT "FAIL VARPTR below HIMEM is the ROM's integer, negative";V:F=1
64 IF USR1(V)<>2*V THEN PRINT "FAIL a negative VARPTR passes 0A7FH";USR1(V);V:F=1
66 IF D>32767 THEN D=D-65536:REM the period idiom: a data address above 32767 must be signed for USR
70 DEFUSR2=&H7002:X=USR2(D):IF A$<>"ABCLO" THEN PRINT "FAIL write-set into packed string: ";A$:F=1
80 POKE 30000,99:DEFUSR3=&H7005:IF USR3(30000)<>99 THEN PRINT "FAIL core sees a POKE";USR3(30000):F=1
90 IF USR3(D+3)<>76 THEN PRINT "FAIL core sees the packed string";USR3(D+3):F=1
100 IF USR3(17129)<>PEEK(17129) OR USR3(17130)<>PEEK(17130) THEN PRINT "FAIL core sees the program image":F=1
110 IF USR3(50000-65536)<>255 THEN PRINT "FAIL unwritten reads 255";USR3(50000-65536):F=1
120 IF USR3(16561)<>PEEK(16561) OR USR3(16562)<>PEEK(16562) THEN PRINT "FAIL core sees the pointers":F=1
130 POKE 30001,7:IF USR3(30001)<>7 THEN PRINT "FAIL delta frame carries a new POKE";USR3(30001):F=1
140 A$="WORLD":IF USR3(D)<>87 THEN PRINT "FAIL delta frame carries a string value";USR3(D):F=1
150 DEFUSR4=&H7008:X=USR4(0):POKE 30002,8
160 IF USR3(30002)<>8 OR USR3(30000)<>99 OR USR3(D)<>87 THEN PRINT "FAIL full resend after NEED":F=1
170 DEFUSR5=&H7009:X=USR5(0):S=V-6:IF PEEK(S-1)<>18 OR PEEK(S-2)<>52 THEN PRINT "FAIL stack pushed below SSP";PEEK(S-1);PEEK(S-2):F=1
180 DEFUSR6=&H7007:X=USR6(0):IF X<>0 THEN PRINT "FAIL sustained routine":F=1
190 DEFUSR7=&H700A:X=USR7(0):IF PEEK(15400)<>65 OR PEEK(30000)<>1 THEN PRINT "FAIL video plus write-set":F=1
205 DEFUSR8=&H700B:X=USR8(0):IF INP(255)<>63 THEN PRINT "FAIL MODE 32-column";INP(255):F=1
206 DEFUSR8=&H700C:X=USR8(0):IF INP(255)<>127 THEN PRINT "FAIL MODE 64-column";INP(255):F=1
210 DEFUSR9=&H7777:IF USR9(5)<>5 THEN PRINT "FAIL plain RET keeps the argument":F=1
220 IF F THEN PRINT "Z80 FIXTURE FAILED":Z(9)=0
230 PRINT "Z80 FIXTURE OK"
EOF
out=$(TRS80_Z80="$core" "$here/basic" "$tmp" 2>"$tmp.err" </dev/null); rc=$?
err=$(cat "$tmp.err")
[ "$rc" = "0" ] || fail "main program rc=$rc" "$out
$err"
[ "$out" = "Z80 FIXTURE OK" ] || fail "main program output" "$out"
[ -z "$err" ] || fail "main program wrote to stderr (no stub tally expected with a core)" "$err"

# --- the keyboard callback: batch mode reads keys from stdin lines, so a fed
# "A" shows as row 0 bit 1 plus SHIFT (row 7 bit 0) on an all-rows read = 3
printf '10 DEFUSR=&H7001:K=USR(0):PRINT K;PEEK(15424)\n' > "$tmp"
out=$(printf 'A\n' | TRS80_Z80="$core" "$here/basic" "$tmp" 2>&1); rc=$?
[ "$rc" = "0" ] && [ "$out" = " 3  3 " ] || fail "keyboard callback: rc=$rc" "$out"

# --- CLS restores 64-column mode after 32-column (the Dancing Demon idiom:
# CHR$(23) from BASIC, then a routine's CLS).  The write-set clears bit 3
# of 403DH, the ROM's print flag, so the PRINT after the call steps one
# byte again (15361 holds the B); without it the stage the demon paints
# from BASIC lands on every other cell.
printf '10 DEFUSR=&H700B:X=USR(0):IF INP(255)<>63 THEN PRINT "no 32col":END\n20 PRINT CHR$(23);:DEFUSR=&H700D:X=USR(0):PRINT@0,"AB";:PRINT INP(255);PEEK(16445);PEEK(15361)\n' > "$tmp"
out=$(TRS80_Z80="$core" "$here/basic" "$tmp" 2>&1 </dev/null); rc=$?
[ "$rc" = "0" ] && [ "$out" = "AB 127  0  66 " ] || fail "CLS restores 64-column and the print flag: rc=$rc" "$out"

# --- an undefined entry is ?FC on this side, never sent
printf '10 X=USR6(0)\n' > "$tmp"
out=$(TRS80_Z80="$core" "$here/basic" "$tmp" 2>&1 </dev/null); rc=$?
[ "$rc" = "1" ] && [ "$out" = "?FC ERROR IN 10" ] || fail "undefined entry: rc=$rc" "$out"

# --- ERR from the core: ?FC plus the text, and the core stays up
printf '10 DEFUSR=&H7006:X=USR(0)\n20 PRINT "NOT REACHED"\n' > "$tmp"
out=$(TRS80_Z80="$core" "$here/basic" "$tmp" 2>&1 </dev/null); rc=$?
want='USR CORE: rom called 0000H, no ROM here
?FC ERROR IN 10'
[ "$rc" = "1" ] && [ "$out" = "$want" ] || fail "ERR path: rc=$rc" "$out"
printf '10 ON ERROR GOTO 30\n20 DEFUSR=&H7006:X=USR(0)\n30 DEFUSR=&H7003:PRINT USR(4)\n' > "$tmp"
out=$(TRS80_Z80="$core" "$here/basic" "$tmp" 2>/dev/null </dev/null); rc=$?
[ "$rc" = "0" ] && [ "$out" = " 8 " ] || fail "core still up after ERR: rc=$rc" "$out"

# --- the stores a routine made before its ERR arrive ahead of it: BASIC's
# PEEK and the core's own memory (read back by 7005H) agree afterwards
printf '10 ON ERROR GOTO 30\n20 DEFUSR=&H700E:X=USR(30000)\n30 RESUME 40\n40 DEFUSR=&H7005:PRINT PEEK(30000);USR(30000)\n' > "$tmp"
out=$(TRS80_Z80="$core" "$here/basic" "$tmp" 2>/dev/null </dev/null); rc=$?
[ "$rc" = "0" ] && [ "$out" = " 42  42 " ] || fail "stores before an ERR: rc=$rc" "$out"

# --- timeout: the core is dead for the session, later calls are the stub
printf '10 DEFUSR=&H7004:X=USR(0)\n' > "$tmp"
out=$(TRS80_Z80="$core" TRS80_Z80_TIMEOUT=300 "$here/basic" "$tmp" 2>&1 </dev/null); rc=$?
want='USR CORE: no reply within 300 ms; the core is dead for this session, USR is the stub
?FC ERROR IN 10'
[ "$rc" = "1" ] && [ "$out" = "$want" ] || fail "timeout path: rc=$rc" "$out"
printf '10 ON ERROR GOTO 30\n20 DEFUSR=&H7004:X=USR(0)\n30 DEFUSR=&H7003:PRINT USR(4)\n' > "$tmp"
out=$(TRS80_Z80="$core" TRS80_Z80_TIMEOUT=300 "$here/basic" "$tmp" 2>&1 </dev/null); rc=$?
want='USR CORE: no reply within 300 ms; the core is dead for this session, USR is the stub
 4 
USR STUB: 1 CALL NOT EXECUTED (7003H x1): no Z80 core, each returned its argument; TRS80_USR=strict raises ?FC instead'
[ "$rc" = "0" ] && [ "$out" = "$want" ] || fail "stub after timeout: rc=$rc" "$out"

# --- a core that EXITS between calls is met on the next write.  That write
# used to be a gawk fatal (exit 2, the program lost, a terminal left raw);
# it is the timeout's ending now: one notice, ?FC at the call, the stub
# afterwards, and nothing from gawk itself on stderr.  Always the reference
# stub: dying on request is its feature, not a real core's.
stub="python3 $here/programs/tests/z80_stub.py"
printf '10 ON ERROR GOTO 40\n20 DEFUSR=&H7003:PRINT USR(4)\n30 FOR I=1 TO 300:NEXT:PRINT USR(5)\n40 PRINT "HANDLER";ERR/2+1;ERL;USR(6)\n' > "$tmp"
out=$(TRS80_Z80="$stub" Z80_STUB_DIE_AFTER=1 "$here/basic" "$tmp" 2>&1 </dev/null); rc=$?
want=' 8 
USR CORE: the core has exited; it is dead for this session, USR is the stub
HANDLER 5  30  6 
USR STUB: 1 CALL NOT EXECUTED (7003H x1): no Z80 core, each returned its argument; TRS80_USR=strict raises ?FC instead'
[ "$rc" = "0" ] && [ "$out" = "$want" ] || fail "core exited between calls: rc=$rc" "$out"
# the same death met on the READ (the write got through, the answer is an end
# of file): which of the two a host gives depends on its pipes, so both are
# pinned, with the same ending -- never "no reply within N ms", the core is
# not slow, it is gone
out=$(TRS80_Z80="$stub" Z80_STUB_DIE_ON_CALL=2 "$here/basic" "$tmp" 2>&1 </dev/null); rc=$?
[ "$rc" = "0" ] && [ "$out" = "$want" ] || fail "core exited, met on the read: rc=$rc" "$out"
printf '10 DEFUSR=&H7003:PRINT USR(4)\n20 FOR I=1 TO 300:NEXT\n' > "$tmp"
out=$(TRS80_Z80="$stub" Z80_STUB_DIE_AFTER=1 "$here/basic" "$tmp" 2>&1 </dev/null); rc=$?
[ "$rc" = "0" ] && [ "$out" = " 8 " ] || fail "BYE to a core that has exited: rc=$rc" "$out"

# --- a core that answers NEED to a FULL frame is a protocol violation, not
# a request: NEED means "I did not see frame gen-1", and a full frame IS
# gen 1.  The retry loop took it as one and resent for ever, so a stuck
# core hung the interpreter with no message and no way out (the 2026-09-19
# audit, L-47).  It now ends like any other bad line.  `timeout` is the
# check: before the fix this never returns.
printf '10 DEFUSR=&H7000:PRINT "R=";USR(5)\n20 PRINT "AFTER"\n' > "$tmp"
out=$(TRS80_Z80="$stub" Z80_STUB_ALWAYS_NEED=1 timeout 20 "$here/basic" "$tmp" 2>&1 </dev/null); rc=$?
[ "$rc" != "124" ] || fail "a core stuck on NEED hung the interpreter" "(timed out)"
case $out in
  *"'NEED' answered a full frame"*"?FC ERROR IN 10"*) ;;
  *) fail "NEED to a full frame" "$out" ;;
esac

# --- a routine that ends by jumping to READY (JP 1A19H) ends the PROGRAM:
# `ready=1` on the RET line.  The statement after the call must not run, the
# write-set is still applied, and it is not an error (the 2026-09-19 audit,
# L-44: the call was taken for an ordinary return and the program went on).
# Entry 7002 on purpose: its RET is followed by a write-set, and the field has
# to be read before those W lines replace the RET line.
printf '10 DEFUSR=&H7002:X=USR(30000):PRINT "SAME LINE"\n20 PRINT "AFTER"\n' > "$tmp"
out=$(printf '\nLOAD "%s"\nRUN\nPRINT "B=";PEEK(30001)\n' "$tmp" | TRS80_DUMB=1 TRS80_Z80="$stub" Z80_STUB_READY=1 "$here/basic" 2>&1)
case $out in *"SAME LINE"*|*AFTER*) fail "ready=1: the program ran on past the call" "$out" ;; esac
case $out in *"B= 66"*) ;; *) fail "ready=1: the write-set was not applied" "$out" ;; esac
out=$(TRS80_Z80="$stub" "$here/basic" "$tmp" 2>&1 </dev/null)
case $out in *AFTER*) ;; *) fail "a plain RET: the program did not run on" "$out" ;; esac

# --- building the frame never reads the keyboard: a byte POKEd at 3800-38FFH
# sits in MEM[], and reading that address back for the frame took a line of
# stdin (at a terminal, a keystroke) away from the program.  The core asks
# for the matrix with K; the frame does not carry it.
printf '10 POKE 14400,1:DEFUSR=&H7003:X=USR(4):LINE INPUT A$:PRINT X;"GOT ";A$\n' > "$tmp"
out=$(printf 'HELLO\n' | TRS80_Z80="$stub" "$here/basic" "$tmp" 2>&1)
want="HELLO
 8 GOT HELLO"
[ "$out" = "$want" ] || fail "the frame read the keyboard" "$out"

# --- fallbacks: a command that will not start, and a protocol mismatch
printf '10 DEFUSR=&H7003:PRINT USR(4)\n' > "$tmp"
out=$(TRS80_Z80="/nonexistent/z80core" "$here/basic" "$tmp" 2>&1 </dev/null | grep -v 'not found\|No such file'); rc=$?
want="USR CORE: cannot start '/nonexistent/z80core'; USR is the stub for this session
 4 
USR STUB: 1 CALL NOT EXECUTED (7003H x1): no Z80 core, each returned its argument; TRS80_USR=strict raises ?FC instead"
[ "$out" = "$want" ] || fail "cannot-start fallback" "$out"
out=$(TRS80_Z80="$core" Z80_STUB_PROTO=2 "$here/basic" "$tmp" 2>&1 </dev/null)
want="USR CORE: '$core' speaks protocol 2, this interpreter speaks 1; USR is the stub for this session
 4 
USR STUB: 1 CALL NOT EXECUTED (7003H x1): no Z80 core, each returned its argument; TRS80_USR=strict raises ?FC instead"
[ "$out" = "$want" ] || fail "protocol mismatch fallback" "$out"
out=$(TRS80_Z80="" "$here/basic" "$tmp" 2>&1 </dev/null)   # empty: no core, even one beside the checkout
want=' 4 
USR STUB: 1 CALL NOT EXECUTED (7003H x1): no Z80 core, each returned its argument; TRS80_USR=strict raises ?FC instead'
[ "$out" = "$want" ] || fail "no TRS80_Z80: byte-identical stub" "$out"

rm -f "$tmp" "$tmp.err"
echo "Z80 FIXTURE OK"
