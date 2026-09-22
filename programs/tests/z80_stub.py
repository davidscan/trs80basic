#!/usr/bin/env python3
"""z80_stub.py -- the reference implementation of PROTOCOL.md on the core's
side, with canned behaviour per entry address instead of a Z80.

It stands in for ../trs80_z80_core so the interpreter's shim (src/p77_z80.awk)
can be built and tested here, the way the OLLAMA channel was built against
ollama_stub.sh.  A real core is conformant when programs/tests/z80.sh passes
with TRS80_Z80 pointing at it and these entries implemented as machine code.

Entries (hex):
  7000  paint "HI" at the top-left of the screen (V), one tick, RET
  7001  read the whole keyboard matrix (K 255), echo the byte at 3C40H, HL=byte
  7002  store "ABC" at address ARG via the write-set
  7003  HL = 2*ARG, result=1 (the 0A9AH path)
  7004  hang (never answers) -- the timeout path
  7005  HL = the core's byte at address ARG (what the frame delivered)
  7006  ERR rom -- called into ROM space
  7007  a sustained routine: 20 ticks, stops early on BREAK
  7008  forget everything: the NEXT call is answered with NEED full
  7009  push 1234H at SP-2/SP-1 -- the stack lands in the write-set
  700A  a video byte AND a write-set byte in one call
  700B  OUT (FFH) bit 3 set: 32-column mode (MODE 1)
  700C  OUT (FFH) bit 3 clear: 64-column mode (MODE 0)
  700D  32-column, then CLS (CALL 01C9H) restores 64-column and clears
        bit 3 of 403DH (16445), the ROM's print flag, in the write-set
  700E  store 42 at address ARG, then call into ROM space: the store is
        sent as a W line AHEAD of the ERR rom, and stays in the stub's memory
  anything else: an immediate RET (hl=0, result=0, no writes)

Z80_STUB_PROTO=<n> makes the stub claim another protocol version.
Z80_STUB_DIE_AFTER=<n> makes it exit right after its n-th RET: a core that
dies BETWEEN calls, which the interpreter meets on its next write.
Z80_STUB_DIE_ON_CALL=<n> makes it exit when it has READ its n-th CALL frame,
without answering: the interpreter's write succeeds and its read meets the
end of file (the order a Linux pipe usually gives the case above).
Z80_STUB_READY=1 ends every call with `ready=1` on its RET line: the
routine jumped to the ROM's READY entry (1A19H) instead of returning, and
the BASIC program that called it is over (the 2026-09-19 audit, L-44).
Z80_STUB_ALWAYS_NEED=1 answers EVERY frame with NEED full, a full one
included.  That is a protocol violation -- NEED means "I did not see frame
gen-1", and a full frame IS gen 1 -- and it used to spin the interpreter
for ever (the 2026-09-19 audit, L-47).
"""
import os
import sys
import time

PROTO = os.environ.get("Z80_STUB_PROTO", "1")
DIE_AFTER = int(os.environ.get("Z80_STUB_DIE_AFTER", "0"))
DIE_ON_CALL = int(os.environ.get("Z80_STUB_DIE_ON_CALL", "0"))
ALWAYS_NEED = os.environ.get("Z80_STUB_ALWAYS_NEED", "") not in ("", "0")
READY = os.environ.get("Z80_STUB_READY", "") not in ("", "0")
rets = 0
calls = 0
mem = {}
gen = 0


def send(s):
    sys.stdout.write(s + "\n")
    sys.stdout.flush()


def recv():
    line = sys.stdin.readline()
    if not line:
        sys.exit(0)
    return line.rstrip("\r\n")


def fields(line):
    return dict(kv.split("=", 1) for kv in line.split()[1:] if "=" in kv)


def apply_run(run):
    addr, bs = run.split(":", 1)
    a = int(addr)
    for i, b in enumerate(bs.split(",")):
        mem[a + i] = int(b)


def ret(hl=0, result=0, cycles=100, brk=0, writes=()):
    send("RET hl=%d result=%d cycles=%d break=%d writes=%d%s"
         % (hl & 0xFFFF, result, cycles, brk, len(writes),
            " ready=1" if READY else ""))
    for w in writes:
        send("W " + w)
    global rets
    rets += 1
    if rets == DIE_AFTER:
        sys.exit(0)


def tick(cycles=1000):
    send("T %d" % cycles)
    return recv() == "BREAK"


def main():
    global gen
    hello = recv()
    if not hello.startswith("HELLO "):
        send("ERR bad expected HELLO")
        return
    send("Z80 proto=%s name=z80_stub pid=%d" % (PROTO, os.getpid()))
    while True:
        line = recv()
        if line == "BYE":
            return
        if not line.startswith("CALL "):
            send("ERR bad expected CALL")
            continue
        h = fields(line)
        runs = []
        while True:
            l = recv()
            if l == "GO":
                break
            if l.startswith("M "):
                runs.append(l[2:])
        global calls
        calls += 1
        if calls == DIE_ON_CALL:
            sys.exit(0)
        g = int(h["gen"])
        full = h["full"] == "1"
        if ALWAYS_NEED:
            send("NEED full")
            continue
        if not full and g != gen + 1:
            send("NEED full")
            continue
        if full:
            mem.clear()
        gen = g
        for r in runs:
            apply_run(r)
        entry = int(h["entry"])
        arg = int(float(h["arg"]) // 1)      # 0A7FH is the ROM's CINT: floor
        sp = int(h["sp"])
        # the entries that take the argument through 0A7FH (7002, 7003,
        # 7005): outside -32768..32767 the ROM exits ?OV, sent as `ERR ov`
        if entry in (0x7002, 0x7003, 0x7005) and not -32768 <= arg <= 32767:
            send("ERR ov USR argument %s is outside -32768..32767 at 0A7FH" % h["arg"])
            continue

        if entry == 0x7000:
            send("V 15360:72,73")
            tick()
            ret()
        elif entry == 0x7001:
            send("K 255")
            k = recv()
            v = int(k.split()[1]) if k.startswith("K ") else 0
            send("V 15424:%d" % v)
            ret(hl=v, result=1)
        elif entry == 0x7002:
            ret(writes=["%d:65,66,67" % (arg & 0xFFFF)])
        elif entry == 0x7003:
            ret(hl=(2 * arg) & 0xFFFF, result=1)
        elif entry == 0x7004:
            time.sleep(30)
            ret()
        elif entry == 0x7005:
            ret(hl=mem.get(arg & 0xFFFF, 255), result=1)
        elif entry == 0x7006:
            send("ERR rom called 0000H, no ROM here")
        elif entry == 0x7007:
            brk = 0
            for _ in range(20):
                if tick(5000):
                    brk = 1
                    break
            ret(cycles=100000, brk=brk)
        elif entry == 0x7008:
            gen = 0
            mem.clear()
            ret()
        elif entry == 0x7009:
            ret(writes=["%d:52,18" % (sp - 2)])
        elif entry == 0x700A:
            send("V 15400:65")
            ret(writes=["30000:1"])
        elif entry == 0x700B:
            send("MODE 1")            # OUT (FFH) with bit 3 set: 32-column
            ret()
        elif entry == 0x700C:
            send("MODE 0")            # OUT (FFH) with bit 3 clear: 64-column
            ret()
        elif entry == 0x700D:
            send("MODE 1")            # 32-column, then CLS restores 64-column
            send("MODE 0")            # and clears bit 3 of the ROM's port image
            ret(writes=["16445:%d" % (mem.get(16445, 0) & 0xF7)])
        elif entry == 0x700E:
            mem[arg & 0xFFFF] = 42    # the routine's store happened on this side
            send("W %d:42" % (arg & 0xFFFF))
            send("ERR rom called 0000H, no ROM here")
        else:
            ret()


if __name__ == "__main__":
    main()
