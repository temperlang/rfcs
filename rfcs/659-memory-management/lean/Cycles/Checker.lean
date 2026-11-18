import Cycles.Syntax

/-!
# The checker

An executable version of the RFC's Steps I–V for Stage 1.  It follows the
RFC's structure rather than its worklists: each fixed point is computed by
iterating once per node, which is slow but easy to reason about.
-/

namespace Cycles

inductive Node where
  /-- Values of a declared type, or of *AnyValue*. -/
  | ty (t : Ty)
  /-- Any class, in any library, that implements a non-sealed interface `t`. -/
  | fake (t : Ty)
  deriving DecidableEq, Repr, Inhabited

def Node.type : Node → Ty
  | .ty t => t
  | .fake t => t

def Node.isFake : Node → Bool
  | .fake _ => true
  | .ty _ => false

inductive EdgeKind where
  | hasA (early : Bool)
  | canBeA
  deriving DecidableEq, Repr, Inhabited

structure Edge where
  src : Node
  dst : Node
  kind : EdgeKind
  label : String
  /-- Added by Step V from a fake class to a forbidden type; diagrams of cycles omit it. -/
  onlyForForbids : Bool := false
  deriving DecidableEq, Repr, Inhabited

def reverseEdges (es : List Edge) : List Edge :=
  es.map fun e => { e with src := e.dst, dst := e.src }

def allNodes (p : Program) : List Node :=
  (p.map fun d => Node.ty (.named d.name)) ++ [Node.ty .anyValue] ++
    (p.filter fun d => d.kind == DeclKind.iface false).map (fun d => Node.fake (.named d.name)) ++
    [Node.fake .anyValue]

/-- Steps I and II for one declaration: has-a edges and can-be-a edges. -/
def declEdges (p : Program) (d : Decl) : List Edge :=
  let src := Node.ty (.named d.name)
  match d.kind with
  | .cls => d.props.map fun q =>
      ({ src := src, dst := .ty q.type, kind := .hasA (q.kind == PropKind.early),
         label := "." ++ q.name } : Edge)
  | .iface true => (p.filter fun e => e.supers.contains d.name).map fun e =>
      ({ src := src, dst := .ty (.named e.name), kind := .canBeA, label := "can-be-a" } : Edge)
  | .iface false =>
      [{ src := src, dst := .fake (.named d.name), kind := .canBeA, label := "can-be-a" }]

/-- The drop-order graph for `main`, before pruning. -/
def edgesFor (p : Program) (main : String) : List Edge :=
  let anyEdge : Edge :=
    { src := .ty .anyValue, dst := .fake .anyValue, kind := .canBeA, label := "can-be-a" }
  let fakeEdges := ((allNodes p).filter (·.isFake)).map fun n =>
    ({ src := n, dst := .ty (.named main), kind := .hasA false, label := ".x" } : Edge)
  p.flatMap (declEdges p) ++ anyEdge :: fakeEdges

def reachStep (edges : List Edge) (seen : List Node) : List Node :=
  dedup (seen ++ (edges.filter fun e => seen.contains e.src).map (·.dst))

/-- Nodes reachable from `start` by at least one edge, if `fuel` is enough. -/
def reachFrom (edges : List Edge) (fuel : Nat) (start : Node) : List Node :=
  (List.range fuel).foldl (fun seen _ => reachStep edges seen)
    (dedup ((edges.filter fun e => e.src == start).map (·.dst)))

/--
Whether `reachFrom` reached its fixed point.  The checker fails if not, so
proofs can use the fixed point without an argument that `fuel` is enough.
-/
def reachConverged (edges : List Edge) (fuel : Nat) (start : Node) : Bool :=
  let r := reachFrom edges fuel start
  reachStep edges r == r

/--
Whether `n`'s own or inherited clauses forbid `f`.  mainType's own clauses
don't count; Step V is what checks them.
-/
def declares (p : Program) (main : String) (n : Node) (f : String) : Bool :=
  n != Node.ty (.named main) &&
    (match n.type with
     | .named m => (p.forbidsOf m).any fun g => p.isSubtype (.named f) (.named g)
     | .anyValue => false)

/--
Step III's "always": the greatest set of nodes reachable from mainNode, not
including it, such that each either declares `f` or has edges only from
members.
-/
def alwaysStep (p : Program) (main : String) (edges : List Edge) (live : List Node)
    (f : String) (s : List Node) : List Node :=
  s.filter fun n =>
    declares p main n f ||
      edges.all fun e => !(e.dst == n && live.contains e.src && !s.contains e.src)

def alwaysForbidden (p : Program) (main : String) (edges : List Edge) (f : String) :
    List Node :=
  let mainNode := Node.ty (.named main)
  let fuel := (allNodes p).length + 1
  let reach := reachFrom edges fuel mainNode
  (List.range fuel).foldl (fun s _ => alwaysStep p main edges (mainNode :: reach) f s)
    (reach.filter (· != mainNode))

/-- Whether `alwaysForbidden` reached its fixed point, and its reachability did. -/
def alwaysConverged (p : Program) (main : String) (edges : List Edge) (f : String) :
    Bool :=
  let mainNode := Node.ty (.named main)
  let fuel := (allNodes p).length + 1
  let reach := reachFrom edges fuel mainNode
  let s := alwaysForbidden p main edges f
  reachConverged edges fuel mainNode && alwaysStep p main edges (mainNode :: reach) f s == s

structure Result where
  /-- Step IV: non-early has-a edges on cycles through mainNode. -/
  cycleEdges : List Edge
  /-- Step V: has-a edges that could point to a forbidden type. -/
  mismatches : List (String × Edge)
  /-- Every fixed point was reached within its fuel. -/
  converged : Bool
  deriving Repr

def Result.ok (r : Result) : Bool :=
  r.converged && r.cycleEdges.isEmpty && r.mismatches.isEmpty

def fuelFor (p : Program) : Nat := (allNodes p).length + 1

/-- Step III: the graph with fake classes' edges pruned where mainType is always forbidden. -/
def prunedEdges (p : Program) (main : String) : List Edge :=
  let edges0 := edgesFor p main
  let alwaysMain := alwaysForbidden p main edges0 main
  edges0.filter fun e => !(e.src.isFake && alwaysMain.contains e.src)

/-- Step V's edges from each fake class to each type mainType forbids. -/
def fakeForbidsEdgesFor (p : Program) (main : String) : List Edge :=
  ((allNodes p).filter (·.isFake)).flatMap fun n => (p.forbidsOf main).map fun f =>
    { src := n, dst := .ty (.named f), kind := .hasA false, label := ".x",
      onlyForForbids := true }

/-- Step V: has-a edges on paths from mainNode that could point to an `f`. -/
def stepVBad (p : Program) (main : String) (extra : List Edge) (f : String) : List Edge :=
  let mainNode := Node.ty (.named main)
  let edgesV := prunedEdges p main ++ extra
  let fwdV := reachFrom edgesV (fuelFor p) mainNode
  let always := alwaysForbidden p main (edgesFor p main ++ extra) f
  edgesV.filter fun e =>
    match e.kind with
    | .hasA _ =>
      (e.src == mainNode || fwdV.contains e.src) && !always.contains e.src &&
        p.mayBeA e.dst.type f
    | .canBeA => false

/--
`fakeForbidsEdges` adds Step V's edges from fake classes to forbidden types;
turning it off gives the checker as it was before them, for comparison.
-/
def check (p : Program) (main : String) (fakeForbidsEdges : Bool := true) : Result :=
  let mainNode := Node.ty (.named main)
  let fuel := fuelFor p
  let edges0 := edgesFor p main
  let edges := prunedEdges p main
  -- Step IV
  let fwd := reachFrom edges fuel mainNode
  let back := reachFrom (reverseEdges edges) fuel mainNode
  let fromMain (u : Node) : Bool := u == mainNode || fwd.contains u
  let toMain (v : Node) : Bool := v == mainNode || back.contains v
  let cycleEdges := edges.filter fun e =>
    e.kind == EdgeKind.hasA false && fromMain e.src && toMain e.dst
  -- Step V
  let forbidden := p.forbidsOf main
  let extra : List Edge := if fakeForbidsEdges then fakeForbidsEdgesFor p main else []
  let mismatches : List (String × Edge) :=
    if !cycleEdges.isEmpty then [] else
      forbidden.flatMap fun f => (stepVBad p main extra f).map fun e => (f, e)
  let converged :=
    alwaysConverged p main edges0 main &&
      reachConverged edges fuel mainNode &&
      reachConverged (reverseEdges edges) fuel mainNode &&
      reachConverged (edges ++ extra) fuel mainNode &&
      forbidden.all fun f => alwaysConverged p main (edges0 ++ extra) f
  { cycleEdges := cycleEdges, mismatches := mismatches, converged := converged }

/-- Every class passes. -/
def Program.passes (p : Program) (fakeForbidsEdges : Bool := true) : Bool :=
  p.all fun d => d.kind != DeclKind.cls || (check p d.name fakeForbidsEdges).ok

end Cycles
