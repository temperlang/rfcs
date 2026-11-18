import Cycles.Soundness

/-!
# The fuel is enough

The checker computes each fixed point by iterating once per node, and fails
if that didn't reach the fixed point.  For a well-formed program it always
does (`check_converged`): reachability only grows a duplicate-free list of
nodes, and "always" only shrinks one.
-/

namespace Cycles

section Dedup
variable {α : Type} [DecidableEq α]

theorem nodup_foldl_dedup (xs acc : List α) (h : acc.Nodup) :
    (xs.foldl (fun acc y => if acc.contains y then acc else acc ++ [y]) acc).Nodup := by
  induction xs generalizing acc with
  | nil => exact h
  | cons y ys ih =>
    apply ih
    show (if acc.contains y then acc else acc ++ [y]).Nodup
    split
    · exact h
    · rename_i hy
      have hy' : y ∉ acc := by simpa using hy
      unfold List.Nodup
      rw [List.pairwise_append]
      refine ⟨h, List.pairwise_singleton _ _, ?_⟩
      intro a ha b hb hab
      simp only [List.mem_singleton] at hb
      subst hb hab
      exact hy' ha

theorem nodup_dedup (xs : List α) : (dedup xs).Nodup :=
  nodup_foldl_dedup xs [] List.nodup_nil

theorem foldl_dedup_prefix (xs acc : List α) :
    ∃ ys, xs.foldl (fun acc y => if acc.contains y then acc else acc ++ [y]) acc = acc ++ ys := by
  induction xs generalizing acc with
  | nil => exact ⟨[], by simp⟩
  | cons y ys ih =>
    simp only [List.foldl_cons]
    split
    · exact ih acc
    · obtain ⟨zs, hz⟩ := ih (acc ++ [y])
      exact ⟨y :: zs, by rw [hz]; simp⟩

theorem foldl_dedup_nodup (xs acc : List α) (h : (acc ++ xs).Nodup) :
    xs.foldl (fun acc y => if acc.contains y then acc else acc ++ [y]) acc = acc ++ xs := by
  induction xs generalizing acc with
  | nil => simp
  | cons y ys ih =>
    simp only [List.foldl_cons]
    have hy : y ∉ acc := by
      unfold List.Nodup at h
      rw [List.pairwise_append] at h
      exact fun hy => h.2.2 y hy y (List.mem_cons_self _ _) rfl
    rw [if_neg (by simpa using hy), ih (acc ++ [y]) (by simpa using h)]
    simp

/-- Deduplicating a duplicate-free list with more elements keeps it as a prefix. -/
theorem dedup_append_prefix {s : List α} (hs : s.Nodup) (xs : List α) :
    ∃ ys, dedup (s ++ xs) = s ++ ys := by
  unfold dedup
  rw [List.foldl_append, foldl_dedup_nodup s [] (by simpa using hs)]
  simpa using foldl_dedup_prefix xs s

theorem length_le_of_nodup {l U : List α} (hl : l.Nodup) (hsub : ∀ x ∈ l, x ∈ U) :
    l.length ≤ U.length := by
  induction l generalizing U with
  | nil => simp
  | cons a l ih =>
    rw [List.nodup_cons] at hl
    have ha : a ∈ U := hsub a (List.mem_cons_self _ _)
    have hrest := ih hl.2 (U := U.erase a) fun x hx =>
      (List.mem_erase_of_ne (fun h => hl.1 (by rw [← h]; exact hx))).2 (hsub x (List.mem_cons_of_mem _ hx))
    rw [List.length_erase_of_mem ha] at hrest
    have := List.length_pos_of_mem ha
    simp only [List.length_cons]
    omega

end Dedup

/-! ## Iteration -/

theorem foldl_const_fixed {β γ : Type} (f : β → β) (l : List γ) (x : β) (hx : f x = x) :
    l.foldl (fun s _ => f s) x = x := by
  induction l with
  | nil => rfl
  | cons _ l ih => rw [List.foldl_cons, hx]; exact ih

/-- Iterating `f`, where each step either reaches a fixed point or increases `m`. -/
theorem foldl_measure {β γ : Type} (f : β → β) (m : β → Nat) (inv : β → Prop)
    (step : ∀ s, inv s → inv (f s) ∧ (f s = s ∨ m s < m (f s)))
    (l : List γ) (x : β) (hx : inv x) :
    inv (l.foldl (fun s _ => f s) x) ∧
      (f (l.foldl (fun s _ => f s) x) = l.foldl (fun s _ => f s) x ∨
        m x + l.length ≤ m (l.foldl (fun s _ => f s) x)) := by
  induction l generalizing x with
  | nil => exact ⟨hx, Or.inr (by simp)⟩
  | cons a l ih =>
    simp only [List.foldl_cons, List.length_cons]
    obtain ⟨hfx, hor⟩ := step x hx
    rcases hor with heq | hlt
    · rw [heq, foldl_const_fixed f l x heq]
      exact ⟨hx, Or.inl heq⟩
    · obtain ⟨hr, hr'⟩ := ih (f x) hfx
      refine ⟨hr, ?_⟩
      rcases hr' with h | h
      · exact Or.inl h
      · right; omega

/-! ## Reachability and "always" -/

theorem reachFrom_nodup {es : List Edge} {U : List Node} (hU : ∀ e ∈ es, e.dst ∈ U)
    (fuel : Nat) (start : Node) :
    (reachFrom es fuel start).Nodup ∧ ∀ x ∈ reachFrom es fuel start, x ∈ U := by
  unfold reachFrom
  refine foldl_induct (fun s : List Node => s.Nodup ∧ ∀ x ∈ s, x ∈ U) _ _ _ ⟨nodup_dedup _, ?_⟩ ?_
  · intro x hx
    rw [mem_dedup, List.mem_map] at hx
    obtain ⟨e, he, rfl⟩ := hx
    exact hU e (List.mem_filter.1 he).1
  · intro s _ ⟨_, hsub⟩
    refine ⟨nodup_dedup _, fun x hx => ?_⟩
    rcases mem_reachStep.1 hx with hx | ⟨e, he, _, rfl⟩
    · exact hsub x hx
    · exact hU e he

theorem reachConverged_of_bound {es : List Edge} {U : List Node} (hU : ∀ e ∈ es, e.dst ∈ U)
    (start : Node) : reachConverged es (U.length + 1) start = true := by
  have init := reachFrom_nodup hU 0 start
  unfold reachFrom at init
  simp only [List.range_zero, List.foldl_nil] at init
  unfold reachConverged
  simp only [beq_iff_eq]
  unfold reachFrom
  have step : ∀ s : List Node, (s.Nodup ∧ ∀ x ∈ s, x ∈ U) →
      ((reachStep es s).Nodup ∧ ∀ x ∈ reachStep es s, x ∈ U) ∧
        (reachStep es s = s ∨ s.length < (reachStep es s).length) := by
    intro s ⟨hnd, hsub⟩
    refine ⟨⟨nodup_dedup _, fun x hx => ?_⟩, ?_⟩
    · rcases mem_reachStep.1 hx with hx | ⟨e, he, _, rfl⟩
      · exact hsub x hx
      · exact hU e he
    · obtain ⟨ys, hys⟩ :=
        dedup_append_prefix hnd ((es.filter fun e => s.contains e.src).map (·.dst))
      have hst : reachStep es s = s ++ ys := hys
      rw [hst]
      cases ys with
      | nil => simp
      | cons y ys => right; simp
  obtain ⟨hinv, h | h⟩ :=
    foldl_measure (reachStep es) List.length _ step (List.range (U.length + 1)) _ init
  · exact h
  · have := length_le_of_nodup hinv.1 hinv.2
    simp only [List.length_range] at h
    omega

theorem alwaysConverged_of_bound {p : Program} {main f : String} {es : List Edge}
    (hU : ∀ e ∈ es, e.dst ∈ allNodes p) : alwaysConverged p main es f = true := by
  unfold alwaysConverged
  simp only [Bool.and_eq_true, beq_iff_eq]
  refine ⟨reachConverged_of_bound hU _, ?_⟩
  have bound := reachFrom_nodup hU ((allNodes p).length + 1) (.ty (.named main))
  unfold alwaysForbidden
  simp only
  generalize hr : reachFrom es ((allNodes p).length + 1) (.ty (.named main)) = reach at bound
  let x0 := reach.filter (· != Node.ty (.named main))
  have hx0 : x0.length ≤ (allNodes p).length :=
    Nat.le_trans (List.length_filter_le _ _) (length_le_of_nodup bound.1 bound.2)
  let g := alwaysStep p main es (.ty (.named main) :: reach) f
  have step : ∀ s : List Node, s.length ≤ x0.length →
      (g s).length ≤ x0.length ∧ (g s = s ∨ x0.length - s.length < x0.length - (g s).length) := by
    intro s hs
    have hsub : List.Sublist (g s) s := List.filter_sublist _
    have hle := hsub.length_le
    refine ⟨Nat.le_trans hle hs, ?_⟩
    by_cases heq : (g s).length = s.length
    · exact Or.inl (hsub.eq_of_length heq)
    · right; omega
  rcases (foldl_measure g (fun s => x0.length - s.length) _ step
      (List.range ((allNodes p).length + 1)) x0 (Nat.le_refl _)).2 with h | h
  · exact h
  · simp only [List.length_range] at h
    omega

/-! ## Every node is in `allNodes` -/

/-- What `wellFormed` says about each declaration. -/
theorem wf_decl_all {p : Program} (wf : p.wellFormed = true) {d : Decl} (hd : d ∈ p) :
    (d.kind = .cls ∨ d.props = []) ∧
      (∀ q ∈ d.props, ∀ n, q.type = .named n → (p.lookup n).isSome = true) ∧
      (∀ f ∈ d.forbids, (p.lookup f).isSome = true) := by
  simp only [Program.wellFormed, Bool.and_eq_true, List.all_eq_true] at wf
  obtain ⟨⟨⟨⟨_, hcls⟩, htypes⟩, hforbids⟩, _⟩ := wf.2 d hd
  refine ⟨?_, fun q hq n hn => ?_, hforbids⟩
  · simpa [Bool.or_eq_true, List.isEmpty_iff] using hcls
  · have := htypes q hq
    rw [hn] at this
    exact this

theorem ty_mem_allNodes {p : Program} {n : String} (h : (p.lookup n).isSome = true) :
    Node.ty (.named n) ∈ allNodes p := by
  obtain ⟨d, hd⟩ := Option.isSome_iff_exists.1 h
  obtain ⟨hdp, hdn⟩ := lookup_mem hd
  unfold allNodes
  simp only [List.mem_append, List.mem_map]
  exact Or.inl (Or.inl (Or.inl ⟨d, hdp, by rw [hdn]⟩))

theorem any_mem_allNodes {p : Program} : Node.ty .anyValue ∈ allNodes p := by
  unfold allNodes; simp

theorem tyNode_mem_allNodes {p : Program} {t : Ty}
    (h : ∀ n, t = .named n → (p.lookup n).isSome = true) : Node.ty t ∈ allNodes p := by
  cases t with
  | anyValue => exact any_mem_allNodes
  | named n => exact ty_mem_allNodes (h n rfl)

theorem lookup_isSome_of_mem {p : Program} {d : Decl} (hd : d ∈ p) :
    (p.lookup d.name).isSome = true := by
  unfold Program.lookup
  rw [Option.isSome_iff_exists]
  cases h : List.find? (fun e => e.name == d.name) p with
  | none =>
    rw [List.find?_eq_none] at h
    exact absurd (by simp) (h d hd)
  | some e => exact ⟨e, rfl⟩

theorem edgesFor_nodes {p : Program} (wf : p.wellFormed = true) {main : String}
    (hm : (p.lookup main).isSome = true) :
    ∀ e ∈ edgesFor p main, e.src ∈ allNodes p ∧ e.dst ∈ allNodes p := by
  intro e he
  unfold edgesFor at he
  simp only [List.mem_append, List.mem_cons, List.mem_flatMap, List.mem_map,
    List.mem_filter] at he
  rcases he with ⟨d, hd, hed⟩ | rfl | ⟨n, ⟨hn, _⟩, rfl⟩
  · have hsrc := ty_mem_allNodes (lookup_isSome_of_mem hd)
    unfold declEdges at hed
    obtain ⟨_, htypes, _⟩ := wf_decl_all wf hd
    split at hed
    · simp only [List.mem_map] at hed
      obtain ⟨q, hq, rfl⟩ := hed
      exact ⟨hsrc, tyNode_mem_allNodes (htypes q hq)⟩
    · simp only [List.mem_map, List.mem_filter] at hed
      obtain ⟨d', ⟨hd', _⟩, rfl⟩ := hed
      exact ⟨hsrc, ty_mem_allNodes (lookup_isSome_of_mem hd')⟩
    · simp only [List.mem_singleton] at hed
      subst hed
      refine ⟨hsrc, ?_⟩
      rename_i hk
      unfold allNodes
      simp only [List.mem_append, List.mem_map, List.mem_filter, List.mem_singleton]
      exact Or.inl (Or.inr ⟨d, ⟨hd, by simp [hk]⟩, rfl⟩)
  · exact ⟨any_mem_allNodes, by unfold allNodes; simp⟩
  · exact ⟨hn, ty_mem_allNodes hm⟩

theorem fakeForbidsEdgesFor_nodes {p : Program} (wf : p.wellFormed = true) {main : String} :
    ∀ e ∈ fakeForbidsEdgesFor p main, e.src ∈ allNodes p ∧ e.dst ∈ allNodes p := by
  intro e he
  unfold fakeForbidsEdgesFor at he
  simp only [List.mem_flatMap, List.mem_map, List.mem_filter] at he
  obtain ⟨n, ⟨hn, _⟩, f, hf, rfl⟩ := he
  refine ⟨hn, ty_mem_allNodes ?_⟩
  obtain ⟨m, _, dm, hdm, hfm⟩ := Program.mem_forbidsOf.1 hf
  exact (wf_decl_all wf (lookup_mem hdm).1).2.2 f hfm

/-- For a well-formed program, every fixed point the checker computes converges. -/
theorem check_converged {p : Program} (wf : p.wellFormed = true) {main : String}
    (hm : (p.lookup main).isSome = true) (ff : Bool) : (check p main ff).converged = true := by
  have hE := edgesFor_nodes wf hm
  have hX := fakeForbidsEdgesFor_nodes wf (main := main)
  have hP : ∀ e ∈ prunedEdges p main, e.src ∈ allNodes p ∧ e.dst ∈ allNodes p :=
    fun e he => hE e (List.mem_filter.1 he).1
  have hExtra : ∀ e ∈ (if ff then fakeForbidsEdgesFor p main else []),
      e.src ∈ allNodes p ∧ e.dst ∈ allNodes p := by
    split
    · exact hX
    · simp
  have app : ∀ {a b : List Edge}, (∀ e ∈ a, e.src ∈ allNodes p ∧ e.dst ∈ allNodes p) →
      (∀ e ∈ b, e.src ∈ allNodes p ∧ e.dst ∈ allNodes p) →
      ∀ e ∈ a ++ b, e.dst ∈ allNodes p := by
    intro a b ha hb e he
    rcases List.mem_append.1 he with he | he
    · exact (ha e he).2
    · exact (hb e he).2
  simp only [check, Bool.and_eq_true, List.all_eq_true]
  refine ⟨⟨⟨⟨alwaysConverged_of_bound fun e he => (hE e he).2,
    reachConverged_of_bound (fun e he => (hP e he).2) _⟩,
    reachConverged_of_bound (U := allNodes p) ?_ _⟩,
    reachConverged_of_bound (app hP hExtra) _⟩,
    fun f _ => alwaysConverged_of_bound (app hE hExtra)⟩
  intro e he
  unfold reverseEdges at he
  obtain ⟨e', he', rfl⟩ := List.mem_map.1 he
  exact (hP e' he').1

end Cycles
