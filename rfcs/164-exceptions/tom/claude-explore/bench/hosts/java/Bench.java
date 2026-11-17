// Times failbench's runners: ns per item, min and median of 7 runs after warm-up.
// Arguments: n, then optionally a failure rate in per mille and a variant.
// `long` and `long5` are hand-written here, not generated: the nullable
// step as an internal function could be lowered, returning a primitive
// `long` with an out-of-range sentinel for null, so nothing is boxed.
import failbench.FailbenchGlobal;
import java.util.*;
import java.util.function.IntBinaryOperator;
public class Bench {
    static final long NONE = Long.MIN_VALUE;

    static long stepLong(int x) {
        if (x < 0) return NONE;
        return x * 3 + 1;
    }
    static long l2(int x) { long v = stepLong(x); if (v == NONE) return NONE; return v + 1; }
    static long l3(int x) { long v = l2(x); if (v == NONE) return NONE; return v + 1; }
    static long l4(int x) { long v = l3(x); if (v == NONE) return NONE; return v + 1; }
    static long l5(int x) { long v = l4(x); if (v == NONE) return NONE; return v + 1; }

    static int runLong(int n, int failMille) {
        int sum = 0;
        for (int i = 0; i < n; i++) {
            long v = stepLong(FailbenchGlobal.inputAt(i, failMille));
            sum += v == NONE ? 0 : (int) v;
        }
        return sum;
    }
    static int runLong5(int n, int failMille) {
        int sum = 0;
        for (int i = 0; i < n; i++) {
            long v = l5(FailbenchGlobal.inputAt(i, failMille));
            sum += v == NONE ? 0 : (int) v;
        }
        return sum;
    }

    public static void main(String[] a) {
        int n = a.length > 0 ? Integer.parseInt(a[0]) : 200000;
        int only = a.length > 1 ? Integer.parseInt(a[1]) : -1;
        String[] names = {"bubble", "null", "result", "long", "bubble5", "null5", "result5", "long5"};
        List<IntBinaryOperator> fs = List.of(
            FailbenchGlobal::runBubble, FailbenchGlobal::runNull, FailbenchGlobal::runResult, Bench::runLong,
            FailbenchGlobal::runBubble5, FailbenchGlobal::runNull5, FailbenchGlobal::runResult5, Bench::runLong5);
        for (int pct : new int[]{0, 1, 10, 100}) {
            if (only >= 0 && pct != only) continue;
            for (int k = 0; k < names.length; k++) {
                if (a.length > 2 && !a[2].equals(names[k])) continue;
                for (int i = 0; i < 10; i++) fs.get(k).applyAsInt(n, pct);
                double[] ts = new double[7];
                for (int i = 0; i < 7; i++) {
                    long t = System.nanoTime();
                    fs.get(k).applyAsInt(n, pct);
                    ts[i] = (System.nanoTime() - t) / (double) n;
                }
                Arrays.sort(ts);
                System.out.printf("java %d %s %.1f %.1f%n", pct, names[k], ts[0], ts[3]);
            }
        }
        // Checked after timing, so the check's failures don't shape the
        // JIT's profile for the 0 percent runs.
        if (runLong(2000, 10) != FailbenchGlobal.runNull(2000, 10) || runLong5(2000, 10) != FailbenchGlobal.runNull5(2000, 10)) {
            throw new AssertionError("long variants disagree");
        }
    }
}
