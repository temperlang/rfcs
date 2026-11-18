import Cycles.Soundness

/-!
# The main theorems

`forbidsKept` and `acyclic_of_passes`.  Separate compilation
(`check_extend`) is in `Extend.lean`.
-/

namespace Cycles

/-! ## Graph paths -/

theorem GPath.append {es : List Edge} {u w v : Node} {p1 p2 : List Edge}
    (g1 : GPath es u w p1) (g2 : GPath es w v p2) : GPath es u v (p1 ++ p2) := by
  induction g1 with
  | nil => simpa using g2
  | cons e he hs _ ih => exact GPath.cons e he hs (ih g2)

theorem GPath.mem {es : List Edge} {u v : Node} {path : List Edge}
    (g : GPath es u v path) : ∀ x ∈ path, x ∈ es := by
  induction g with
  | nil => simp
  | cons e he _ _ ih =>
    intro x hx
    rcases List.mem_cons.1 hx with hx | hx
    · subst hx; exact he
    · exact ih x hx

theorem GPath.mono {es es' : List Edge} {u v : Node} {path : List Edge}
    (g : GPath es u v path) (sub : ∀ x ∈ path, x ∈ es') : GPath es' u v path := by
  induction g with
  | nil => exact GPath.nil _
  | cons e _ hs _ ih =>
    exact GPath.cons e (sub e (List.mem_cons_self _ _)) hs
      (ih (fun x hx => sub x (List.mem_cons_of_mem _ hx)))

theorem GPath.reach {es : List Edge} {fuel : Nat} {u : Node}
    (conv : reachConverged es fuel u = true) {w v : Node} {path : List Edge}
    (g : GPath es w v path) (hw : w = u ∨ w ∈ reachFrom es fuel u) :
    (path = [] ∧ v = w) ∨ v ∈ reachFrom es fuel u := by
  induction g with
  | nil => exact Or.inl ⟨rfl, rfl⟩
  | @cons w v rest e he hs _ ih =>
    right
    have hdst : e.dst ∈ reachFrom es fuel u := by
      rcases hw with hw | hw
      · exact reachFrom_of_start he (by rw [hs, hw])
      · exact reachFrom_closed conv he (by rw [hs]; exact hw)
    rcases ih (Or.inr hdst) with ⟨_, hv⟩ | hv
    · rw [hv]; exact hdst
    · exact hv

/-- The has-a edge for property `q` of class `d`. -/
def hasAEdge (d : Decl) (q : Property) : Edge :=
  { src := .ty (.named d.name), dst := .ty q.type,
    kind := .hasA (q.kind == PropKind.early), label := "." ++ q.name }

theorem hasA_edge_mem {p : Program} {main : String} {d : Decl} (hd : d ∈ p)
    (hk : d.kind = .cls) {q : Property} (hq : q ∈ d.props) :
    hasAEdge d q ∈ edgesFor p main := by
  apply mem_edgesFor_of_declEdges hd
  unfold declEdges
  rw [hk]
  exact List.mem_map_of_mem _ hq

theorem HPath.head {h : Heap} {a b : Nat} {s : Nat × String} {rest : List (Nat × String)}
    (path : HPath h a b (s :: rest)) : s.1 = a := by
  cases path
  rfl

/-! ## Mapping pointer paths into a class's graph -/

/-- `t` is a super-type of the class of some object strictly inside the path. -/
def Inter (p : Program) (h : Heap) (steps : List (Nat × String)) (t : Ty) : Prop :=
  ∃ s ∈ steps.tail, ∃ o, h[s.1]? = some o ∧ p.isSubtype (.named o.cls) t = true

/--
A pointer path from `y` to `z` maps into any class's graph, starting at
`y`'s class: each pointer is a has-a edge to the property's type, then
can-be-a edges down to the next object's class.  Either the map reaches
the last has-a edge, into a super-type of `z`'s class, or it reaches a fake
class first.  Every node it passes on the way stands for an object strictly
inside the path.
-/
theorem walk {p : Program} (wf : p.wellFormed = true) {h : Heap} (wt : WellTyped p h)
    (cd : ClassesDeclared p h) (main : String) {y z : Nat} {steps : List (Nat × String)}
    (path : HPath h y z steps) (ne : steps ≠ []) {oy oz : Obj}
    (hy : h[y]? = some oy) (hz : h[z]? = some oz) :
    ∃ d q, p.lookup oy.cls = some d ∧ q ∈ d.props ∧ steps.head? = some (y, q.name) ∧
    ((∃ es e, GPath (edgesFor p main) (.ty (.named oy.cls)) e.src es ∧
      e ∈ edgesFor p main ∧ (∃ k, e.kind = .hasA k) ∧ e.src.isFake = false ∧
      p.isSubtype (.named oz.cls) e.dst.type = true ∧
      (∀ x ∈ es, Inter p h steps x.dst.type ∧ x.src.isFake = false) ∧
      e.dst = .ty e.dst.type ∧ (es ++ [e]).head? = some (hasAEdge d q)) ∨
    (∃ es v, GPath (edgesFor p main) (.ty (.named oy.cls)) v es ∧ v.isFake = true ∧
      v ∈ allNodes p ∧ es ≠ [] ∧
      (∀ x ∈ es, Inter p h steps x.dst.type ∧ x.src.isFake = false) ∧
      es.head? = some (hasAEdge d q))) := by
  induction path generalizing oy with
  | nil => exact absurd rfl ne
  | @cons a b c n rest pt rpath ih =>
    obtain ⟨o0, ho0, hmem⟩ := pt
    rw [hy] at ho0
    cases ho0
    obtain ⟨d, hd, hdk⟩ := cd a oy hy
    obtain ⟨ob, q, hob, hq, hqn, hsub⟩ := wt a b oy d n hy hd hmem
    obtain ⟨hdp, hdn⟩ := lookup_mem hd
    have he1 := hasA_edge_mem (main := main) hdp hdk hq
    have hsrc : Node.ty (.named d.name) = .ty (.named oy.cls) := by rw [hdn]
    refine ⟨d, q, hd, hq, by simp [hqn], ?_⟩
    cases rest with
    | nil =>
      cases rpath
      rw [hob] at hz
      cases hz
      left
      refine ⟨[], hasAEdge d q, ?_, he1, ⟨_, rfl⟩, rfl, hsub, by simp, rfl, by simp⟩
      have : (hasAEdge d q).src = .ty (.named oy.cls) := by simp [hasAEdge, hdn]
      rw [this]
      exact GPath.nil _
    | cons s rest' =>
      have hs1 : s.1 = b := rpath.head
      have inter : ∀ t, p.isSubtype (.named ob.cls) t = true →
          Inter p h ((a, n) :: s :: rest') t :=
        fun t ht => ⟨s, List.mem_cons_self _ _, ob, by rw [hs1]; exact hob, ht⟩
      have interMono : ∀ t, Inter p h (s :: rest') t → Inter p h ((a, n) :: s :: rest') t := by
        rintro t ⟨s', hs', o', ho', ht⟩
        exact ⟨s', List.mem_cons_of_mem _ hs', o', ho', ht⟩
      obtain ⟨db, hdb, _⟩ := cd b ob hob
      obtain ⟨v1, es1, g1, hes1, hv1⟩ := canBeA_path wf (main := main) hdb hsub
      have hfirst : ∀ x ∈ hasAEdge d q :: es1,
          Inter p h ((a, n) :: s :: rest') x.dst.type ∧ x.src.isFake = false := by
        intro x hx
        rcases List.mem_cons.1 hx with hx | hx
        · subst hx
          exact ⟨inter _ hsub, rfl⟩
        · obtain ⟨_, hnf, hxs⟩ := hes1 x hx
          exact ⟨inter _ hxs, hnf⟩
      rcases hv1 with hv1 | ⟨hvf, _, hvn⟩
      · subst hv1
        obtain ⟨_, _, _, _, _, hrest⟩ := ih (List.cons_ne_nil _ _) hob hz
        rcases hrest with
            ⟨es, e, g, he, hk, hnf, hsubE, hes, hdst, _⟩ | ⟨es, v, g, hvf, hvn, hne, hes, _⟩
        · left
          refine ⟨hasAEdge d q :: es1 ++ es, e, ?_, he, hk, hnf, hsubE, ?_, hdst, by simp⟩
          · rw [← hsrc]
            exact GPath.cons _ he1 rfl (GPath.append g1 g)
          · intro x hx
            rcases List.mem_append.1 hx with hx | hx
            · exact hfirst x hx
            · exact ⟨interMono _ (hes x hx).1, (hes x hx).2⟩
        · right
          refine ⟨hasAEdge d q :: es1 ++ es, v, ?_, hvf, hvn, by simp, ?_, by simp⟩
          · rw [← hsrc]
            exact GPath.cons _ he1 rfl (GPath.append g1 g)
          · intro x hx
            rcases List.mem_append.1 hx with hx | hx
            · exact hfirst x hx
            · exact ⟨interMono _ (hes x hx).1, (hes x hx).2⟩
      · right
        refine ⟨hasAEdge d q :: es1, v1, ?_, hvf, hvn, by simp, hfirst, by simp⟩
        rw [← hsrc]
        exact GPath.cons _ he1 rfl g1

/-! ## What a passing check says -/

theorem check_ok_of_passes {p : Program} (ok : p.passes = true) {n : String} {d : Decl}
    (hd : p.lookup n = some d) (hk : d.kind = .cls) : (check p n).ok = true := by
  obtain ⟨hdp, hdn⟩ := lookup_mem hd
  unfold Program.passes at ok
  have := List.all_eq_true.1 ok d hdp
  simp only [hk, bne_self_eq_false, Bool.false_or] at this
  rw [hdn] at this
  exact this

theorem stepVBad_nil {p : Program} {main : String} (ok : (check p main).ok = true) {f : String}
    (hf : f ∈ p.forbidsOf main) : stepVBad p main (fakeForbidsEdgesFor p main) f = [] := by
  simp only [check, Result.ok, Bool.and_eq_true] at ok
  obtain ⟨⟨_, cyc⟩, mis⟩ := ok
  simp only [cyc, Bool.not_true, Bool.false_eq_true, if_false, if_true, List.isEmpty_iff,
    List.flatMap_eq_nil_iff, List.map_eq_nil_iff] at mis
  exact mis f hf

theorem stepV_converged {p : Program} {main : String} (ok : (check p main).ok = true)
    {f : String} (hf : f ∈ p.forbidsOf main) :
    alwaysConverged p main (edgesFor p main ++ fakeForbidsEdgesFor p main) f = true ∧
    reachConverged (prunedEdges p main ++ fakeForbidsEdgesFor p main) (fuelFor p)
      (.ty (.named main)) = true := by
  simp only [check, Result.ok, Bool.and_eq_true, List.all_eq_true, if_true] at ok
  exact ⟨ok.1.1.2 f hf, ok.1.1.1.2⟩

theorem mem_prunedEdges {p : Program} {main : String} {e : Edge} (he : e ∈ edgesFor p main)
    (hnf : e.src.isFake = false) : e ∈ prunedEdges p main := by
  unfold prunedEdges
  exact List.mem_filter.2 ⟨he, by simp [hnf]⟩

/-! ## Invariant 4 -/

/-- The object at `x` forbids some super-type of `b`. -/
def Forb (p : Program) (h : Heap) (b : String) (x : Nat) : Prop :=
  ∃ o, h[x]? = some o ∧ ∃ g ∈ p.forbidsOf o.cls, p.isSubtype (.named b) (.named g) = true

/-- On a path to `z`, either nothing forbids, or there's a last object that does. -/
theorem last_forbidder {p : Program} {h : Heap} {b : String} {x z : Nat}
    {steps : List (Nat × String)} (path : HPath h x z steps) :
    (∀ s ∈ steps, ¬ Forb p h b s.1) ∨
      ∃ y steps', HPath h y z steps' ∧ steps' ≠ [] ∧ Forb p h b y ∧
        ∀ s ∈ steps'.tail, ¬ Forb p h b s.1 := by
  induction path with
  | nil => exact Or.inl (by simp)
  | @cons a a1 c n rest pt rpath ih =>
    rcases ih with hall | hsuffix
    · by_cases hf : Forb p h b a
      · exact Or.inr ⟨a, (a, n) :: rest, HPath.cons pt rpath, by simp, hf, hall⟩
      · left
        intro s hs
        rcases List.mem_cons.1 hs with hs | hs
        · subst hs; exact hf
        · exact hall s hs
    · exact Or.inr hsuffix

theorem isSubtype_trans {p : Program} {a b : String} {t : Ty}
    (conv : p.ancestorsConverged a = true) (hab : p.isSubtype (.named a) (.named b) = true)
    (hbt : p.isSubtype (.named b) t = true) : p.isSubtype (.named a) t = true := by
  cases t with
  | anyValue => simp [Program.isSubtype]
  | named c =>
    rw [Program.isSubtype_named] at *
    exact Program.ancestors_trans conv hab c hbt

theorem conv_of_lookup {p : Program} (wf : p.wellFormed = true) {n : String} {d : Decl}
    (hd : p.lookup n = some d) : p.ancestorsConverged n = true := by
  obtain ⟨hdp, hdn⟩ := lookup_mem hd
  have := (wf_decl wf hdp).2
  rwa [hdn] at this

theorem forbidsKept {p : Program} (wf : p.wellFormed = true) (ok : p.passes = true)
    {h : Heap} (r : Reachable p h) : ForbidsKept p h := by
  intro a b o ob f steps ha hf path ne hb
  cases hB : p.isSubtype (.named ob.cls) (.named f) with
  | false => rfl
  | true =>
  exfalso
  have wt := wellTyped r
  have cd := classesDeclared r
  obtain ⟨dB, hdB, hdBk⟩ := cd b ob hb
  have convB := conv_of_lookup wf hdB
  rcases last_forbidder (b := ob.cls) path with hall | ⟨y, steps', path', ne', hFy, hlast⟩
  · cases steps with
    | nil => exact ne rfl
    | cons s rest =>
      have := hall s (List.mem_cons_self _ _)
      rw [path.head] at this
      exact this ⟨o, ha, f, hf, hB⟩
  · obtain ⟨oy, hy, g, hg, hBg⟩ := hFy
    obtain ⟨dD, hdD, hdDk⟩ := cd y oy hy
    have okD := check_ok_of_passes ok hdD hdDk
    have mis := stepVBad_nil okD hg
    obtain ⟨aconv, rconv⟩ := stepV_converged okD hg
    -- Nodes standing for objects inside the path don't declare `g`.
    have noDecl : ∀ x : Edge, Inter p h steps' x.dst.type → declares p oy.cls x.dst g = false := by
      intro x ⟨s, hs, o', ho', hsub'⟩
      obtain ⟨d', hd', _⟩ := cd s.1 o' ho'
      have conv' := conv_of_lookup wf hd'
      unfold declares
      cases hxt : x.dst.type with
      | anyValue => simp
      | named m =>
        simp only [Bool.and_eq_false_iff]
        right
        rw [List.any_eq_false]
        intro g' hg' hgg'
        rw [hxt] at hsub'
        apply hlast s hs
        refine ⟨o', ho', g', Program.forbidsOf_mono conv' hsub' hg', ?_⟩
        exact isSubtype_trans convB hBg hgg'
    have mayB : ∀ t, p.isSubtype (.named ob.cls) t = true → p.mayBeA t g = true := by
      intro t ht
      obtain ⟨hdBp, hdBn⟩ := lookup_mem hdB
      unfold Program.mayBeA
      simp only [Bool.or_eq_true, List.any_eq_true, Bool.and_eq_true, beq_iff_eq]
      left
      exact ⟨dB, hdBp, ⟨⟨hdBk, by rw [hdBn]; exact ht⟩, by rw [hdBn]; exact hBg⟩⟩
    -- Whatever `walk` finds is a Step V mismatch.
    have bad : ∀ e : Edge, ∀ es : List Edge, ∀ k,
        GPath (edgesFor p oy.cls ++ fakeForbidsEdgesFor p oy.cls) (.ty (.named oy.cls)) e.src es →
        (∀ x ∈ es, x ∈ prunedEdges p oy.cls ++ fakeForbidsEdgesFor p oy.cls) →
        (∀ x ∈ es, declares p oy.cls x.dst g = false) →
        e ∈ prunedEdges p oy.cls ++ fakeForbidsEdgesFor p oy.cls → e.kind = .hasA k →
        p.mayBeA e.dst.type g = true → False := by
      intro e es k gp inV nd he hk hmay
      have hin : e ∈ stepVBad p oy.cls (fakeForbidsEdgesFor p oy.cls) g := by
        unfold stepVBad
        refine List.mem_filter.2 ⟨he, ?_⟩
        rw [hk]
        simp only [Bool.and_eq_true, Bool.or_eq_true, beq_iff_eq, Bool.not_eq_true',
          List.contains_eq_any_beq]
        refine ⟨⟨?_, ?_⟩, hmay⟩
        · rcases GPath.reach rconv (gp.mono inV) (Or.inl rfl) with ⟨_, hsrc⟩ | hsrc
          · exact Or.inl hsrc
          · right
            exact List.any_eq_true.2 ⟨e.src, hsrc, by simp⟩
        · have := not_always_of_path aconv gp nd
          rw [List.any_eq_false]
          intro x hx hxe
          simp at hxe
          subst hxe
          exact this hx
      rw [mis] at hin
      simp at hin
    obtain ⟨_, _, _, _, _, hw⟩ := walk wf wt cd oy.cls path' ne' hy hb
    rcases hw with
        ⟨es, e, gp, he, ⟨k, hk⟩, hnf, hsubE, hes, _, _⟩ | ⟨es, v, gp, hvf, hvn, hne, hes, _⟩
    · have inP : ∀ x ∈ es, x ∈ prunedEdges p oy.cls :=
        fun x hx => mem_prunedEdges (gp.mem x hx) (hes x hx).2
      exact bad e es k
        (gp.mono fun x hx => List.mem_append_left _ (gp.mem x hx))
        (fun x hx => List.mem_append_left _ (inP x hx))
        (fun x hx => noDecl x (hes x hx).1)
        (List.mem_append_left _ (mem_prunedEdges he hnf)) hk (mayB _ hsubE)
    · let x : Edge :=
        { src := v, dst := .ty (.named g), kind := .hasA false, label := ".x",
          onlyForForbids := true }
      have hx : x ∈ fakeForbidsEdgesFor p oy.cls := by
        unfold fakeForbidsEdgesFor
        simp only [List.mem_flatMap, List.mem_filter, List.mem_map]
        exact ⟨v, ⟨hvn, hvf⟩, g, hg, rfl⟩
      have inP : ∀ x ∈ es, x ∈ prunedEdges p oy.cls :=
        fun x hx => mem_prunedEdges (gp.mem x hx) (hes x hx).2
      exact bad x es false
        (gp.mono fun x hx => List.mem_append_left _ (gp.mem x hx))
        (fun x hx => List.mem_append_left _ (inP x hx))
        (fun x hx => noDecl x (hes x hx).1)
        (List.mem_append_right _ hx) rfl
        (mayB _ hBg)

/-! ## Acyclicity -/

theorem stepIV_facts {p : Program} {main : String} (ok : (check p main).ok = true) :
    (∀ e ∈ prunedEdges p main, e.kind = .hasA false →
      (e.src = .ty (.named main) ∨
        e.src ∈ reachFrom (prunedEdges p main) (fuelFor p) (.ty (.named main))) →
      (e.dst = .ty (.named main) ∨
        e.dst ∈ reachFrom (reverseEdges (prunedEdges p main)) (fuelFor p) (.ty (.named main))) →
      False) ∧
    alwaysConverged p main (edgesFor p main) main = true ∧
    reachConverged (reverseEdges (prunedEdges p main)) (fuelFor p) (.ty (.named main)) = true := by
  simp only [check, Result.ok, Bool.and_eq_true, List.isEmpty_iff] at ok
  obtain ⟨⟨conv, cyc⟩, _⟩ := ok
  rw [List.filter_eq_nil_iff] at cyc
  refine ⟨?_, conv.1.1.1.1, conv.1.1.2⟩
  intro e he hk hs hd
  apply cyc e he
  rw [hk]
  rcases hs with hs | hs <;> rcases hd with hd | hd <;> simp [hs, hd]

theorem GPath.reverse {es : List Edge} {u v : Node} {path : List Edge}
    (g : GPath es u v path) : GPath (reverseEdges es) v u (reverseEdges path).reverse := by
  induction g with
  | nil => exact GPath.nil _
  | @cons u v rest e he hs _ ih =>
    let e' : Edge := { e with src := e.dst, dst := e.src }
    have he' : e' ∈ reverseEdges es := List.mem_map_of_mem _ he
    have last : GPath (reverseEdges es) e.dst u [e'] := by
      refine GPath.cons e' he' rfl ?_
      show GPath (reverseEdges es) e.src u []
      rw [hs]
      exact GPath.nil _
    have := GPath.append ih last
    simpa [reverseEdges] using this

/-- Splits a path whose edges start with `e`. -/
theorem GPath.of_head {es : List Edge} {u v : Node} {path : List Edge} {e : Edge}
    (g : GPath es u v path) (hh : path.head? = some e) :
    ∃ rest, path = e :: rest ∧ e.src = u ∧ GPath es e.dst v rest := by
  cases g with
  | nil => simp at hh
  | cons e' _ hs g' =>
    simp at hh
    subst hh
    exact ⟨_, rfl, hs, g'⟩

theorem HPath.append {h : Heap} {a m b : Nat} {l1 l2 : List (Nat × String)}
    (g1 : HPath h a m l1) (g2 : HPath h m b l2) : HPath h a b (l1 ++ l2) := by
  induction g1 with
  | nil => exact g2
  | cons pt _ ih => exact HPath.cons pt (ih g2)

theorem HPath.split {h : Heap} {a b : Nat} {l1 l2 : List (Nat × String)}
    (g : HPath h a b (l1 ++ l2)) : ∃ m, HPath h a m l1 ∧ HPath h m b l2 := by
  induction l1 generalizing a with
  | nil => exact ⟨a, HPath.nil _, g⟩
  | cons s l1' ih =>
    cases g with
    | cons pt g' =>
      obtain ⟨m, g1, g2⟩ := ih g'
      exact ⟨m, HPath.cons pt g1, g2⟩

theorem HPath.src_obj {h : Heap} {a b : Nat} {steps : List (Nat × String)}
    (g : HPath h a b steps) (ne : steps ≠ []) : ∃ o, h[a]? = some o := by
  cases g with
  | nil => exact absurd rfl ne
  | cons pt _ => obtain ⟨o, ho, _⟩ := pt; exact ⟨o, ho⟩

theorem GPath.nil_eq {es : List Edge} {u v : Node} (g : GPath es u v []) : u = v := by
  cases g
  rfl

/-- The part of a path from one of its steps on. -/
theorem HPath.suffix {h : Heap} {y z : Nat} {steps : List (Nat × String)}
    (g : HPath h y z steps) {s : Nat × String} (hs : s ∈ steps) :
    ∃ rest, HPath h s.1 z (s :: rest) := by
  obtain ⟨l1, l2, rfl⟩ := List.append_of_mem hs
  obtain ⟨m, _, g2⟩ := g.split
  have hm : s.1 = m := g2.head
  exact ⟨l2, by rw [hm]; exact g2⟩

/-- A cycle, started from one of its steps. -/
theorem HPath.rotate {h : Heap} {a : Nat} {steps : List (Nat × String)}
    (g : HPath h a a steps) {s : Nat × String} (hs : s ∈ steps) :
    ∃ rest, HPath h s.1 s.1 (s :: rest) := by
  obtain ⟨l1, l2, rfl⟩ := List.append_of_mem hs
  obtain ⟨m, g1, g2⟩ := g.split
  have hm : s.1 = m := g2.head
  exact ⟨l2 ++ l1, by rw [hm]; exact HPath.append g2 g1⟩

/--
The RFC's *Why it's enough* note: a cycle has a step through a non-early
field (`exists_nonEarly_of_cycle`).  Start the cycle at that step's object,
of class `C`, and map it into `C`'s graph (`walk`, then `canBeA_path`) until
it returns to `C`'s node or reaches a fake class, whose `.x` edge leads back.
Either way it's a cycle through `C`'s node whose first edge is non-early.
The `.x` edge isn't pruned: the fake class isn't "always" forbidding `C`
(`not_always_of_path`), since an object on the path that forbade a
super-type of `C` would reach the start, contradicting `forbidsKept`.  So
Step IV would have reported the first edge, and `C` would have failed.
-/
theorem acyclic_of_passes {p : Program} (wf : p.wellFormed = true) (ok : p.passes = true)
    {h : Heap} (r : Reachable p h) : acyclic h = true := by
  have wt := wellTyped r
  have cd := classesDeclared r
  have fk := forbidsKept wf ok r
  unfold acyclic
  rw [List.all_eq_true]
  intro a _
  cases hc : (reachableAddrs h a).contains a with
  | false => rfl
  | true =>
  exfalso
  have ha : a ∈ reachableAddrs h a := by simpa using hc
  obtain ⟨steps, ne, cyc⟩ := hpath_of_mem_reachableAddrs ha
  obtain ⟨s, hs, hnonEarly⟩ := exists_nonEarly_of_cycle (earlyPointsOlder r) cyc ne
  obtain ⟨rest, cyc'⟩ := cyc.rotate hs
  obtain ⟨ox, hox⟩ := cyc'.src_obj (by simp)
  obtain ⟨dC, hdC, hdCk⟩ := cd s.1 ox hox
  have convC := conv_of_lookup wf hdC
  obtain ⟨noCyc, aconv, bconv⟩ := stepIV_facts (check_ok_of_passes ok hdC hdCk)
  let mainN : Node := .ty (.named ox.cls)
  -- No node standing for an object on the cycle declares that it forbids `C`.
  have noDecl : ∀ n : Node,
      (Inter p h (s :: rest) n.type ∨ p.isSubtype (.named ox.cls) n.type = true) →
      declares p ox.cls n ox.cls = false := by
    intro n hn
    unfold declares
    cases hnt : n.type with
    | anyValue => simp
    | named m =>
      simp only [Bool.and_eq_false_iff]
      right
      rw [List.any_eq_false]
      intro g' hg' hCg'
      rw [hnt] at hn
      rcases hn with ⟨s', hs', o', ho', hsub'⟩ | hsub'
      · obtain ⟨d', hd', _⟩ := cd s'.1 o' ho'
        have hg'' := Program.forbidsOf_mono (conv_of_lookup wf hd') hsub' hg'
        obtain ⟨rest', path'⟩ := cyc'.suffix (List.mem_cons_of_mem _ hs')
        have := fk s'.1 s.1 o' ox g' _ ho' hg'' path' (by simp) hox
        rw [hCg'] at this
        contradiction
      · have hg'' := Program.forbidsOf_mono convC hsub' hg'
        have := fk s.1 s.1 ox ox g' _ hox hg'' cyc' (by simp) hox
        rw [hCg'] at this
        contradiction
  -- The fake classes' `.x` edges that the map might use aren't pruned.
  have xUnpruned : ∀ (v : Node) (es : List Edge), GPath (edgesFor p ox.cls) mainN v es →
      (∀ x ∈ es, Inter p h (s :: rest) x.dst.type ∨
        p.isSubtype (.named ox.cls) x.dst.type = true) →
      v.isFake = true → v ∈ allNodes p →
      ({ src := v, dst := mainN, kind := .hasA false, label := ".x" } : Edge) ∈
        prunedEdges p ox.cls := by
    intro v es gp hes hvf hvn
    have hnot := not_always_of_path aconv gp (fun x hx => noDecl x.dst (hes x hx))
    unfold prunedEdges
    refine List.mem_filter.2 ⟨?_, by simp [hvf, hnot]⟩
    unfold edgesFor
    simp only [List.mem_append, List.mem_cons, List.mem_map, List.mem_filter]
    right; right
    exact ⟨v, ⟨hvn, hvf⟩, rfl⟩
  -- Builds the cycle through mainN, starting with the non-early first edge.
  obtain ⟨d, q, hd, hq, hhead, hw⟩ := walk wf wt cd ox.cls cyc' (by simp) hox hox
  rw [hdC] at hd
  cases hd
  have hqn : q.name = s.2 := by
    simp at hhead
    exact (congrArg Prod.snd hhead).symm
  have hk1 : (hasAEdge dC q).kind = .hasA false := by
    simp only [hasAEdge]
    congr 1
    cases hqk : q.kind with
    | early =>
      exfalso
      apply hnonEarly
      refine ⟨ox, dC, hox, hdC, ?_⟩
      unfold isEarlyName
      exact List.any_eq_true.2 ⟨q, hq, by simp [hqk, hqn]⟩
    | setOnce => rfl
    | var => rfl
  have inP : ∀ x : Edge, x ∈ edgesFor p ox.cls → x.src.isFake = false →
      x ∈ prunedEdges p ox.cls := fun x hx hnf => mem_prunedEdges hx hnf
  have finish : ∀ L : List Edge, GPath (prunedEdges p ox.cls) mainN mainN L →
      L.head? = some (hasAEdge dC q) → False := by
    intro L gL hL
    obtain ⟨L', _, hsrc, gL'⟩ := gL.of_head hL
    have he1 : hasAEdge dC q ∈ prunedEdges p ox.cls :=
      gL.mem _ (by rw [‹L = _›]; exact List.mem_cons_self _ _)
    apply noCyc _ he1 hk1 (Or.inl hsrc)
    cases L' with
    | nil => exact Or.inl gL'.nil_eq
    | cons x L'' =>
      right
      have gr := gL'.reverse
      rcases GPath.reach bconv gr (Or.inl rfl) with ⟨hnil, _⟩ | hin
      · simp [reverseEdges] at hnil
      · exact hin
  rcases hw with ⟨es, e, gp, he, ⟨k, hk⟩, hnf, hsubE, hes, hdst, hh⟩ |
      ⟨es, v, gp, hvf, hvn, hne, hes, hh⟩
  · have esP : ∀ x ∈ es, x ∈ prunedEdges p ox.cls :=
      fun x hx => inP x (gp.mem x hx) (hes x hx).2
    obtain ⟨v1, es1, g1, hes1, hv1⟩ := canBeA_path wf (main := ox.cls) hdC hsubE
    have g1' : GPath (edgesFor p ox.cls) e.dst v1 es1 := by rw [hdst]; exact g1
    have gfull := GPath.append gp (GPath.cons e he rfl g1')
    have es1P : ∀ x ∈ es1, x ∈ prunedEdges p ox.cls :=
      fun x hx => inP x (g1.mem x hx) (hes1 x hx).2.1
    have allP : ∀ x ∈ es ++ e :: es1, x ∈ prunedEdges p ox.cls := by
      intro x hx
      rcases List.mem_append.1 hx with hx | hx
      · exact esP x hx
      · rcases List.mem_cons.1 hx with hx | hx
        · subst hx; exact inP x he hnf
        · exact es1P x hx
    have hhead' : (es ++ e :: es1).head? = some (hasAEdge dC q) := by
      cases es with
      | nil => simpa using hh
      | cons x es' => simpa using hh
    rcases hv1 with hv1 | ⟨hvf, _, hvn⟩
    · subst hv1
      exact finish _ (gfull.mono allP) hhead'
    · have hx := xUnpruned v1 _ gfull (by
        intro x hx
        rcases List.mem_append.1 hx with hx | hx
        · exact Or.inl (hes x hx).1
        · rcases List.mem_cons.1 hx with hx | hx
          · subst hx; exact Or.inr hsubE
          · exact Or.inr (hes1 x hx).2.2) hvf hvn
      refine finish _ (GPath.append (gfull.mono allP) (GPath.cons _ hx rfl (GPath.nil _))) ?_
      simpa using hhead'
  · have esP : ∀ x ∈ es, x ∈ prunedEdges p ox.cls :=
      fun x hx => inP x (gp.mem x hx) (hes x hx).2
    have hx := xUnpruned v es gp (fun x hx => Or.inl (hes x hx).1) hvf hvn
    refine finish _ (GPath.append (gp.mono esP) (GPath.cons _ hx rfl (GPath.nil _))) ?_
    cases es with
    | nil => exact absurd rfl hne
    | cons x es' => simpa using hh

end Cycles
