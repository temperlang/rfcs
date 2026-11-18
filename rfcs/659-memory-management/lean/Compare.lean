import Cycles.Generic.Random
open Cycles (DeclKind)
open Cycles.Generic

/-- Edges Step III prunes, other than instance edges. -/
def prunedSet (p : Program) (d : Decl) (inst : Instances) : List Edge :=
  let env := d.formals
  let mainTy := mainTypeOf d
  let mainNode := Node.ty mainTy
  let (_, edges0, _) := explore p env (some mainTy) [mainNode] inst
  let alwaysMain := alwaysForbidden edges0 mainNode
    (fun n => n != mainNode && declaresTy p env n mainTy)
  edges0.filter fun e => e.src.isFake && alwaysMain.contains e.src

def sameSet {α} [BEq α] (a b : List α) : Bool := a.all b.contains && b.all a.contains

def main (args : List String) : IO UInt32 := do
  let trials := (args[0]? >>= String.toNat?).getD 2000
  IO.setRandSeed ((args[1]? >>= String.toNat?).getD 5)
  let mut checked := 0
  let mut differ := 0
  let mut caught := 0
  for _ in List.range trials do
    let p ← randProgram 3 2
    if p.wellFormed then
      for d in p do
        if d.kind == DeclKind.cls then
          checked := checked + 1
          let a := check p d.name true .mainLike
          let b := check p d.name true .edges
          let r := check p d.name true .rfc
          if r.ok && !b.ok then caught := caught + 1
          if a.ok != b.ok || !sameSet a.cycleEdges b.cycleEdges ||
              !sameSet a.mismatches b.mismatches ||
              !sameSet (prunedSet p d .mainLike) (prunedSet p d .edges) then
            differ := differ + 1
            IO.println s!"Differ for {d.name}:\n{repr p}"
  IO.println s!"{checked} class checks compared; {differ} differ; \
    {caught} fail only because of instance edges."
  return 0
