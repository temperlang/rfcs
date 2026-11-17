// What a compiler-known result type might cost on the JVM, hand-written
// beside failbench's generated `bubble` and `null` runners. ns per item,
// min and median of 7 runs after warm-up. Arguments: n, rate in per
// mille, variant.
//
//   rec      a sealed interface with records Ok(int) and Failed(Bad):
//            an Ok per success, unless the JIT removes it
//   obj      success as the plain value, failure as a Failed object: the
//            return type is Object, so an int is boxed (an Integer) unless
//            the JIT removes the box; a reference T would cost nothing
//   long     a primitive long with Long.MIN_VALUE for failure (as the
//            first benchmark's `long`; the failure's data is lost)
//   nothrow  today's bubbling, thrown as a RuntimeException subclass
//            with writableStackTrace=false, so no stack trace is taken
//
// Each has a depth-5 form passing the failure up four more functions.
import failbench.FailbenchGlobal;
import java.util.*;
import java.util.function.IntBinaryOperator;

public class Bench {
    record Bad(int input) {}
    sealed interface Res permits Ok, Failed {}
    record Ok(int value) implements Res {}
    record Failed(Bad error) implements Res {}

    static int inputAt(int i, int failMille) {
        int x = i % 1000;
        return (i % 1000) * 37 % 1000 < failMille ? -1 - x : x;
    }

    // rec
    static Res stepRec(int x) { return x < 0 ? new Failed(new Bad(x)) : new Ok(x * 3 + 1); }
    static Res rec2(int x) { Res r = stepRec(x); return r instanceof Ok o ? new Ok(o.value() + 1) : r; }
    static Res rec3(int x) { Res r = rec2(x); return r instanceof Ok o ? new Ok(o.value() + 1) : r; }
    static Res rec4(int x) { Res r = rec3(x); return r instanceof Ok o ? new Ok(o.value() + 1) : r; }
    static Res rec5(int x) { Res r = rec4(x); return r instanceof Ok o ? new Ok(o.value() + 1) : r; }
    static int runRec(int n, int m) { int s = 0; for (int i = 0; i < n; i++) { s += stepRec(inputAt(i, m)) instanceof Ok o ? o.value() : 0; } return s; }
    static int runRec5(int n, int m) { int s = 0; for (int i = 0; i < n; i++) { s += rec5(inputAt(i, m)) instanceof Ok o ? o.value() : 0; } return s; }

    // obj
    static Object stepObj(int x) { if (x < 0) return new Failed(new Bad(x)); return x * 3 + 1; }
    static Object obj2(int x) { Object r = stepObj(x); return r instanceof Failed ? r : (Object) ((Integer) r + 1); }
    static Object obj3(int x) { Object r = obj2(x); return r instanceof Failed ? r : (Object) ((Integer) r + 1); }
    static Object obj4(int x) { Object r = obj3(x); return r instanceof Failed ? r : (Object) ((Integer) r + 1); }
    static Object obj5(int x) { Object r = obj4(x); return r instanceof Failed ? r : (Object) ((Integer) r + 1); }
    static int runObj(int n, int m) { int s = 0; for (int i = 0; i < n; i++) { Object r = stepObj(inputAt(i, m)); s += r instanceof Integer v ? v : 0; } return s; }
    static int runObj5(int n, int m) { int s = 0; for (int i = 0; i < n; i++) { Object r = obj5(inputAt(i, m)); s += r instanceof Integer v ? v : 0; } return s; }

    // long
    static final long NONE = Long.MIN_VALUE;
    static long stepLong(int x) { if (x < 0) return NONE; return x * 3 + 1; }
    static long l2(int x) { long v = stepLong(x); if (v == NONE) return NONE; return v + 1; }
    static long l3(int x) { long v = l2(x); if (v == NONE) return NONE; return v + 1; }
    static long l4(int x) { long v = l3(x); if (v == NONE) return NONE; return v + 1; }
    static long l5(int x) { long v = l4(x); if (v == NONE) return NONE; return v + 1; }
    static int runLong(int n, int m) { int s = 0; for (int i = 0; i < n; i++) { long v = stepLong(inputAt(i, m)); s += v == NONE ? 0 : (int) v; } return s; }
    static int runLong5(int n, int m) { int s = 0; for (int i = 0; i < n; i++) { long v = l5(inputAt(i, m)); s += v == NONE ? 0 : (int) v; } return s; }

    // nothrow
    static final class Lite extends RuntimeException {
        final Bad error;
        Lite(Bad error) { super(null, null, false, false); this.error = error; }
    }
    static int stepThrow(int x) { if (x < 0) throw new Lite(new Bad(x)); return x * 3 + 1; }
    static int t2(int x) { return stepThrow(x) + 1; }
    static int t3(int x) { return t2(x) + 1; }
    static int t4(int x) { return t3(x) + 1; }
    static int t5(int x) { return t4(x) + 1; }
    static int runThrow(int n, int m) { int s = 0; for (int i = 0; i < n; i++) { int x = inputAt(i, m); try { s += stepThrow(x); } catch (Lite e) { } } return s; }
    static int runThrow5(int n, int m) { int s = 0; for (int i = 0; i < n; i++) { int x = inputAt(i, m); try { s += t5(x); } catch (Lite e) { } } return s; }

    public static void main(String[] a) {
        int n = a.length > 0 ? Integer.parseInt(a[0]) : 200000;
        int only = a.length > 1 ? Integer.parseInt(a[1]) : -1;
        String[] names = {"bubble", "null", "rec", "obj", "long", "nothrow",
                          "bubble5", "null5", "rec5", "obj5", "long5", "nothrow5"};
        List<IntBinaryOperator> fs = List.of(
            FailbenchGlobal::runBubble, FailbenchGlobal::runNull, Bench::runRec, Bench::runObj, Bench::runLong, Bench::runThrow,
            FailbenchGlobal::runBubble5, FailbenchGlobal::runNull5, Bench::runRec5, Bench::runObj5, Bench::runLong5, Bench::runThrow5);
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
        // Checked after timing, so the check's failures don't shape the JIT's profile.
        for (int k = 0; k < names.length; k++) {
            boolean five = names[k].endsWith("5");
            int want = five ? FailbenchGlobal.runNull5(2000, 10) : FailbenchGlobal.runNull(2000, 10);
            if (fs.get(k).applyAsInt(2000, 10) != want) throw new AssertionError(names[k] + " disagrees");
        }
    }
}
