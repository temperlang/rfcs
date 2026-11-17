// Times failbench's runners: ns per item, min and median of 7 runs after warm-up.
use failbench::*;
use std::time::Instant;
fn main() {
    let n: i32 = std::env::args().nth(1).map(|s| s.parse().unwrap()).unwrap_or(200000);
    let fs: [(&str, fn(i32, i32) -> i32); 6] = [
        ("bubble", run_bubble), ("null", run_null), ("result", run_result),
        ("bubble5", run_bubble5), ("null5", run_null5), ("result5", run_result5),
    ];
    let only: i32 = std::env::args().nth(2).map(|s| s.parse().unwrap()).unwrap_or(-1);
    for pct in [0, 1, 10, 100] {
        if only >= 0 && pct != only { continue; }
        let pick = std::env::args().nth(3);
        for (name, f) in fs.iter() {
            if pick.as_deref().map_or(false, |p| p != *name) { continue; }
            for _ in 0..3 { std::hint::black_box(f(std::hint::black_box(n), std::hint::black_box(pct))); }
            let mut ts: Vec<f64> = (0..7).map(|_| {
                let t = Instant::now();
                std::hint::black_box(f(std::hint::black_box(n), std::hint::black_box(pct)));
                t.elapsed().as_nanos() as f64 / n as f64
            }).collect();
            ts.sort_by(|a, b| a.partial_cmp(b).unwrap());
            println!("rust {pct} {name} {:.1} {:.1}", ts[0], ts[3]);
        }
    }
}
