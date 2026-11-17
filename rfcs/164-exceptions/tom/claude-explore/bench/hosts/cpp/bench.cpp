// Times failbench's runners: ns per item, min and median of 7 runs after warm-up.
#include "failbench/init.hpp"
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <string>
using namespace failbench;
typedef int32_t (*Fn)(int32_t, int32_t);
int main(int argc, char** argv) {
  int n = argc > 1 ? atoi(argv[1]) : 200000;
  const char* names[] = {"bubble", "null", "result", "bubble5", "null5", "result5"};
  Fn fs[] = {runBubble, runNull, runResult, runBubble5, runNull5, runResult5};
  volatile int32_t sink = 0;
  int only = argc > 2 ? atoi(argv[2]) : -1;
  for (int pct : {0, 1, 10, 100}) {
    if (only >= 0 && pct != only) continue;
    for (int k = 0; k < 6; k++) {
      if (argc > 3 && std::string(argv[3]) != names[k]) continue;
      for (int i = 0; i < 3; i++) sink = sink + fs[k](n, pct);
      double ts[7];
      for (int i = 0; i < 7; i++) {
        auto t = std::chrono::steady_clock::now();
        sink = sink + fs[k](n, pct);
        ts[i] = std::chrono::duration<double, std::nano>(std::chrono::steady_clock::now() - t).count() / n;
      }
      std::sort(ts, ts + 7);
      printf("cpp %d %s %.1f %.1f\n", pct, names[k], ts[0], ts[3]);
      fflush(stdout);
    }
  }
}
