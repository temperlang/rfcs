import Cycles.Fuel
import Cycles.Acyclic

/-!
# Separate compilation

`check_extend`: adding a library `q` on top of `p` doesn't change whether
`p`'s classes pass.  `q` adds nodes and edges, but none that a graph for one
of `p`'s types reaches: the only edges from a type to its subtypes are from
sealed interfaces, which `q` can't extend.  `mayBeA` and `openTo` don't
change either, since a class in `q` can only implement `p`'s non-sealed
interfaces, for which `openTo` was already true.  The fixed points converge
for both programs (`check_converged`), so they can be compared by what they
mean rather than by how many iterations they took.
-/

namespace Cycles

/-- `p` declares `n`. -/
abbrev InP (p : Program) (n : String) : Prop := (p.lookup n).isSome = true

section Names
variable {p q : Program}

theorem lookup_append_inP {n : String} (h : InP p n) : (p ++ q).lookup n = p.lookup n := by
  obtain ⟨d, hd⟩ := Option.isSome_iff_exists.1 h
  unfold Program.lookup at *
  rw [List.find?_append, hd]
  rfl

theorem lookup_append_none {n : String} (h : p.lookup n = none) :
    (p ++ q).lookup n = q.lookup n := by
  unfold Program.lookup at *
  rw [List.find?_append, h]
  rfl

theorem supersOf_append {m : String} (h : InP p m) : (p ++ q).supersOf m = p.supersOf m := by
  unfold Program.supersOf
  rw [lookup_append_inP h]

theorem ext_decl (ext : p.extendsOk q = true) {d : Decl} (hd : d ∈ q) :
    p.lookup d.name = none ∧ ∀ s ∈ d.supers, ∀ e, p.lookup s = some e → e.kind = .iface false := by
  unfold Program.extendsOk at ext
  have := List.all_eq_true.1 ext d hd
  simp only [Bool.and_eq_true, Option.isNone_iff_eq_none, List.all_eq_true] at this
  refine ⟨this.1, fun s hs e he => ?_⟩
  have := this.2 s hs
  rw [he] at this
  simpa using this

theorem not_inP_of_mem_q (ext : p.extendsOk q = true) {d : Decl} (hd : d ∈ q) :
    ¬ InP p d.name := by
  simp [InP, (ext_decl ext hd).1]

theorem mem_p_of_inP (ext : p.extendsOk q = true) {d : Decl} (hd : d ∈ p ++ q)
    (h : InP p d.name) : d ∈ p := by
  rcases List.mem_append.1 hd with hd | hd
  · exact hd
  · exact absurd h (not_inP_of_mem_q ext hd)

theorem eq_of_nodup_names {l : List Decl} (h : (l.map (·.name)).Nodup) {d e : Decl}
    (hd : d ∈ l) (he : e ∈ l) (hn : d.name = e.name) : d = e := by
  induction l with
  | nil => simp at hd
  | cons a l ih =>
    simp only [List.map_cons, List.nodup_cons, List.mem_map] at h
    rcases List.mem_cons.1 hd with h1 | h1 <;> rcases List.mem_cons.1 he with h2 | h2
    · rw [h1, h2]
    · subst h1; exact absurd ⟨e, h2, hn.symm⟩ h.1
    · subst h2; exact absurd ⟨d, h1, hn⟩ h.1
    · exact ih h.2 h1 h2

/-- In a well-formed program, a declaration is what its name looks up. -/
theorem lookup_self (wf : p.wellFormed = true) {d : Decl} (hd : d ∈ p) : p.lookup d.name = some d := by
  have hnd : (p.map (·.name)).Nodup := by
    simp only [Program.wellFormed, Bool.and_eq_true, beq_iff_eq] at wf
    rw [← wf.1]
    exact nodup_dedup _
  obtain ⟨e, he⟩ := Option.isSome_iff_exists.1 (lookup_isSome_of_mem (p := p) hd)
  obtain ⟨hep, hen⟩ := lookup_mem he
  rw [he, eq_of_nodup_names hnd hep hd hen]

theorem inP_of_supersOf (wfp : p.wellFormed = true) {m s : String} (h : s ∈ p.supersOf m) :
    InP p s := by
  obtain ⟨dm, hdm, hs⟩ := mem_supersOf h
  obtain ⟨ds, hds, _⟩ := (wf_decl wfp (lookup_mem hdm).1).1 s hs
  simp [InP, hds]

end Names

/-! ## Subtyping in `p ++ q` -/

section Subtyping
variable {p q : Program}

theorem mem_ancestors_of_chain {n t : String} (conv : p.ancestorsConverged n = true)
    (c : Program.SuperChain p n t) : t ∈ p.ancestors n := by
  induction c with
  | refl => exact Program.mem_ancestors_self
  | step _ hs ih => exact Program.closed_of_converged conv _ ih _ hs

theorem inP_of_chain (wfp : p.wellFormed = true) {a x : String} (ha : InP p a)
    (c : Program.SuperChain p a x) : InP p x := by
  induction c with
  | refl => exact ha
  | step _ hs _ => exact inP_of_supersOf wfp hs

theorem chain_append_iff (wfp : p.wellFormed = true) {a x : String} (ha : InP p a) :
    Program.SuperChain (p ++ q) a x ↔ Program.SuperChain p a x := by
  constructor
  · intro c
    suffices Program.SuperChain p a x ∧ InP p x from this.1
    induction c with
    | refl => exact ⟨.refl, ha⟩
    | step _ hs ih =>
      rw [supersOf_append ih.2] at hs
      exact ⟨.step ih.1 hs, inP_of_supersOf wfp hs⟩
  · intro c
    induction c with
    | refl => exact .refl
    | step c' hs ih =>
      have hm := inP_of_chain wfp ha c'
      exact .step ih (by rw [supersOf_append hm]; exact hs)

theorem conv_of_inP (wf : p.wellFormed = true) {n : String} (h : InP p n) :
    p.ancestorsConverged n = true := by
  obtain ⟨d, hd⟩ := Option.isSome_iff_exists.1 h
  exact conv_of_lookup wf hd

theorem mem_ancestors_append (wf : (p ++ q).wellFormed = true) (wfp : p.wellFormed = true)
    {a x : String} (ha : InP p a) : x ∈ (p ++ q).ancestors a ↔ x ∈ p.ancestors a := by
  constructor
  · intro hx
    exact mem_ancestors_of_chain (conv_of_inP wfp ha)
      ((chain_append_iff wfp ha).1 (Program.chain_of_mem_ancestors hx))
  · intro hx
    have ha' : InP (p ++ q) a := by simp only [InP, lookup_append_inP ha]; exact ha
    exact mem_ancestors_of_chain (conv_of_inP wf ha')
      ((chain_append_iff wfp ha).2 (Program.chain_of_mem_ancestors hx))

theorem inP_of_mem_ancestors (wfp : p.wellFormed = true) {a x : String} (ha : InP p a)
    (hx : x ∈ p.ancestors a) : InP p x :=
  inP_of_chain wfp ha (Program.chain_of_mem_ancestors hx)

theorem isSubtype_append (wf : (p ++ q).wellFormed = true) (wfp : p.wellFormed = true)
    {a : String} (ha : InP p a) (t : Ty) :
    (p ++ q).isSubtype (.named a) t = p.isSubtype (.named a) t := by
  cases t with
  | anyValue => simp [Program.isSubtype]
  | named b =>
    rw [Bool.eq_iff_iff, Program.isSubtype_named, Program.isSubtype_named]
    exact mem_ancestors_append wf wfp ha

theorem mem_forbidsOf_append (wf : (p ++ q).wellFormed = true) (wfp : p.wellFormed = true)
    {a f : String} (ha : InP p a) : f ∈ (p ++ q).forbidsOf a ↔ f ∈ p.forbidsOf a := by
  rw [Program.mem_forbidsOf, Program.mem_forbidsOf]
  constructor
  · rintro ⟨m, hm, d, hd, hf⟩
    rw [mem_ancestors_append wf wfp ha] at hm
    rw [lookup_append_inP (inP_of_mem_ancestors wfp ha hm)] at hd
    exact ⟨m, hm, d, hd, hf⟩
  · rintro ⟨m, hm, d, hd, hf⟩
    have hmP := inP_of_mem_ancestors wfp ha hm
    rw [← mem_ancestors_append wf wfp ha] at hm
    exact ⟨m, hm, d, by rw [lookup_append_inP hmP]; exact hd, hf⟩

/--
A chain of super-types in `p ++ q` that ends in `p` either stays in `p`, or
enters it at one of `p`'s non-sealed interfaces.
-/
theorem chain_exit (ext : p.extendsOk q = true) {a x : String}
    (c : Program.SuperChain (p ++ q) a x) (hx : InP p x) :
    (InP p a ∧ Program.SuperChain p a x) ∨
      ∃ di ∈ p, di.kind = .iface false ∧ Program.SuperChain p di.name x := by
  induction c with
  | refl => exact Or.inl ⟨hx, .refl⟩
  | @step m s _ hs ih =>
    by_cases hm : InP p m
    · rw [supersOf_append hm] at hs
      rcases ih hm with ⟨ha, c⟩ | ⟨di, hdi, hk, c⟩
      · exact Or.inl ⟨ha, .step c hs⟩
      · exact Or.inr ⟨di, hdi, hk, .step c hs⟩
    · have hnone : p.lookup m = none := by simpa [InP] using hm
      obtain ⟨dm, hdm, hsd⟩ := mem_supersOf hs
      rw [lookup_append_none hnone] at hdm
      obtain ⟨e, he⟩ := Option.isSome_iff_exists.1 hx
      have hk := (ext_decl ext (lookup_mem hdm).1).2 s hsd e he
      obtain ⟨hep, hen⟩ := lookup_mem he
      exact Or.inr ⟨e, hep, hk, by rw [hen]; exact .refl⟩

/-- Types whose names `p` declares. -/
def TyIn (p : Program) (t : Ty) : Prop := ∀ n, t = .named n → InP p n

theorem openTo_of_chain (wfp : p.wellFormed = true) {di : Decl} (hdi : di ∈ p)
    (hk : di.kind = .iface false) {x : String} (c : Program.SuperChain p di.name x) :
    p.openTo (.named x) = true := by
  unfold Program.openTo
  rw [List.any_eq_true]
  refine ⟨di, hdi, ?_⟩
  simp only [hk, beq_self_eq_true, Bool.true_and, List.contains_iff_mem]
  exact mem_ancestors_of_chain (conv_of_inP wfp (lookup_isSome_of_mem hdi)) c

theorem openTo_append (wf : (p ++ q).wellFormed = true) (wfp : p.wellFormed = true)
    (ext : p.extendsOk q = true) {t : Ty} (ht : TyIn p t) :
    (p ++ q).openTo t = p.openTo t := by
  cases t with
  | anyValue => rfl
  | named n =>
    have hn : InP p n := ht n rfl
    rw [Bool.eq_iff_iff]
    unfold Program.openTo
    simp only [List.any_eq_true, Bool.and_eq_true, beq_iff_eq, List.contains_iff_mem]
    constructor
    · rintro ⟨d, hd, hk, hanc⟩
      rcases chain_exit ext (Program.chain_of_mem_ancestors hanc) hn with
        ⟨hdP, c⟩ | ⟨di, hdi, hk', c⟩
      · exact ⟨d, mem_p_of_inP ext hd hdP, hk,
          mem_ancestors_of_chain (conv_of_inP wfp hdP) c⟩
      · exact ⟨di, hdi, hk', mem_ancestors_of_chain
          (conv_of_inP wfp (lookup_isSome_of_mem hdi)) c⟩
    · rintro ⟨d, hd, hk, hanc⟩
      exact ⟨d, List.mem_append_left _ hd, hk,
        (mem_ancestors_append wf wfp (lookup_isSome_of_mem hd)).2 hanc⟩

theorem mayBeA_append (wf : (p ++ q).wellFormed = true) (wfp : p.wellFormed = true)
    (ext : p.extendsOk q = true) {t : Ty} (ht : TyIn p t) {f : String} (hf : InP p f) :
    (p ++ q).mayBeA t f = p.mayBeA t f := by
  have hfT : TyIn p (.named f) := fun n h => by cases h; exact hf
  unfold Program.mayBeA
  rw [openTo_append wf wfp ext ht, openTo_append wf wfp ext hfT, Bool.eq_iff_iff]
  simp only [Bool.or_eq_true, List.any_eq_true, Bool.and_eq_true, beq_iff_eq]
  constructor
  · rintro (⟨d, hd, ⟨hk, hst⟩, hsf⟩ | hopen)
    · by_cases hdP : InP p d.name
      · rw [isSubtype_append wf wfp hdP] at hst hsf
        exact Or.inl ⟨d, mem_p_of_inP ext hd hdP, ⟨hk, hst⟩, hsf⟩
      · right
        have exitTo : ∀ x, InP p x → (p ++ q).isSubtype (.named d.name) (.named x) = true →
            p.openTo (.named x) = true := by
          intro x hx hsx
          rcases chain_exit ext
              (Program.chain_of_mem_ancestors (Program.isSubtype_named.1 hsx)) hx with
            ⟨h, _⟩ | ⟨di, hdi, hk', c⟩
          · exact absurd h hdP
          · exact openTo_of_chain wfp hdi hk' c
        refine ⟨?_, exitTo f hf hsf⟩
        cases t with
        | anyValue => rfl
        | named n => exact exitTo n (ht n rfl) hst
    · exact Or.inr hopen
  · rintro (⟨d, hd, ⟨hk, hst⟩, hsf⟩ | hopen)
    · have hdP := lookup_isSome_of_mem hd
      rw [← isSubtype_append (q := q) wf wfp hdP] at hst hsf
      exact Or.inl ⟨d, List.mem_append_left _ hd, ⟨hk, hst⟩, hsf⟩
    · exact Or.inr hopen

end Subtyping

/-! ## Graphs -/

/-- Nodes whose types `p` declares. -/
def NodeIn (p : Program) (n : Node) : Prop := TyIn p n.type

section Graphs
variable {p q : Program}

theorem nodeIn_of_mem_allNodes {n : Node} (h : n ∈ allNodes p) : NodeIn p n := by
  unfold allNodes at h
  simp only [List.mem_append, List.mem_map, List.mem_filter, List.mem_singleton] at h
  intro m hm
  rcases h with ((⟨d, hd, rfl⟩ | rfl) | ⟨d, ⟨hd, _⟩, rfl⟩) | rfl
  · simp only [Node.type, Ty.named.injEq] at hm
    subst hm
    exact lookup_isSome_of_mem hd
  · simp [Node.type] at hm
  · simp only [Node.type, Ty.named.injEq] at hm
    subst hm
    exact lookup_isSome_of_mem hd
  · simp [Node.type] at hm

theorem allNodes_append_sub {n : Node} (h : n ∈ allNodes p) : n ∈ allNodes (p ++ q) := by
  unfold allNodes at *
  simp only [List.mem_append, List.mem_map, List.mem_filter, List.mem_singleton] at *
  rcases h with ((⟨d, hd, rfl⟩ | rfl) | ⟨d, ⟨hd, hk⟩, rfl⟩) | rfl
  · exact Or.inl (Or.inl (Or.inl ⟨d, Or.inl hd, rfl⟩))
  · exact Or.inl (Or.inl (Or.inr rfl))
  · exact Or.inl (Or.inr ⟨d, ⟨Or.inl hd, hk⟩, rfl⟩)
  · exact Or.inr rfl

theorem allNodes_append_inP (ext : p.extendsOk q = true) {n : Node} (hn : NodeIn p n)
    (h : n ∈ allNodes (p ++ q)) : n ∈ allNodes p := by
  unfold allNodes at *
  simp only [List.mem_append, List.mem_map, List.mem_filter, List.mem_singleton] at *
  rcases h with ((⟨d, hd, rfl⟩ | rfl) | ⟨d, ⟨hd, hk⟩, rfl⟩) | rfl
  · exact Or.inl (Or.inl (Or.inl ⟨d, mem_p_of_inP ext (List.mem_append.2 hd) (hn d.name rfl), rfl⟩))
  · exact Or.inl (Or.inl (Or.inr rfl))
  · exact Or.inl (Or.inr ⟨d, ⟨mem_p_of_inP ext (List.mem_append.2 hd) (hn d.name rfl), hk⟩, rfl⟩)
  · exact Or.inr rfl

theorem declEdges_src {X : Program} {d : Decl} {e : Edge} (h : e ∈ declEdges X d) :
    e.src = .ty (.named d.name) := by
  unfold declEdges at h
  split at h <;> simp only [List.mem_map, List.mem_filter, List.mem_singleton] at h
  · obtain ⟨_, _, rfl⟩ := h; rfl
  · obtain ⟨_, _, rfl⟩ := h; rfl
  · subst h; rfl

theorem declEdges_append (wfp : p.wellFormed = true) (ext : p.extendsOk q = true) {d : Decl}
    (hd : d ∈ p) : declEdges (p ++ q) d = declEdges p d := by
  unfold declEdges
  cases hk : d.kind with
  | cls => rfl
  | iface sealed =>
    cases sealed with
    | false => rfl
    | true =>
      simp only [List.filter_append]
      have hnil : q.filter (fun e => e.supers.contains d.name) = [] := by
        rw [List.filter_eq_nil_iff]
        intro e he hc
        have := (ext_decl ext he).2 d.name (by simpa using hc) d (lookup_self wfp hd)
        rw [hk] at this
        cases this
      rw [hnil, List.append_nil]

theorem edgesFor_append (wfp : p.wellFormed = true) (ext : p.extendsOk q = true)
    {main : String} {e : Edge} :
    (e ∈ edgesFor p main → e ∈ edgesFor (p ++ q) main) ∧
      (NodeIn p e.src → e ∈ edgesFor (p ++ q) main → e ∈ edgesFor p main) := by
  unfold edgesFor
  simp only [List.mem_append, List.mem_cons, List.mem_flatMap, List.mem_map, List.mem_filter]
  constructor
  · rintro (⟨d, hd, hed⟩ | h | ⟨n, ⟨hn, hf⟩, h⟩)
    · exact Or.inl ⟨d, Or.inl hd, by rw [declEdges_append wfp ext hd]; exact hed⟩
    · exact Or.inr (Or.inl h)
    · exact Or.inr (Or.inr ⟨n, ⟨allNodes_append_sub hn, hf⟩, h⟩)
  · intro hs
    rintro (⟨d, hd, hed⟩ | h | ⟨n, ⟨hn, hf⟩, rfl⟩)
    · have hdP : InP p d.name := by
        have := hs
        rw [declEdges_src hed] at this
        exact this d.name rfl
      have hdp := mem_p_of_inP ext (List.mem_append.2 hd) hdP
      exact Or.inl ⟨d, hdp, by rw [← declEdges_append wfp ext hdp]; exact hed⟩
    · exact Or.inr (Or.inl h)
    · exact Or.inr (Or.inr ⟨n, ⟨allNodes_append_inP ext hs hn, hf⟩, rfl⟩)

theorem fakeForbidsEdgesFor_append (wf : (p ++ q).wellFormed = true)
    (wfp : p.wellFormed = true) (ext : p.extendsOk q = true) {main : String} (hm : InP p main)
    {e : Edge} :
    (e ∈ fakeForbidsEdgesFor p main → e ∈ fakeForbidsEdgesFor (p ++ q) main) ∧
      (NodeIn p e.src → e ∈ fakeForbidsEdgesFor (p ++ q) main →
        e ∈ fakeForbidsEdgesFor p main) := by
  unfold fakeForbidsEdgesFor
  simp only [List.mem_flatMap, List.mem_map, List.mem_filter]
  constructor
  · rintro ⟨n, ⟨hn, hf⟩, g, hg, h⟩
    exact ⟨n, ⟨allNodes_append_sub hn, hf⟩, g, (mem_forbidsOf_append wf wfp hm).2 hg, h⟩
  · intro hs
    rintro ⟨n, ⟨hn, hf⟩, g, hg, rfl⟩
    exact ⟨n, ⟨allNodes_append_inP ext hs hn, hf⟩, g, (mem_forbidsOf_append wf wfp hm).1 hg, rfl⟩

theorem declares_append (wf : (p ++ q).wellFormed = true) (wfp : p.wellFormed = true)
    {main f : String} (hf : InP p f) {n : Node} (hn : NodeIn p n) :
    declares (p ++ q) main n f = declares p main n f := by
  unfold declares
  cases ht : n.type with
  | anyValue => rfl
  | named m =>
    have hmP : InP p m := hn m ht
    congr 1
    rw [Bool.eq_iff_iff, List.any_eq_true, List.any_eq_true]
    simp only [isSubtype_append wf wfp hf]
    constructor
    · rintro ⟨g, hg, h⟩; exact ⟨g, (mem_forbidsOf_append wf wfp hmP).1 hg, h⟩
    · rintro ⟨g, hg, h⟩; exact ⟨g, (mem_forbidsOf_append wf wfp hmP).2 hg, h⟩

end Graphs

/-! ## Paths and fixed points, by what they mean -/

/-- `E'` has `E`'s edges, and no others from nodes `p` declares; `E` stays in `p`. -/
structure Agree (p : Program) (E E' : List Edge) : Prop where
  sub : ∀ e ∈ E, e ∈ E'
  back : ∀ e ∈ E', NodeIn p e.src → e ∈ E
  closed : ∀ e ∈ E, NodeIn p e.dst

theorem Agree.append {p : Program} {E1 E1' E2 E2' : List Edge} (A1 : Agree p E1 E1')
    (A2 : Agree p E2 E2') : Agree p (E1 ++ E2) (E1' ++ E2') where
  sub e he := by
    rcases List.mem_append.1 he with he | he
    · exact List.mem_append_left _ (A1.sub e he)
    · exact List.mem_append_right _ (A2.sub e he)
  back e he hs := by
    rcases List.mem_append.1 he with he | he
    · exact List.mem_append_left _ (A1.back e he hs)
    · exact List.mem_append_right _ (A2.back e he hs)
  closed e he := by
    rcases List.mem_append.1 he with he | he
    · exact A1.closed e he
    · exact A2.closed e he

theorem Agree.gpath {p : Program} {E E' : List Edge} (A : Agree p E E') {u v : Node}
    {path : List Edge} (g : GPath E' u v path) (hu : NodeIn p u) :
    GPath E u v path ∧ NodeIn p v := by
  induction g with
  | nil => exact ⟨GPath.nil _, hu⟩
  | @cons u v rest e he hs _ ih =>
    have he' := A.back e he (by rw [hs]; exact hu)
    obtain ⟨g', hv⟩ := ih (A.closed e he')
    exact ⟨GPath.cons e he' hs g', hv⟩

theorem Agree.nodeIn {p : Program} {E E' : List Edge} (A : Agree p E E') {u v : Node}
    {path : List Edge} (g : GPath E u v path) (hu : NodeIn p u) : NodeIn p v := by
  induction g with
  | nil => exact hu
  | cons e he _ _ ih => exact ih (A.closed e he)

/-- Some path, maybe empty. -/
def Reach (es : List Edge) (u v : Node) : Prop := ∃ path, GPath es u v path

theorem Agree.reach_iff {p : Program} {E E' : List Edge} (A : Agree p E E') {u v : Node}
    (hu : NodeIn p u) : Reach E' u v ↔ Reach E u v := by
  constructor
  · rintro ⟨path, g⟩; exact ⟨path, (A.gpath g hu).1⟩
  · rintro ⟨path, g⟩; exact ⟨path, g.mono fun x hx => A.sub x (g.mem x hx)⟩

theorem mem_reachFrom_iff {es : List Edge} {fuel : Nat} {u v : Node}
    (conv : reachConverged es fuel u = true) :
    v ∈ reachFrom es fuel u ↔ ∃ e rest, GPath es u v (e :: rest) := by
  constructor
  · intro h
    unfold reachFrom at h
    refine foldl_induct (fun s => ∀ x ∈ s, ∃ e rest, GPath es u x (e :: rest)) _ _ _ ?_ ?_ v h
    · intro x hx
      rw [mem_dedup, List.mem_map] at hx
      obtain ⟨e, he, rfl⟩ := hx
      obtain ⟨he, hs⟩ := List.mem_filter.1 he
      exact ⟨e, [], GPath.cons e he (by simpa using hs) (GPath.nil _)⟩
    · intro s _ hs x hx
      rcases mem_reachStep.1 hx with hx | ⟨e, he, hsrc, rfl⟩
      · exact hs x hx
      · obtain ⟨e0, rest, g⟩ := hs _ hsrc
        exact ⟨e0, rest ++ [e], GPath.append g (GPath.cons e he rfl (GPath.nil _))⟩
  · rintro ⟨e, rest, g⟩
    rcases GPath.reach conv g (Or.inl rfl) with ⟨h, _⟩ | h
    · simp at h
    · exact h

theorem reach_iff {es : List Edge} {fuel : Nat} {u v : Node}
    (conv : reachConverged es fuel u = true) :
    (v = u ∨ v ∈ reachFrom es fuel u) ↔ Reach es u v := by
  rw [mem_reachFrom_iff conv]
  constructor
  · rintro (rfl | ⟨e, rest, g⟩)
    · exact ⟨[], GPath.nil _⟩
    · exact ⟨_, g⟩
  · rintro ⟨path, g⟩
    cases path with
    | nil => exact Or.inl (GPath.nil_eq g).symm
    | cons e rest => exact Or.inr ⟨e, rest, g⟩

theorem reverseEdges_reverseEdges (es : List Edge) : reverseEdges (reverseEdges es) = es := by
  induction es with
  | nil => rfl
  | cons e es ih =>
    simp only [reverseEdges, List.map_cons, List.cons.injEq] at ih ⊢
    exact ⟨trivial, ih⟩

theorem back_iff {es : List Edge} {fuel : Nat} {u v : Node}
    (conv : reachConverged (reverseEdges es) fuel u = true) :
    (v = u ∨ v ∈ reachFrom (reverseEdges es) fuel u) ↔ Reach es v u := by
  rw [reach_iff conv]
  constructor
  · rintro ⟨path, g⟩
    have := g.reverse
    rw [reverseEdges_reverseEdges] at this
    exact ⟨_, this⟩
  · rintro ⟨path, g⟩
    exact ⟨_, g.reverse⟩

theorem Agree.reachFrom_iff {p : Program} {E E' : List Edge} (A : Agree p E E') {u : Node}
    (hu : NodeIn p u) {f1 f2 : Nat} (c1 : reachConverged E f1 u = true)
    (c2 : reachConverged E' f2 u = true) (v : Node) :
    v ∈ reachFrom E f1 u ↔ v ∈ reachFrom E' f2 u := by
  rw [mem_reachFrom_iff c1, mem_reachFrom_iff c2]
  constructor
  · rintro ⟨e, rest, g⟩; exact ⟨e, rest, g.mono fun x hx => A.sub x (g.mem x hx)⟩
  · rintro ⟨e, rest, g⟩; exact ⟨e, rest, (A.gpath g hu).1⟩

/-- The "always" fixed point's defining property, forwards. -/
theorem always_post {p : Program} {main f : String} {es : List Edge}
    (conv : alwaysConverged p main es f = true) {n : Node}
    (hn : n ∈ alwaysForbidden p main es f) :
    declares p main n f = true ∨ ∀ e ∈ es, e.dst = n →
      (e.src = .ty (.named main) ∨
        e.src ∈ reachFrom es ((allNodes p).length + 1) (.ty (.named main))) →
      e.src ∈ alwaysForbidden p main es f := by
  unfold alwaysConverged at conv
  simp only [Bool.and_eq_true, beq_iff_eq] at conv
  have hin := hn
  rw [← conv.2] at hin
  unfold alwaysStep at hin
  have hkeep := (List.mem_filter.1 hin).2
  rw [Bool.or_eq_true, List.all_eq_true] at hkeep
  rcases hkeep with h | h
  · exact Or.inl h
  · right
    intro e he hd hl
    have := h e he
    simp only [Bool.not_eq_true', Bool.and_eq_false_iff] at this
    rcases this with (h1 | h1) | h1
    · simp [hd] at h1
    · exfalso
      rcases hl with hl | hl <;> simp [hl] at h1
    · simpa using h1

/-- The "always" fixed point is the greatest: any set with its defining property is inside. -/
theorem always_greatest {p : Program} {main f : String} {es : List Edge} (S : Node → Prop)
    (hS : ∀ n, S n →
      n ∈ reachFrom es ((allNodes p).length + 1) (.ty (.named main)) ∧
      n ≠ .ty (.named main) ∧
      (declares p main n f = true ∨ ∀ e ∈ es, e.dst = n →
        (e.src = .ty (.named main) ∨
          e.src ∈ reachFrom es ((allNodes p).length + 1) (.ty (.named main))) →
        S e.src)) :
    ∀ n, S n → n ∈ alwaysForbidden p main es f := by
  intro n hn
  unfold alwaysForbidden
  simp only
  refine foldl_induct (fun s => ∀ n, S n → n ∈ s) _ _ _ ?_ ?_ n hn
  · intro n hn
    obtain ⟨h1, h2, _⟩ := hS n hn
    exact List.mem_filter.2 ⟨h1, by simpa using h2⟩
  · intro s _ hs n hn
    unfold alwaysStep
    refine List.mem_filter.2 ⟨hs n hn, ?_⟩
    obtain ⟨_, _, h⟩ := hS n hn
    rw [Bool.or_eq_true, List.all_eq_true]
    rcases h with h | h
    · exact Or.inl h
    · right
      intro e he
      by_cases hd : e.dst = n
      · by_cases hl : e.src = .ty (.named main) ∨
            e.src ∈ reachFrom es ((allNodes p).length + 1) (.ty (.named main))
        · have := hs _ (h e he hd hl)
          simp [this]
        · simp only [not_or] at hl
          simp [hl.1, hl.2]
      · simp [hd]

theorem always_transfer {p1 p2 : Program} {main f : String} {E1 E2 : List Edge}
    (c1 : alwaysConverged p1 main E1 f = true)
    (hreach : ∀ n, n ∈ reachFrom E1 ((allNodes p1).length + 1) (.ty (.named main)) ↔
      n ∈ reachFrom E2 ((allNodes p2).length + 1) (.ty (.named main)))
    (hedge : ∀ e ∈ E2, (e.src = .ty (.named main) ∨
      e.src ∈ reachFrom E1 ((allNodes p1).length + 1) (.ty (.named main))) → e ∈ E1)
    (hdecl : ∀ n ∈ reachFrom E1 ((allNodes p1).length + 1) (.ty (.named main)),
      declares p1 main n f = true → declares p2 main n f = true) :
    ∀ n ∈ alwaysForbidden p1 main E1 f, n ∈ alwaysForbidden p2 main E2 f := by
  intro n hn
  refine always_greatest (fun n => n ∈ alwaysForbidden p1 main E1 f) ?_ n hn
  intro n hn
  obtain ⟨hr, hne⟩ := alwaysForbidden_sub hn
  refine ⟨(hreach n).1 hr, hne, ?_⟩
  rcases always_post c1 hn with h | h
  · exact Or.inl (hdecl n hr h)
  · right
    intro e he hd hl
    have hl1 := hl.imp id (hreach _).2
    exact h e (hedge e he hl1) hd hl1

/-! ## What a check says -/

/-- Step IV finds no cycle through mainNode. -/
def CycleFree (p : Program) (main : String) : Prop :=
  ∀ e ∈ prunedEdges p main, e.kind = .hasA false →
    Reach (prunedEdges p main) (.ty (.named main)) e.src →
    Reach (prunedEdges p main) e.dst (.ty (.named main)) → False

/-- Step V finds no mismatch. -/
def StepVOk (p : Program) (main : String) : Prop :=
  ∀ f ∈ p.forbidsOf main, ∀ e ∈ prunedEdges p main ++ fakeForbidsEdgesFor p main,
    ∀ b, e.kind = .hasA b →
    Reach (prunedEdges p main ++ fakeForbidsEdgesFor p main) (.ty (.named main)) e.src →
    e.src ∉ alwaysForbidden p main (edgesFor p main ++ fakeForbidsEdgesFor p main) f →
    p.mayBeA e.dst.type f = true → False

section Check
variable {p : Program} {main : String}

theorem graphs_converged (wf : p.wellFormed = true) (hm : InP p main) :
    reachConverged (prunedEdges p main) (fuelFor p) (.ty (.named main)) = true ∧
    reachConverged (reverseEdges (prunedEdges p main)) (fuelFor p) (.ty (.named main)) = true ∧
    reachConverged (prunedEdges p main ++ fakeForbidsEdgesFor p main) (fuelFor p)
      (.ty (.named main)) = true := by
  have := check_converged wf hm true
  simp only [check, Bool.and_eq_true, if_true] at this
  exact ⟨this.1.1.1.2, this.1.1.2, this.1.2⟩

/-- For a well-formed program, a check passes when Steps IV and V find nothing. -/
theorem ok_iff (wf : p.wellFormed = true) (hm : InP p main) :
    (check p main).ok = true ↔ CycleFree p main ∧ StepVOk p main := by
  obtain ⟨cP, cB, cV⟩ := graphs_converged wf hm
  constructor
  · intro ok
    have facts := stepIV_facts ok
    refine ⟨fun e he hk hs hd => facts.1 e he hk ((reach_iff cP).2 hs) ((back_iff cB).2 hd), ?_⟩
    intro f hf e he b hk hr hna hmay
    have hnil := stepVBad_nil ok hf
    unfold stepVBad at hnil
    rw [List.filter_eq_nil_iff] at hnil
    apply hnil e he
    rw [hk]
    simp only [Bool.and_eq_true, beq_iff_eq, Bool.or_eq_true, List.contains_iff_mem,
      Bool.not_eq_true']
    refine ⟨⟨(reach_iff cV).2 hr, ?_⟩, hmay⟩
    simpa using hna
  · rintro ⟨cyc, sv⟩
    have conv := check_converged wf hm true
    simp only [check, Bool.and_eq_true, if_true] at conv
    simp only [check, Result.ok, Bool.and_eq_true, List.isEmpty_iff, if_true]
    refine ⟨⟨conv, ?_⟩, ?_⟩
    · rw [List.filter_eq_nil_iff]
      intro e he h
      simp only [Bool.and_eq_true, beq_iff_eq, Bool.or_eq_true, List.contains_iff_mem] at h
      obtain ⟨⟨hk, hs⟩, hd⟩ := h
      exact cyc e he hk ((reach_iff cP).1 hs) ((back_iff cB).1 hd)
    · split
      · rfl
      · simp only [List.flatMap_eq_nil_iff, List.map_eq_nil_iff]
        intro f hf
        unfold stepVBad
        rw [List.filter_eq_nil_iff]
        intro e he h
        cases hk : e.kind with
        | canBeA => rw [hk] at h; simp at h
        | hasA b =>
          rw [hk] at h
          simp only [Bool.and_eq_true, beq_iff_eq, Bool.or_eq_true, List.contains_iff_mem,
            Bool.not_eq_true'] at h
          obtain ⟨⟨hs, hna⟩, hmay⟩ := h
          exact sv f hf e he b hk ((reach_iff cV).1 hs) (by simpa using hna) hmay

end Check

/-! ## Separate compilation -/

section Extend
variable {p q : Program}

theorem inP_of_forbidsOf (wfp : p.wellFormed = true) {m f : String} (hf : f ∈ p.forbidsOf m) :
    InP p f := by
  obtain ⟨_, _, dm, hdm, hfm⟩ := Program.mem_forbidsOf.1 hf
  exact (wf_decl_all wfp (lookup_mem hdm).1).2.2 f hfm

theorem nodeIn_main {main : String} (hm : InP p main) : NodeIn p (.ty (.named main)) := by
  intro n h
  simp only [Node.type, Ty.named.injEq] at h
  subst h
  exact hm

theorem mem_prunedEdges_iff {X : Program} {main : String} {e : Edge} :
    e ∈ prunedEdges X main ↔ e ∈ edgesFor X main ∧
      (e.src.isFake = true → e.src ∉ alwaysForbidden X main (edgesFor X main) main) := by
  unfold prunedEdges
  simp only [List.mem_filter, Bool.not_eq_true', Bool.and_eq_false_iff, List.contains_iff_mem]
  constructor
  · rintro ⟨he, h⟩
    refine ⟨he, fun hf hin => ?_⟩
    rcases h with h | h
    · rw [hf] at h; cases h
    · simp [hin] at h
  · rintro ⟨he, h⟩
    refine ⟨he, ?_⟩
    cases hf : e.src.isFake
    · exact Or.inl rfl
    · exact Or.inr (by simpa using h hf)

/-- "Always" means the same in `p ++ q` as in `p`, given graphs that agree. -/
theorem always_append_iff (wf : (p ++ q).wellFormed = true) (wfp : p.wellFormed = true)
    {main : String} (hm : InP p main) {E E' : List Edge} (A : Agree p E E')
    (nE : ∀ e ∈ E, e.dst ∈ allNodes p) (nE' : ∀ e ∈ E', e.dst ∈ allNodes (p ++ q))
    {f : String} (hf : InP p f) (n : Node) :
    n ∈ alwaysForbidden p main E f ↔ n ∈ alwaysForbidden (p ++ q) main E' f := by
  have hM := nodeIn_main hm
  have reachE := A.reachFrom_iff hM (reachConverged_of_bound nE _) (reachConverged_of_bound nE' _)
  have inP : ∀ n ∈ reachFrom E ((allNodes p).length + 1) (.ty (.named main)), NodeIn p n :=
    fun n hn => nodeIn_of_mem_allNodes ((reachFrom_nodup nE _ _).2 n hn)
  constructor
  · refine always_transfer (alwaysConverged_of_bound nE) reachE ?_ ?_ n
    · intro e he hl
      apply A.back e he
      rcases hl with h | h
      · rw [h]; exact hM
      · exact inP _ h
    · intro n hn h
      rwa [declares_append wf wfp hf (inP n hn)]
  · refine always_transfer (alwaysConverged_of_bound nE') (fun n => (reachE n).symm) ?_ ?_ n
    · intro e he _
      exact A.sub e he
    · intro n hn h
      rwa [← declares_append wf wfp hf (inP n ((reachE n).2 hn))]

/--
Separate compilation: adding another library `q` on top of `p` doesn't
change whether `p`'s classes pass.  With `acyclic_of_passes`, a library that
passes stays sound however later libraries use it.
-/
theorem check_extend (wf : (p ++ q).wellFormed = true) (wfp : p.wellFormed = true)
    (ext : p.extendsOk q = true) {main : String} (hm : InP p main) :
    (check (p ++ q) main).ok = (check p main).ok := by
  have hm' : InP (p ++ q) main := by simp only [InP, lookup_append_inP hm]; exact hm
  rw [Bool.eq_iff_iff, ok_iff wf hm', ok_iff wfp hm]
  have hM := nodeIn_main hm
  have nE := edgesFor_nodes wfp hm
  have nE' := edgesFor_nodes wf hm'
  have nX := fakeForbidsEdgesFor_nodes wfp (main := main)
  have nX' := fakeForbidsEdgesFor_nodes wf (main := main)
  have AE : Agree p (edgesFor p main) (edgesFor (p ++ q) main) :=
    ⟨fun _ he => (edgesFor_append wfp ext).1 he, fun _ he hs => (edgesFor_append wfp ext).2 hs he,
      fun e he => nodeIn_of_mem_allNodes (nE e he).2⟩
  have AX : Agree p (fakeForbidsEdgesFor p main) (fakeForbidsEdgesFor (p ++ q) main) :=
    ⟨fun _ he => (fakeForbidsEdgesFor_append wf wfp ext hm).1 he,
      fun _ he hs => (fakeForbidsEdgesFor_append wf wfp ext hm).2 hs he,
      fun e he => nodeIn_of_mem_allNodes (nX e he).2⟩
  have dstsApp : ∀ {X : Program} {a b : List Edge},
      (∀ e ∈ a, e.src ∈ allNodes X ∧ e.dst ∈ allNodes X) →
      (∀ e ∈ b, e.src ∈ allNodes X ∧ e.dst ∈ allNodes X) → ∀ e ∈ a ++ b, e.dst ∈ allNodes X := by
    intro X a b ha hb e he
    rcases List.mem_append.1 he with he | he
    · exact (ha e he).2
    · exact (hb e he).2
  have hAM := always_append_iff wf wfp hm AE (fun e he => (nE e he).2) (fun e he => (nE' e he).2) hm
  have AP : Agree p (prunedEdges p main) (prunedEdges (p ++ q) main) := by
    refine ⟨fun e he => ?_, fun e he hs => ?_, fun e he => AE.closed e (mem_prunedEdges_iff.1 he).1⟩
    · obtain ⟨he, h⟩ := mem_prunedEdges_iff.1 he
      exact mem_prunedEdges_iff.2 ⟨AE.sub e he, fun hf hin => h hf ((hAM _).2 hin)⟩
    · obtain ⟨he, h⟩ := mem_prunedEdges_iff.1 he
      exact mem_prunedEdges_iff.2 ⟨AE.back e he hs, fun hf hin => h hf ((hAM _).1 hin)⟩
  have AV := AP.append AX
  have hAF : ∀ f, InP p f → ∀ n,
      n ∈ alwaysForbidden p main (edgesFor p main ++ fakeForbidsEdgesFor p main) f ↔
        n ∈ alwaysForbidden (p ++ q) main
          (edgesFor (p ++ q) main ++ fakeForbidsEdgesFor (p ++ q) main) f :=
    fun f hf => always_append_iff wf wfp hm (AE.append AX) (dstsApp nE nX) (dstsApp nE' nX') hf
  refine and_congr ⟨fun h => ?_, fun h => ?_⟩ ⟨fun h => ?_, fun h => ?_⟩
  · intro e he hk ⟨ps, gs⟩ ⟨pd, gd⟩
    exact h e (AP.sub e he) hk ⟨_, gs.mono fun x hx => AP.sub x (gs.mem x hx)⟩
      ⟨_, gd.mono fun x hx => AP.sub x (gd.mem x hx)⟩
  · intro e he hk ⟨ps, gs⟩ ⟨pd, gd⟩
    obtain ⟨gs', hsN⟩ := AP.gpath gs hM
    have heP := AP.back e he hsN
    obtain ⟨gd', _⟩ := AP.gpath gd (AP.closed e heP)
    exact h e heP hk ⟨_, gs'⟩ ⟨_, gd'⟩
  · intro f hf e he b hk ⟨ps, gs⟩ hna hmay
    have hfI := inP_of_forbidsOf wfp hf
    refine h f ((mem_forbidsOf_append wf wfp hm).2 hf) e (AV.sub e he) b hk
      ⟨_, gs.mono fun x hx => AV.sub x (gs.mem x hx)⟩
      (fun hin => hna ((hAF f hfI _).2 hin)) ?_
    rw [mayBeA_append wf wfp ext (AV.closed e he) hfI]
    exact hmay

  · intro f hf e he b hk ⟨ps, gs⟩ hna hmay
    have hfP := (mem_forbidsOf_append wf wfp hm).1 hf
    obtain ⟨gs', hsN⟩ := AV.gpath gs hM
    have heP := AV.back e he hsN
    refine h f hfP e heP b hk ⟨_, gs'⟩
      (fun hin => hna ((hAF f (inP_of_forbidsOf wfp hfP) _).1 hin)) ?_
    rw [← mayBeA_append wf wfp ext (AV.closed e heP) (inP_of_forbidsOf wfp hfP)]
    exact hmay
end Extend

end Cycles
