// Times failbench's runners: ns per item, min and median of 7 runs after warm-up.
const m = await import(new URL("../../temper.out/js/failbench/index.js", import.meta.url));
const N = Number(process.argv[2] || 200000);
const R = [["bubble", m.runBubble], ["null", m.runNull], ["result", m.runResult],
           ["bubble5", m.runBubble5], ["null5", m.runNull5], ["result5", m.runResult5]];
const only = Number(process.argv[3] ?? -1);
for (const pct of [0, 1, 10, 100]) {
  if (only >= 0 && pct !== only) continue;
  for (const [name, f] of R) {
    if (process.argv[4] && process.argv[4] !== name) continue;
    for (let i = 0; i < 5; i++) f(N, pct);
    const ts = [];
    for (let i = 0; i < 7; i++) { const t = process.hrtime.bigint(); f(N, pct); ts.push(Number(process.hrtime.bigint() - t) / N); }
    ts.sort((a, b) => a - b);
    console.log(`js ${pct} ${name} ${ts[0].toFixed(1)} ${ts[3].toFixed(1)}`);
  }
}
