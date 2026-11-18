import Cycles.Generic.Syntax

/-!
# The checker, with type formals

Nodes are types over mainType's type formals: a property's type in the
context of the node it belongs to, a type formal, a sealed interface's
sub-type, or a fake class for a non-sealed interface or *AnyValue*.  A type
formal has can-be-a edges to its `extends` bounds, or to *AnyValue* if it
has none.

The same machinery checks type phrases (`phraseOk`): a type argument meets
a `forbids` bound if it can't be the forbidden type (`mayBeA`) and, in a
graph from the argument, no has-a edge can point to one (`pointsTo`).
There, unlike for mainType, the argument's own clauses count.
-/

namespace Cycles.Generic

open Cycles (PropKind DeclKind dedup)

inductive Node where
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
  onlyForForbids : Bool := false
  deriving DecidableEq, Repr, Inhabited

def reverseEdges (es : List Edge) : List Edge :=
  es.map fun e => { e with src := e.dst, dst := e.src }

/-- Fuel for exploring a graph: at most this many rounds of new nodes. -/
def exploreFuel : Nat := 40

/--
Matches a declaration's super-type arguments, `pat`, against a type's,
binding the declaration's type formals.
-/
def matchSuper (p : Program) (env : Env) (d : Decl) (pat args : List Ty) :
    Option (List (String × Ty)) :=
  if pat.length != args.length then none else
    (pat.zip args).foldlM (init := []) fun σ (b, a) =>
      match b with
      | .param x => if d.formals.any (·.name == x) then some ((x, a) :: σ) else none
      | _ => if p.compat env b a then some σ else none

/--
How Step II handles nodes that are other instantiations of mainType's class,
like `C<Str>` in `C<T>`'s graph.
-/
inductive Instances where
  /-- As the RFC first had it: like any other node. -/
  | rfc
  /-- Step IV treats them as mainNode.  (For comparison with `edges`.) -/
  | mainLike
  /-- Each gets a can-be-a edge to mainNode, like `C<Str>` to `C<T>` for `T = Str`. -/
  | edges
  deriving DecidableEq, Repr

/--
The can-be-a edge from a node that could be mainType, for some binding of
mainType's type formals, to mainNode, labelled with the binding.
-/
def instanceEdge (p : Program) (env : Env) (main : Ty) (n : Node) : List Edge :=
  match n, main with
  | .ty t@(.named c args), .named m margs =>
    if c == m && t != main && p.compat env t main then
      let binding := (margs.zip args).filterMap fun (x, a) =>
        if x == a then none else some (x.toStr ++ " = " ++ a.toStr)
      [{ src := n, dst := .ty main, kind := .canBeA,
         label := "can-be-a (" ++ ", ".intercalate binding ++ ")" }]
    else []
  | _, _ => []

/-- Edges out of a node.  `main` is mainType, for fake classes' `.x` edges. -/
def outEdges (p : Program) (env : Env) (main : Option Ty) (instances : Instances)
    (n : Node) : List Edge :=
  (match main with
   | some m => if instances == .edges then instanceEdge p env m n else []
   | none => []) ++
  match n with
  | .ty t =>
    match t with
    | .named c args =>
      match p.lookup c with
      | some d =>
        match d.kind with
        | .cls => d.props.map fun q =>
            { src := n, dst := .ty (q.type.subst (ctx d args)),
              kind := .hasA (q.kind == PropKind.early), label := "." ++ q.name }
        | .iface true => p.flatMap fun e => e.supers.filterMap fun s =>
            match s with
            | .named i pat =>
              if i == c then
                (matchSuper p env e pat args).map fun σ =>
                  { src := n,
                    dst := .ty (.named e.name (e.formals.map fun x => (σ.lookup x.name).getD .anyValue)),
                    kind := .canBeA, label := "can-be-a" }
              else none
            | _ => none
        | .iface false => [{ src := n, dst := .fake t, kind := .canBeA, label := "can-be-a" }]
      | none => []
    | .anyValue => [{ src := n, dst := .fake .anyValue, kind := .canBeA, label := "can-be-a" }]
    | .param x =>
      let bs := boundsOf env x
      (if bs.isEmpty then [Ty.anyValue] else bs).map fun b =>
        { src := n, dst := .ty b, kind := .canBeA, label := "can-be-a" }
  | .fake _ =>
    match main with
    | some m => [{ src := n, dst := .ty m, kind := .hasA false, label := ".x" }]
    | none => []

/-- The nodes `roots` reach, all their edges, and whether that converged within the fuel. -/
def explore (p : Program) (env : Env) (main : Option Ty) (roots : List Node)
    (instances : Instances := .edges) : List Node × List Edge × Bool :=
  let out := outEdges p env main instances
  let step (ns : List Node) := dedup (ns ++ (ns.flatMap out).map (·.dst))
  let ns := (List.range exploreFuel).foldl (fun ns _ => step ns) (dedup roots)
  (ns, ns.flatMap out, step ns == ns)

def reachStep (edges : List Edge) (seen : List Node) : List Node :=
  dedup (seen ++ (edges.filter fun e => seen.contains e.src).map (·.dst))

/-- Nodes reachable from any of `starts` by at least one edge. -/
def reachFromAll (edges : List Edge) (starts : List Node) : List Node :=
  (List.range (edges.length + 1)).foldl (fun s _ => reachStep edges s)
    (dedup ((edges.filter (starts.contains ·.src)).map (·.dst)))

/-- Nodes reachable from `start` by at least one edge. -/
def reachFrom (edges : List Edge) (start : Node) : List Node := reachFromAll edges [start]

/--
"Always": the greatest set of nodes, among `start` and those it reaches,
each of which declares the forbidden type, or isn't `start` and has edges
only from members.  So `start` is a member only if it declares it.
-/
def alwaysForbidden (edges : List Edge) (start : Node) (declares : Node → Bool) : List Node :=
  let live := start :: reachFrom edges start
  let init := dedup (live.filter fun n => declares n || n != start)
  let step (s : List Node) := s.filter fun n =>
    declares n || (n != start &&
      edges.all fun e => !(e.dst == n && live.contains e.src && !s.contains e.src))
  (List.range (init.length + 1)).foldl (fun s _ => step s) init

/-- Whether the node's own or inherited clauses forbid `f`. -/
def declaresTy (p : Program) (env : Env) (n : Node) (f : Ty) : Bool :=
  match n.type with
  | .named .. => (p.forbidsOf n.type).any fun g => p.isSubtype env f g
  | .param x => (formalForbids env x).any fun g => p.isSubtype env f g
  | .anyValue => false

/-- Has-a edges from `start` or nodes it reaches, not "always" forbidding `f`, that can point to an `f`. -/
def badEdges (p : Program) (env : Env) (edges : List Edge) (start : Node)
    (always : List Node) (f : Ty) : List Edge :=
  let live := start :: reachFrom edges start
  edges.filter fun e =>
    match e.kind with
    | .hasA _ => live.contains e.src && !always.contains e.src && p.mayBeA env e.dst.type f
    | .canBeA => false

/-- Step V's edges from each fake class to each forbidden type. -/
def fakeForbidsEdges (nodes : List Node) (forbidden : List Ty) : List Edge :=
  (nodes.filter (·.isFake)).flatMap fun n => forbidden.map fun f =>
    { src := n, dst := .ty f, kind := .hasA false, label := ".x", onlyForForbids := true }

/--
Whether a value of type `s` might point to a `g`: a graph from `s`, where
fake classes have only edges to `g`, has a has-a edge that can point to a
`g` from a node that doesn't always forbid it.  `s`'s own clauses count.
Also true if the graph doesn't converge.
-/
def pointsTo (p : Program) (env : Env) (s g : Ty) : Bool :=
  let (nodes, edges0, conv) := explore p env none [.ty s]
  let edges := edges0 ++ fakeForbidsEdges nodes [g]
  let always := alwaysForbidden edges (.ty s) (fun n => declaresTy p env n g)
  !conv || !(badEdges p env edges (.ty s) always g).isEmpty

/--
A type argument meets a `forbids` bound: it isn't a subtype of the forbidden
type, its values can't be one, and they don't point to one.  The first
matters even for a type with no values, since `canBind` relies on it.
-/
def argForbidsOk (p : Program) (env : Env) (a g : Ty) : Bool :=
  !p.isSubtype env a g && !p.mayBeA env a g && !pointsTo p env a g

/-- A type phrase is valid in `env`: its type arguments meet their formals' bounds. -/
def phraseOk (p : Program) (env : Env) : Ty → Bool
  | .anyValue => true
  | .param x => (formalOf env x).isSome
  | .named n args =>
    args.attach.all (fun ⟨a, _⟩ => phraseOk p env a) &&
      match p.lookup n with
      | none => false
      | some d =>
        d.formals.length == args.length &&
          (d.formals.zip args).all fun (x, a) =>
            let σ := ctx d args
            x.bounds.all (fun b => p.isSubtype env a (b.subst σ)) &&
              x.forbids.all fun g => argForbidsOk p env a (g.subst σ)

/-- Every type phrase in the declarations that values are stored under or are. -/
def phrasesOk (p : Program) : Bool :=
  p.all fun d =>
    let env := d.formals
    d.props.all (fun q => phraseOk p env q.type) && d.supers.all (phraseOk p env) &&
      d.formals.all fun x => x.bounds.all (phraseOk p env)

structure Result where
  cycleEdges : List Edge
  mismatches : List (Ty × Edge)
  converged : Bool
  deriving Repr

def Result.ok (r : Result) : Bool :=
  r.converged && r.cycleEdges.isEmpty && r.mismatches.isEmpty

def mainTypeOf (d : Decl) : Ty := .named d.name (d.formals.map fun x => .param x.name)

/--
Steps I–V for class `c`.  `withFakeForbidsEdges` is as in Stage 1.

A run-time cycle through a `C<A>` maps into `C<T>`'s graph with `T` bound
to `A`, starting at mainNode, but may come back to a node like `C<Str>`
rather than to `C<T>`, as for `class C<T>(public var c: C<Str>?)`.  So by
default (`instances := .edges`), Step II gives each node that could be
mainType a can-be-a edge to mainNode, and Step IV finds such cycles like
any other.
-/
def check (p : Program) (c : String) (withFakeForbidsEdges : Bool := true)
    (instances : Instances := .edges) : Result :=
  match p.lookup c with
  | none => { cycleEdges := [], mismatches := [], converged := false }
  | some d =>
    let env := d.formals
    let mainTy := mainTypeOf d
    let mainNode := Node.ty mainTy
    let (nodes, edges0, conv) := explore p env (some mainTy) [mainNode] instances
    -- Step III
    let alwaysMain := alwaysForbidden edges0 mainNode
      (fun n => n != mainNode && declaresTy p env n mainTy)
    let edges := edges0.filter fun e => !(e.src.isFake && alwaysMain.contains e.src)
    -- Step IV
    let isMain (n : Node) : Bool :=
      n == mainNode ||
        (instances == .mainLike && match n with
          | .ty t => t.head? == some c && p.compat env t mainTy
          | .fake _ => false)
    let mains := nodes.filter isMain
    let fwd := reachFrom edges mainNode
    let back := reachFromAll (reverseEdges edges) mains
    let cycleEdges := edges.filter fun e =>
      e.kind == EdgeKind.hasA false && (e.src == mainNode || fwd.contains e.src) &&
        (isMain e.dst || back.contains e.dst)
    -- Step V
    let forbidden := p.forbidsOf mainTy
    let extra := if withFakeForbidsEdges then fakeForbidsEdges nodes forbidden else []
    let mismatches : List (Ty × Edge) :=
      if !cycleEdges.isEmpty then [] else
        forbidden.flatMap fun f =>
          let always := alwaysForbidden (edges0 ++ extra) mainNode
            (fun n => n != mainNode && declaresTy p env n f)
          (badEdges p env (edges ++ extra) mainNode always f).map fun e => (f, e)
    { cycleEdges := cycleEdges, mismatches := mismatches, converged := conv }

/-- Every class passes, and every type phrase is valid. -/
def Program.passes (p : Program) (withFakeForbidsEdges : Bool := true)
    (instances : Instances := .edges) : Bool :=
  phrasesOk p &&
    p.all fun d =>
      d.kind != DeclKind.cls || (check p d.name withFakeForbidsEdges instances).ok

end Cycles.Generic
