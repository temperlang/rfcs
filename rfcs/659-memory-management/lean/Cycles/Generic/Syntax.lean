import Cycles.Syntax

/-!
# Stage 2: type formals

Stage 1's language, plus type formals on classes and interfaces, with
`extends` and `forbids` bounds.  Types are invariant in their arguments.

A `forbids` clause on a type formal means that the formal neither binds to
nor points to the type: `<T forbids Y>` rules out type arguments whose values
might be a `Y`, or might point to one.  Type phrases are checked for that
(`Checker.lean`'s `phraseOk`), and the cycle checker relies on it.

Polymorphic recursion, as in `class N<T>(public n: N<Box<T>>?)`, makes a
graph without end.  The checker gives up on it, since its graph doesn't
converge within the fuel; Stage 3 would widen deep type arguments instead.
-/

namespace Cycles.Generic

open Cycles (PropKind DeclKind dedup)

/-- A type: a named class or interface with type arguments, *AnyValue*, or a type formal. -/
inductive Ty where
  | named (name : String) (args : List Ty)
  | anyValue
  | param (name : String)
  deriving Repr, Inhabited

mutual
def Ty.decEq : (a b : Ty) → Decidable (a = b)
  | .named n as, .named m bs =>
    if h : n = m then
      match Ty.decEqList as bs with
      | isTrue h' => isTrue (by rw [h, h'])
      | isFalse h' => isFalse (by intro e; cases e; exact h' rfl)
    else isFalse (by intro e; cases e; exact h rfl)
  | .anyValue, .anyValue => isTrue rfl
  | .param n, .param m =>
    if h : n = m then isTrue (by rw [h]) else isFalse (by intro e; cases e; exact h rfl)
  | .named .., .anyValue => isFalse (by intro e; cases e)
  | .named .., .param _ => isFalse (by intro e; cases e)
  | .anyValue, .named .. => isFalse (by intro e; cases e)
  | .anyValue, .param _ => isFalse (by intro e; cases e)
  | .param _, .named .. => isFalse (by intro e; cases e)
  | .param _, .anyValue => isFalse (by intro e; cases e)
def Ty.decEqList : (as bs : List Ty) → Decidable (as = bs)
  | [], [] => isTrue rfl
  | a :: as, b :: bs =>
    match Ty.decEq a b, Ty.decEqList as bs with
    | isTrue h1, isTrue h2 => isTrue (by rw [h1, h2])
    | isFalse h1, _ => isFalse (by intro e; cases e; exact h1 rfl)
    | _, isFalse h2 => isFalse (by intro e; cases e; exact h2 rfl)
  | [], _ :: _ => isFalse (by intro e; cases e)
  | _ :: _, [] => isFalse (by intro e; cases e)
end

instance : DecidableEq Ty := Ty.decEq

/-- Replaces type formal references. -/
def Ty.subst (σ : List (String × Ty)) : Ty → Ty
  | .named n args => .named n (args.attach.map fun ⟨a, _⟩ => a.subst σ)
  | .anyValue => .anyValue
  | .param n => (σ.lookup n).getD (.param n)

/-- Mentions no type formal. -/
def Ty.isGround : Ty → Bool
  | .named _ args => args.attach.all fun ⟨a, _⟩ => a.isGround
  | .anyValue => true
  | .param _ => false

/-- The type formals it mentions. -/
def Ty.params : Ty → List String
  | .named _ args => args.attach.flatMap fun ⟨a, _⟩ => a.params
  | .anyValue => []
  | .param n => [n]

/-- The named types it mentions, with their arities. -/
def Ty.names : Ty → List (String × Nat)
  | .named n args => (n, args.length) :: args.attach.flatMap fun ⟨a, _⟩ => a.names
  | _ => []

/-- For edge labels: `C<A, B>`. -/
def Ty.toStr : Ty → String
  | .named n [] => n
  | .named n args => n ++ "<" ++ ", ".intercalate (args.attach.map fun ⟨a, _⟩ => a.toStr) ++ ">"
  | .anyValue => "AnyValue"
  | .param n => n

def Ty.head? : Ty → Option String
  | .named n _ => some n
  | _ => none

structure Formal where
  name : String
  /-- `extends` bounds; named types. -/
  bounds : List Ty := []
  /-- Types that the formal neither binds to nor points to. -/
  forbids : List Ty := []
  deriving DecidableEq, Repr, Inhabited

structure Property where
  name : String
  type : Ty
  nullable : Bool := false
  kind : PropKind
  deriving DecidableEq, Repr, Inhabited

structure Decl where
  name : String
  kind : DeclKind
  formals : List Formal := []
  /-- Interfaces it directly extends, over its type formals. -/
  supers : List Ty := []
  /-- Backed properties; only classes have them. -/
  props : List Property := []
  /-- Types that values of this type never point to, over its type formals. -/
  forbids : List Ty := []
  deriving DecidableEq, Repr, Inhabited

abbrev Program := List Decl

/-- The type formals in scope: mainType's, or a declaration's. -/
abbrev Env := List Formal

/-- Binds a declaration's type formals to arguments. -/
def ctx (d : Decl) (args : List Ty) : List (String × Ty) :=
  (d.formals.map (·.name)).zip args

/-- `$`-prefixed type formals stand for a class's own, while matching it against types. -/
def isVar (n : String) : Bool := n.startsWith "$"

def formalOf (env : Env) (n : String) : Option Formal := env.find? (·.name == n)

def boundsOf (env : Env) (n : String) : List Ty := ((formalOf env n).map (·.bounds)).getD []

def formalForbids (env : Env) (n : String) : List Ty :=
  ((formalOf env n).map (·.forbids)).getD []

namespace Program

def lookup (p : Program) (n : String) : Option Decl :=
  List.find? (fun d => d.name == n) p

def isClass (p : Program) (n : String) : Bool :=
  match p.lookup n with
  | some d => d.kind == DeclKind.cls
  | none => false

def supersOf (p : Program) : Ty → List Ty
  | .named n args =>
    match p.lookup n with
    | some d => d.supers.map (·.subst (ctx d args))
    | none => []
  | _ => []

/-- `t` and its super-types, with their arguments. -/
def ancestors (p : Program) (t : Ty) : List Ty :=
  (List.range (p.length + 1)).foldl (fun seen _ => dedup (seen ++ seen.flatMap p.supersOf)) [t]

/-- `a <: b`.  Type formals in `env` are rigid, but known by their bounds. -/
def isSubtype (p : Program) (env : Env) (a b : Ty) : Bool :=
  match a, b with
  | _, .anyValue => true
  | .anyValue, _ => false
  | .param x, _ => b == .param x || (boundsOf env x).any fun ub => (p.ancestors ub).contains b
  | .named .., _ => (p.ancestors a).contains b

/-- The `forbids` clauses of a named type, its own and inherited, in context. -/
def forbidsOf (p : Program) (t : Ty) : List Ty :=
  dedup ((p.ancestors t).flatMap fun a =>
    match a with
    | .named m margs =>
      match p.lookup m with
      | some dm => dm.forbids.map (·.subst (ctx dm margs))
      | none => []
    | _ => [])

/-- Whether a class from another library could be a value of `t`. -/
def openTo (p : Program) : Ty → Bool
  | .named n _ =>
    p.any fun d => d.kind == DeclKind.iface false &&
      (p.ancestors (.named d.name [])).any fun a => a.head? == some n
  | _ => true

/--
Whether type formal `x` could be bound to `s`.  A type formal can't be bound
to a subtype of a type it forbids; type phrases are checked for that.  Only
ground types are ruled out, which is conservative.
-/
def canBind (p : Program) (env : Env) (x : String) (s : Ty) : Bool :=
  !s.isGround || !((formalForbids env x).any fun g =>
    let g' := g.subst [(x, s)]
    g'.isGround && p.isSubtype [] s g')

mutual
/--
Whether two types could be the same type, for some binding of type formals.
`$` formals match anything.  Conservative: it doesn't check that a formal
used twice is bound the same way both times.
-/
def compat (p : Program) (env : Env) : Ty → Ty → Bool
  | .param x, b =>
    isVar x || (match b with
      | .param _ => true
      | _ => canBind p env x b)
  | a, .param y => isVar y || canBind p env y a
  | .anyValue, .anyValue => true
  | .named n as, .named m bs => n == m && compatList p env as bs
  | _, _ => false
def compatList (p : Program) (env : Env) : List Ty → List Ty → Bool
  | [], [] => true
  | a :: as, b :: bs => compat p env a b && compatList p env as bs
  | _, _ => false
end

/-- Binds a `$` formal, or checks it against its binding, loosely. -/
def bindVar (p : Program) (env : Env) (σ : List (String × Ty)) (x : String) (b : Ty) :
    Option (List (String × Ty)) :=
  match σ.lookup x with
  | none => some ((x, b) :: σ)
  | some b' => if p.compat env b' b then some σ else none

mutual
/--
Unifies two types, binding `$` formals consistently.  Other type formals
match whatever they could be bound to, as in `compat`.
-/
def unify (p : Program) (env : Env) (σ : List (String × Ty)) : Ty → Ty → Option (List (String × Ty))
  | .param x, b =>
    if isVar x then bindVar p env σ x b
    else match b with
      | .param y => if isVar y then bindVar p env σ y (.param x) else some σ
      | _ => if canBind p env x b then some σ else none
  | a, .param y =>
    if isVar y then bindVar p env σ y a
    else if canBind p env y a then some σ else none
  | .anyValue, .anyValue => some σ
  | .named n as, .named m bs => if n == m then unifyList p env σ as bs else none
  | _, _ => none
def unifyList (p : Program) (env : Env) (σ : List (String × Ty)) :
    List Ty → List Ty → Option (List (String × Ty))
  | [], [] => some σ
  | a :: as, b :: bs => (unify p env σ a b).bind fun σ' => unifyList p env σ' as bs
  | _, _ => none
end

/-- Whether some class in `p`, for some binding of its type formals, is a subtype of both. -/
def classOverlaps (p : Program) (env : Env) (t f : Ty) : Bool :=
  p.any fun d =>
    d.kind == DeclKind.cls &&
      (let ancs := p.ancestors (.named d.name (d.formals.map fun x => .param ("$" ++ x.name)))
       ancs.any fun a1 => ancs.any fun a2 =>
         ((p.unify env [] a1 t).bind fun σ => p.unify env σ a2 f).isSome)

/--
Whether a value of type `t` could be an `f`, for some binding of `env`'s
type formals that meets their bounds, in `p` or a later library.  A type
formal's values aren't of any type its `forbids` clauses cover.
-/
def mayBeAF (p : Program) (env : Env) : Nat → Ty → Ty → Bool
  | 0, _, _ => true
  | fuel + 1, t, f =>
    match t, f with
    | .anyValue, _ => true
    | _, .anyValue => true
    | .param x, _ =>
      !((formalForbids env x).any fun g => p.isSubtype env f g) &&
        (boundsOf env x).all fun b => mayBeAF p env fuel b f
    | _, .param y =>
      !((formalForbids env y).any fun g => p.isSubtype env t g) &&
        (boundsOf env y).all fun b => mayBeAF p env fuel t b
    | _, _ => p.classOverlaps env t f || (p.openTo t && p.openTo f)

def mayBeA (p : Program) (env : Env) (t f : Ty) : Bool := p.mayBeAF env 3 t f

/-- Every named type, with its arity, declared at that arity. -/
def namesOk (p : Program) (t : Ty) : Bool :=
  t.names.all fun (n, k) =>
    match p.lookup n with
    | some d => d.formals.length == k
    | none => false

/-- Names of `n`'s strict ancestors, if the fuel is enough. -/
def nameAncestors (p : Program) (n : String) : List String :=
  let step (s : List String) := dedup (s ++ s.flatMap fun m =>
    (((p.lookup m).map (·.supers)).getD []).filterMap (·.head?))
  (List.range (p.length + 1)).foldl (fun s _ => step s)
    ((((p.lookup n).map (·.supers)).getD []).filterMap (·.head?))

/--
Names are unique, and none is `$`-prefixed; type formals' names are unique
in each declaration, and their bounds are named types; only interfaces are
extended, and no declaration is its own ancestor; only classes have
properties; every type mentions only declared names, at their arities, and
its declaration's type formals.  A super-type that's a sealed interface has
each of the declaration's type formals as an argument, once, and ground
types otherwise, so the cycle checker can find the sub-type from the
super-type.
-/
def wellFormed (p : Program) : Bool :=
  let names := p.map (·.name)
  dedup names == names &&
    p.all fun d =>
      let fs := d.formals.map (·.name)
      let inScope (t : Ty) := p.namesOk t && t.params.all (fs.contains ·)
      !isVar d.name && dedup fs == fs && fs.all (!isVar ·) &&
        d.formals.all (fun x =>
          x.bounds.all (fun b => b.head?.isSome && inScope b) && x.forbids.all inScope) &&
        d.supers.all (fun s =>
          inScope s &&
          match s with
          | .named i args =>
            i != d.name &&
              (match p.lookup i with
               | some e =>
                 e.kind != DeclKind.cls &&
                   (e.kind != DeclKind.iface true ||
                     (args.all (fun a => a.isGround || a matches .param _) &&
                       let ps := args.flatMap (·.params)
                       dedup ps == ps && fs.all (ps.contains ·)))
               | none => false)
          | _ => false) &&
        !(p.nameAncestors d.name).contains d.name &&
        (d.kind == DeclKind.cls || d.props.isEmpty) &&
        d.props.all (fun q => inScope q.type) &&
        d.forbids.all inScope

end Program

end Cycles.Generic
