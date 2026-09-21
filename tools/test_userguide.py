#!/usr/bin/env python3
"""The guide generator reads support/manpages.txt the way the interpreter does.

There are two readers of that file: init_man (src/p10_head.awk), which the
`man` metacommand uses, and parse_manpages (make_userguide.py), which builds
the reference part of docs/USER_GUIDE.md.  They must agree, or the guide says
something `man` does not.  They did not: init_man skips a line beginning with
'#' as a comment in the file, parse_manpages kept it, and the metacommands
banner near the end of the file was tacked onto the body of whichever entry
came before it and printed in the guide (the 2026-09-19 audit, L-20).

    python3 -m unittest test_userguide        # from tools/
"""
import os
import re
import shutil
import subprocess
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_userguide as mug                                   # noqa: E402


class TestManpageReading(unittest.TestCase):
    def test_no_body_line_is_a_file_comment(self):
        """A '#' line belongs to the file, so no entry may carry one."""
        for header, body in mug.parse_manpages():
            for line in body:
                self.assertFalse(
                    line.startswith("#"),
                    "%s carries the file comment %r" % (" ".join(header), line))

    def test_the_two_readers_agree_on_every_body(self):
        """What `man K` prints is what the generator files under K."""
        awk = mug.ROOT / "trs80basic.awk"
        if not awk.exists():
            raise AssertionError("trs80basic.awk is not built: cat src/p*.awk")
        if not shutil.which("gawk"):
            raise AssertionError("gawk is required")
        bodies = {}
        for header, body in mug.parse_manpages():
            bodies[header[0]] = body
        keys = sorted(bodies)
        env = dict(os.environ, TRS80_DUMB="1", TRS80_Z80="",
                   TRS80_MANFILE=str(mug.MANPAGES))
        script = "\n" + "".join("man %s\n" % k for k in keys)
        p = subprocess.run(["gawk", "-b", "-f", str(awk)], input=script,
                           capture_output=True, text=True, env=env)
        # each answer runs from the echoed ">man K" to the next "READY"
        blocks = dict(re.findall(r"^>man (\S+)\n(.*?)^READY$",
                                 p.stdout, re.S | re.M))
        self.assertEqual(sorted(blocks), keys, "man answered for a different set")
        for k in keys:
            shown = blocks[k].split("\n")
            while shown and not shown[-1].strip():
                shown.pop()
            self.assertEqual(shown, bodies[k],
                             "man %s and the guide disagree" % k)

    def test_the_guide_is_current(self):
        """docs/USER_GUIDE.md matches what the generator would write."""
        guide = mug.GUIDE.read_text()
        span = re.search(re.escape(mug.BEGIN) + r".*?" + re.escape(mug.END),
                         guide, re.S)
        self.assertIsNotNone(span, "the generated-reference markers are gone")
        self.assertEqual(span.group(0), mug.generate(),
                         "stale: run python3 tools/make_userguide.py")


if __name__ == "__main__":
    unittest.main()
