import Cycles.Generic.Checker

/-!
# Run-time semantics, with type formals

As in Stage 1, but each object has a ground type, `C<A>`, and its
properties' types are in that type's context.  `new` only makes objects of
valid types (`phraseOk`): a type a program can mention has passed the type
phrase check, and a generic function's type arguments meet their bounds.
-/

namespace Cycles.Generic

open Cycles (PropKind DeclKind dedup)

structure Obj where
  ty : Ty
  fields : List (String × Option Nat)
  deriving DecidableEq, Repr, Inhabited

abbrev Heap := List Obj

inductive Step where
  | new (t : Ty) (early : List (String × Option Nat))
  | set (obj : Nat) (field : String) (val : Option Nat)
  deriving DecidableEq, Repr

def valueOk (p : Program) (h : Heap) (t : Ty) (nullable : Bool) : Option Nat → Bool
  | none => nullable
  | some a =>
    match h[a]? with
    | some o => p.isSubtype [] o.ty t
    | none => false

def lookupField (fs : List (String × Option Nat)) (n : String) : Option (Option Nat) :=
  (fs.find? (·.1 == n)).map (·.2)

def isEarlyName (d : Decl) (n : String) : Bool :=
  d.props.any fun q => q.name == n && q.kind == PropKind.early

/-- The class declaration and type arguments of a ground class type. -/
def classOf (p : Program) : Ty → Option (Decl × List Ty)
  | .named c args =>
    match p.lookup c with
    | some d => if d.kind == DeclKind.cls then some (d, args) else none
    | none => none
  | _ => none

/-- `checkPhrase := false` skips `phraseOk`, for callers that only make valid types. -/
def applyNew (p : Program) (h : Heap) (t : Ty) (args : List (String × Option Nat))
    (checkPhrase : Bool := true) : Option Heap :=
  match classOf p t with
  | none => none
  | some (d, targs) =>
    let σ := ctx d targs
    let ok := t.isGround && (!checkPhrase || phraseOk p [] t) &&
      args.all (fun a => isEarlyName d a.1) &&
      d.props.all fun q =>
        q.kind != PropKind.early ||
          match lookupField args q.name with
          | some v => valueOk p h (q.type.subst σ) q.nullable v
          | none => false
    if ok then
      some (h ++ [{ ty := t,
                    fields := d.props.map fun q =>
                      (q.name, if q.kind == PropKind.early then (lookupField args q.name).getD none
                               else none) }])
    else none

def setField (o : Obj) (f : String) (v : Option Nat) : Obj :=
  { o with fields := o.fields.map fun x => if x.1 == f then (x.1, v) else x }

def applySet (p : Program) (h : Heap) (a : Nat) (f : String) (v : Option Nat) : Option Heap :=
  match h[a]? with
  | none => none
  | some o =>
    match classOf p o.ty with
    | none => none
    | some (d, targs) =>
      match d.props.find? (·.name == f) with
      | none => none
      | some q =>
        let ok := !isEarlyName d q.name &&
          (match q.kind with
           | .early => false
           | .setOnce => lookupField o.fields q.name == some none
           | .var => true) &&
          valueOk p h (q.type.subst (ctx d targs)) q.nullable v
        if ok then some (h.set a (setField o f v)) else none

def apply (p : Program) (h : Heap) (checkPhrase : Bool := true) : Step → Option Heap
  | .new t args => applyNew p h t args checkPhrase
  | .set a f v => applySet p h a f v

def succs (h : Heap) (a : Nat) : List Nat :=
  match h[a]? with
  | some o => o.fields.filterMap (·.2)
  | none => []

def reachableAddrs (h : Heap) (a : Nat) : List Nat :=
  (List.range (h.length + 1)).foldl
    (fun seen _ => dedup (seen ++ seen.flatMap (succs h)))
    (succs h a)

def acyclic (h : Heap) : Bool :=
  (List.range h.length).all fun a => !(reachableAddrs h a).contains a

end Cycles.Generic
