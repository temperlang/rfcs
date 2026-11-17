# /// script
# requires-python = ">=3.11"
# ///
# Per-call cost of checking a returned value for a Failed object (values design, dynamic backends).
import time
class Failed: __slots__ = ("e",)
class Node: __slots__ = ("x",)
node = Node()
def leaf(): return node
def plain():
    return leaf()
def checked():
    r = leaf()
    if isinstance(r, Failed): return r
    return r
def checked_type():
    r = leaf()
    if type(r) is Failed: return r
    return r
N = 3_000_000
for rnd in range(3):
    out = []
    for f in (plain, checked, checked_type):
        t = time.perf_counter()
        for _ in range(N): f()
        out.append((time.perf_counter() - t) / N * 1e9)
    print(f"round {rnd}: plain {out[0]:.1f} ns, isinstance +{out[1]-out[0]:.1f} ns, type-is +{out[2]-out[0]:.1f} ns")
