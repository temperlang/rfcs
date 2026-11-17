# /// script
# requires-python = ">=3.11"
# ///
"""Builds and runs one backend's failbench timing harness.

    uv run hosts/run.py BACKEND [N]

Run from the benchmark's directory (the one holding src/), after
`temper build` (or `temper test -b BACKEND`) has filled temper.out/.
Each line printed is `backend rate variant min median`, with the
failure rate in per mille and times in ns per item: the fastest and the
median of 7 timed runs after warm-up runs.

Two extra modes repeat a backend with inlining limited, so a nullable
`Int` crosses real calls, as it does where functions are too big to
inline or called through interfaces: `java-noinline` (HotSpot doesn't
inline the step functions, generated or hand-written) and
`csharp-noinline` (`DOTNET_JitNoInline=1`: no inlining at all).

`TEMPER` names the temper command (default: `temper` on PATH). For
interp, each variant runs as its own small library on the interpreter,
timed from outside: the time for REPS passes over the inputs, less the
time with none, so the build and the inputs' setup cancel out.
"""

import os
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
OUT = ROOT / "temper.out"
TEMPER = os.environ.get("TEMPER", "temper")
VARIANTS = {
    "bubble": "runBubble", "null": "runNull", "result": "runResult",
    "bubble5": "runBubble5", "null5": "runNull5", "result5": "runResult5",
}


def sh(*cmd: str | Path, cwd: Path | None = None, env: dict | None = None) -> None:
    subprocess.run([str(c) for c in cmd], cwd=cwd, env=env, check=True)


# Each builds its harness if needed and gives the command that runs it,
# and the environment it needs, if any.

def cpp():
    exe = HERE / "cpp" / "bench"
    sh("g++", "-O2", "-std=c++17", f"-I{OUT / 'cpp'}", "-o", exe,
       HERE / "cpp" / "bench.cpp", OUT / "cpp" / "failbench" / "init.cpp", "-lpthread")
    return [exe], None


def rust():
    sh("cargo", "build", "--release", "-q", cwd=HERE / "rust")
    return [HERE / "rust" / "target" / "release" / "bench"], None


def java():
    classes = HERE / "java" / "out"
    sources = [str(p) for p in (OUT / "java").glob("*/src/main/java/**/*.java")
               if "/std/" not in str(p)]
    sh("javac", "-nowarn", "-d", classes, HERE / "java" / "Bench.java", *sources)
    return ["java", "-cp", classes, "Bench"], None


def csharp():
    proj = HERE / "csharp"
    sh("dotnet", "build", "-c", "Release", "-v", "q", "-nologo", cwd=proj)
    return ["dotnet", proj / "bin" / "Release" / "net6.0" / "Bench.dll"], None


def js():
    return ["node", HERE / "js" / "bench.mjs"], None


def py():
    env = dict(os.environ)
    env["PYTHONPATH"] = os.pathsep.join(
        str(OUT / "py" / d) for d in ("failbench", "temper-core"))
    return [os.environ.get("BENCH_PY", "python3"), HERE / "py" / "bench.py"], env


def lua():
    env = dict(os.environ)
    lua_out = OUT / "lua"
    env["LUA_PATH"] = f"{lua_out}/?.lua;{lua_out}/?/init.lua;;"
    return ["lua", HERE / "lua" / "bench.lua"], env


DRIVER = """# Driver

    let {{ {fn} }} = import("failbench");
    var s = 0;
    for (var k = 0; k < {reps}; k += 1) {{ s += {fn}({n}, {pct}); }}
    console.log(s.toString());
"""


def interp(n: int, reps: int = 5) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        shutil.copytree(ROOT / "src", work / "failbench")
        (work / "drv").mkdir()
        (work / "drv" / "config.temper.md").write_text('# Driver\n\n    export let name = "drv";\n')

        def timed(fn: str, pct: int, r: int) -> float:
            (work / "drv" / "drv.temper.md").write_text(DRIVER.format(fn=fn, n=n, pct=pct, reps=r))
            t = time.perf_counter()
            subprocess.run([TEMPER, "run", "--library", "drv", "-b", "interp", "-w", str(work)],
                           check=True, stdout=subprocess.DEVNULL)
            return time.perf_counter() - t

        for pct in RATES:
            for name, fn in VARIANTS.items():
                timed(fn, pct, 1)  # warm the file cache
                per = []
                for _ in range(7):
                    base = timed(fn, pct, 0)
                    full = timed(fn, pct, reps)
                    per.append((full - base) * 1e9 / (n * reps))
                per.sort()
                print(f"interp {pct} {name} {per[0]:.1f} {statistics.median(per):.1f}", flush=True)


RUNNERS = {"cpp": cpp, "rust": rust, "java": java, "csharp": csharp, "js": js,
           "py": py, "lua": lua, "java-noinline": java, "csharp-noinline": csharp}
RATES = (0, 1, 10, 100)  # per mille: 0, 0.1, 1, and 10 percent
DEFAULT_N = {"py": 50000, "lua": 50000, "interp": 100000}

if __name__ == "__main__":
    backend = sys.argv[1]
    n = int(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_N.get(backend, 200000)
    if backend == "interp":
        interp(n)
    else:
        # A fresh process per failure rate and variant, so a JIT's
        # profile from one doesn't shape the code timed for the next.
        cmd, env = RUNNERS[backend]()
        label = backend
        if backend == "java-noinline":
            cmd = cmd[:1] + ["-XX:CompileCommand=quiet"] + [
                f"-XX:CompileCommand=dontinline,{m}" for m in (
                    ["failbench.FailbenchGlobal::step*", "Bench::stepLong"]
                    + [f"failbench.FailbenchGlobal::{p}{k}" for p in "bnr" for k in range(2, 6)]
                    + [f"Bench::l{k}" for k in range(2, 6)])] + cmd[1:]
        if backend == "csharp-noinline":
            env = dict(os.environ, DOTNET_JitNoInline="1")
        variants = list(VARIANTS) + (["long", "long5"] if backend.startswith("java") else [])
        for pct in RATES:
            for variant in variants:
                out = subprocess.run([str(c) for c in cmd] + [str(n), str(pct), variant],
                                     env=env, check=True, capture_output=True, text=True).stdout
                for line in out.splitlines():
                    parts = line.split()
                    if len(parts) == 5:
                        print(" ".join([label] + parts[1:]), flush=True)
