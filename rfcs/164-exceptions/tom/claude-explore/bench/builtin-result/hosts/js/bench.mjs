// What a compiler-known result type might cost in JS, hand-written beside
// failbench's generated `bubble` and `null` runners. ns per item, min and
// median of 7 runs after warm-up. Arguments: n, rate in per mille, variant.
//
//   value    success as the plain value, failure as a Failed object
//            (checked with instanceof)
//   nothrow  today's bubbling, thrown as a plain object (no Error, so
//            no stack trace is captured)
//
// Each has a depth-5 form passing the failure up four more functions.
const m = await import(new URL("../../../temper.out/js/failbench/index.js", import.meta.url));

class Bad { constructor(input) { this.input = input; } }
class Failed { constructor(error) { this.error = error; } }

// Written as the generated code is (its inputAt, `| 0` arithmetic, while
// loops), so only the failure handling differs from `null`.
const inputAt = m.inputAt;

function stepValue(x) { if (x < 0) { return new Failed(new Bad(x)); } return (Math.imul(x, 3) + 1) | 0; }
function v2(x) { const r = stepValue(x); if (r instanceof Failed) { return r; } return (r + 1) | 0; }
function v3(x) { const r = v2(x); if (r instanceof Failed) { return r; } return (r + 1) | 0; }
function v4(x) { const r = v3(x); if (r instanceof Failed) { return r; } return (r + 1) | 0; }
function v5(x) { const r = v4(x); if (r instanceof Failed) { return r; } return (r + 1) | 0; }
function runValue(n, failMille) {
  let sum = 0;
  let i = 0;
  while (i < n) {
    const r = stepValue(inputAt(i, failMille));
    sum = (sum + (r instanceof Failed ? 0 : r)) | 0;
    i = (i + 1) | 0;
  }
  return sum;
}
function runValue5(n, failMille) {
  let sum = 0;
  let i = 0;
  while (i < n) {
    const r = v5(inputAt(i, failMille));
    sum = (sum + (r instanceof Failed ? 0 : r)) | 0;
    i = (i + 1) | 0;
  }
  return sum;
}

// Generated bubbling, as today's (`throw Error()`), but throwing a plain object.
function stepThrow(x) { if (x < 0) { throw { failed: new Bad(x) }; } return (Math.imul(x, 3) + 1) | 0; }
function t2(x) { return (stepThrow(x) + 1) | 0; }
function t3(x) { return (t2(x) + 1) | 0; }
function t4(x) { return (t3(x) + 1) | 0; }
function t5(x) { return (t4(x) + 1) | 0; }
function runThrow(n, failMille) {
  let sum = 0;
  let i = 0;
  while (i < n) {
    const x = inputAt(i, failMille);
    let t;
    try { t = stepThrow(x); } catch { t = 0; }
    sum = (sum + t) | 0;
    i = (i + 1) | 0;
  }
  return sum;
}
function runThrow5(n, failMille) {
  let sum = 0;
  let i = 0;
  while (i < n) {
    const x = inputAt(i, failMille);
    let t;
    try { t = t5(x); } catch { t = 0; }
    sum = (sum + t) | 0;
    i = (i + 1) | 0;
  }
  return sum;
}

const N = Number(process.argv[2] || 200000);
const R = [["bubble", m.runBubble], ["null", m.runNull], ["value", runValue], ["nothrow", runThrow],
           ["bubble5", m.runBubble5], ["null5", m.runNull5], ["value5", runValue5], ["nothrow5", runThrow5]];
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
// Checked after timing, so the check's failures don't shape the JIT's profile.
for (const [name, f] of R) {
  const want = name.endsWith("5") ? m.runNull5(2000, 10) : m.runNull(2000, 10);
  if (f(2000, 10) !== want) throw new Error(`${name} disagrees`);
}
