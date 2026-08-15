---------------------------- MODULE AccBank ----------------------------
(***************************************************************************)
(* WT64v1 v2.0 "TRAIN" — fp32 ACC bank ownership/drain contract.           *)
(*                                                                         *)
(* SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0 *)
(* SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN)                      *)
(*                         and WaveTensor contributors                     *)
(*                                                                         *)
(* Gate: spec §23.7 risk 3 / §23.8 prerequisite (4) —                      *)
(*   "ACC bank 는 순수 tagged-wave 모델 밖의 신규 architectural state —      *)
(*    tag-keyed bank aliasing 은 silent-gradient-corruption 클래스.         *)
(*    RTL 전에 TLA+/formal 선행."                                           *)
(* This model MUST pass before any v2.0 ACC-bank RTL is written.           *)
(*                                                                         *)
(* ======================= WHAT IS BEING PROVED =========================== *)
(*                                                                         *)
(* The spec (§23.1, .claude-memos/wt64v1_spec.md:2012) says the bank is    *)
(* selected by `tag pcid[1:0]`.  pcid[1:0] is a 2-BIT slice with 4 values,  *)
(* but only 2 banks exist, and an accumulation's logical identity spans     *)
(* the full 80-bit tag (wave_number[79:48] / thread_id[47:32] /            *)
(* port_context_id[31:16] / ...).  The bank key is therefore MASSIVELY      *)
(* non-injective on stream identity BY CONSTRUCTION.  Two logically         *)
(* distinct accumulations that agree only on pcid[1:0] land in the same     *)
(* bank.  If nothing stops them, the drained value is a well-formed finite  *)
(* fp32 that is simply WRONG — no error flag, no lower_required, no status  *)
(* bit.  That is the silent-gradient-corruption class.                     *)
(*                                                                         *)
(* This model deliberately BAKES IN the non-injective key (see the ASSUME   *)
(* `AliasingIsExercised` below — TLC refuses a config in which no two       *)
(* streams collide) and then proves that the proposed EXPLICIT ownership/   *)
(* drain contract makes corruption unreachable anyway.                     *)
(*                                                                         *)
(* ================= MEASURED GUARDS, NOT ASSERTED GUARDS ================= *)
(*                                                                         *)
(* An earlier draft of this model claimed five "load-bearing" ownership     *)
(* guards.  A per-guard deletion experiment refuted four of them: deleting  *)
(* Accumulate's owner check, Drain's owner check, Fill's image-owner check  *)
(* or CommitOwn's bank-zeroing produced BYTE-IDENTICAL TLC output, because  *)
(* the stream-side FSM (st) already excluded every transition those guards  *)
(* were supposed to stop:                                                  *)
(*   - st[s]="own"     => owner[BankKey(s)] = s   (so owner checks on the   *)
(*     "own"-gated actions could never see a mismatch),                    *)
(*   - one spill slot  => st[s]="spilled" implies mem.own = s,             *)
(*   - Drain/Spill zeroed the bank on release => BankFree(b) implied        *)
(*     bank[b] = << >>, so the acquire-time zero rewrote an empty cell.     *)
(*                                                                         *)
(* The current model is restructured so that every advertised guard         *)
(* demonstrably carries load, and run.sh MEASURES that claim:              *)
(*                                                                         *)
(*  1. SRAM semantics (stale retention).  Drain and Spill RELEASE the bank  *)
(*     but do NOT clear the cells — hardware stores do not scrub SRAM.      *)
(*     The acquire-time zero (CommitOwn / 0x7E) is therefore the ONLY       *)
(*     thing standing between a new owner and the previous owner's stale    *)
(*     partials.  Deleting it now breaks NoSilentAliasing.                 *)
(*  2. Attempt surfaces.  Hardware cannot rely on software being in the     *)
(*     state software claims to be in.  The model lets a context ATTEMPT    *)
(*     an op from a desynced state — a VFMA_ACC or drain still in flight    *)
(*     after 0x7D SPILL (v1.9 pipelined dispatch makes this real), a raw    *)
(*     0x7E issued outside the acquire handshake — and the HARDWARE guard   *)
(*     answers it with a refusal plus a sticky fault bit.  This mirrors     *)
(*     exactly how the v1.9 bank tables allow a colliding launch attempt    *)
(*     and answer it with `bank_tag_collision_error_r` (Cluster.v:1036).    *)
(*  3. Per-guard deletion is a CONSTANT, not an edit.  `DisabledGuards`     *)
(*     names the guards to delete; one .cfg per guard runs the deletion     *)
(*     experiment and MUST produce a counterexample naming that guard's     *)
(*     own invariant.  A guard is called load-bearing ONLY on that          *)
(*     evidence.  README §5 tabulates the measured results.                *)
(*  4. NSlots >= 2 spill slots.  With a single slot the cross-context       *)
(*     spill/fill leak was structurally unreachable and the mem conjunct    *)
(*     of Inv_NoCrossContextLeak was vacuous.  Two slots make the hazard    *)
(*     real; a witness run proves it is reachable in the good model.        *)
(*                                                                         *)
(* ==================== ABSTRACTION: OPAQUE VALUES ======================== *)
(*                                                                         *)
(* No fp32 arithmetic is modelled.  A contribution is the OPAQUE TOKEN      *)
(* [str |-> s, idx |-> i] and a bank cell holds the SEQUENCE of tokens      *)
(* folded into it — i.e. an uninterpreted ⊕-term recorded in application    *)
(* order.  Two things fall out for free:                                   *)
(*   - identity corruption  = a bank sequence containing tokens of two      *)
(*                            different streams (NoSilentAliasing);         *)
(*   - order corruption     = a bank sequence whose idx field is not the    *)
(*                            ascending-wave-order canonical prefix         *)
(*                            (Inv_Canonical).                             *)
(* IEEE-754 semantics are OUT OF SCOPE and belong to the bit-exact golden   *)
(* model (scripts/golden_fp32.py) — see README.md §9 "스코프 밖".          *)
(***************************************************************************)
EXTENDS Naturals, Sequences, FiniteSets

CONSTANTS
    Streams,           \* set of logically distinct accumulation streams.
                       \* A stream IS a full 80-bit tag identity; distinct
                       \* elements differ SOMEWHERE in the 80 bits (thread_id,
                       \* wave_number, output_port_id[7:2], ...) — not
                       \* necessarily in pcid[1:0].
    Pcid,              \* [Streams -> Nat] — the pcid[1:0] value each stream
                       \* carries.  This is the ONLY part of the identity the
                       \* hardware bank selector can see (spec §23.1).
    NBanks,            \* physical ACC banks per cluster.  Spec: 2.
    K,                 \* contributions per stream before it may drain.
                       \* GHOST: no architectural carrier exists today —
                       \* see README §8 item (h) — the biggest open gap.
    NSlots,            \* 0x7D ACC_SPILL slots.  MUST be >= 2: with a single
                       \* slot, `st[s]="spilled"` implies the slot is s's own
                       \* and the cross-context fill hazard is unreachable
                       \* (measured — see README §5).
    DisabledGuards     \* subset of GuardNames.  {} is the GOOD model.  Each
                       \* deletion .cfg removes exactly ONE guard, so the
                       \* counterexample it produces is attributable to that
                       \* guard alone.  AllGuardsDeleted is the refuted
                       \* implicit "requester ID" design of spec §23.1.

--------------------------------------------------------------------------
(* The hardware-enforced checks under experiment.  Each name appears in
   exactly one action.  "commit_zero" is strictly an EFFECT (the acquire-
   time zero), not a guard predicate, but it is deletable the same way and
   its deletion run must fail the same way. *)
GuardNames == {"commit_free",    \* CommitOwn: only a FREE bank may be granted
               "commit_zero",    \* CommitOwn: granting also zeroes the cells
               "acc_owner",      \* Accumulate: only the owner's ops land
               "drain_owner",    \* Drain: only the owner reads the bank out
               "fill_owner",     \* Fill: only the image's owner may restore it
               "fill_bankfree",  \* Fill: only into a currently-free bank
               "zero_owner"}     \* raw 0x7E: only the owner may zero a bank

NoDeletions      == {}
DelCommitFree    == {"commit_free"}
DelCommitZero    == {"commit_zero"}
DelAccOwner      == {"acc_owner"}
DelDrainOwner    == {"drain_owner"}
DelFillOwner     == {"fill_owner"}
DelFillBankFree  == {"fill_bankfree"}
DelZeroOwner     == {"zero_owner"}
AllGuardsDeleted == GuardNames

Armed(g)      == g \notin DisabledGuards
(* Accept-path obligation of guard g: with g armed the condition must hold;
   with g deleted the action proceeds unconditionally.  Deleting g from a
   .cfg IS the guard-deletion experiment. *)
Pass(g, cond)  == Armed(g) => cond
(* Fault-path trigger of guard g: the guard is armed and the condition
   fails — the attempt is refused and the sticky fault bit is raised.
   With g deleted the fault path vanishes (the attempt lands instead). *)
Fault(g, cond) == Armed(g) /\ ~cond

--------------------------------------------------------------------------
(* Fixed instantiation used by the shipped .cfg files (overridden with
   `CONSTANT X <- XDefault`).  sA and sB deliberately COLLIDE:
   BankOf(0) = 0 and BankOf(2) = 0.  They are distinct 80-bit identities
   that agree on pcid[1:0] — exactly the spec's hazard.  sC lands in the
   other bank so the model also covers non-colliding concurrency. *)
StreamsDefault == {"sA", "sB", "sC"}

PcidDefault ==
    [s \in StreamsDefault |->
        CASE s = "sA" -> 0     \* pcid[1:0] = 2'b00 -> bank 0
          [] s = "sB" -> 2     \* pcid[1:0] = 2'b10 -> bank 0   <-- ALIAS
          [] OTHER    -> 1 ]   \* pcid[1:0] = 2'b01 -> bank 1

(* Larger instantiation (AccBank_large.cfg): FOUR streams and BOTH banks
   contended — sA/sB alias onto bank 0, sC/sD alias onto bank 1.  Used to
   show the result is not an artifact of the minimal 3-stream config. *)
StreamsLarge == {"sA", "sB", "sC", "sD"}

PcidLarge ==
    [s \in StreamsLarge |->
        CASE s = "sA" -> 0     \* -> bank 0
          [] s = "sB" -> 2     \* -> bank 0   <-- ALIAS
          [] s = "sC" -> 1     \* -> bank 1
          [] OTHER    -> 3 ]   \* -> bank 1   <-- ALIAS

--------------------------------------------------------------------------
Banks   == 0 .. (NBanks - 1)
Slots   == 0 .. (NSlots - 1)

NoOwner == "no_owner"          \* the bank's ownership register, unowned
(* A drained result is a RECORD, not an "empty-or-sequence" union: TLC
   refuses to compare a string sentinel with a sequence, and a boolean
   `has` flag is clearer than a sentinel anyway. *)
NoResult == [has |-> FALSE, val |-> << >>]
NoImage  == [own |-> NoOwner, val |-> << >>]

States  == {"idle", "req", "own", "spilled", "done"}

(* The hardware bank selector: a 2-bit slice indexing 2 banks.  With
   NBanks = 2 this is 2:1 non-injective on pcid alone, and (since pcid is
   itself only 16 of the 80 identity bits, and is REBUILT as
   {8'h00, eff_output_port_id} on every forwarded tag — EHDecode.v:561)
   it is far worse than 2:1 on stream identity. *)
BankOf(p)  == p % NBanks
BankKey(s) == BankOf(Pcid[s])

Tok(s, i)     == [str |-> s, idx |-> i]
Tokens        == {Tok(s, i) : s \in Streams, i \in 1..K}

(* The GHOST reference accumulator: the canonical fold of exactly stream
   s's first n contributions, in ascending wave-order K (spec §23.1
   "ascending wave-order K").  Sequence position = ⊕-application order. *)
CanonSeq(s, n) == [i \in 1..n |-> Tok(s, i)]

(* Which streams have tokens inside an accumulated term. *)
Writers(sq) == {sq[i].str : i \in 1..Len(sq)}

--------------------------------------------------------------------------
ASSUME AssumeBanks    == NBanks \in Nat /\ NBanks >= 1
ASSUME AssumeK        == K \in Nat /\ K >= 1
ASSUME AssumeStreams  == IsFiniteSet(Streams) /\ Streams # {}
ASSUME AssumePcid     == Pcid \in [Streams -> Nat]
ASSUME AssumeGuards   == DisabledGuards \subseteq GuardNames
ASSUME AssumeDisjoint == NoOwner \notin Streams

(* NON-VACUITY GUARD.  If the configured streams do not actually collide in
   the bank selector, this model proves nothing about aliasing and TLC must
   refuse to run.  Keeps a future constant edit from silently gutting the
   gate. *)
ASSUME AliasingIsExercised ==
    \E a, b \in Streams : a # b /\ BankKey(a) = BankKey(b)

(* NON-VACUITY GUARD.  With NSlots = 1, `st[s]="spilled"` implies the only
   image in memory is s's own, the fill-owner guard can never see a foreign
   image, and the mem conjunct of Inv_NoCrossContextLeak is vacuous — this
   was MEASURED (deleting the guard changed nothing at 1 slot).  Two slots
   make the cross-context hazard reachable; AccBank_witness_fill_foreign
   proves it stays reachable. *)
ASSUME AssumeSlots == NSlots \in Nat /\ NSlots >= 2

--------------------------------------------------------------------------
VARIABLES
    bank,      \* [Banks -> Seq(Tokens)] — accumulated ⊕-term per bank.
               \* SRAM semantics: contents PERSIST across release.  Only the
               \* acquire-time zero (or a raw 0x7E) clears a cell.
    owner,     \* [Banks -> Streams \cup {NoOwner}] — the HARDWARE ownership
               \* register (the "explicit ownership contract" made physical)
    st,        \* [Streams -> States] — the STREAM-side view of ownership
    issued,    \* [Streams -> 0..K] — contributions this stream has emitted
    pend,      \* Streams \cup {NoOwner} — the single deferred-commit claim
               \* staging register.  Mirrors v1.9 `mu_pending_other`
               \* (Cluster.v:1041-1044): a claim REQUESTED at T is committed
               \* or rejected at T+1, and never mutates bank state at T.
               \* This is the residual-risk-11 phantom-row lesson.
    mem,       \* [Slots -> [own |-> ..., val |-> ...]] — 0x7D ACC_SPILL
               \* slots.  own is the owner token recorded WITH the image.
               \* GHOST as of today: no spill-image format carries an owner
               \* tag yet — README §8 item (l).
    drained,   \* [Streams -> [has: BOOLEAN, val: Seq(Tokens)]] — what each stream
               \* actually took out of the machine.  THE observable.
    conflict   \* sticky, synthesizable status bit raised when ANY hardware
               \* guard refuses an attempt.  v1.9 §26.5 precedent: a LOUD
               \* fault, not a simulation-only $error (Cluster.v:1036
               \* bank_tag_collision_error_r).

vars == << bank, owner, st, issued, pend, mem, drained, conflict >>

MaxLen == K * Cardinality(Streams)

TypeOK ==
    /\ DOMAIN bank = Banks
    /\ \A b \in Banks : \A i \in 1..Len(bank[b]) : bank[b][i] \in Tokens
    /\ \A b \in Banks : Len(bank[b]) <= MaxLen
    /\ owner \in [Banks -> Streams \cup {NoOwner}]
    /\ st \in [Streams -> States]
    /\ issued \in [Streams -> 0..K]
    /\ pend \in Streams \cup {NoOwner}
    /\ DOMAIN mem = Slots
    /\ \A m \in Slots :
          /\ mem[m].own \in Streams \cup {NoOwner}
          /\ \A i \in 1..Len(mem[m].val) : mem[m].val[i] \in Tokens
    /\ \A s \in Streams :
          /\ drained[s].has \in BOOLEAN
          /\ \A i \in 1..Len(drained[s].val) : drained[s].val[i] \in Tokens
    /\ conflict \in BOOLEAN

--------------------------------------------------------------------------
Init ==
    /\ bank     = [b \in Banks   |-> << >>]
    /\ owner    = [b \in Banks   |-> NoOwner]
    /\ st       = [s \in Streams |-> "idle"]
    /\ issued   = [s \in Streams |-> 0]
    /\ pend     = NoOwner
    /\ mem      = [m \in Slots   |-> NoImage]
    /\ drained  = [s \in Streams |-> NoResult]
    /\ conflict = FALSE

BankFree(b) == owner[b] = NoOwner

--------------------------------------------------------------------------
(* --- ACQUIRE, phase 1 of 2 (cycle T) -----------------------------------
   The claim is REGISTERED ONLY.  No bank, no ownership register and no
   accumulator cell is touched.  A claim that is rejected at T+1 therefore
   leaves no phantom allocation behind.  (v1.9 residual risk 11: the T-time
   unconditional allocation left phantom rows for busy-rejected dispatches
   and could exhaust the table — spec §26.8 item 11.) *)
RequestOwn(s) ==
    /\ st[s] = "idle"
    /\ pend = NoOwner
    /\ pend' = s
    /\ st' = [st EXCEPT ![s] = "req"]
    /\ UNCHANGED << bank, owner, issued, mem, drained, conflict >>

(* --- ACQUIRE, phase 2 of 2 (cycle T+1), accepted -----------------------
   Two deletable pieces:
     "commit_free": the grant is gated on the LIVE bank-free condition,
        re-read at T+1.  Deleted -> the claim STEALS a live bank.
     "commit_zero": the grant also zeroes the accumulator cells.  Under
        SRAM semantics the released bank still holds the PREVIOUS owner's
        stale partials, so this zero is the only thing that keeps them out
        of the new owner's fold.  Deleted -> stale tokens survive into the
        new accumulation (measured: NoSilentAliasing breaks).
   Fused acquire+zero is the model's realization of 0x7E FP_ACC_ZERO in
   its recommended ATOMIC form; the raw non-atomic form is the separate
   Zero/ZeroFault pair below. *)
CommitOwn(s) ==
    LET b == BankKey(s)
    IN  /\ st[s] = "req"
        /\ pend = s
        /\ Pass("commit_free", BankFree(b))
        /\ owner'  = [owner  EXCEPT ![b] = s]
        /\ bank'   = [bank   EXCEPT ![b] = IF Armed("commit_zero")
                                           THEN << >> ELSE @]
        /\ issued' = [issued EXCEPT ![s] = 0]
        /\ st'     = [st     EXCEPT ![s] = "own"]
        /\ pend'   = NoOwner
        /\ UNCHANGED << mem, drained, conflict >>

(* --- ACQUIRE, phase 2 of 2 (cycle T+1), refused ------------------------
   The bank is live under a FOREIGN owner (only 2 banks per cluster exist,
   so oversubscription is expected, not exotic).  The claim is REFUSED —
   the incumbent's partials are untouched — and the sticky status bit is
   raised so the refusal is LOUD.  This is the fault path of the
   "commit_free" guard: delete the guard and the refusal disappears,
   replaced by the steal. *)
RejectOwn(s) ==
    LET b == BankKey(s)
    IN  /\ st[s] = "req"
        /\ pend = s
        /\ Fault("commit_free", BankFree(b))
        /\ st' = [st EXCEPT ![s] = "idle"]      \* software may retry
        /\ pend' = NoOwner
        /\ conflict' = TRUE
        /\ UNCHANGED << bank, owner, issued, mem, drained >>

(* --- ACCUMULATE (0x70 VFMA_ACC, stateful form) -------------------------
   ATTEMPT SURFACE: "own" is the well-behaved path.  "spilled" is the
   desync path — with v1.9 pipelined dispatch a VFMA_ACC can still be in
   flight when the 0x7D SPILL retires, so the hardware WILL see accumulate
   ops for a bank the issuer no longer owns.  The "acc_owner" guard is what
   answers them; it is checkable in RTL because the op's launch-time tag
   travels with it.  Deleted -> the stray op lands in whatever the bank
   holds now (measured: NoSilentAliasing breaks). *)
AccAttempt(s) == st[s] \in {"own", "spilled"} /\ issued[s] < K

Accumulate(s) ==
    LET b == BankKey(s)
    IN  /\ AccAttempt(s)
        /\ Pass("acc_owner", owner[b] = s)
        /\ bank'   = [bank   EXCEPT ![b] = Append(@, Tok(s, issued[s] + 1))]
        /\ issued' = [issued EXCEPT ![s] = @ + 1]
        /\ UNCHANGED << owner, st, pend, mem, drained, conflict >>

AccumulateFault(s) ==
    LET b == BankKey(s)
    IN  /\ AccAttempt(s)
        /\ Fault("acc_owner", owner[b] = s)
        /\ conflict' = TRUE
        /\ UNCHANGED << bank, owner, st, issued, pend, mem, drained >>

(* --- DRAIN + RELEASE ---------------------------------------------------
   The accumulation leaves the machine (0x7C STORE_QUANT or 0x7D SPILL —
   the drain opcode is NOT pinned by the spec, see README §8 (i)) and
   ownership is released in the same atomic event.  SRAM semantics: the
   cells are NOT cleared — the stale value stays behind for the next
   acquire-time zero to scrub.

   `issued[s] = K` is a GHOST guard: nothing on the dec_* bus carries a
   fragment/contribution count (spec §23.6a contract 1), so a real
   implementation cannot check it today.  Flagged in README §8 (h).

   ATTEMPT SURFACE: as with Accumulate, a drain can still be in flight
   after a spill; "drain_owner" answers it.  Deleted -> the stray drain
   reads out ANOTHER context's live partials (measured:
   Inv_NoCrossContextLeak breaks). *)
DrainAttempt(s) == st[s] \in {"own", "spilled"} /\ issued[s] = K

Drain(s) ==
    LET b == BankKey(s)
    IN  /\ DrainAttempt(s)
        /\ Pass("drain_owner", owner[b] = s)
        /\ drained' = [drained EXCEPT ![s] = [has |-> TRUE, val |-> bank[b]]]
        /\ owner'   = [owner   EXCEPT ![b] =
                          IF @ = s THEN NoOwner ELSE @]
        /\ st'      = [st EXCEPT ![s] = "done"]
        /\ UNCHANGED << bank, issued, pend, mem, conflict >>

DrainFault(s) ==
    LET b == BankKey(s)
    IN  /\ DrainAttempt(s)
        /\ Fault("drain_owner", owner[b] = s)
        /\ conflict' = TRUE
        /\ UNCHANGED << bank, owner, st, issued, pend, mem, drained >>

(* --- 0x7D ACC_SPILL ----------------------------------------------------
   Evict a LIVE partial accumulation to a free spill slot and release the
   bank.  This is how software survives having only 2 banks per cluster.
   Ownership travels WITH the spilled image (mem[m].own) — a GHOST field
   today, README §8 (l).  SRAM semantics: the bank cells retain the value
   just spilled; the next acquire zeroes them.
   No advertised hardware guard: on the "own" surface the spiller is the
   owner by Inv_OwnerAgreement, and slot allocation is a software address
   choice, not a hardware check. *)
Spill(s) ==
    LET b == BankKey(s)
    IN  /\ st[s] = "own"
        /\ \E m \in Slots :
              /\ mem[m].own = NoOwner
              /\ mem' = [mem EXCEPT ![m] = [own |-> s, val |-> bank[b]]]
        /\ owner' = [owner EXCEPT ![b] = IF @ = s THEN NoOwner ELSE @]
        /\ st'    = [st EXCEPT ![s] = "spilled"]
        /\ UNCHANGED << bank, issued, pend, drained, conflict >>

(* --- 0x7D ACC_FILL -----------------------------------------------------
   Restore a spilled image and re-acquire the bank.  The fill ADDRESSES a
   slot (software-chosen, like any memory operand), so with NSlots >= 2 a
   fill can genuinely address a FOREIGN image — that is the cross-context
   hazard, reachable in the good model (witness run).  Two deletable
   guards:
     "fill_owner":    the image's recorded owner must be the filler.
        Deleted -> a context restores ANOTHER context's partials: a data
        LEAK, not merely corruption (measured: Inv_NoCrossContextLeak
        breaks end to end).
     "fill_bankfree": the pcid-selected bank must be free at fill time.
        Deleted -> the fill lands on top of a live foreign owner
        (measured: Inv_OwnerAgreement breaks). *)
Fill(s) ==
    LET b == BankKey(s)
    IN  /\ st[s] = "spilled"
        /\ Pass("fill_bankfree", BankFree(b))
        /\ \E m \in Slots :
              /\ mem[m].own # NoOwner
              /\ Pass("fill_owner", mem[m].own = s)
              /\ bank' = [bank EXCEPT ![b] = mem[m].val]
              /\ mem'  = [mem  EXCEPT ![m] = NoImage]
        /\ owner' = [owner EXCEPT ![b] = s]
        /\ st'    = [st EXCEPT ![s] = "own"]
        /\ UNCHANGED << issued, pend, drained, conflict >>

FillFaultForeign(s) ==
    /\ st[s] = "spilled"
    /\ \E m \in Slots :
          /\ mem[m].own # NoOwner
          /\ Fault("fill_owner", mem[m].own = s)
    /\ conflict' = TRUE
    /\ UNCHANGED << bank, owner, st, issued, pend, mem, drained >>

FillFaultBusy(s) ==
    LET b == BankKey(s)
    IN  /\ st[s] = "spilled"
        /\ \E m \in Slots : mem[m].own = s
        /\ Fault("fill_bankfree", BankFree(b))
        /\ conflict' = TRUE
        /\ UNCHANGED << bank, owner, st, issued, pend, mem, drained >>

(* --- 0x7E FP_ACC_ZERO, RAW (non-atomic) FORM ---------------------------
   The ISA row reads as a plain zeroing op that can be issued against a
   bank.  Taken literally — no ownership check, not fused with acquire —
   a foreign 0x7E landing mid-accumulation guts the incumbent's partials
   and the incumbent later drains a well-formed, silently wrong value.
   That is the ZERO RACE, and AccBank_del_zero_owner.cfg exhibits it as a
   TLC counterexample (Inv_Value breaks).

   ATTEMPT SURFACE: a context that has NOT gone through the acquire
   handshake ("idle") issues the raw op against its pcid-selected bank —
   the non-atomic startup sequence "zero first, then accumulate", or any
   desynced/stray issue.  With "zero_owner" ARMED the hardware refuses
   every such attempt (sticky fault): on this surface the issuer never
   owns the bank, so the accept path Zero(s) below never fires in the
   good model — BY DESIGN, the only sanctioned zero is the atomic one
   inside CommitOwn.  That is the measured content of the README
   recommendation "acquire+zero must be one atomic event, and a raw 0x7E
   must be ownership-checked". *)
ZeroAttempt(s) == st[s] = "idle"

Zero(s) ==
    LET b == BankKey(s)
    IN  /\ ZeroAttempt(s)
        /\ Pass("zero_owner", owner[b] = s)
        /\ bank' = [bank EXCEPT ![b] = << >>]
        /\ UNCHANGED << owner, st, issued, pend, mem, drained, conflict >>

ZeroFault(s) ==
    LET b == BankKey(s)
    IN  /\ ZeroAttempt(s)
        /\ Fault("zero_owner", owner[b] = s)
        /\ conflict' = TRUE
        /\ UNCHANGED << bank, owner, st, issued, pend, mem, drained >>

--------------------------------------------------------------------------
AllDone == \A s \in Streams : st[s] = "done"

Terminating == AllDone /\ UNCHANGED vars

Next ==
    \/ \E s \in Streams :
          \/ RequestOwn(s)
          \/ CommitOwn(s)
          \/ RejectOwn(s)
          \/ Accumulate(s)
          \/ AccumulateFault(s)
          \/ Drain(s)
          \/ DrainFault(s)
          \/ Spill(s)
          \/ Fill(s)
          \/ FillFaultForeign(s)
          \/ FillFaultBusy(s)
          \/ Zero(s)
          \/ ZeroFault(s)
    \/ Terminating

(***************************************************************************)
(* FAIRNESS — READ THIS BEFORE CITING THE LIVENESS RESULT.                 *)
(*                                                                         *)
(* ASSUMED OBLIGATION, NOT A PROVED PROPERTY OF ANY EXISTING DESIGN:       *)
(* STRONG fairness on every progress action is the model's stand-in for a  *)
(* FAIR CLAIM/ISSUE ARBITER.  Neither spec §23.1 nor the v1.9 RTL          *)
(* provides one — nothing in the ISA or the Cluster arbitration promises   *)
(* that a stream whose claim is enabled infinitely often is ever granted.  *)
(* The v2.0 ACC-bank RTL MUST DISCHARGE this obligation (e.g. a round-     *)
(* robin grant among pending claims) or the Liveness result below does     *)
(* not transfer to hardware.  Every SAFETY result is independent of this   *)
(* assumption.                                                             *)
(*                                                                         *)
(* Why SF and not WF: weak fairness is provably too weak here and TLC      *)
(* says so — every progress action can be repeatedly DISABLED (a           *)
(* competing stream holding the aliased bank, the single `pend` staging    *)
(* register being occupied, the stream's own spill), and under             *)
(* WF_vars(Accumulate) TLC finds a real counterexample in which a stream   *)
(* spills and fills forever at issued < K.  SF (fire if enabled            *)
(* infinitely often) closes it.                                            *)
(*                                                                         *)
(* Spill and the fault actions are deliberately left UNFAIR: spilling is   *)
(* an optional software policy, and a refusal must never be something the  *)
(* machine has to perform in order to make progress.                       *)
(***************************************************************************)
Fairness ==
    /\ \A s \in Streams : SF_vars(RequestOwn(s))
    /\ \A s \in Streams : SF_vars(CommitOwn(s))
    /\ \A s \in Streams : SF_vars(Accumulate(s))
    /\ \A s \in Streams : SF_vars(Drain(s))
    /\ \A s \in Streams : SF_vars(Fill(s))

Spec == Init /\ [][Next]_vars /\ Fairness

--------------------------------------------------------------------------
(*                            P R O P E R T I E S                          *)
--------------------------------------------------------------------------

(***************************************************************************)
(* CENTRAL INVARIANT — NoSilentAliasing.                                   *)
(*                                                                         *)
(* "Two logically-distinct accumulation streams never write the same bank  *)
(*  slot without an intervening explicit ownership transfer."              *)
(*                                                                         *)
(* Stated as: no accumulated ⊕-term anywhere in the machine (bank cell or  *)
(* spill image) ever contains contributions from more than one stream.     *)
(* An explicit ownership transfer necessarily zeroes the bank (CommitOwn's  *)
(* "commit_zero" effect), so surviving foreign tokens are exactly the      *)
(* absence of that transfer.  Note stale single-owner data in a RELEASED   *)
(* bank is allowed — SRAM retains it — but a MIXTURE never exists.         *)
(***************************************************************************)
NoSilentAliasing ==
    /\ \A b \in Banks : Cardinality(Writers(bank[b])) <= 1
    /\ \A m \in Slots : Cardinality(Writers(mem[m].val)) <= 1

(* Exclusive ownership: every token in an OWNED bank belongs to the owner.
   (A released bank may retain the previous owner's stale tokens — SRAM —
   which is why this is conditioned on ownership; the stale data is dead:
   unreadable without acquire, scrubbed by the acquire-time zero.) *)
Inv_Exclusive ==
    \A b \in Banks :
        (owner[b] # NoOwner) => Writers(bank[b]) \subseteq {owner[b]}

(* The hardware ownership register and the stream-side view never diverge.
   Divergence is the precursor state of every corruption trace: the victim
   still believes it owns the bank while the hardware has handed it away. *)
Inv_OwnerAgreement ==
    \A s \in Streams : (st[s] = "own") => (owner[BankKey(s)] = s)

(* No phantom allocation: a claim that has been requested but not yet
   committed never appears in the ownership register. *)
Inv_NoPhantom ==
    \A s \in Streams : (st[s] = "req") => (owner[BankKey(s)] # s)

(* Canonical accumulation order, STRUCTURAL half: whatever is in an OWNED
   bank is the owner's own contributions, in ascending wave-order K, with
   no gaps and no reordering.  (The NUMERIC half — that this fixed order
   yields the required bits — is discharged by scripts/golden_fp32.py, not
   here.) *)
Inv_Canonical ==
    \A b \in Banks :
        owner[b] # NoOwner => bank[b] = CanonSeq(owner[b], Len(bank[b]))

(* A drain never publishes a short accumulation. *)
Inv_Complete ==
    \A s \in Streams : drained[s].has => Len(drained[s].val) = K

(* Neither a spill slot nor a drained result ever carries another
   context's data.  Cross-context LEAK, distinct from corruption. *)
Inv_NoCrossContextLeak ==
    /\ \A m \in Slots :
          mem[m].own # NoOwner => Writers(mem[m].val) \subseteq {mem[m].own}
    /\ \A s \in Streams :
          drained[s].has => Writers(drained[s].val) \subseteq {s}

(***************************************************************************)
(* THE PAYOFF — Inv_Value.                                                 *)
(*                                                                         *)
(* What a stream took OUT of the machine equals the ghost reference        *)
(* accumulator: exactly the multiset of its own K contributions, folded in  *)
(* exactly the canonical order, no more and no fewer.                      *)
(*                                                                         *)
(* This is the invariant that defines "silent": every corruption trace     *)
(* ends in a state where drained[s].val is a well-formed accumulated      *)
(* term that is simply the WRONG term.  Without a ghost accumulator the    *)
(* model cannot express the failure at all.                                *)
(***************************************************************************)
Inv_Value ==
    \A s \in Streams : drained[s].has => drained[s].val = CanonSeq(s, K)

Safety ==
    /\ TypeOK
    /\ NoSilentAliasing
    /\ Inv_Exclusive
    /\ Inv_OwnerAgreement
    /\ Inv_NoPhantom
    /\ Inv_Canonical
    /\ Inv_Complete
    /\ Inv_NoCrossContextLeak
    /\ Inv_Value

(***************************************************************************)
(* LIVENESS — the contract must not merely be safe, it must let every      *)
(* stream finish.  A "correct" design that refuses every aliased claim      *)
(* forever would satisfy all the safety invariants above and be useless.   *)
(* Note this holds DESPITE sA and sB permanently colliding in bank 0.      *)
(*                                                                         *)
(* CONDITIONAL RESULT: holds only under the ASSUMED strong-fairness        *)
(* obligation documented at `Fairness` above — a fair arbiter the RTL must *)
(* later provide.  Cite it as "liveness, given a fair arbiter", never as   *)
(* an unconditional property of the contract.                              *)
(***************************************************************************)
Liveness == \A s \in Streams : <>(st[s] = "done")

(* Ownership is never leaked: a bank held forever by a finished stream
   would starve its aliases. *)
NoOwnershipLeak == <>[](\A b \in Banks : AllDone => BankFree(b))

--------------------------------------------------------------------------
(***************************************************************************)
(* HAZARD-REACHABILITY WITNESSES — ALL DELIBERATELY FALSE.                 *)
(*                                                                         *)
(* Each is checked as an INVARIANT in its own AccBank_witness_*.cfg, where *)
(* TLC MUST report a violation.  A witness counterexample proves that the  *)
(* hazard its guard answers is actually REACHABLE in the good model — i.e. *)
(* that Safety holds because the contract CONTAINS the hazard, not because *)
(* the configuration never exercises it, and that the corresponding fault  *)
(* path is live code.  One witness per guarded hazard.                     *)
(***************************************************************************)

(* An acquire claim genuinely contends with a live foreign owner
   (RejectOwn's trigger state). *)
Witness_NoAcquireContention ==
    ~\E s \in Streams :
        st[s] = "req" /\ pend = s /\ ~BankFree(BankKey(s))

(* A stray accumulate attempt (in flight after spill) genuinely reaches
   the hardware while the issuer does not own the bank
   (AccumulateFault's trigger state). *)
Witness_NoStrayAccumulate ==
    ~\E s \in Streams :
        AccAttempt(s) /\ owner[BankKey(s)] # s

(* Same for a stray drain attempt (DrainFault's trigger state). *)
Witness_NoStrayDrain ==
    ~\E s \in Streams :
        DrainAttempt(s) /\ owner[BankKey(s)] # s

(* Two different contexts' spill images coexist, so a fill can address a
   FOREIGN image — the cross-context leak hazard (FillFaultForeign's
   trigger state).  Unreachable at NSlots = 1; that is why AssumeSlots
   demands >= 2. *)
Witness_NoForeignFillTarget ==
    ~\E s \in Streams :
        /\ st[s] = "spilled"
        /\ \E m \in Slots : mem[m].own \notin {NoOwner, s}

(* A fill's own image is ready but the pcid-selected bank is live under a
   foreign owner (FillFaultBusy's trigger state). *)
Witness_NoBusyFill ==
    ~\E s \in Streams :
        /\ st[s] = "spilled"
        /\ \E m \in Slots : mem[m].own = s
        /\ ~BankFree(BankKey(s))

(* The zero-race window: a raw 0x7E can be issued while a FOREIGN owner
   holds a non-empty accumulation in the targeted bank (ZeroFault's
   trigger state — and, with "zero_owner" deleted, the exact state from
   which the race counterexample fires). *)
Witness_NoZeroRaceWindow ==
    ~\E s \in Streams :
        /\ ZeroAttempt(s)
        /\ owner[BankKey(s)] \notin {NoOwner, s}
        /\ bank[BankKey(s)] # << >>

==========================================================================
