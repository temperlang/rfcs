// What a compiler-known result type might cost in C#, hand-written beside
// failbench's generated `bubble` and `null` runners. ns per item, min and
// median of 7 runs after warm-up. Arguments: n, rate in per mille, variant.
//
//   rstruct  a readonly struct Result<T, E> (a flag, the value, the
//            failure), returned by value; the failure, Bad, is a class
//   flag     the plain value, with the failure in an `out` parameter
//            (null on success)
//
// Each has a depth-5 form passing the failure up four more functions.
using System; using System.Diagnostics; using System.Runtime.CompilerServices; using Failbench;

int n = args.Length > 0 ? int.Parse(args[0]) : 200000;
var R = new (string, Func<int, int, int>)[] {
    ("bubble", FailbenchGlobal.RunBubble), ("null", FailbenchGlobal.RunNull),
    ("rstruct", Hand.RunStruct), ("flag", Hand.RunFlag),
    ("bubble5", FailbenchGlobal.RunBubble5), ("null5", FailbenchGlobal.RunNull5),
    ("rstruct5", Hand.RunStruct5), ("flag5", Hand.RunFlag5) };
int only = args.Length > 1 ? int.Parse(args[1]) : -1;
foreach (var pct in new[] { 0, 1, 10, 100 }) {
    if (only >= 0 && pct != only) continue;
    foreach (var (name, f) in R) {
        if (args.Length > 2 && args[2] != name) continue;
        for (int i = 0; i < 3; i++) f(n, pct);
        var ts = new double[7];
        for (int i = 0; i < 7; i++) { var sw = Stopwatch.StartNew(); f(n, pct); ts[i] = sw.Elapsed.TotalMilliseconds * 1e6 / n; }
        Array.Sort(ts);
        Console.WriteLine($"csharp {pct} {name} {ts[0]:F1} {ts[3]:F1}");
    }
}
// Checked after timing, so the check's failures don't shape the JIT's profile.
if (Hand.RunStruct(2000, 10) != FailbenchGlobal.RunNull(2000, 10) || Hand.RunFlag(2000, 10) != FailbenchGlobal.RunNull(2000, 10)
    || Hand.RunStruct5(2000, 10) != FailbenchGlobal.RunNull5(2000, 10) || Hand.RunFlag5(2000, 10) != FailbenchGlobal.RunNull5(2000, 10)) {
    throw new Exception("hand-written variants disagree");
}

public sealed class Bad { public readonly int Input; public Bad(int input) { Input = input; } }

public readonly struct Result<T, E> where E : class {
    public readonly bool Ok; public readonly T Value; public readonly E? Error;
    Result(bool ok, T value, E? error) { Ok = ok; Value = value; Error = error; }
    public static Result<T, E> Success(T value) => new(true, value, null);
    public static Result<T, E> Failure(E error) => new(false, default!, error);
}

public static class Hand {
    static int InputAt(int i, int failMille) {
        int x = i % 1000;
        return (i % 1000) * 37 % 1000 < failMille ? -1 - x : x;
    }

    static Result<int, Bad> Step(int x) => x < 0 ? Result<int, Bad>.Failure(new Bad(x)) : Result<int, Bad>.Success(x * 3 + 1);
    static Result<int, Bad> S2(int x) { var r = Step(x); return r.Ok ? Result<int, Bad>.Success(r.Value + 1) : r; }
    static Result<int, Bad> S3(int x) { var r = S2(x); return r.Ok ? Result<int, Bad>.Success(r.Value + 1) : r; }
    static Result<int, Bad> S4(int x) { var r = S3(x); return r.Ok ? Result<int, Bad>.Success(r.Value + 1) : r; }
    static Result<int, Bad> S5(int x) { var r = S4(x); return r.Ok ? Result<int, Bad>.Success(r.Value + 1) : r; }

    static int StepF(int x, out Bad? error) {
        if (x < 0) { error = new Bad(x); return 0; }
        error = null; return x * 3 + 1;
    }
    static int F2(int x, out Bad? e) { int v = StepF(x, out e); return e == null ? v + 1 : 0; }
    static int F3(int x, out Bad? e) { int v = F2(x, out e); return e == null ? v + 1 : 0; }
    static int F4(int x, out Bad? e) { int v = F3(x, out e); return e == null ? v + 1 : 0; }
    static int F5(int x, out Bad? e) { int v = F4(x, out e); return e == null ? v + 1 : 0; }

    public static int RunStruct(int n, int m) { int s = 0; for (int i = 0; i < n; i++) { var r = Step(InputAt(i, m)); s += r.Ok ? r.Value : 0; } return s; }
    public static int RunStruct5(int n, int m) { int s = 0; for (int i = 0; i < n; i++) { var r = S5(InputAt(i, m)); s += r.Ok ? r.Value : 0; } return s; }
    public static int RunFlag(int n, int m) { int s = 0; for (int i = 0; i < n; i++) { int v = StepF(InputAt(i, m), out var e); s += e == null ? v : 0; } return s; }
    public static int RunFlag5(int n, int m) { int s = 0; for (int i = 0; i < n; i++) { int v = F5(InputAt(i, m), out var e); s += e == null ? v : 0; } return s; }
}
