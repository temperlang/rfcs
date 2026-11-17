// Times failbench's runners: ns per item, min and median of 7 runs after warm-up.
using System; using System.Collections.Generic; using System.Diagnostics; using Failbench;
int n = args.Length > 0 ? int.Parse(args[0]) : 200000;
var R = new (string, Func<int, int, int>)[] {
    ("bubble", FailbenchGlobal.RunBubble), ("null", FailbenchGlobal.RunNull), ("result", FailbenchGlobal.RunResult),
    ("bubble5", FailbenchGlobal.RunBubble5), ("null5", FailbenchGlobal.RunNull5), ("result5", FailbenchGlobal.RunResult5) };
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
