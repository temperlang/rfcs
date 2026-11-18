import Cycles.Generic.Semantics

/-!
# Bounded search, with type formals

`new` steps use only the given types, which callers check with `phraseOk`.
-/

namespace Cycles.Generic

open Cycles (PropKind DeclKind dedup)

def cartesian {α : Type} : List (List α) → List (List α)
  | [] => [[]]
  | xs :: rest => xs.flatMap fun x => (cartesian rest).map (x :: ·)

/-- Values a property of type `t` could take. -/
def valuesFor (p : Program) (h : Heap) (t : Ty) (nullable : Bool) : List (Option Nat) :=
  (if nullable then [none] else []) ++
    ((List.range h.length).filter fun a => valueOk p h t nullable (some a)).map some

def candidates (p : Program) (types : List Ty) (h : Heap) : List Step :=
  let news := types.flatMap fun t =>
    match classOf p t with
    | none => []
    | some (d, targs) =>
      let early := d.props.filter (·.kind == PropKind.early)
      (cartesian (early.map fun q =>
          (valuesFor p h (q.type.subst (ctx d targs)) q.nullable).map fun v => (q.name, v))).map
        (Step.new t)
  let sets := (List.range h.length).flatMap fun a =>
    match h[a]? with
    | none => []
    | some o =>
      match classOf p o.ty with
      | none => []
      | some (d, targs) =>
        (d.props.filter fun q => q.kind != PropKind.early && !isEarlyName d q.name).flatMap fun q =>
          (valuesFor p h (q.type.subst (ctx d targs)) true).map (Step.set a q.name)
  news ++ sets

/-- A sequence of at most `depth` steps from `h` that makes a cycle. -/
def findCycle (p : Program) (types : List Ty) : Nat → Heap → List Step → Option (List Step)
  | 0, _, _ => none
  | depth + 1, h, trace =>
    (candidates p types h).findSome? fun s =>
      match apply p h false s with
      | none => none
      | some h' =>
        if !acyclic h' then some (trace ++ [s])
        else findCycle p types depth h' (trace ++ [s])

/-- Ground class types with arguments up to depth two, that are valid type phrases. -/
def groundClassTypes (p : Program) : List Ty :=
  let base : List Ty := .anyValue ::
    (p.filter (·.formals.isEmpty)).map fun d => .named d.name []
  let depth1 : List Ty := p.flatMap fun d =>
    if d.formals.length == 1 then base.map fun b => .named d.name [b] else []
  let args := base ++ depth1
  let all : List Ty := p.flatMap fun d =>
    if d.kind != DeclKind.cls then []
    else if d.formals.isEmpty then [.named d.name []]
    else if d.formals.length == 1 then args.map fun a => .named d.name [a]
    else []
  all.filter (phraseOk p [])

end Cycles.Generic
