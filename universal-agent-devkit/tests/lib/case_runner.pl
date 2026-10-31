#!/usr/bin/perl
# tests/lib/case_runner.pl — chốt hết giờ cho MỘT lời gọi hook của hooks/tests/hook_contract_test.sh (#685).
#   case_runner.pl BELL_S CPU_FILE BELLS_FILE -- lệnh [đối số…]
# Chạy lệnh trong process group riêng; stdout và stderr của con ghi ra HAI file tạm (không phải pipe của `$(...)`, nên một cháu còn
# sống không giữ được pipe và treo người gọi); khi con thoát hoặc hết giờ, bơm file stdout về fd 1 và file stderr về fd 2 của chính nó.
#   hết BELL_S giây: TERM rồi KILL cả nhóm, ghi một dòng vào BELLS_FILE, exit 142 (hook không trả lời: không bao giờ PASS);
#   con thoát mã khác 0: cộng CPU các tiến trình cháu còn sống trong nhóm (`ps -g`; Darwin mất CPU của cháu chưa wait() khi hook
#   gọi os._exit) vào CPU của con, rồi giết cả nhóm; con thoát 0: không động tới nhóm.
# CPU (mili-giây, cây tiến trình của hook) ghi vào CPU_FILE. Chỉ dùng I/O nội tại của perl (không cat/rm) và /bin/ps tuyệt đối: chạy được
# dưới PATH rỗng của ca K-4 (PATH="${NOJQ_BIN}" chỉ có bash và cat). Exit = exit của con (128+sig khi bị tín hiệu).
use strict;
use warnings;

my ($bell, $cpu_file, $bells_file) = splice(@ARGV, 0, 3);
shift @ARGV if @ARGV && $ARGV[0] eq '--';
die "case_runner.pl: thiếu lệnh\n" unless @ARGV && defined $bells_file;
$bell = 30 unless $bell && $bell =~ /^\d+(?:\.\d+)?$/ && $bell > 0;

my $dir = $cpu_file;
$dir =~ s{/[^/]*\z}{} or $dir = '.';
my $so = "$dir/.o.$$";
my $se = "$dir/.e.$$";

my $pid = fork();
die "case_runner.pl: fork: $!\n" unless defined $pid;
if (!$pid) {
    setpgrp(0, 0);
    open(STDOUT, '>', $so) or exit 127;
    open(STDERR, '>', $se) or exit 127;
    { no warnings 'exec'; exec { $ARGV[0] } @ARGV; }
    print STDERR "case_runner.pl: không chạy được $ARGV[0]: $!\n";
    exit 127;
}
setpgrp($pid, $pid);   # chạy đua với setpgrp của con: hai bên cùng đặt một giá trị

my $timed_out = 0;
$SIG{ALRM} = sub {
    $timed_out = 1;
    kill 'TERM', -$pid;
    select(undef, undef, undef, 0.3);
    kill 'KILL', -$pid;
};
# alarm nguyên giây (perl không hỗ trợ lẻ nếu thiếu Time::HiRes); Time::HiRes là lõi của perl 5.8+
my $have_hires = eval { require Time::HiRes; 1 };
if ($have_hires) { Time::HiRes::alarm($bell); } else { alarm(int($bell + 0.999)); }

my $status = -1;
while (1) {
    my $r = waitpid($pid, 0);
    if ($r == $pid) { $status = $?; last; }
    last if $r == -1 && !$!{EINTR};
}
if ($have_hires) { Time::HiRes::alarm(0); } else { alarm(0); }

my $rc;
if ($timed_out) { $rc = 142; }
elsif ($status == -1) { $rc = 127; }
elsif ($status & 127) { $rc = 128 + ($status & 127); }
else { $rc = $status >> 8; }

my @t = times();
my $cpu_ms = int(($t[2] + $t[3]) * 1000);

if (!$timed_out && $rc != 0) {
    # cháu chưa wait() vẫn nằm trong nhóm: đọc CPU của chúng trước khi giết
    if (open(my $ps, '-|', '/bin/ps', '-o', 'cputime=', '-g', $pid)) {
        while (my $l = <$ps>) {
            $l =~ s/\s+//g;
            my @p = split /:/, $l;
            next unless @p && !grep { !/^\d+(?:\.\d+)?$/ } @p;
            my $s = 0;
            $s = $s * 60 + $_ for @p;
            $cpu_ms += int($s * 1000);
        }
        close($ps);
    }
}
if ($timed_out || $rc != 0) {
    kill 'TERM', -$pid;
    select(undef, undef, undef, 0.1);
    kill 'KILL', -$pid;
}

if (open(my $cf, '>', $cpu_file)) { print $cf "$cpu_ms\n"; close($cf); }
if ($timed_out && open(my $bf, '>>', $bells_file)) { print $bf "bell\n"; close($bf); }

for my $pair ([$so, \*STDOUT], [$se, \*STDERR]) {
    my ($file, $fh) = @$pair;
    if (open(my $in, '<', $file)) {
        binmode($in);
        binmode($fh);
        local $/ = \65536;
        while (defined(my $chunk = <$in>)) { print {$fh} $chunk; }
        close($in);
    }
    unlink $file;
}
exit $rc;
