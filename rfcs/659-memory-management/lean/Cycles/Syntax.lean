/-!
# A micro language for RFC 659's memory cycle checker

Stage 1: no type formals.  A program is a list of class and interface
declarations, with `forbids` clauses on classes and interfaces.
-/

namespace Cycles

/-- How a property gets its value.  See *Drop-order graphs* in the RFC. -/
inductive PropKind where
  /-- Set by `new` from objects that already exist: a `<=` edge. -/
  | early
  /-- Not `var`, but set after the object exists, at most once: a `<` edge. -/
  | setOnce
  /-- `var`: set any number of times: a `<` edge. -/
  | var
  deriving DecidableEq, Repr, Inhabited

/-- A type: a named class or interface, or *AnyValue*. -/
inductive Ty where
  | named (name : String)
  | anyValue
  deriving DecidableEq, Repr, Inhabited

structure Property where
  name : String
  type : Ty
  nullable : Bool := false
  kind : PropKind
  deriving DecidableEq, Repr, Inhabited

inductive DeclKind where
  | cls
  | iface (sealed : Bool)
  deriving DecidableEq, Repr, Inhabited

structure Decl where
  name : String
  kind : DeclKind
  /-- Interfaces it directly extends. -/
  supers : List String := []
  /-- Backed properties; only classes have them. -/
  props : List Property := []
  /-- Types that values of this type never point to, directly or not. -/
  forbids : List String := []
  deriving DecidableEq, Repr, Inhabited

abbrev Program := List Decl

/-- Removes duplicates, keeping first occurrences in order. -/
def dedup {α : Type} [DecidableEq α] (xs : List α) : List α :=
  xs.foldl (fun acc x => if acc.contains x then acc else acc ++ [x]) []

namespace Program

def lookup (p : Program) (n : String) : Option Decl :=
  List.find? (fun d => d.name == n) p

def isClass (p : Program) (n : String) : Bool :=
  match p.lookup n with
  | some d => d.kind == DeclKind.cls
  | none => false

def supersOf (p : Program) (n : String) : List String :=
  ((p.lookup n).map (·.supers)).getD []

def ancStep (p : Program) (seen : List String) : List String :=
  dedup (seen ++ seen.flatMap p.supersOf)

/-- `n` and every interface it extends, directly or not, if the fuel is enough. -/
def ancestors (p : Program) (n : String) : List String :=
  (List.range (p.length + 1)).foldl (fun seen _ => p.ancStep seen) [n]

/-- Whether `ancestors n` reached its fixed point; `wellFormed` requires it. -/
def ancestorsConverged (p : Program) (n : String) : Bool :=
  p.ancStep (p.ancestors n) == p.ancestors n

def isSubtype (p : Program) (a b : Ty) : Bool :=
  match a, b with
  | _, .anyValue => true
  | .anyValue, .named _ => false
  | .named x, .named y => (p.ancestors x).contains y

/-- The `forbids` clauses of `n`, its own and inherited. -/
def forbidsOf (p : Program) (n : String) : List String :=
  dedup ((p.ancestors n).flatMap fun m => ((p.lookup m).map (·.forbids)).getD [])

/--
Whether a class from some other library could be a value of `t`: `t` is
*AnyValue*, or a non-sealed interface extends it.  Classes and sealed
interfaces are closed: all their subtypes are in `p`.
-/
def openTo (p : Program) (t : Ty) : Bool :=
  match t with
  | .anyValue => true
  | .named n =>
    p.any fun d => d.kind == DeclKind.iface false && (p.ancestors d.name).contains n

/-- Whether a value of type `t` could be an `f`, in `p` or in a later library. -/
def mayBeA (p : Program) (t : Ty) (f : String) : Bool :=
  p.any (fun d =>
    d.kind == DeclKind.cls && p.isSubtype (.named d.name) t &&
      p.isSubtype (.named d.name) (.named f))
  || (p.openTo t && p.openTo (.named f))

/--
Names are unique, only interfaces are extended, only classes have
properties, every name used is declared, and `ancestors` converges.
-/
def wellFormed (p : Program) : Bool :=
  let names := p.map (·.name)
  dedup names == names &&
    p.all fun d =>
      d.supers.all (fun s =>
        s != d.name &&
          (match p.lookup s with
           | some e => e.kind != DeclKind.cls
           | none => false)) &&
      (d.kind == DeclKind.cls || d.props.isEmpty) &&
      d.props.all (fun q =>
        match q.type with
        | .named n => (p.lookup n).isSome
        | .anyValue => true) &&
      d.forbids.all (fun f => (p.lookup f).isSome) &&
      p.ancestorsConverged d.name

/--
Whether `q` could be another library built on `p`: its names are new, and
it extends only `p`'s non-sealed interfaces, never a class or a sealed
interface.
-/
def extendsOk (p q : Program) : Bool :=
  q.all fun d =>
    (p.lookup d.name).isNone &&
      d.supers.all fun s =>
        match p.lookup s with
        | some e => e.kind == DeclKind.iface false
        | none => true

end Program

end Cycles
