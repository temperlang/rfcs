// What a compiler-known result type might cost in Rust, hand-written beside
// failbench's generated `bubble` and `null` runners. ns per item, min and
// median of 7 runs after warm-up. Arguments: n, rate in per mille, variant.
//
//   result   Result<i32, Bad> by value, with Bad a small struct (the input)
//
// Today's `bubble` is already a native Result, with temper_core's error
// (an optional cause) as E; `result5` passes the failure up four more
// functions with `?`, as failbench's b2..b5 do.
use failbench::*;
use std::time::Instant;

#[derive(Clone, Copy)]
pub struct Bad {
    #[allow(dead_code)]
    input: i32,
}

#[inline]
fn input_at(i: i32, fail_mille: i32) -> i32 {
    let x = i % 1000;
    if (i % 1000) * 37 % 1000 < fail_mille { -1 - x } else { x }
}

fn step(x: i32) -> Result<i32, Bad> {
    if x < 0 {
        return Err(Bad { input: x });
    }
    Ok(x.wrapping_mul(3).wrapping_add(1))
}
fn r2(x: i32) -> Result<i32, Bad> { Ok(step(x)?.wrapping_add(1)) }
fn r3(x: i32) -> Result<i32, Bad> { Ok(r2(x)?.wrapping_add(1)) }
fn r4(x: i32) -> Result<i32, Bad> { Ok(r3(x)?.wrapping_add(1)) }
fn r5(x: i32) -> Result<i32, Bad> { Ok(r4(x)?.wrapping_add(1)) }

fn run_result_native(n: i32, fail_mille: i32) -> i32 {
    let mut sum = 0i32;
    for i in 0..n { sum = sum.wrapping_add(step(input_at(i, fail_mille)).unwrap_or(0)); }
    sum
}
fn run_result_native5(n: i32, fail_mille: i32) -> i32 {
    let mut sum = 0i32;
    for i in 0..n { sum = sum.wrapping_add(r5(input_at(i, fail_mille)).unwrap_or(0)); }
    sum
}

fn main() {
    let n: i32 = std::env::args().nth(1).map(|s| s.parse().unwrap()).unwrap_or(200000);
    let fs: [(&str, fn(i32, i32) -> i32); 6] = [
        ("bubble", run_bubble), ("null", run_null), ("result", run_result_native),
        ("bubble5", run_bubble5), ("null5", run_null5), ("result5", run_result_native5),
    ];
    let only: i32 = std::env::args().nth(2).map(|s| s.parse().unwrap()).unwrap_or(-1);
    let pick = std::env::args().nth(3);
    for pct in [0, 1, 10, 100] {
        if only >= 0 && pct != only { continue; }
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
    assert_eq!(run_result_native(2000, 10), run_null(2000, 10));
    assert_eq!(run_result_native5(2000, 10), run_null5(2000, 10));
}
