// What a compiler-known result type might cost in C++, hand-written beside
// failbench's generated `bubble` and `null` runners. ns per item, min and
// median of 7 runs after warm-up. Arguments: n, rate in per mille, variant.
//
//   variant   std::variant<int32_t, Bad>, by value
//   tagged    a small struct by value: a flag, the value, the failure
//   expected  std::expected<int32_t, Bad> (C++23)
//
// Each has a depth-5 form (`variant5` ...) passing the failure up four
// more functions, as failbench's b2..b5 do.
#include "failbench/init.hpp"
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <variant>
#if __cplusplus > 202002L
#include <expected>
#endif

struct Bad { int32_t input; };


static inline int32_t inputAt(int32_t i, int32_t failMille) {
  int32_t x = i % 1000;
  return (i % 1000) * 37 % 1000 < failMille ? -1 - x : x;
}

// std::variant
using V = std::variant<int32_t, Bad>;
static V stepV(int32_t x) {
  if (x < 0) return Bad{x};
  return x * 3 + 1;
}
static V v2(int32_t x) { V r = stepV(x); if (auto p = std::get_if<int32_t>(&r)) return *p + 1; return r; }
static V v3(int32_t x) { V r = v2(x); if (auto p = std::get_if<int32_t>(&r)) return *p + 1; return r; }
static V v4(int32_t x) { V r = v3(x); if (auto p = std::get_if<int32_t>(&r)) return *p + 1; return r; }
static V v5(int32_t x) { V r = v4(x); if (auto p = std::get_if<int32_t>(&r)) return *p + 1; return r; }

// A tagged struct.
struct T { bool ok; int32_t value; Bad error; };
static T stepT(int32_t x) {
  if (x < 0) return T{false, 0, Bad{x}};
  return T{true, x * 3 + 1, Bad{0}};
}
static T t2(int32_t x) { T r = stepT(x); if (r.ok) return T{true, r.value + 1, Bad{0}}; return r; }
static T t3(int32_t x) { T r = t2(x); if (r.ok) return T{true, r.value + 1, Bad{0}}; return r; }
static T t4(int32_t x) { T r = t3(x); if (r.ok) return T{true, r.value + 1, Bad{0}}; return r; }
static T t5(int32_t x) { T r = t4(x); if (r.ok) return T{true, r.value + 1, Bad{0}}; return r; }

#if __cplusplus > 202002L
using E = std::expected<int32_t, Bad>;
static E stepE(int32_t x) {
  if (x < 0) return std::unexpected(Bad{x});
  return x * 3 + 1;
}
static E e2(int32_t x) { E r = stepE(x); if (r) return *r + 1; return r; }
static E e3(int32_t x) { E r = e2(x); if (r) return *r + 1; return r; }
static E e4(int32_t x) { E r = e3(x); if (r) return *r + 1; return r; }
static E e5(int32_t x) { E r = e4(x); if (r) return *r + 1; return r; }
#endif

template <typename F>
static int32_t loop(int32_t n, int32_t failMille, F f) {
  int32_t sum = 0;
  for (int32_t i = 0; i < n; i++) sum += f(inputAt(i, failMille));
  return sum;
}

static int32_t runVariant(int32_t n, int32_t m) { return loop(n, m, [](int32_t x) { V r = stepV(x); auto p = std::get_if<int32_t>(&r); return p ? *p : 0; }); }
static int32_t runVariant5(int32_t n, int32_t m) { return loop(n, m, [](int32_t x) { V r = v5(x); auto p = std::get_if<int32_t>(&r); return p ? *p : 0; }); }
static int32_t runTagged(int32_t n, int32_t m) { return loop(n, m, [](int32_t x) { T r = stepT(x); return r.ok ? r.value : 0; }); }
static int32_t runTagged5(int32_t n, int32_t m) { return loop(n, m, [](int32_t x) { T r = t5(x); return r.ok ? r.value : 0; }); }
#if __cplusplus > 202002L
static int32_t runExpected(int32_t n, int32_t m) { return loop(n, m, [](int32_t x) { E r = stepE(x); return r ? *r : 0; }); }
static int32_t runExpected5(int32_t n, int32_t m) { return loop(n, m, [](int32_t x) { E r = e5(x); return r ? *r : 0; }); }
#endif

typedef int32_t (*Fn)(int32_t, int32_t);
struct Named { const char* name; Fn f; };
static const Named ALL[] = {
  {"bubble", failbench::runBubble}, {"null", failbench::runNull},
  {"variant", runVariant}, {"tagged", runTagged},
#if __cplusplus > 202002L
  {"expected", runExpected},
#endif
  {"bubble5", failbench::runBubble5}, {"null5", failbench::runNull5},
  {"variant5", runVariant5}, {"tagged5", runTagged5},
#if __cplusplus > 202002L
  {"expected5", runExpected5},
#endif
};

int main(int argc, char** argv) {
  int n = argc > 1 ? atoi(argv[1]) : 200000;
  int only = argc > 2 ? atoi(argv[2]) : -1;
  volatile int32_t sink = 0;
  for (int pct : {0, 1, 10, 100}) {
    if (only >= 0 && pct != only) continue;
    for (const Named& v : ALL) {
      if (argc > 3 && std::string(argv[3]) != v.name) continue;
      for (int i = 0; i < 3; i++) sink = sink + v.f(n, pct);
      double ts[7];
      for (int i = 0; i < 7; i++) {
        auto t = std::chrono::steady_clock::now();
        sink = sink + v.f(n, pct);
        ts[i] = std::chrono::duration<double, std::nano>(std::chrono::steady_clock::now() - t).count() / n;
      }
      std::sort(ts, ts + 7);
      printf("cpp %d %s %.1f %.1f\n", pct, v.name, ts[0], ts[3]);
      fflush(stdout);
    }
  }
  // Checked after timing, so the check's failures don't shape anything timed.
  for (const Named& v : ALL) {
    bool five = std::string(v.name).back() == '5';
    if (v.f(2000, 10) != (five ? failbench::runNull5 : failbench::runNull)(2000, 10)) {
      fprintf(stderr, "%s disagrees\n", v.name);
      return 1;
    }
  }
}
