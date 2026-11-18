import Cycles.Semantics

/-!
# Stage 0: bounded search for cycles

Tries every sequence of steps up to a given length, looking for one that
makes a cycle.  For a program that passes the checker, finding one means
the checker is unsound, or the model is wrong.
-/

namespace Cycles

def cartesian {α : Type} : List (List α) → List (List α)
  | [] => [[]]
  | xs :: rest => xs.flatMap fun x => (cartesian rest).map (x :: ·)

/-- The steps worth trying on `h`.  `apply` rejects any that aren't allowed. -/
def candidates (p : Program) (h : Heap) : List Step :=
  let vals : List (Option Nat) := none :: (List.range h.length).map some
  let news := (p.filter fun d => d.kind == DeclKind.cls).flatMap fun d =>
    let early := d.props.filter (·.kind == PropKind.early)
    let choices := early.map fun q => (vals.filter (valueOk p h q)).map fun v => (q.name, v)
    (cartesian choices).map (Step.new d.name ·)
  let sets := (List.range h.length).flatMap fun a =>
    let fieldNames := ((h[a]?).map fun o => o.fields.map (·.1)).getD []
    fieldNames.flatMap fun f => vals.map (Step.set a f ·)
  news ++ sets

/-- Searches sequences of at most `depth` more steps for one that makes a cycle. -/
def findCycle (p : Program) : Nat → Heap → List Step → Option (List Step)
  | 0, _, _ => none
  | depth + 1, h, trace =>
    (candidates p h).findSome? fun s =>
      match apply p h s with
      | none => none
      | some h' =>
        if !acyclic h' then some (trace ++ [s]) else findCycle p depth h' (trace ++ [s])

end Cycles
