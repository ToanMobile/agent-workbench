"""tests/lib/cpu_probe.py — CPU time của một phép tính trong tiến trình, đo ở tiến trình con fork (#1010, INSTINCT-069).

Giới hạn đồng hồ tường cho việc thuần CPU (regex trên dòng 1 MB) phình theo tải máy: ca c của test_fail_line_prefixed.sh tốn
0,09–0,12 s CPU (đo 05/11 ở load 23–57) nhưng đo 5,03 s tường ở load 70 và làm đỏ oan merge gate #1007.
CPU của tiến trình con (rusage của os.wait4, user + sys) là đúng chi phí của phép tính, tải bao nhiêu cũng vậy.
Việc đơn luồng có CPU <= tường, nên ngưỡng tính bằng giây CPU chỉ bỏ phần thời gian chờ do tải máy (đúng mục đích); với chính
phép tính nó chặt như ngưỡng tường lúc máy rảnh (khi không tranh CPU thì CPU ≈ tường), và regex thảm hoạ vẫn vượt nó (đột biến #1011).
Regex thảm hoạ không bao giờ trả về, và re.search chạy trong C nên signal.alarm không dừng được: tiến trình con có RLIMIT_CPU
(kernel giết nó khi quá giới hạn CPU, tải không làm chậm việc đó) và một chuông chặn treo rộng theo đồng hồ tường (chỉ cho tiến
trình con bị đói hoặc bị chặn; không bao giờ tính là đạt).

    cpu_of(fn, arg, limit_s) -> (cpu_s, why)   why None = chạy hết; cpu_s = inf khi tiến trình con bị giết hoặc ném lỗi.
"""
import os
import resource
import signal
import time


def cpu_of(fn, arg, limit_s, hang_s=60.0):
    pid = os.fork()
    if pid == 0:   # tiến trình con: không bao giờ quay lại mã của bên gọi
        code = 3
        try:
            soft = int(limit_s) + 1   # giây nguyên, trên ngưỡng: con tới ngưỡng vẫn được đo, quá ngưỡng thì bị giết (SIGXCPU)
            resource.setrlimit(resource.RLIMIT_CPU, (soft, soft + 1))
            fn(arg)
            code = 0
        finally:
            os._exit(code)
    end = time.monotonic() + hang_s
    while True:
        got, status, ru = os.wait4(pid, os.WNOHANG)
        if got:
            break
        if time.monotonic() > end:
            os.kill(pid, signal.SIGKILL)
            os.wait4(pid, 0)
            return float("inf"), "no result after %g s of wall time (hang bell)" % hang_s
        time.sleep(0.005)
    cpu = ru.ru_utime + ru.ru_stime
    if os.WIFSIGNALED(status):
        return float("inf"), "killed by signal %d after %.2f s CPU (RLIMIT_CPU %d s)" % (os.WTERMSIG(status), cpu, int(limit_s) + 1)
    if os.WEXITSTATUS(status):
        return float("inf"), "the probe raised (exit %d)" % os.WEXITSTATUS(status)
    return cpu, None


def worst_cpu(fn, args, limit_s):
    """(CPU lớn nhất qua các args tính bằng giây, lý do của lần đo đó hoặc None)."""
    worst, why = 0.0, None
    for a in args:
        cpu, w = cpu_of(fn, a, limit_s)
        if cpu >= worst:
            worst, why = cpu, w
    return worst, why
