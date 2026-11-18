import Cycles

/-!
`lake exe search [trials] [depth] [seed] [new|old|ext] [classes] [interfaces]`

With `old`, uses the checker without Step V's edges from fake classes.  With
`ext`, tests separate compilation: see `extensionTrials`.
Programs have 3 classes and 2 interfaces unless given.

Checks a few hand-written programs, then generates random programs and,
for each one that passes the checker, searches step sequences of up to
`depth` steps for a cycle.
-/

open Cycles

/-- `class Node(public var next: Node?)`: fails the checker, and makes a cycle. -/
def selfLoop : Program :=
  [{ name := "Node", kind := .cls,
     props := [{ name := "next", type := .named "Node", nullable := true, kind := .var }] }]

/-- An immutable cons list of strings: passes, and makes no cycle. -/
def consList : Program :=
  [{ name := "Str", kind := .cls },
   { name := "Cons", kind := .cls,
     props := [{ name := "head", type := .named "Str", kind := .early },
               { name := "tail", type := .named "Cons", nullable := true, kind := .early }] }]

/-- The RFC's `MessagePlugin` example, with a `var` list of plugins. -/
def messager : Program :=
  [{ name := "MessagePlugin", kind := .iface false, forbids := ["Messager"] },
   { name := "Messager", kind := .cls,
     props := [{ name := "plugins", type := .named "MessagePlugin", nullable := true,
                 kind := .var }] }]

/--
`class C(public i: I?) forbids Z`, with `I` open and forbidding `C`.  Some
other library's implementation of `I` could point to a `Z`, so `C` should
fail, and only does with Step V's fake-class edges.
-/
def openForbids : Program :=
  [{ name := "Z", kind := .cls },
   { name := "I", kind := .iface false, forbids := ["C"] },
   { name := "C", kind := .cls, forbids := ["Z"],
     props := [{ name := "i", type := .named "I", nullable := true, kind := .early }] }]

def flipCoin : IO Bool := do
  pure ((← IO.rand 0 1) == 1)

def randPick {α : Type} [Inhabited α] (xs : List α) : IO α := do
  pure xs[(← IO.rand 0 (xs.length - 1))]!

def randKind : IO PropKind := randPick [.early, .setOnce, .var]

def randForbids (names : List String) : IO (List String) := do
  if (← IO.rand 0 2) == 0 then
    pure [← randPick names]
  else
    pure []

/--
`nClasses` classes `C0`, `C1`, ... and `nIfaces` interfaces `I0`, `I1`, ...;
an interface may extend earlier ones.
-/
def randProgram (nClasses nIfaces : Nat) : IO Program := do
  let ifaces := (List.range nIfaces).map (s!"I{·}")
  let classes := (List.range nClasses).map (s!"C{·}")
  let names := classes ++ ifaces
  let tys : List Ty := .anyValue :: names.map Ty.named
  let mut p : Program := []
  for k in List.range nIfaces do
    let sealed ← flipCoin
    let supers ← (ifaces.take k).filterM fun _ => do pure ((← IO.rand 0 2) == 0)
    let forbids ← randForbids names
    p := p ++ [({ name := s!"I{k}", kind := .iface sealed, supers := supers,
                  forbids := forbids } : Decl)]
  for c in classes do
    let supers ← ifaces.filterM fun _ => do pure ((← IO.rand 0 2) == 0)
    let mut props : List Property := []
    for k in List.range (← IO.rand 0 2) do
      let q : Property :=
        { name := s!"p{k}", type := (← randPick tys), nullable := (← flipCoin),
          kind := (← randKind) }
      props := props ++ [q]
    let forbids ← randForbids names
    p := p ++ [({ name := c, kind := .cls, supers := supers, props := props,
                  forbids := forbids } : Decl)]
  pure p

/--
Another library on top of `p`: classes `D0`, ... and interfaces `J0`, ...,
which may extend `p`'s non-sealed interfaces.
-/
def randExtension (p : Program) (nClasses nIfaces : Nat) : IO Program := do
  let ifaces := (List.range nIfaces).map (s!"J{·}")
  let classes := (List.range nClasses).map (s!"D{·}")
  let openInP := (p.filter fun d => d.kind == DeclKind.iface false).map (·.name)
  let names := p.map (·.name) ++ classes ++ ifaces
  let tys : List Ty := .anyValue :: names.map Ty.named
  let mut q : Program := []
  for k in List.range nIfaces do
    let sealed ← flipCoin
    let supers ← (openInP ++ ifaces.take k).filterM fun _ => do pure ((← IO.rand 0 2) == 0)
    let forbids ← randForbids names
    q := q ++ [({ name := s!"J{k}", kind := .iface sealed, supers := supers,
                  forbids := forbids } : Decl)]
  for c in classes do
    let supers ← (openInP ++ ifaces).filterM fun _ => do pure ((← IO.rand 0 2) == 0)
    let mut props : List Property := []
    for k in List.range (← IO.rand 0 2) do
      let prop : Property :=
        { name := s!"p{k}", type := (← randPick tys), nullable := (← flipCoin),
          kind := (← randKind) }
      props := props ++ [prop]
    let forbids ← randForbids names
    q := q ++ [({ name := c, kind := .cls, supers := supers, props := props,
                  forbids := forbids } : Decl)]
  pure q

/--
For programs `p` that pass, adds a random extension `q` and checks that
`p`'s classes still pass in `p ++ q`, and, if `q`'s classes pass too, that
`p ++ q` makes no cycle.
-/
def extensionTrials (trials depth nClasses nIfaces : Nat) : IO UInt32 := do
  let mut tried := 0
  let mut bothPass := 0
  for _ in List.range trials do
    let p ← randProgram nClasses nIfaces
    if p.wellFormed && p.passes then
      let q ← randExtension p 2 1
      let pq := p ++ q
      if pq.wellFormed && p.extendsOk q then
        tried := tried + 1
        for d in p do
          if d.kind == DeclKind.cls && (check pq d.name).ok != (check p d.name).ok then
            IO.println s!"Check changed for {d.name}:\n{repr p}\n{repr q}"
            return 1
        if pq.passes then
          bothPass := bothPass + 1
          if let some steps := findCycle pq depth [] [] then
            IO.println s!"Counterexample:\n{repr p}\n{repr q}\n{repr steps}"
            return 1
  IO.println s!"{tried} passing programs extended; checks unchanged.  \
    {bothPass} extensions passed; no cycles within {depth} steps."
  return 0

def report (name : String) (p : Program) (depth : Nat) : IO Unit := do
  let results := (p.filter fun d => d.kind == DeclKind.cls).map fun d =>
    (d.name, (check p d.name).ok)
  IO.println s!"{name}: passes {results}, cycle {repr (findCycle p depth [] [])}"

def main (args : List String) : IO UInt32 := do
  let trials := (args[0]? >>= String.toNat?).getD 500
  let depth := (args[1]? >>= String.toNat?).getD 3
  let seed := (args[2]? >>= String.toNat?).getD 1
  let fakeForbidsEdges := args[3]? != some "old"
  let nClasses := (args[4]? >>= String.toNat?).getD 3
  let nIfaces := (args[5]? >>= String.toNat?).getD 2
  IO.setRandSeed seed
  if args[3]? == some "ext" then
    return (← extensionTrials trials depth nClasses nIfaces)
  report "selfLoop" selfLoop depth
  report "consList" consList depth
  report "messager" messager depth
  IO.println s!"openForbids: C passes {(check openForbids "C").ok}, \
    {(check openForbids "C" (fakeForbidsEdges := false)).ok} without fake forbids edges"
  let mut passing := 0
  let mut failing := 0
  let mut failingWithCycles := 0
  for _ in List.range trials do
    let p ← randProgram nClasses nIfaces
    if p.wellFormed then
      let cycle := findCycle p depth [] []
      if p.passes fakeForbidsEdges then
        passing := passing + 1
        if let some steps := cycle then
          IO.println s!"Counterexample:\n{repr p}\n{repr steps}"
          return 1
      else
        failing := failing + 1
        if cycle.isSome then failingWithCycles := failingWithCycles + 1
  IO.println s!"{passing} of {trials} random programs passed; no cycles within {depth} steps."
  -- A sanity check that the search finds cycles when there are some.
  IO.println s!"Of the {failing} that failed, {failingWithCycles} made cycles within {depth} steps."
  return 0
