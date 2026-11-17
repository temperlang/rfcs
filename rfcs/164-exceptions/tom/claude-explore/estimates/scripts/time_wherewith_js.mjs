// Times Wherewith workloads in JS. Usage: node time_wherewith_js.mjs JS_OUT_DIR (a copy of temper.out/js)
const ww = await import(process.argv[2] + "/wherewith/index.js");
const { Dialect, PlaceholderStyle: PS, QueryBuilder: QB } = ww;
function example() {
  const b = new QB(Dialect.common);
  b.appendSafe('SELECT title, "dueDate" FROM tasks WHERE title LIKE ');
  b.appendString("Launch");
  b.appendSafe(" || '%' ESCAPE '!' ORDER BY \"dueDate\" NULLS LAST LIMIT ");
  b.appendInt(20); b.appendSafe(" OFFSET "); b.appendInt(40);
  return b.build();
}
function bigger() {
  const b = new QB(Dialect.common);
  b.appendSafe("SELECT u.id, u.name, count(o.id) AS orders, sum(o.total) AS spent FROM users AS u LEFT JOIN orders AS o ON o.user_id = u.id WHERE u.created_at >= ");
  b.appendString("2026-01-01"); b.appendSafe(" AND (u.status = "); b.appendString("active");
  b.appendSafe(" OR u.status = "); b.appendString("trial");
  b.appendSafe(") AND u.id NOT IN (SELECT user_id FROM bans) GROUP BY u.id, u.name HAVING count(o.id) > ");
  b.appendInt(2); b.appendSafe(" ORDER BY spent DESC NULLS LAST LIMIT "); b.appendInt(50);
  return b.build();
}
const render4 = (q) => { q.render(Dialect.sqlite, PS.question); q.render(Dialect.postgres, PS.dollarNumbered); q.render(Dialect.mysql, PS.percentS); q.render(Dialect.duckdb, PS.dollarNumbered); };
function syntaxError() { const b = new QB(Dialect.common); b.appendSafe("SELECT a, b FROM t WHERE a = (b + "); return b.templateProblem; }
function nearMiss() { const b = new QB(Dialect.common); b.appendSafe("SELECT a, b FROM t WHERE a = (b + 1)"); return b.templateProblem; }
const q = example(), qb = bigger();
const jobs = [["example: build", example], ["example: render x4", () => render4(q)], ["bigger: build", bigger], ["bigger: render x4", () => render4(qb)], ["valid, like the syntax error", nearMiss], ["syntax error (1 failure)", syntaxError]];
for (let round = 0; round < 3; round++) {
  const row = [];
  for (const [name, fn] of jobs) {
    for (let i = 0; i < 2000; i++) fn();
    let n = 0; const t0 = process.hrtime.bigint();
    while (Number(process.hrtime.bigint() - t0) < 3e8) { fn(); n++; }
    row.push(`${name} ${(Number(process.hrtime.bigint() - t0) / n / 1000).toFixed(1)} us`);
  }
  console.log(row.join("; "));
}
