import Cycles.Syntax

/-!
# Lemmas about `dedup`, `ancestors` and subtyping
-/

namespace Cycles

theorem foldl_induct {β γ : Type} (P : β → Prop) (f : β → γ → β) (l : List γ) (init : β)
    (h0 : P init) (hs : ∀ b x, P b → P (f b x)) : P (l.foldl f init) := by
  induction l generalizing init with
  | nil => exact h0
  | cons x xs ih => exact ih (f init x) (hs init x h0)

theorem mem_foldl_dedup {α : Type} [DecidableEq α] {x : α} (xs acc : List α) :
    x ∈ xs.foldl (fun acc y => if acc.contains y then acc else acc ++ [y]) acc ↔
      x ∈ acc ∨ x ∈ xs := by
  induction xs generalizing acc with
  | nil => simp
  | cons y ys ih =>
    simp only [List.foldl_cons]
    rw [ih]
    split
    · rename_i hy
      have hy' : y ∈ acc := by simpa using hy
      constructor
      · intro h
        rcases h with h | h
        · exact Or.inl h
        · exact Or.inr (List.mem_cons_of_mem _ h)
      · intro h
        rcases h with h | h
        · exact Or.inl h
        · rcases List.mem_cons.1 h with h | h
          · subst h; exact Or.inl hy'
          · exact Or.inr h
    · simp only [List.mem_append, List.mem_singleton, List.mem_cons, List.not_mem_nil, or_false]
      constructor
      · intro h
        rcases h with (h | h) | h
        · exact Or.inl h
        · exact Or.inr (Or.inl h)
        · exact Or.inr (Or.inr h)
      · intro h
        rcases h with h | h | h
        · exact Or.inl (Or.inl h)
        · exact Or.inl (Or.inr h)
        · exact Or.inr h

theorem mem_dedup {α : Type} [DecidableEq α] {x : α} {xs : List α} :
    x ∈ dedup xs ↔ x ∈ xs := by
  unfold dedup
  rw [mem_foldl_dedup]
  simp

namespace Program

theorem mem_ancStep {p : Program} {seen : List String} {x : String} :
    x ∈ p.ancStep seen ↔ x ∈ seen ∨ ∃ m ∈ seen, x ∈ p.supersOf m := by
  unfold ancStep
  rw [mem_dedup]
  simp [List.mem_flatMap]

/-- `t` is `e`, or reached from it through `supers`. -/
inductive SuperChain (p : Program) (e : String) : String → Prop where
  | refl : SuperChain p e e
  | step {m s : String} : SuperChain p e m → s ∈ p.supersOf m → SuperChain p e s

theorem chain_of_mem_ancestors {p : Program} {e t : String} (ht : t ∈ p.ancestors e) :
    SuperChain p e t := by
  unfold ancestors at ht
  refine foldl_induct (fun seen => ∀ x ∈ seen, SuperChain p e x) _ _ _ ?_ ?_ t ht
  · intro x hx
    simp at hx
    subst hx
    exact SuperChain.refl
  · intro seen _ hseen x hx
    rcases mem_ancStep.1 hx with hx | ⟨m, hm, hxm⟩
    · exact hseen x hx
    · exact SuperChain.step (hseen m hm) hxm

/-- A set of names closed under `supers`. -/
def Closed (p : Program) (S : List String) : Prop :=
  ∀ m ∈ S, ∀ s ∈ p.supersOf m, s ∈ S

theorem ancestors_subset {p : Program} {S : List String} (hS : p.Closed S) {n : String}
    (hn : n ∈ S) : ∀ x ∈ p.ancestors n, x ∈ S := by
  unfold ancestors
  refine foldl_induct (fun seen => ∀ x ∈ seen, x ∈ S) _ _ _ ?_ ?_
  · intro x hx
    simp at hx
    subst hx
    exact hn
  · intro seen _ hseen x hx
    rcases mem_ancStep.1 hx with hx | ⟨m, hm, hxm⟩
    · exact hseen x hx
    · exact hS m (hseen m hm) x hxm

theorem closed_of_converged {p : Program} {n : String} (conv : p.ancestorsConverged n = true) :
    p.Closed (p.ancestors n) := by
  intro m hm s hs
  unfold ancestorsConverged at conv
  have heq : p.ancStep (p.ancestors n) = p.ancestors n := by simpa using conv
  rw [← heq]
  exact mem_ancStep.2 (Or.inr ⟨m, hm, hs⟩)

theorem mem_ancestors_self {p : Program} {n : String} : n ∈ p.ancestors n := by
  unfold ancestors
  refine foldl_induct (fun seen => n ∈ seen) _ _ _ (by simp) ?_
  intro seen _ h
  exact mem_ancStep.2 (Or.inl h)

theorem isSubtype_named {p : Program} {e t : String} :
    p.isSubtype (.named e) (.named t) = true ↔ t ∈ p.ancestors e := by
  simp [isSubtype]

theorem mem_forbidsOf {p : Program} {n f : String} :
    f ∈ p.forbidsOf n ↔ ∃ m ∈ p.ancestors n, ∃ d, p.lookup m = some d ∧ f ∈ d.forbids := by
  unfold forbidsOf
  rw [mem_dedup]
  simp only [List.mem_flatMap]
  constructor
  · rintro ⟨m, hm, hf⟩
    cases hd : p.lookup m with
    | none => simp [hd] at hf
    | some d => exact ⟨m, hm, d, hd, by simpa [hd] using hf⟩
  · rintro ⟨m, hm, d, hd, hf⟩
    exact ⟨m, hm, by simpa [hd] using hf⟩

/-- Subtyping is transitive, given that `ancestors` converges for the subtype. -/
theorem ancestors_trans {p : Program} {e t : String} (conv : p.ancestorsConverged e = true)
    (ht : t ∈ p.ancestors e) : ∀ x ∈ p.ancestors t, x ∈ p.ancestors e :=
  ancestors_subset (closed_of_converged conv) ht

/-- A subtype keeps its super-types' `forbids` clauses. -/
theorem forbidsOf_mono {p : Program} {e t : String} (conv : p.ancestorsConverged e = true)
    (hsub : p.isSubtype (.named e) (.named t) = true) {f : String}
    (hf : f ∈ p.forbidsOf t) : f ∈ p.forbidsOf e := by
  rw [isSubtype_named] at hsub
  obtain ⟨m, hm, d, hd, hfd⟩ := mem_forbidsOf.1 hf
  exact mem_forbidsOf.2 ⟨m, ancestors_trans conv hsub m hm, d, hd, hfd⟩

end Program

end Cycles
