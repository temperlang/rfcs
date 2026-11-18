import Cycles.Syntax

/-!
# Run-time semantics

A heap is a list of objects; an object's address is its index, so a smaller
address is an older object.  Programs run as sequences of two kinds of step:
creating an object, and setting a property.

Set-once properties may be set at any time, not just while a constructor
runs.  That allows more heaps than Temper does, which is fine for a
soundness proof.  Non-early properties start unset, even when they aren't
nullable, since they're set after the object exists.
-/

namespace Cycles

structure Obj where
  cls : String
  fields : List (String × Option Nat)
  deriving DecidableEq, Repr, Inhabited

abbrev Heap := List Obj

inductive Step where
  /-- Create an instance of a class, giving values for its early properties. -/
  | new (cls : String) (early : List (String × Option Nat))
  /-- Set a set-once or `var` property. -/
  | set (obj : Nat) (field : String) (val : Option Nat)
  deriving DecidableEq, Repr

/-- Whether `v` may be stored in a property `q`. -/
def valueOk (p : Program) (h : Heap) (q : Property) : Option Nat → Bool
  | none => q.nullable
  | some a =>
    match h[a]? with
    | some o => p.isSubtype (.named o.cls) q.type
    | none => false

def lookupField (fs : List (String × Option Nat)) (n : String) : Option (Option Nat) :=
  (fs.find? (·.1 == n)).map (·.2)

/-- Whether a property named `n` is early.  Such properties are never set. -/
def isEarlyName (d : Decl) (n : String) : Bool :=
  d.props.any fun q => q.name == n && q.kind == PropKind.early

/-- The object that `new` makes from `args`. -/
def newObj (c : String) (d : Decl) (args : List (String × Option Nat)) : Obj :=
  { cls := c,
    fields := d.props.map fun q =>
      (q.name, if q.kind == PropKind.early then (lookupField args q.name).getD none else none) }

/-- Whether `new` may make an instance of `d` from `args`. -/
def newOk (p : Program) (h : Heap) (d : Decl) (args : List (String × Option Nat)) : Bool :=
  d.kind == DeclKind.cls &&
    args.all (fun a => isEarlyName d a.1) &&
    d.props.all fun q =>
      q.kind != PropKind.early ||
        match lookupField args q.name with
        | some v => valueOk p h q v
        | none => false

def applyNew (p : Program) (h : Heap) (c : String) (args : List (String × Option Nat)) :
    Option Heap :=
  match p.lookup c with
  | none => none
  | some d => if newOk p h d args then some (h ++ [newObj c d args]) else none

/-- Whether `q`, the first property of `o`'s class named `q.name`, may be set to `v`. -/
def setOk (p : Program) (h : Heap) (o : Obj) (d : Decl) (q : Property) (v : Option Nat) :
    Bool :=
  !isEarlyName d q.name &&
    (match q.kind with
     | .early => false
     | .setOnce => lookupField o.fields q.name == some none
     | .var => true) &&
    valueOk p h q v

def setField (o : Obj) (f : String) (v : Option Nat) : Obj :=
  { o with fields := o.fields.map fun x => if x.1 == f then (x.1, v) else x }

def applySet (p : Program) (h : Heap) (a : Nat) (f : String) (v : Option Nat) :
    Option Heap :=
  match h[a]? with
  | none => none
  | some o =>
    match p.lookup o.cls with
    | none => none
    | some d =>
      match d.props.find? (·.name == f) with
      | none => none
      | some q => if setOk p h o d q v then some (h.set a (setField o f v)) else none

/-- Runs a step, or returns none if it isn't allowed. -/
def apply (p : Program) (h : Heap) : Step → Option Heap
  | .new c args => applyNew p h c args
  | .set a f v => applySet p h a f v

/-- Heaps that some sequence of steps produces. -/
inductive Reachable (p : Program) : Heap → Prop where
  | init : Reachable p []
  | step {h h' : Heap} (s : Step) : Reachable p h → apply p h s = some h' → Reachable p h'

def succs (h : Heap) (a : Nat) : List Nat :=
  match h[a]? with
  | some o => o.fields.filterMap (·.2)
  | none => []

/-- Addresses reachable from `a` by at least one pointer. -/
def reachableAddrs (h : Heap) (a : Nat) : List Nat :=
  (List.range (h.length + 1)).foldl
    (fun seen _ => dedup (seen ++ seen.flatMap (succs h)))
    (succs h a)

def acyclic (h : Heap) : Bool :=
  (List.range h.length).all fun a => !(reachableAddrs h a).contains a

end Cycles
