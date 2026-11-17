# /// script
# requires-python = ">=3.11"
# ///
"""Builds and runs one backend's builtin-result timing harness.

    uv run builtin-result/run.py BACKEND [N]

Run from the benchmark's directory (the one holding src/), after
`temper build` has filled temper.out/ for the backend. Each harness in
builtin-result/hosts/ times failbench's generated `bubble` and `null`
runners beside hand-written versions of what a compiler-known result
type could become on that backend (see each harness's header). Each
line printed is `backend rate variant min median`, with the failure
rate in per mille and times in ns per item: the fastest and the median
of 7 timed runs after warm-up runs. Each failure rate and variant runs
in a fresh process.

As in hosts/run.py, `java-noinline` keeps HotSpot from inlining the
step functions and the four levels above them (generated and
hand-written alike), and `csharp-noinline` sets DOTNET_JitNoInline=1.
"""

import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent / "hosts"
ROOT = HERE.parent.parent
OUT = ROOT / "temper.out"


def sh(*cmd, cwd=None, env=None) -> None:
    # Build tools' chatter goes to stderr, keeping stdout for timings.
    subprocess.run([str(c) for c in cmd], cwd=cwd, env=env, check=True, stdout=sys.stderr)


def cpp():
    exe = HERE / "cpp" / "bench"
    sh("g++", "-O2", "-std=c++23", f"-I{OUT / 'cpp'}", "-o", exe,
       HERE / "cpp" / "bench.cpp", OUT / "cpp" / "failbench" / "init.cpp", "-lpthread")
    return [exe], None, ["bubble", "null", "variant", "tagged", "expected"]


def rust():
    sh("cargo", "build", "--release", "-q", cwd=HERE / "rust")
    return [HERE / "rust" / "target" / "release" / "bench"], None, ["bubble", "null", "result"]


def java():
    classes = HERE / "java" / "out"
    sources = [str(p) for p in (OUT / "java").glob("*/src/main/java/**/*.java")
               if "/std/" not in str(p)]
    sh("javac", "-nowarn", "-d", classes, HERE / "java" / "Bench.java", *sources)
    return (["java", "-cp", classes, "Bench"], None,
            ["bubble", "null", "rec", "obj", "long", "nothrow"])


def csharp():
    proj = HERE / "csharp"
    sh("dotnet", "build", "-c", "Release", "-v", "q", "-nologo", cwd=proj)
    sh("dotnet", "build-server", "shutdown")
    return (["dotnet", proj / "bin" / "Release" / "net6.0" / "Bench.dll"], None,
            ["bubble", "null", "rstruct", "flag"])


def js():
    # The generated JS imports @temperlang/core by name.
    link = OUT / "js" / "node_modules" / "@temperlang" / "core"
    if not link.exists():
        link.parent.mkdir(parents=True, exist_ok=True)
        link.symlink_to(Path("..") / ".." / "temper-core")
    return ["node", HERE / "js" / "bench.mjs"], None, ["bubble", "null", "value", "nothrow"]


def py():
    env = dict(os.environ)
    env["PYTHONPATH"] = os.pathsep.join(str(OUT / "py" / d) for d in ("failbench", "temper-core"))
    return ([os.environ.get("BENCH_PY", "python3"), HERE / "py" / "bench.py"], env,
            ["bubble", "null", "value"])


def lua():
    env = dict(os.environ)
    lua_out = OUT / "lua"
    env["LUA_PATH"] = f"{lua_out}/?.lua;{lua_out}/?/init.lua;;"
    return ["lua", HERE / "lua" / "bench.lua"], env, ["bubble", "null", "value"]


RUNNERS = {"cpp": cpp, "rust": rust, "java": java, "csharp": csharp, "js": js,
           "py": py, "lua": lua, "java-noinline": java, "csharp-noinline": csharp}
RATES = (0, 1, 10, 100)  # per mille: 0, 0.1, 1, and 10 percent
DEFAULT_N = {"py": 50000, "lua": 50000}

if __name__ == "__main__":
    backend = sys.argv[1]
    n = int(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_N.get(backend, 200000)
    cmd, env, variants = RUNNERS[backend]()
    if backend == "java-noinline":
        steps = (["failbench.FailbenchGlobal::step*"]
                 + [f"failbench.FailbenchGlobal::{p}{k}" for p in "bn" for k in range(2, 6)]
                 + [f"Bench::step*"]
                 + [f"Bench::{p}{k}" for p in ("rec", "obj", "l", "t") for k in range(2, 6)])
        cmd = cmd[:1] + ["-XX:CompileCommand=quiet"] + [
            f"-XX:CompileCommand=dontinline,{m}" for m in steps] + cmd[1:]
    if backend == "csharp-noinline":
        env = dict(os.environ, DOTNET_JitNoInline="1")
    for pct in RATES:
        for variant in variants + [v + "5" for v in variants]:
            out = subprocess.run([str(c) for c in cmd] + [str(n), str(pct), variant],
                                 env=env, check=True, capture_output=True, text=True,
                                 timeout=300).stdout
            for line in out.splitlines():
                parts = line.split()
                if len(parts) == 5:
                    print(" ".join([backend] + parts[1:]), flush=True)
