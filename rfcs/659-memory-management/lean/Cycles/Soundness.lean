import Cycles.Checker
import Cycles.Semantics
import Cycles.Subtyping

/-!
# Stage 1: invariants and lemmas

The invariants that hold by induction on steps (`earlyPointsOlder`,
`wellTyped`, `classesDeclared`), the birth order argument
(`exists_nonEarly_of_cycle`), and lemmas about the checker's graphs
(`canBeA_path`, `not_always_of_path`).  `Acyclic.lean` puts them together.
-/

namespace Cycles

/--
Invariant 1: an early property points to an older object.  Stated over
field entries, so it doesn't depend on property names being unique.
-/
def EarlyPointsOlder (p : Program) (h : Heap) : Prop :=
  ∀ (a b : Nat) (o : Obj) (d : Decl) (n : String),
    h[a]? = some o → p.lookup o.cls = some d → isEarlyName d n = true →
    (n, some b) ∈ o.fields → b < a

theorem lt_of_valueOk {p : Program} {h : Heap} {q : Property} {b : Nat}
    (hv : valueOk p h q (some b) = true) : b < h.length := by
  simp only [valueOk] at hv
  split at hv
  · rename_i o ho
    exact (List.getElem?_eq_some_iff.1 ho).1
  · contradiction

theorem earlyPointsOlder_new {p : Program} {h h' : Heap} {c : String}
    {args : List (String × Option Nat)}
    (ih : EarlyPointsOlder p h) (hs : applyNew p h c args = some h') :
    EarlyPointsOlder p h' := by
  unfold applyNew at hs
  split at hs
  · contradiction
  · rename_i d hd
    split at hs
    · rename_i hok
      cases hs
      intro a b o d' n ha hd' hn hmem
      by_cases hlt : a < h.length
      · rw [List.getElem?_append_left hlt] at ha
        exact ih a b o d' n ha hd' hn hmem
      · have hle : a < h.length + 1 := by
          have := (List.getElem?_eq_some_iff.1 ha).1
          simpa using this
        have heq : a = h.length := by omega
        subst heq
        rw [List.getElem?_append_right (Nat.le_refl _)] at ha
        simp at ha
        subst ha
        simp only [newObj] at hd' hmem
        rw [hd] at hd'
        cases hd'
        simp only [List.mem_map] at hmem
        obtain ⟨q, hq, hqe⟩ := hmem
        simp only [Prod.mk.injEq] at hqe
        obtain ⟨hqn, hqv⟩ := hqe
        split at hqv
        · rename_i hearly
          simp only [newOk, Bool.and_eq_true, List.all_eq_true] at hok
          have hq' := hok.2 q hq
          simp only [Bool.or_eq_true, bne_iff_ne, ne_eq] at hq'
          rcases hq' with hne | hlook
          · simp at hearly
            exact absurd hearly hne
          · split at hlook
            · rename_i v hv
              rw [hv] at hqv
              simp at hqv
              subst hqv
              exact lt_of_valueOk hlook
            · contradiction
        · contradiction
    · contradiction

theorem earlyPointsOlder_set {p : Program} {h h' : Heap} {a : Nat} {f : String}
    {v : Option Nat}
    (ih : EarlyPointsOlder p h) (hs : applySet p h a f v = some h') :
    EarlyPointsOlder p h' := by
  unfold applySet at hs
  split at hs
  · contradiction
  · rename_i o ho
    split at hs
    · contradiction
    · rename_i d hd
      split at hs
      · contradiction
      · rename_i q hq
        split at hs
        · rename_i hok
          cases hs
          intro a' b o' d' n ha' hd' hn hmem
          by_cases hidx : a' = a
          · subst hidx
            have hlt : a' < h.length := (List.getElem?_eq_some_iff.1 ho).1
            rw [List.getElem?_set_self hlt] at ha'
            simp at ha'
            subst ha'
            simp only [setField] at hd' hmem
            rw [hd] at hd'
            cases hd'
            simp only [List.mem_map] at hmem
            obtain ⟨x, hx, hxe⟩ := hmem
            split at hxe
            · rename_i hxf
              simp only [Prod.mk.injEq] at hxe
              have hqf := List.find?_some hq
              simp only [beq_iff_eq] at hxf hqf
              simp only [setOk, Bool.and_eq_true, Bool.not_eq_true'] at hok
              have : n = q.name := by rw [← hxe.1, hxf, hqf]
              rw [this] at hn
              rw [hok.1.1] at hn
              contradiction
            · subst hxe
              exact ih a' b o d n ho hd hn hx
          · rw [List.getElem?_set_ne (Ne.symm hidx)] at ha'
            exact ih a' b o' d' n ha' hd' hn hmem
        · contradiction

theorem earlyPointsOlder {p : Program} {h : Heap} (r : Reachable p h) :
    EarlyPointsOlder p h := by
  induction r with
  | init => intro a b o d n ha; simp at ha
  | step s _ hs ih =>
    cases s with
    | new c args => exact earlyPointsOlder_new ih hs
    | set a f v => exact earlyPointsOlder_set ih hs

/--
Invariant 2: every stored pointer is to an object whose class is a subtype
of the type of a property with that name.
-/
def WellTyped (p : Program) (h : Heap) : Prop :=
  ∀ (a b : Nat) (o : Obj) (d : Decl) (n : String),
    h[a]? = some o → p.lookup o.cls = some d → (n, some b) ∈ o.fields →
    ∃ ob q, h[b]? = some ob ∧ q ∈ d.props ∧ q.name = n ∧
      p.isSubtype (.named ob.cls) q.type = true

theorem obj_of_valueOk {p : Program} {h : Heap} {q : Property} {b : Nat}
    (hv : valueOk p h q (some b) = true) :
    ∃ ob, h[b]? = some ob ∧ p.isSubtype (.named ob.cls) q.type = true := by
  simp only [valueOk] at hv
  split at hv
  · rename_i ob hob
    exact ⟨ob, hob, hv⟩
  · contradiction

/-- Setting a field keeps every object's class. -/
theorem getElem?_set_setField {h : Heap} {a b : Nat} {o ob : Obj} {f : String}
    {v : Option Nat} (hb : h[b]? = some ob) :
    ∃ ob', (h.set a (setField o f v))[b]? = some ob' ∧
      (h[a]? = some o → ob'.cls = ob.cls) := by
  by_cases hab : a = b
  · subst hab
    have hlt : a < h.length := (List.getElem?_eq_some_iff.1 hb).1
    refine ⟨setField o f v, List.getElem?_set_self hlt, ?_⟩
    intro ho
    rw [ho] at hb
    cases hb
    rfl
  · exact ⟨ob, by rw [List.getElem?_set_ne hab]; exact hb, fun _ => rfl⟩

theorem wellTyped_new {p : Program} {h h' : Heap} {c : String}
    {args : List (String × Option Nat)}
    (ih : WellTyped p h) (hs : applyNew p h c args = some h') :
    WellTyped p h' := by
  unfold applyNew at hs
  split at hs
  · contradiction
  · rename_i d hd
    split at hs
    · rename_i hok
      cases hs
      intro a b o d' n ha hd' hmem
      by_cases hlt : a < h.length
      · rw [List.getElem?_append_left hlt] at ha
        obtain ⟨ob, q, hb, hq⟩ := ih a b o d' n ha hd' hmem
        have hblt : b < h.length := (List.getElem?_eq_some_iff.1 hb).1
        exact ⟨ob, q, by rw [List.getElem?_append_left hblt]; exact hb, hq⟩
      · have hle : a < h.length + 1 := by
          have := (List.getElem?_eq_some_iff.1 ha).1
          simpa using this
        have heq : a = h.length := by omega
        subst heq
        rw [List.getElem?_append_right (Nat.le_refl _)] at ha
        simp at ha
        subst ha
        simp only [newObj] at hd' hmem
        rw [hd] at hd'
        cases hd'
        simp only [List.mem_map] at hmem
        obtain ⟨q, hq, hqe⟩ := hmem
        simp only [Prod.mk.injEq] at hqe
        obtain ⟨hqn, hqv⟩ := hqe
        split at hqv
        · rename_i hearly
          simp only [newOk, Bool.and_eq_true, List.all_eq_true] at hok
          have hq' := hok.2 q hq
          simp only [Bool.or_eq_true, bne_iff_ne, ne_eq] at hq'
          rcases hq' with hne | hlook
          · simp at hearly
            exact absurd hearly hne
          · split at hlook
            · rename_i v hv
              rw [hv] at hqv
              simp at hqv
              subst hqv
              obtain ⟨ob, hob, hsub⟩ := obj_of_valueOk hlook
              have hblt : b < (List.length h) := (List.getElem?_eq_some_iff.1 hob).1
              exact ⟨ob, q, by rw [List.getElem?_append_left hblt]; exact hob, hq, hqn, hsub⟩
            · contradiction
        · contradiction
    · contradiction

theorem wellTyped_set {p : Program} {h h' : Heap} {a : Nat} {f : String}
    {v : Option Nat}
    (ih : WellTyped p h) (hs : applySet p h a f v = some h') :
    WellTyped p h' := by
  unfold applySet at hs
  split at hs
  · contradiction
  · rename_i o ho
    split at hs
    · contradiction
    · rename_i d hd
      split at hs
      · contradiction
      · rename_i q hq
        split at hs
        · rename_i hok
          cases hs
          -- Rebuilds a fact about `b` in the old heap for the new one.
          have lift : ∀ (b : Nat) (ob : Obj) (t : Ty), h[b]? = some ob →
              p.isSubtype (.named ob.cls) t = true →
              ∃ ob', (h.set a (setField o f v))[b]? = some ob' ∧
                p.isSubtype (.named ob'.cls) t = true := by
            intro b ob t hb ht
            obtain ⟨ob', hb', hcls⟩ := getElem?_set_setField (a := a) (o := o) (f := f) (v := v) hb
            exact ⟨ob', hb', by rw [hcls ho]; exact ht⟩
          intro a' b o' d' n ha' hd' hmem
          by_cases hidx : a' = a
          · subst hidx
            have hlt : a' < h.length := (List.getElem?_eq_some_iff.1 ho).1
            rw [List.getElem?_set_self hlt] at ha'
            simp at ha'
            subst ha'
            simp only [setField] at hd' hmem
            rw [hd] at hd'
            cases hd'
            simp only [List.mem_map] at hmem
            obtain ⟨x, hx, hxe⟩ := hmem
            split at hxe
            · rename_i hxf
              simp only [Prod.mk.injEq] at hxe
              obtain ⟨hxn, hxv⟩ := hxe
              subst hxv
              have hqf := List.find?_some hq
              have hqm := List.mem_of_find?_eq_some hq
              simp only [beq_iff_eq] at hxf hqf
              simp only [setOk, Bool.and_eq_true] at hok
              obtain ⟨ob, hob, hsub⟩ := obj_of_valueOk hok.2
              obtain ⟨ob', hob', hsub'⟩ := lift b ob q.type hob hsub
              exact ⟨ob', q, hob', hqm, by rw [hqf, ← hxf, hxn], hsub'⟩
            · subst hxe
              obtain ⟨ob, q', hb, hq', hqn, hsub⟩ := ih a' b o d n ho hd hx
              obtain ⟨ob', hob', hsub'⟩ := lift b ob q'.type hb hsub
              exact ⟨ob', q', hob', hq', hqn, hsub'⟩
          · rw [List.getElem?_set_ne (Ne.symm hidx)] at ha'
            obtain ⟨ob, q', hb, hq', hqn, hsub⟩ := ih a' b o' d' n ha' hd' hmem
            obtain ⟨ob', hob', hsub'⟩ := lift b ob q'.type hb hsub
            exact ⟨ob', q', hob', hq', hqn, hsub'⟩
        · contradiction

theorem wellTyped {p : Program} {h : Heap} (r : Reachable p h) : WellTyped p h := by
  induction r with
  | init => intro a b o d n ha; simp at ha
  | step s _ hs ih =>
    cases s with
    | new c args => exact wellTyped_new ih hs
    | set a f v => exact wellTyped_set ih hs

/-- Invariant 3: every object's class is a declared class. -/
def ClassesDeclared (p : Program) (h : Heap) : Prop :=
  ∀ (a : Nat) (o : Obj), h[a]? = some o → ∃ d, p.lookup o.cls = some d ∧ d.kind = .cls

theorem classesDeclared {p : Program} {h : Heap} (r : Reachable p h) :
    ClassesDeclared p h := by
  induction r with
  | init => intro a o ha; simp at ha
  | @step h h' s _ hs ih =>
    intro a o ha
    cases s with
    | new c args =>
      simp only [apply, applyNew] at hs
      split at hs
      · contradiction
      · rename_i d hd
        split at hs
        · rename_i hok
          cases hs
          by_cases hlt : a < h.length
          · rw [List.getElem?_append_left hlt] at ha
            exact ih a o ha
          · have hle : a < h.length + 1 := by
              have := (List.getElem?_eq_some_iff.1 ha).1
              simpa using this
            have heq : a = h.length := by omega
            subst heq
            rw [List.getElem?_append_right (Nat.le_refl _)] at ha
            simp at ha
            subst ha
            simp only [newOk, Bool.and_eq_true, beq_iff_eq] at hok
            exact ⟨d, hd, hok.1.1⟩
        · contradiction
    | set b f v =>
      simp only [apply, applySet] at hs
      split at hs
      · contradiction
      · rename_i o' ho'
        split at hs
        · contradiction
        · rename_i d hd
          split at hs
          · contradiction
          · split at hs
            · cases hs
              by_cases hab : a = b
              · subst hab
                have hlt : a < h.length := (List.getElem?_eq_some_iff.1 ho').1
                rw [List.getElem?_set_self hlt] at ha
                simp at ha
                subst ha
                exact ih a o' ho'
              · rw [List.getElem?_set_ne (Ne.symm hab)] at ha
                exact ih a o ha
            · contradiction

/-! ## Pointer paths -/

/-- `a` points to `b` through a field named `n`. -/
def PointsTo (h : Heap) (a b : Nat) (n : String) : Prop :=
  ∃ o, h[a]? = some o ∧ (n, some b) ∈ o.fields

/-- A chain of pointers from `a` to `b`; each step is an address and a field name. -/
inductive HPath (h : Heap) : Nat → Nat → List (Nat × String) → Prop where
  | nil (a : Nat) : HPath h a a []
  | cons {a b c : Nat} {n : String} {rest : List (Nat × String)} :
      PointsTo h a b n → HPath h b c rest → HPath h a c ((a, n) :: rest)

/-- A step through a field that the object's class declares early. -/
def EarlyStep (p : Program) (h : Heap) (s : Nat × String) : Prop :=
  ∃ o d, h[s.1]? = some o ∧ p.lookup o.cls = some d ∧ isEarlyName d s.2 = true

theorem lt_of_earlyPath {p : Program} {h : Heap} (inv : EarlyPointsOlder p h)
    {a b : Nat} {steps : List (Nat × String)} (path : HPath h a b steps)
    (ne : steps ≠ []) (early : ∀ s ∈ steps, EarlyStep p h s) : b < a := by
  induction path with
  | nil => contradiction
  | @cons a b c n rest pt _ ih =>
    obtain ⟨o, ho, hmem⟩ := pt
    obtain ⟨o', d, ho', hd, hn⟩ := early (a, n) (List.mem_cons_self _ _)
    rw [ho] at ho'
    cases ho'
    have hba : b < a := inv a b o d n ho hd hn hmem
    cases rest with
    | nil =>
      cases ‹HPath h b c []›
      exact hba
    | cons s rest' =>
      have := ih (List.cons_ne_nil _ _) (fun s hs => early s (List.mem_cons_of_mem _ hs))
      omega

/-- The RFC's birth order argument: a cycle has a step through a non-early field. -/
theorem exists_nonEarly_of_cycle {p : Program} {h : Heap} (inv : EarlyPointsOlder p h)
    {a : Nat} {steps : List (Nat × String)} (path : HPath h a a steps) (ne : steps ≠ []) :
    ∃ s ∈ steps, ¬ EarlyStep p h s := by
  apply Classical.byContradiction
  intro hall
  have early : ∀ s ∈ steps, EarlyStep p h s := by
    intro s hs
    apply Classical.byContradiction
    intro hn
    exact hall ⟨s, hs, hn⟩
  have := lt_of_earlyPath inv path ne early
  omega

theorem HPath.snoc {h : Heap} {a b c : Nat} {n : String} {steps : List (Nat × String)}
    (path : HPath h a b steps) (pt : PointsTo h b c n) :
    HPath h a c (steps ++ [(b, n)]) := by
  induction path with
  | nil => exact HPath.cons pt (HPath.nil _)
  | cons pt' _ ih => exact HPath.cons pt' (ih pt)

theorem pointsTo_of_mem_succs {h : Heap} {a b : Nat} (hb : b ∈ succs h a) :
    ∃ n, PointsTo h a b n := by
  unfold succs at hb
  cases ho : h[a]? with
  | none => simp [ho] at hb
  | some o =>
    rw [ho] at hb
    obtain ⟨⟨n, v⟩, hmem, hv⟩ := List.mem_filterMap.1 hb
    simp at hv
    subst hv
    exact ⟨n, o, ho, hmem⟩

theorem hpath_of_mem_reachableAddrs {h : Heap} {a b : Nat} (hb : b ∈ reachableAddrs h a) :
    ∃ steps, steps ≠ [] ∧ HPath h a b steps := by
  unfold reachableAddrs at hb
  refine foldl_induct (fun seen => ∀ x ∈ seen, ∃ steps, steps ≠ [] ∧ HPath h a x steps)
    _ _ _ ?_ ?_ b hb
  · intro x hx
    obtain ⟨n, pt⟩ := pointsTo_of_mem_succs hx
    exact ⟨[(a, n)], by simp, HPath.cons pt (HPath.nil _)⟩
  · intro seen _ hseen x hx
    rw [mem_dedup, List.mem_append, List.mem_flatMap] at hx
    rcases hx with hx | ⟨m, hm, hxm⟩
    · exact hseen x hx
    · obtain ⟨steps, _, path⟩ := hseen m hm
      obtain ⟨n, pt⟩ := pointsTo_of_mem_succs hxm
      exact ⟨steps ++ [(m, n)], by simp, path.snoc pt⟩

/-! ## From the checker to the heap -/

/-- A path through `es` from `u` to `v`, as its edges in order. -/
inductive GPath (es : List Edge) : Node → Node → List Edge → Prop where
  | nil (u : Node) : GPath es u u []
  | cons {u v : Node} {rest : List Edge} (e : Edge) :
      e ∈ es → e.src = u → GPath es e.dst v rest → GPath es u v (e :: rest)

/--
Invariant 4: if an object's class forbids `f`, no object it reaches is an
`f`.  It follows from typing and the checker, without induction on steps.

Proof plan: take a pointer path from `a` to `b` and, on it, the last object
whose class forbids `f`; call its class `D`.  Map the rest of the path into
`D`'s graph: each pointer is a has-a edge to the field's type, then can-be-a
edges down to the next object's class (`canBeA_path`), unless they reach a
fake class first.  No node on the mapped path declares `f`, since the
object it stands for would inherit the clause (`Program.forbidsOf_mono`), so by the
fixed point no node on it is "always" forbidding `f` (`not_always_of_path`).
If the path reaches `b`'s class, the last has-a edge is into a type `b`'s
class is a subtype of, so `mayBeA` holds: a Step V mismatch.  If it reaches a
fake class, that class's edge to `f` is one: Step V's fake-class edges.
-/
def ForbidsKept (p : Program) (h : Heap) : Prop :=
  ∀ (a b : Nat) (o ob : Obj) (f : String) (steps : List (Nat × String)),
    h[a]? = some o → f ∈ p.forbidsOf o.cls → HPath h a b steps → steps ≠ [] →
    h[b]? = some ob → p.isSubtype (.named ob.cls) (.named f) = false

/-- What `wellFormed` says about each declaration that the proofs use. -/
theorem wf_decl {p : Program} (wf : p.wellFormed = true) {d : Decl} (hd : d ∈ p) :
    (∀ s ∈ d.supers, ∃ ds, p.lookup s = some ds ∧ ds.kind ≠ DeclKind.cls) ∧
      p.ancestorsConverged d.name = true := by
  simp only [Program.wellFormed, Bool.and_eq_true, List.all_eq_true] at wf
  obtain ⟨⟨⟨⟨hsupers, _⟩, _⟩, _⟩, hconv⟩ := wf.2 d hd
  refine ⟨fun s hs => ?_, hconv⟩
  have hl := (hsupers s hs).2
  cases hds : p.lookup s with
  | none => simp [hds] at hl
  | some ds =>
    rw [hds] at hl
    exact ⟨ds, rfl, by simpa using hl⟩

theorem lookup_mem {p : Program} {n : String} {d : Decl} (h : p.lookup n = some d) :
    d ∈ p ∧ d.name = n := by
  unfold Program.lookup at h
  exact ⟨List.mem_of_find?_eq_some h, by simpa using List.find?_some h⟩

theorem mem_supersOf {p : Program} {m s : String} (h : s ∈ p.supersOf m) :
    ∃ dm, p.lookup m = some dm ∧ s ∈ dm.supers := by
  unfold Program.supersOf at h
  cases hm : p.lookup m with
  | none => simp [hm] at h
  | some dm => exact ⟨dm, rfl, by simpa [hm] using h⟩

theorem mem_edgesFor_of_declEdges {p : Program} {main : String} {d : Decl} {x : Edge}
    (hd : d ∈ p) (hx : x ∈ declEdges p d) : x ∈ edgesFor p main := by
  unfold edgesFor
  exact List.mem_append.2 (Or.inl (List.mem_flatMap.2 ⟨d, hd, hx⟩))

/--
A type's node reaches, by can-be-a edges, the node of any declared type that
is a subtype of it, or else a fake class standing in for that type.  Every
node on the way is a super-type of it.
-/
theorem canBeA_path {p : Program} (wf : p.wellFormed = true) {main e : String} {t : Ty}
    {de : Decl} (he : p.lookup e = some de) (hsub : p.isSubtype (.named e) t = true) :
    ∃ v es, GPath (edgesFor p main) (.ty t) v es ∧
      (∀ x ∈ es, x.kind = .canBeA ∧ x.src.isFake = false ∧
        p.isSubtype (.named e) x.dst.type = true) ∧
      (v = .ty (.named e) ∨
        (v.isFake = true ∧ p.isSubtype (.named e) v.type = true ∧ v ∈ allNodes p)) := by
  have conv : p.ancestorsConverged e = true := by
    obtain ⟨hde, hname⟩ := lookup_mem he
    have := (wf_decl wf hde).2
    rwa [hname] at this
  cases t with
  | anyValue =>
    refine ⟨.fake .anyValue,
      [{ src := .ty .anyValue, dst := .fake .anyValue, kind := .canBeA, label := "can-be-a" }],
      ?_, ?_, ?_⟩
    · refine GPath.cons _ ?_ rfl (GPath.nil _)
      unfold edgesFor
      simp
    · simp [Node.isFake, Node.type, Program.isSubtype]
    · right
      refine ⟨rfl, by simp [Node.type, Program.isSubtype], ?_⟩
      unfold allNodes
      simp
  | named t' =>
    rw [Program.isSubtype_named] at hsub
    have chain := Program.chain_of_mem_ancestors hsub
    clear hsub
    have toAnc : ∀ x, Program.SuperChain p e x → x ∈ p.ancestors e := by
      have closed := Program.closed_of_converged conv
      intro x hx
      induction hx with
      | refl => exact Program.mem_ancestors_self
      | step _ hy ih' => exact closed _ ih' _ hy
    induction chain with
    | refl => exact ⟨_, [], GPath.nil _, by simp, Or.inl rfl⟩
    | @step m s hcm hs ih =>
      obtain ⟨v, es, path, kinds, hv⟩ := ih
      obtain ⟨dm, hdm, hsdm⟩ := mem_supersOf hs
      obtain ⟨hdmp, hdmn⟩ := lookup_mem hdm
      obtain ⟨ds, hds, hdsk⟩ := (wf_decl wf hdmp).1 s hsdm
      obtain ⟨hdsp, hdsn⟩ := lookup_mem hds
      have hsAnc : s ∈ p.ancestors e := toAnc s (Program.SuperChain.step hcm hs)
      cases hk : ds.kind with
      | cls => exact absurd hk hdsk
      | iface sealed =>
        cases sealed with
        | true =>
          let x : Edge :=
            { src := .ty (.named s), dst := .ty (.named m), kind := .canBeA, label := "can-be-a" }
          refine ⟨v, x :: es, GPath.cons x ?_ rfl path, ?_, hv⟩
          · apply mem_edgesFor_of_declEdges hdsp
            unfold declEdges
            rw [hk, hdsn]
            simp only [List.mem_map, List.mem_filter]
            exact ⟨dm, ⟨hdmp, by simpa [hdsn] using hsdm⟩, by rw [hdmn]⟩
          · intro y hy
            rcases List.mem_cons.1 hy with hy | hy
            · subst hy
              exact ⟨rfl, rfl, Program.isSubtype_named.2 (toAnc m hcm)⟩
            · exact kinds y hy
        | false =>
          let x : Edge :=
            { src := .ty (.named s), dst := .fake (.named s), kind := .canBeA,
              label := "can-be-a" }
          refine ⟨.fake (.named s), [x], GPath.cons x ?_ rfl (GPath.nil _), ?_, ?_⟩
          · apply mem_edgesFor_of_declEdges hdsp
            unfold declEdges
            rw [hk, hdsn]
            simp
          · intro y hy
            simp only [List.mem_singleton] at hy
            subst hy
            exact ⟨rfl, rfl, Program.isSubtype_named.2 hsAnc⟩
          · right
            refine ⟨rfl, Program.isSubtype_named.2 hsAnc, ?_⟩
            unfold allNodes
            simp only [List.mem_append, List.mem_map, List.mem_filter, List.mem_singleton]
            left; right
            exact ⟨ds, ⟨hdsp, by simp [hk]⟩, by rw [hdsn]⟩

theorem mem_reachStep {es : List Edge} {seen : List Node} {x : Node} :
    x ∈ reachStep es seen ↔ x ∈ seen ∨ ∃ e ∈ es, e.src ∈ seen ∧ e.dst = x := by
  unfold reachStep
  rw [mem_dedup, List.mem_append, List.mem_map]
  simp [List.mem_filter, and_assoc]

theorem reachFrom_of_start {es : List Edge} {fuel : Nat} {start : Node} {e : Edge}
    (he : e ∈ es) (hs : e.src = start) : e.dst ∈ reachFrom es fuel start := by
  unfold reachFrom
  refine foldl_induct (fun seen => e.dst ∈ seen) _ _ _ ?_ ?_
  · show e.dst ∈ dedup _
    rw [mem_dedup, List.mem_map]
    exact ⟨e, List.mem_filter.2 ⟨he, by simp [hs]⟩, rfl⟩
  · intro seen _ h
    exact mem_reachStep.2 (Or.inl h)

theorem reachFrom_closed {es : List Edge} {fuel : Nat} {start : Node}
    (conv : reachConverged es fuel start = true) {e : Edge} (he : e ∈ es)
    (hs : e.src ∈ reachFrom es fuel start) : e.dst ∈ reachFrom es fuel start := by
  unfold reachConverged at conv
  have heq : reachStep es (reachFrom es fuel start) = reachFrom es fuel start := by
    simpa using conv
  rw [← heq]
  exact mem_reachStep.2 (Or.inr ⟨e, he, hs, rfl⟩)

/-- "Always" only holds of nodes reachable from mainNode, and never of mainNode. -/
theorem alwaysForbidden_sub {p : Program} {main f : String} {es : List Edge} {x : Node}
    (hx : x ∈ alwaysForbidden p main es f) :
    x ∈ reachFrom es ((allNodes p).length + 1) (.ty (.named main)) ∧
      x ≠ .ty (.named main) := by
  unfold alwaysForbidden at hx
  refine foldl_induct
    (fun s => ∀ y ∈ s, y ∈ reachFrom es ((allNodes p).length + 1) (.ty (.named main)) ∧
      y ≠ .ty (.named main)) _ _ _ ?_ ?_ x hx
  · intro y hy
    obtain ⟨h1, h2⟩ := List.mem_filter.1 hy
    exact ⟨h1, by simpa using h2⟩
  · intro s _ hs y hy
    unfold alwaysStep at hy
    exact hs y (List.mem_filter.1 hy).1

/--
The fixed point's defining property, used backwards: if a path from mainNode
to `v` passes no node that declares `f`, then `v` isn't "always" forbidding
`f`.
-/
theorem not_always_of_path {p : Program} {main f : String} {es : List Edge} {v : Node}
    {path : List Edge} (conv : alwaysConverged p main es f = true)
    (gp : GPath es (.ty (.named main)) v path)
    (none : ∀ x ∈ path, declares p main x.dst f = false) :
    v ∉ alwaysForbidden p main es f := by
  unfold alwaysConverged at conv
  simp only [Bool.and_eq_true, beq_iff_eq] at conv
  obtain ⟨rconv, fix⟩ := conv
  -- Generalize the start from mainNode to any live node that isn't "always".
  suffices aux : ∀ u v path, GPath es u v path →
      (u = .ty (.named main) ∨ u ∈ reachFrom es ((allNodes p).length + 1) (.ty (.named main))) →
      u ∉ alwaysForbidden p main es f →
      (∀ x ∈ path, declares p main x.dst f = false) →
      v ∉ alwaysForbidden p main es f by
    exact aux _ _ _ gp (Or.inl rfl) (fun h => (alwaysForbidden_sub h).2 rfl) none
  intro u v path gp
  induction gp with
  | nil => intro _ hu _; exact hu
  | @cons u v rest e he hsrc _ ih =>
    intro hlive hu hnone
    have hdecl : declares p main e.dst f = false := hnone e (List.mem_cons_self _ _)
    have hdst : e.dst ∉ alwaysForbidden p main es f := by
      intro hin
      rw [← fix] at hin
      unfold alwaysStep at hin
      have hkeep := (List.mem_filter.1 hin).2
      rw [hdecl, Bool.false_or, List.all_eq_true] at hkeep
      have := hkeep e he
      simp only [Bool.not_eq_true', Bool.and_eq_false_iff] at this
      have hlive' : e.src ∈ .ty (.named main) ::
          reachFrom es ((allNodes p).length + 1) (.ty (.named main)) := by
        rw [hsrc]
        rcases hlive with h | h
        · rw [h]; exact List.mem_cons_self _ _
        · exact List.mem_cons_of_mem _ h
      rcases this with (h | h) | h
      · simp at h
      · simp [hlive'] at h
      · rw [hsrc] at h
        simp [hu] at h
    refine ih ?_ hdst (fun x hx => hnone x (List.mem_cons_of_mem _ hx))
    right
    rcases hlive with h | h
    · exact reachFrom_of_start he (by rw [hsrc, h])
    · exact reachFrom_closed rconv he (by rw [hsrc]; exact h)

end Cycles
