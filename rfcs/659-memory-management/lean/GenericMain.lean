import Cycles.Generic.Random

/-!
`lake exe search2 [trials] [depth] [seed] [new|old|rfc] [classes] [interfaces]`

`old` leaves out Step V's fake-class edges; `rfc` leaves out the can-be-a
edges from other instantiations of mainType's class (see `check`).

Stage 2's search: hand-written programs with type formals, then random
ones.  For each random program that passes, searches step sequences of up
to `depth` steps, making objects of the program's valid ground class types
with arguments up to depth two, for a cycle.
-/

open Cycles (PropKind DeclKind)
open Cycles.Generic

def T : Ty := .param "T"
def named (n : String) (args : List Ty := []) : Ty := .named n args

def str : Decl := { name := "Str", kind := .cls }

/-- `class Cell<T forbids Cell<T>>(public var v: T?)`: passes. -/
def cell : Program :=
  [str, { name := "Cell", kind := .cls,
          formals := [{ name := "T", forbids := [named "Cell" [T]] }],
          props := [{ name := "v", type := T, nullable := true, kind := .var }] }]

/-- `class Cell<T>(public var v: T?)`: fails, and `Cell<AnyValue>` can hold itself. -/
def cellNoForbids : Program :=
  [str, { name := "Cell", kind := .cls, formals := [{ name := "T" }],
          props := [{ name := "v", type := T, nullable := true, kind := .var }] }]

/--
The RFC's contextual example: `class C<T forbids Str>(public strs: Box<Str>)
forbids Box<T>`, with `class Box<T forbids Box<T>>(public v: T)`.  `Box` needs
its bound, like the RFC's core types, or a `Box<Cell<...>>` could hold a
`Cell` that holds the `Box`.  Passes, and fails
without the bound.
-/
def contextual (bound : Bool) : Program :=
  [str, { name := "Num", kind := .cls },
   { name := "Box", kind := .cls, formals := [{ name := "T", forbids := [named "Box" [T]] }],
     props := [{ name := "v", type := T, kind := .early }] },
   { name := "C", kind := .cls,
     formals := [{ name := "T", forbids := if bound then [named "Str"] else [] }],
     props := [{ name := "strs", type := named "Box" [named "Str"], kind := .early }],
     forbids := [named "Box" [T]] }]

/--
`class C<T>(public var c: C<Str>?)`: fails, but passes without the can-be-a
edge from `C<Str>` to `C<T>`, though a `C<Str>` can point to itself.
-/
def otherInstance : Program :=
  [str, { name := "C", kind := .cls, formals := [{ name := "T" }],
          props := [{ name := "c", type := named "C" [named "Str"], nullable := true,
                      kind := .var }] }]

/--
`interface Plugin<T> forbids Owner<T>` and `class Owner<T>(public var p: Plugin<T>?)`:
passes, since an implementation of `Plugin<T>` can't point back.
-/
def plugins : Program :=
  [str,
   { name := "Plugin", kind := .iface false, formals := [{ name := "T" }],
     forbids := [named "Owner" [T]] },
   { name := "Owner", kind := .cls, formals := [{ name := "T" }],
     props := [{ name := "p", type := named "Plugin" [T], nullable := true, kind := .var }] },
   { name := "Holder", kind := .cls, supers := [named "Plugin" [named "Str"]],
     props := [{ name := "s", type := named "Str", nullable := true, kind := .var }] }]

def report (name : String) (p : Program) (types : List Ty) (depth : Nat) : IO Unit := do
  let results := (p.filter fun d => d.kind == DeclKind.cls).map fun d =>
    (d.name, (check p d.name).ok)
  let valid := types.map fun t => (repr t |>.pretty, phraseOk p [] t)
  IO.println s!"{name}: wellFormed {p.wellFormed}, phrases {phrasesOk p}, passes {results}"
  IO.println s!"  valid: {valid}"
  IO.println s!"  cycle: {repr (findCycle p (groundClassTypes p) depth [] [])}"

def main (args : List String) : IO UInt32 := do
  let trials := (args[0]? >>= String.toNat?).getD 500
  let depth := (args[1]? >>= String.toNat?).getD 3
  let seed := (args[2]? >>= String.toNat?).getD 1
  let withFake := args[3]? != some "old"
  let instances : Instances := if args[3]? == some "rfc" then .rfc else .edges
  let nClasses := (args[4]? >>= String.toNat?).getD 3
  let nIfaces := (args[5]? >>= String.toNat?).getD 2
  IO.setRandSeed seed
  report "cell" cell [named "Cell" [.anyValue], named "Cell" [named "Str"],
    named "Cell" [named "Cell" [named "Str"]]] depth
  report "cellNoForbids" cellNoForbids [named "Cell" [.anyValue]] depth
  report "contextual" (contextual true) [named "C" [named "Num"], named "C" [named "Str"],
    named "C" [.anyValue],
    named "C" [named "Box" [named "Str"]]] depth
  report "contextual without bound" (contextual false) [] depth
  report "plugins" plugins [named "Owner" [named "Str"]] depth
  report "otherInstance" otherInstance [named "C" [named "Str"]] depth
  IO.println s!"  passes without instance edges: {(check otherInstance "C" true .rfc).ok}"
  let mut wellFormed := 0
  let mut passing := 0
  let mut failing := 0
  let mut failingWithCycles := 0
  for _ in List.range trials do
    let p ← randProgram nClasses nIfaces
    if p.wellFormed then
      wellFormed := wellFormed + 1
      let types := groundClassTypes p
      let cycle := findCycle p types depth [] []
      if p.passes withFake instances then
        passing := passing + 1
        if let some steps := cycle then
          IO.println s!"Counterexample:\n{repr p}\n{repr steps}"
          return 1
      else
        failing := failing + 1
        if cycle.isSome then failingWithCycles := failingWithCycles + 1
  IO.println s!"{wellFormed} of {trials} random programs well-formed; {passing} passed; \
    no cycles within {depth} steps."
  IO.println s!"Of the {failing} that failed, {failingWithCycles} made cycles within {depth} steps."
  return 0
