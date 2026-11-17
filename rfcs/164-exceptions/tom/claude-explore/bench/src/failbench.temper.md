# Failure-cost benchmark

A loop over `n` integers, where `failMille` of every 1000 are
negative and make a cheap step fail. The failures are spread through
each block of 1000 (`(i % 1000) * 37 % 1000` visits every residue
once), so every backend sees the same pattern, at exactly the given
rate. Inputs are computed in the loop rather than read from a list, so
list access (which differs a lot between backends) doesn't hide the
cost of failing. Successful steps give values from 1 to 3001, mostly
outside the JVM's cache of small `Integer`s (-128 to 127), so a
nullable `Int` that isn't optimized away allocates.

    export let inputAt(i: Int, failMille: Int): Int {
      let x = i % 1000;
      if ((i % 1000) * 37 % 1000 < failMille) { -1 - x } else { x }
    }

## The result type

Written as user code today: a sealed interface with a success and a
failure class. Both carry both type parameters, since a `Failed` has to
be a `Result<T, E>` for the caller's `T`.

    export sealed interface Result<@out T, @out E> {}
    export class Ok<@out T, @out E>(public value: T) extends Result<T, E> {}
    export class Failed<@out T, @out E>(public error: E) extends Result<T, E> {}

The reason a step failed: the input it rejected.

    export class Bad(public input: Int) {}

## The failing step, three ways

    let stepBubble(x: Int): Int throws Bubble {
      if (x < 0) { bubble() }
      x * 3 + 1
    }

    let stepNull(x: Int): Int? {
      if (x < 0) { return null }
      x * 3 + 1
    }

    let stepResult(x: Int): Result<Int, Bad> {
      if (x < 0) { return new Failed<Int, Bad>(new Bad(x)); }
      new Ok<Int, Bad>(x * 3 + 1)
    }

## Five calls deep

The failure passes up four more functions, each adding 1 on success,
so the result version allocates a new `Ok` at each level (the value
changes) but passes a `Failed` up as it is.

    let b2(x: Int): Int throws Bubble { stepBubble(x) + 1 }
    let b3(x: Int): Int throws Bubble { b2(x) + 1 }
    let b4(x: Int): Int throws Bubble { b3(x) + 1 }
    let b5(x: Int): Int throws Bubble { b4(x) + 1 }

    let n2(x: Int): Int? {
      let v = stepNull(x);
      if (v == null) { return null; }
      v + 1
    }
    let n3(x: Int): Int? {
      let v = n2(x);
      if (v == null) { return null; }
      v + 1
    }
    let n4(x: Int): Int? {
      let v = n3(x);
      if (v == null) { return null; }
      v + 1
    }
    let n5(x: Int): Int? {
      let v = n4(x);
      if (v == null) { return null; }
      v + 1
    }

    let r2(x: Int): Result<Int, Bad> {
      let r = stepResult(x);
      when (r) { is Ok<Int, Bad> -> new Ok<Int, Bad>(r.value + 1); else -> r; }
    }
    let r3(x: Int): Result<Int, Bad> {
      let r = r2(x);
      when (r) { is Ok<Int, Bad> -> new Ok<Int, Bad>(r.value + 1); else -> r; }
    }
    let r4(x: Int): Result<Int, Bad> {
      let r = r3(x);
      when (r) { is Ok<Int, Bad> -> new Ok<Int, Bad>(r.value + 1); else -> r; }
    }
    let r5(x: Int): Result<Int, Bad> {
      let r = r4(x);
      when (r) { is Ok<Int, Bad> -> new Ok<Int, Bad>(r.value + 1); else -> r; }
    }

## Runners

Each sums the steps for `n` inputs, with 0 for a failure.

    export let runBubble(n: Int, failMille: Int): Int {
      var sum = 0;
      for (var i = 0; i < n; i += 1) {
        let x = inputAt(i, failMille);
        sum += stepBubble(x) orelse 0;
      }
      sum
    }

    export let runNull(n: Int, failMille: Int): Int {
      var sum = 0;
      for (var i = 0; i < n; i += 1) {
        let x = inputAt(i, failMille);
        sum += stepNull(x) ?? 0;
      }
      sum
    }

    export let runResult(n: Int, failMille: Int): Int {
      var sum = 0;
      for (var i = 0; i < n; i += 1) {
        let x = inputAt(i, failMille);
        let r = stepResult(x);
        sum += when (r) { is Ok<Int, Bad> -> r.value; else -> 0; };
      }
      sum
    }

    export let runBubble5(n: Int, failMille: Int): Int {
      var sum = 0;
      for (var i = 0; i < n; i += 1) {
        let x = inputAt(i, failMille);
        sum += b5(x) orelse 0;
      }
      sum
    }

    export let runNull5(n: Int, failMille: Int): Int {
      var sum = 0;
      for (var i = 0; i < n; i += 1) {
        let x = inputAt(i, failMille);
        sum += n5(x) ?? 0;
      }
      sum
    }

    export let runResult5(n: Int, failMille: Int): Int {
      var sum = 0;
      for (var i = 0; i < n; i += 1) {
        let x = inputAt(i, failMille);
        let r = r5(x);
        sum += when (r) { is Ok<Int, Bad> -> r.value; else -> 0; };
      }
      sum
    }

## Agreement

    test("all variants agree") {
      for (let mille of [0, 1, 10, 100, 1000]) {
        let one = runNull(2000, mille);
        assert(runBubble(2000, mille) == one);
        assert(runResult(2000, mille) == one);
        let five = runNull5(2000, mille);
        assert(runBubble5(2000, mille) == five);
        assert(runResult5(2000, mille) == five);
      }
      assert(runNull(2000, 1000) == 0);
    }

    test("failures are at the given rate") {
      var failed = 0;
      for (var i = 0; i < 2000; i += 1) { if (inputAt(i, 10) < 0) { failed += 1 } }
      assert(failed == 20);
    }
