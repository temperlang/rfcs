# What a compiler-known result type might cost in Python, hand-written
# beside failbench's generated `bubble` and `null` runners. ns per item,
# min and median of 7 runs after warm-up. Arguments: n, rate in per mille,
# variant.
#
#   value  success as the plain value, failure as a Failed object
#          (checked with isinstance)
#
# Each has a depth-5 form passing the failure up four more functions.
import statistics, sys, time
import failbench as m
from temper_core import int_add, int_mul


class Bad:
    __slots__ = ("input",)
    def __init__(self, input): self.input = input


class Failed:
    __slots__ = ("error",)
    def __init__(self, error): self.error = error


# Written as the generated code is (its arithmetic helpers, its input_at,
# while loops), so only the failure handling differs from `null`.
input_at = m.input_at


def step_value(x):
    if x < 0:
        return Failed(Bad(x))
    return int_add(int_mul(x, 3), 1)


def v2(x):
    r = step_value(x)
    if isinstance(r, Failed):
        return r
    return int_add(r, 1)


def v3(x):
    r = v2(x)
    if isinstance(r, Failed):
        return r
    return int_add(r, 1)


def v4(x):
    r = v3(x)
    if isinstance(r, Failed):
        return r
    return int_add(r, 1)


def v5(x):
    r = v4(x)
    if isinstance(r, Failed):
        return r
    return int_add(r, 1)


def run_value(n, fail_mille):
    sum = 0
    i = 0
    while i < n:
        x = input_at(i, fail_mille)
        sum = int_add(sum, 0 if isinstance(r := step_value(x), Failed) else r)
        i = int_add(i, 1)
    return sum


def run_value5(n, fail_mille):
    sum = 0
    i = 0
    while i < n:
        x = input_at(i, fail_mille)
        sum = int_add(sum, 0 if isinstance(r := v5(x), Failed) else r)
        i = int_add(i, 1)
    return sum


N = int(sys.argv[1]) if len(sys.argv) > 1 else 50000
R = [("bubble", m.run_bubble), ("null", m.run_null), ("value", run_value),
     ("bubble5", m.run_bubble5), ("null5", m.run_null5), ("value5", run_value5)]
only = int(sys.argv[2]) if len(sys.argv) > 2 else -1
for pct in [0, 1, 10, 100]:
    if only >= 0 and pct != only: continue
    for name, f in R:
        if len(sys.argv) > 3 and sys.argv[3] != name: continue
        for _ in range(2): f(N, pct)
        ts = []
        for _ in range(7):
            t = time.perf_counter_ns(); f(N, pct); ts.append((time.perf_counter_ns() - t) / N)
        print(f"py {pct} {name} {min(ts):.1f} {statistics.median(ts):.1f}", flush=True)
for name, f in R:
    want = m.run_null5(2000, 10) if name.endswith("5") else m.run_null(2000, 10)
    assert f(2000, 10) == want, name
