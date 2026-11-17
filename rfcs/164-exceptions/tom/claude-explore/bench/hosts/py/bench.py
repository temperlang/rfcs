# Times failbench's runners: ns per item, min and median of 7 runs after warm-up.
import statistics, sys, time
import failbench as m
N = int(sys.argv[1]) if len(sys.argv) > 1 else 50000
R = [("bubble", m.run_bubble), ("null", m.run_null), ("result", m.run_result),
     ("bubble5", m.run_bubble5), ("null5", m.run_null5), ("result5", m.run_result5)]
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
