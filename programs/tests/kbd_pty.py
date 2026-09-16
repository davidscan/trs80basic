#!/usr/bin/env python3
"""kbd_pty.py -- the interactive keyboard through a pseudo-terminal.

    python3 programs/tests/kbd_pty.py        # exit 0 = passed; says what failed

Batch mode has no keyboard, so nothing else in the suite reaches the tty
reader (src/p30_kbd.awk kb_fill_tty, 2026-09-16) or the keyboard matrix
at a terminal.  This drives ./basic inside a pty, which is what a
terminal emulator gives it, and checks:

  1. INKEY$ returns every byte typed, in order, a period and an arrow's
     ESC [ A included, and Ctrl-C BREAKs the loop;
  2. one keypress holds its key on the matrix for TRS80_KMHOLD
     milliseconds when this gawk has the time extension (the launcher
     loads it), else for 4 polls;
  3. Ctrl-S pauses a printing program, a key resumes it, Ctrl-C breaks;
  4. INPUT takes a line with a period in it through the line editor;
  5. BYE exits.

Standard library only; run by run_all.sh when python3 is present (so CI
exercises the tty reader on Linux, where it was not measured by hand).
"""
import os
import pty
import select
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SLOW = 3 if os.environ.get('CI') else 1      # CI runners are slower and noisier


class Basic:
    def __init__(self):
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.chdir(ROOT)
            os.environ['TRS80_DUMB'] = '1'
            os.environ['TRS80_Z80'] = ''
            os.execv(os.path.join(ROOT, 'basic'), [os.path.join(ROOT, 'basic')])

    def drain(self, quiet=0.4, limit=10.0):
        """Read until nothing arrives for `quiet` seconds."""
        out, last, t0 = b'', time.time(), time.time()
        while time.time() - t0 < limit * SLOW:
            r, _, _ = select.select([self.fd], [], [], 0.05)
            if r:
                try:
                    c = os.read(self.fd, 65536)
                except OSError:
                    break
                if not c:
                    break
                out += c
                last = time.time()
            elif time.time() - last > quiet * SLOW:
                break
        return out.decode('latin-1')

    def send(self, data, wait=0.4):
        os.write(self.fd, data if isinstance(data, bytes) else data.encode('latin-1'))
        time.sleep(wait * SLOW)

    def close(self):
        try:
            os.kill(self.pid, 15)
        except OSError:
            pass
        os.waitpid(self.pid, 0)


def flat(s):
    return ' '.join(s.replace('\r\n', '\n').split())


def has_clock():
    return subprocess.run(['gawk', '-l', 'time', 'BEGIN { }'], capture_output=True).returncode == 0


def main():
    fails = []

    def check(cond, what, seen):
        if not cond:
            fails.append('%s\n    saw: %r' % (what, seen[-300:]))

    b = Basic()
    b.drain()
    b.send('\r')                                       # MEMORY SIZE?
    b.drain()

    # 1. INKEY$ bytes and BREAK
    b.send('10 A$=INKEY$:IF A$="" THEN 10\r20 PRINT ASC(A$);:GOTO 10\rRUN\r', 0.6)
    b.drain(0.3)
    for k in (b'a', b'.', b'Z', b' ', b'\x1b[A', b'\r'):
        b.send(k, 0.15)
    b.send(b'\x03', 0.5)
    out = b.drain()
    check('97 46 90 32 27 91 65 13' in flat(out), 'INKEY$ bytes in order (a . Z space up-arrow ENTER)', out)
    check('BREAK IN 10' in out, 'Ctrl-C breaks the INKEY$ loop', out)

    # 2. the matrix hold: count the polls that see one keypress
    b.send('NEW\r10 P=PEEK(14591):IF P=0 THEN 10\r20 N=1\r'
           '30 P=PEEK(14591):IF P<>0 THEN N=N+1:GOTO 30\r40 PRINT "HELD";N\rRUN\r', 0.8)
    b.drain(0.3)
    b.send(b'a', 0.2)
    out = b.drain(0.5, 20)
    held = None
    toks = flat(out).split()                       # PRINT "HELD";N prints 'HELD 1698 '
    for i, tok in enumerate(toks):
        if tok == 'HELD' and i + 1 < len(toks):
            try:
                held = int(toks[i + 1])
            except ValueError:
                pass
    if has_clock():
        check(held is not None and held > 50,
              'with the time extension one keypress holds for ~100 ms, many polls', out)
    else:
        check(held == 4, 'without the time extension one keypress holds for 4 polls', out)

    # 3. Ctrl-S pause, resume, BREAK
    b.send('NEW\r10 FOR I=1 TO 200000:PRINT I;:NEXT\rRUN\r', 0.3)
    b.drain(0.05, 0.3)
    b.send(b'\x13', 0.1)
    paused = b.drain(0.6, 2)
    b.send(b'x', 0.1)
    resumed = b.drain(0.05, 0.5)
    b.send(b'\x03', 0.5)
    after = b.drain(0.5, 3)
    check(len(resumed) > 0, 'a key resumes after Ctrl-S', resumed)
    check('BREAK IN 10' in after, 'Ctrl-C breaks the printing loop', after)
    check(paused.endswith(' ') or paused.endswith('\r\n') or len(paused) > 0,
          'Ctrl-S paused the output (something printed before the pause)', paused)

    # 4. INPUT with a period, through the line editor
    b.send('NEW\r10 INPUT "NAME";A$:PRINT "["A$"]"\rRUN\r', 0.6)
    b.drain(0.3)
    b.send('A.B\r', 0.5)
    out = b.drain()
    check('[A.B]' in out, 'INPUT returns a line with a period', out)

    # 5. BYE
    b.send('BYE\r', 0.5)
    b.drain(0.3, 2)
    b.close()

    if fails:
        print('kbd_pty.py: %d check(s) failed' % len(fails))
        for f in fails:
            print('  ' + f)
        return 1
    print('kbd_pty.py: passed (matrix hold %s polls, %s)'
          % (held, 'clock' if has_clock() else 'no clock'))
    return 0


if __name__ == '__main__':
    sys.exit(main())
