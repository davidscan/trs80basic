# bound.pl N CMD... -- run CMD in its own process group; after N seconds
# kill the whole group and exit 124.  A test whose only failure is a hang
# (a core never killed, a close that waits for ever) then fails instead of
# holding the suite, and no orphan keeps a $(...) or a log open (the
# 2026-09-30 audit, BM-12).  Otherwise CMD's exit status, or 128+signal.
#   VAR=x perl programs/tests/bound.pl 30 ./basic prog.bas
my $n = shift;
my $p = fork;
defined $p or die "bound.pl: fork: $!\n";
if (!$p) { setpgrp(0, 0); exec @ARGV or exit 127 }
$SIG{ALRM} = sub { kill 'KILL', -$p; print STDERR "BOUNDED: killed after ${n}s: @ARGV\n"; exit 124 };
alarm $n;
waitpid($p, 0);
alarm 0;
exit($? & 127 ? 128 + ($? & 127) : $? >> 8);
