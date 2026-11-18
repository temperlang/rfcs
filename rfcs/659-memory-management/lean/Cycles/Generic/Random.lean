import Cycles.Generic.Search

/-!
Random programs with type formals, for the searches.
-/

namespace Cycles.Generic

open Cycles (PropKind DeclKind)

def flipCoin : IO Bool := do
  pure ((← IO.rand 0 1) == 1)

def randPick {α : Type} [Inhabited α] (xs : List α) : IO α := do
  pure xs[(← IO.rand 0 (xs.length - 1))]!

def randKind : IO PropKind := randPick [.early, .setOnce, .var]

/-- A random type over the type formals `fs`, with arguments nested up to `depth`. -/
partial def randTy (decls : List (String × Nat)) (fs : List String) (depth : Nat) : IO Ty := do
  let r ← IO.rand 0 9
  if r < 3 && !fs.isEmpty then
    return .param (← randPick fs)
  if r < 4 then
    return .anyValue
  let (n, k) ← randPick decls
  if k == 0 then
    return .named n []
  if depth == 0 then
    let arg ← if fs.isEmpty then pure Ty.anyValue else pure (Ty.param (← randPick fs))
    return .named n [arg]
  return .named n [← randTy decls fs (depth - 1)]

/--
`nClasses` classes and `nIfaces` interfaces, each with at most one type
formal, `T`.  Type formals may have an `extends` bound and a `forbids`
bound, often on their own declaration's type.
-/
def randProgram (nClasses nIfaces : Nat) : IO Program := do
  let ifaceNames := (List.range nIfaces).map (s!"I{·}")
  let classNames := (List.range nClasses).map (s!"C{·}")
  let mut arity : List (String × Nat) := []
  for n in ifaceNames ++ classNames do
    arity := arity ++ [(n, if ← flipCoin then 1 else 0)]
  let mut sealedOf : List (String × Bool) := []
  for n in ifaceNames do
    sealedOf := sealedOf ++ [(n, ← flipCoin)]
  let arityOf (n : String) := (arity.lookup n).getD 0
  let fsOf (n : String) := if arityOf n == 1 then ["T"] else []
  let superTy (d i : String) : IO (Option Ty) := do
    if arityOf i == 0 then
      -- A sealed super-type must mention each of the sub-type's formals.
      if (sealedOf.lookup i).getD false && arityOf d == 1 then pure none
      else pure (some (.named i []))
    else if (sealedOf.lookup i).getD false then
      if arityOf d == 1 then pure (some (.named i [.param "T"]))
      else pure (some (.named i [← randTy (arity.filter (·.2 == 0)) [] 0]))
    else pure (some (.named i [← randTy arity (fsOf d) 1]))
  let formalsOf (d : String) : IO (List Formal) := do
    if arityOf d == 0 then return []
    let bounds ← if (← IO.rand 0 3) == 0 then
        pure [.named (← randPick ifaceNames) (if arityOf ifaceNames[0]! == 0 then [] else [])]
      else pure []
    let bounds := bounds.filter fun b => match b with
      | .named n [] => arityOf n == 0
      | _ => false
    let forbids ← match ← IO.rand 0 3 with
      | 0 => pure [.named d [.param "T"]]
      | 1 => pure [← randTy arity ["T"] 1]
      | _ => pure []
    pure [{ name := "T", bounds := bounds, forbids := forbids }]
  let mut p : Program := []
  for k in List.range nIfaces do
    let n := s!"I{k}"
    let mut supers : List Ty := []
    for i in ifaceNames.take k do
      if (← IO.rand 0 2) == 0 then
        if let some s ← superTy n i then supers := supers ++ [s]
    let forbids ← if (← IO.rand 0 2) == 0 then pure [← randTy arity (fsOf n) 1] else pure []
    p := p ++ [({ name := n, kind := .iface ((sealedOf.lookup n).getD false),
                  formals := ← formalsOf n, supers := supers, forbids := forbids } : Decl)]
  for n in classNames do
    let mut supers : List Ty := []
    for i in ifaceNames do
      if (← IO.rand 0 2) == 0 then
        if let some s ← superTy n i then supers := supers ++ [s]
    let mut props : List Property := []
    for k in List.range (← IO.rand 0 2) do
      props := props ++ [{ name := s!"p{k}", type := ← randTy arity (fsOf n) 1,
                           nullable := ← flipCoin, kind := ← randKind }]
    let forbids ← if (← IO.rand 0 2) == 0 then pure [← randTy arity (fsOf n) 1] else pure []
    p := p ++ [({ name := n, kind := .cls, formals := ← formalsOf n, supers := supers,
                  props := props, forbids := forbids } : Decl)]
  pure p

end Cycles.Generic
