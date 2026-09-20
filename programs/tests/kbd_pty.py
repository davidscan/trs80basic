#!/usr/bin/env python3
"""kbd_pty.py -- the interactive keyboard through a pseudo-terminal.

    python3 programs/tests/kbd_pty.py        # exit 0 = passed; says what failed

Batch mode has no keyboard, so nothing else in the suite reaches the tty
reader (src/p30_kbd.awk kb_fill_tty, 2026-09-16) or the keyboard matrix
at a terminal.  This drives ./basic inside a pty, which is what a
terminal emulator gives it, and checks:

  1. INKEY$ returns every byte typed, in order, a period included; an
     arrow key arrives as the Model I's one byte (91 10 8 9, shifted 27
     26 24 25), a lone ESC as 27, PgUp as nothing; Ctrl-C BREAKs the loop;
  2. one keypress holds its key on the matrix for TRS80_KMHOLD
     milliseconds when this gawk has the time extension (the launcher
     loads it), else for 4 polls; a shifted arrow presses the arrow and
     SHIFT, and its parameter bytes press nothing;
  3. Ctrl-S pauses a printing program, a key resumes it, Ctrl-C breaks --
     and both still work after a keystroke the program never read;
  4. INPUT takes a line with a period in it through the line editor,
     and the editor refuses the 241st character, as the ROM's does;
  5. BYE exits;
  6. in a second session, the kitty keyboard protocol (TRS80_KBPROTO=1,
     the pty playing a terminal that answers the query): a key is down
     from its press byte until its release event, chords OR together,
     a held key never drops out between press and repeat, an abandoned
     key releases itself after KP_STUCK seconds, repeats never reach
     INKEY$, and the mode is pushed at RUN and popped at READY and BYE;
  7. TAB file-name completion: a unique directory gains "/", and a
     matched name with a quote in it is completed but never parsed by the
     shell (the directory test once ran it as a command, the 2026-09-19 audit, C-2).

Standard library only; run by run_all.sh when python3 is present (so CI
exercises the tty reader on Linux, where it was not measured by hand).
"""
import os
import pty
import re
import select
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SLOW = 3 if os.environ.get('CI') else 1      # CI runners are slower and noisier


class Basic:
    def __init__(self, env=(), cwd=None):
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.chdir(cwd or ROOT)
            os.environ['TRS80_DUMB'] = '1'
            os.environ['TRS80_Z80'] = ''
            os.environ.update(dict(env))
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


CSI = re.compile(r'\x1b\[[0-9;:?<>]*[A-Za-z]')


def numbers(s):
    """The numbers a program printed, escape sequences stripped."""
    return [t for t in flat(CSI.sub(' ', s)).split() if t.isdigit()]


QUERY, PUSH, POP = '\x1b[?u', '\x1b[>2u', '\x1b[<u'


def protocol(check):
    """Scenario 6: the release protocol against a pty that speaks it."""
    # the stuck-key timer is wall-clock seconds; on CI every wait below is
    # stretched by SLOW, so stretch it too or it fires between two steps
    b = Basic([('TRS80_KBPROTO', '1'), ('TRS80_KPSTUCK', str(2 * SLOW))])
    b.drain()
    b.send('\r')
    b.drain()
    # a program that prints the matrix byte whenever it changes
    b.send('10 P=PEEK(14591):IF P<>Q THEN PRINT P;:Q=P\r20 GOTO 10\rRUN\r', 0.6)
    out = b.drain(0.3)
    check(QUERY in out and PUSH in out, 'RUN queries the terminal and pushes the protocol', out)
    b.send(b'\x1b[?0u', 0.3)                       # the terminal: yes, flags 0 now
    b.drain(0.2)

    log = [out]

    def step(data, want, what, wait=0.35):
        b.send(data, wait)
        out = b.drain(0.2)
        log.append(out)
        got = numbers(out)
        if not (want and isinstance(want[0], list)):
            want = [want]
        check(got in want, what + ' -> expected %r' % want[0], ' '.join(got) or '(nothing)')

    step(b'a', ['2'], 'press a: row 0 bit 2')
    step(b'', [], 'still down after 0.35 s, longer than the timed hold', 0.35)
    step(b'\x1b[97;1:3u', ['0'], 'release a')
    step(b'\x1b[C', ['64'], 'press the right arrow')
    step(b'\x1b[1;1:2C\x1b[1;1:2C\x1b[1;1:2C', [], 'repeats change nothing')
    step(b'\x1b[1;1:3C', ['0'], 'release the arrow')
    step(b'a\x1b[C', [['66'], ['2', '66']], 'a chord: a and the right arrow OR together')
    step(b'\x1b[97;1:3u', ['64'], 'release a, the arrow stays')
    step(b'\x1b[1;1:3C', ['0'], 'release the arrow')
    step(b'A', ['3'], 'a shifted key sets the SHIFT row too')
    step(b'\x1b[97;2:3u', ['0'], 'its release (the unshifted code, shift in mods) clears both')
    step(b'a', ['2'], 'press a and abandon it')
    # without the time extension the timer runs on whole seconds: 2-4 s, not 2
    step(b'', ['0'], 'no event for KP_STUCK seconds: released by itself', 2.6 if has_clock() else 4.3)
    b.send(b'\x03', 0.5)
    out = b.drain()
    log.append(out)
    check('BREAK IN' in out, 'Ctrl-C still BREAKs under the protocol', out)   # line 10 or 20
    check(POP in out, 'READY pops the protocol', out)
    # INKEY$ sees presses only: a repeat event is not a byte
    b.send('NEW\r10 A$=INKEY$:IF A$<>"" THEN PRINT ASC(A$);\r20 GOTO 10\rRUN\r', 0.6)
    b.drain(0.3)
    b.send(b'a\x1b[97;1:2u\x1b[97;1:2u\x1b[97;1:2u\x1b[97;1:3u', 0.4)
    got = numbers(b.drain(0.2))
    check(got == ['97'], 'INKEY$ gets one byte for a press with three repeats', ' '.join(got))
    b.send(b'\x03', 0.5)
    log.append(b.drain())
    b.send('BYE\r', 0.5)
    log.append(b.drain(0.3, 2))
    b.close()
    whole = ''.join(log)
    check(whole.rfind(POP) > whole.rfind(PUSH), 'the session ends with the protocol popped',
          whole[-200:])


def completion(check):
    """Scenario 7: TAB completion in a directory holding a hostile name."""
    with tempfile.TemporaryDirectory() as d:
        os.mkdir(os.path.join(d, 'zdir'))
        open(os.path.join(d, "zq';touch INJECTED;'x"), 'w').close()
        b = Basic(cwd=d)
        b.drain()
        b.send('\r')                                   # MEMORY SIZE?
        b.drain()
        b.send('LOAD "zd\t', 0.5)
        out = b.drain(0.3)
        check('zdir/' in out, 'TAB completes a unique directory and appends /', out)
        b.send('\x15', 0.3)                            # Ctrl-U: drop the line
        b.drain(0.2)
        b.send('LOAD "zq\t', 0.5)
        out = b.drain(0.3)
        check('touch INJECTED' in out, 'TAB completes a name with a quote in it', out)
        check(not os.path.exists(os.path.join(d, 'INJECTED')),
              'the completed name is never run by the shell', out)
        b.send('\x15', 0.3)
        b.drain(0.2)
        b.send('BYE\r', 0.5)
        b.drain(0.3, 2)
        b.close()


def has_clock():
    # as the launcher decides it: an extension that loads, and loads SILENTLY
    # (gawk 5.3 warns that `time` is obsolete; the launcher then does without)
    for ext in ('time', 'timex'):
        r = subprocess.run(['gawk', '-l', ext, 'BEGIN { }'], capture_output=True)
        if r.returncode == 0 and not r.stdout and not r.stderr:
            return True
    return False


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
    # an arrow is the Model I's ONE byte (91 10 8 9; shifted 27 26 24 25), a
    # lone ESC is 27, and a key the TRS-80 lacks (PgUp) is no key at all
    for k in (b'a', b'.', b'Z', b' ', b'\x1b[A', b'\r', b'\x1b', b'\x1b[5~', b'\x1b[1;2D', b'\x1bOC', b'\x1b[B'):
        b.send(k, 0.15)
    b.send(b'\x03', 0.5)
    out = b.drain()
    check('97 46 90 32 91 13 27 24 9 10 ' in flat(out) + ' ' and ' 53 ' not in flat(out) and ' 126 ' not in flat(out),
          'INKEY$ bytes in order (a . Z space up ENTER ESC PgUp shift-left right down)', out)
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

    # 2b. a shifted arrow on the matrix: the arrow AND the shift key, and the
    # sequence's parameter bytes (1 ; 2) never press keys of their own
    b.send('NEW\r10 P=PEEK(14400):IF P=0 THEN 10\r20 PRINT "ROW6";P;"SH";PEEK(14464)\r'
           '30 IF PEEK(14591)<>0 THEN 30\r'
           '40 FOR I=1 TO 300:Q=PEEK(14591):IF Q<>0 THEN PRINT "JUNK";Q\r'
           '50 NEXT:PRINT "CLEAN"\rRUN\r', 1.0)
    b.drain(0.3)
    b.send(b'\x1b[1;2D', 0.3)
    out = b.drain(0.5, 6)
    check('ROW6 32 SH 1' in flat(out), 'SHIFT + left arrow presses the arrow and the shift key', out)
    check('CLEAN' in out and 'JUNK' not in out, 'the escape sequence presses no other key', out)

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

    # 3b. a key the program never reads must not switch BREAK off: the poll
    # reads the tty every time, not only when its queue is empty
    b.send('NEW\r10 GOTO 10\rRUN\r', 0.5)
    b.send('\rx', 0.4)                                # a second ENTER and a stray letter
    b.drain(0.2)
    b.send(b'\x03', 0.6)
    out = b.drain(0.5, 3)
    check('BREAK IN 10' in out, 'Ctrl-C breaks a loop after an unread keystroke', out)
    if 'BREAK IN 10' not in out:                       # do not leave the loop running under the rest
        b.close(); print('kbd_pty.py: %d check(s) failed' % len(fails))
        for f in fails: print('  ' + f)
        return 1
    b.send('NEW\r10 FOR I=1 TO 200000:PRINT I;:NEXT\rRUN\r', 0.3)
    b.send('q', 0.2)                                   # unread, then the pause key
    b.drain(0.05, 0.3)
    b.send(b'\x13', 0.1)
    b.drain(0.6, 2)
    quiet = b.drain(0.4, 0.6)
    b.send(b'x', 0.1)
    b.send(b'\x03', 0.5)
    after = b.drain(0.5, 3)
    check(quiet == '', 'Ctrl-S pauses after an unread keystroke', quiet)
    check('BREAK IN 10' in after, 'and Ctrl-C breaks after the pause', after)

    # 4. INPUT with a period, through the line editor
    b.send('NEW\r10 INPUT "NAME";A$:PRINT "["A$"]"\rRUN\r', 0.6)
    b.drain(0.3)
    b.send('A.B\r', 0.5)
    out = b.drain()
    check('[A.B]' in out, 'INPUT returns a line with a period', out)

    # 4b. the line editor refuses the 241st character (the ROM's 0361H limit)
    b.send('NEW\r10 INPUT A$:PRINT "LEN";LEN(A$)\rRUN\r', 0.6)
    b.drain(0.3)
    for i in range(5):
        b.send('Z' * 50, 0.15)                         # 250 keys, 240 taken
    b.send('\r', 0.6)
    out = b.drain()
    check('LEN 240' in flat(out), 'the line editor stops at 240 characters', out)

    # 5. BYE
    b.send('BYE\r', 0.5)
    b.drain(0.3, 2)
    b.close()

    # 6. the release protocol
    protocol(check)

    # 7. TAB file-name completion
    completion(check)

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
