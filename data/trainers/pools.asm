; Species pools for the party spec system (Phase 2).
;
; A pool is the set of species a trainer's slots may roll. Pools are declarative
; and hand-editable; Phase 3 fills in all 19 gym-leader / Elite Four / Champion
; pools plus the shared route-trainer pools, against the pattern established
; here. Constants and the rationale for the record shapes live in
; constants/party_spec_constants.asm.
;
; LAYOUT. Each pool is three CONTIGUOUS runs - Kanto entries, then Johto, then
; Time Warp - and the table entry carries one count per run. At runtime
; RogueBuildParty skips the runs whose species group is not active this run
; (RogueGetActiveGroupMask), so a pool shrinks to the player's unlock state with
; no per-entry group byte and no scanning. This mirrors the tier-entry shape in
; engine/pokemon/rarity.asm.
;
; COUNTS ARE COMPUTED BY THE ASSEMBLER from the run labels. They used to be
; hand-summed EQUs in the rarity tables, kept in sync by hand across two files,
; which is exactly the bookkeeping that rots silently. Do not reintroduce them.
;
; Every pool must define all four labels even when a run is empty - put the
; labels adjacent and the count comes out zero:
;
;   FooPool:        ; Kanto run
;       pool_mon PIDGEY
;   FooPool_Johto:  ; Johto run
;       pool_mon HOOTHOOT
;   FooPool_Warp:   ; Time Warp run (empty here)
;   FooPool_End:

; \1 = species, \2 = optional form spec (default POOL_FORM_ROLL).
;
; `pool_mon SANDSLASH` rolls the form the normal gated way. `pool_mon SANDSLASH,
; 1` pins Alolan Sandslash - which changes its TYPE to Ice, so a pinned form is
; how a type-themed pool gets an off-type body on theme. `pool_mon NINETALES,
; POOL_FORM_BASE` guarantees the Fire one.
MACRO pool_mon
	db \1
	IF _NARG >= 2
	db \2
	ELSE
	db POOL_FORM_ROLL
	ENDC
ENDM

; \1 = pool label. Requires \1, \1_Johto, \1_Warp and \1_End.
MACRO trainer_pool
	db (\1_Johto - \1)      / POOL_ENTRY_SIZE ; Kanto run count
	db (\1_Warp  - \1_Johto) / POOL_ENTRY_SIZE ; Johto run count
	db (\1_End   - \1_Warp)  / POOL_ENTRY_SIZE ; Time Warp run count
	dw \1
ENDM

; --- Banded pools (data/trainers/band_pools.asm, from PARTY_ROSTER.md) -----
; The band_* macros live in data/trainers/band_pool_macros.asm, INCLUDEd by
; party_specs.asm: it runs a fourth pass (BAND_POOL_PASS 3) before this file
; exists, to learn which bands have an Ace or Off-type pool.

; Pool ids, in table order. A spec's `pool_id` indexes this table.
;
; Kanto/Johto run membership below follows engine/pokemon/rarity.asm's own
; group split, not type or generation intuition - checked directly rather
; than assumed, per FalknerPool's own AERODACTYL precedent. One real trap
; found doing this: WEAVILE, MAMOSWINE, MISMAGIUS, ANNIHILAPE, MAGNEZONE,
; SIRFETCHD, LICKILICKY, TANGROWTH, PORYGON_Z, KLEAVOR, RHYPERIOR, ELECTIVIRE
; and MAGMORTAR all read as ordinary Gen 2 (or later) species by name, but
; rarity.asm classifies every one of them as WARP-group, "classification-only,
; reached by EVOLVING something in the Kanto or Johto pool, not by being
; rolled" - putting any of them directly in a pool_mon list here would have
; made a late-game-only species available from round one. None of the 18
; pools below reference any of the 13; each becomes reachable exactly the
; way the rarity tables intend, by including its Kanto/Johto pre-evolution
; (PRIMEAPE, MAGNETON, FARFETCHD, SNEASEL, PILOSWINE, MISDREAVUS, LICKITUNG,
; TANGELA, PORYGON2, SCYTHER, RHYDON, ELECTABUZZ, MAGMAR) and letting
; ScaleTrainer_evolution promote it at a high enough level. The one Warp
; species with NO pre-evolution in this tree, MR_RIME, is left out of every
; pool below for the same reason none of the 18 pools use a `_Warp` run at
; all - matching FalknerPool's own empty one - rather than risk a second
; group-membership mistake for one mon under this phase's time budget.
;
; BROCK and WILL match the original plan's own pools.txt illustrative
; example verbatim (translating its `ESPEON`/`UMBREON` names to this tree's
; `JOLTEON` forms 1/2 - see [[project_forms_are_not_species]]); the other 16
; are this pass's own type-plus-authored-team derivation in the same style,
; absent a written brief entry for each of them.
	const_def
	const POOL_FALKNER
; Phase 7f: procedural stage-event characters (PROCEDURAL_WILD_AREA_PLAN.md).
; Trainer Revamp (TRAINER_REVAMP_FIXES_PLAN.md step 4). Appended rather than
; slotted in by role so no existing pool id moves.
; Gym leader banded pools, one id each (a `band_same` is an alias, not an id).
DEF BAND_POOL_PASS = 0
INCLUDE "data/trainers/band_pools.asm"
DEF NUM_TRAINER_POOLS EQU const_value

TrainerPoolTable::
	table_width POOL_TABLE_ENTRY_SIZE, TrainerPoolTable
	trainer_pool FalknerPool
DEF BAND_POOL_PASS = 1
INCLUDE "data/trainers/band_pools.asm"
	assert_table_length NUM_TRAINER_POOLS

; ---------------------------------------------------------------------------
; Falkner - Flying. The Phase 2 worked example; Phase 3 adds the other 18.
;
; ARTICUNO is an ordinary member here, NOT a gated one. Measured, not assumed:
; it sits in KantoUltraball in engine/pokemon/rarity.asm, and this tree's
; RARITY_TIER_UBER is exactly {MEW, MEWTWO}, so BIT_PSPEC_ALLOW_UBER does not
; cover the legendary birds. See that flag's note in
; constants/party_spec_constants.asm.
;
; MEWTWO was here through Phase 2 purely so BIT_PSPEC_ALLOW_UBER had an uber to
; reject. Phase 3 removed it: it was off-theme, and the test that needed it
; (test_uber_filter_reads_the_spec_flag) drives PartyGenPoolCandidateOk directly
; with wCurPartySpecies written by hand, so it never read the pool at all.
; SabrinaPool is where MEW and MEWTWO are real, on-theme content.
;
; AERODACTYL is deliberately in the Kanto run despite being a fossil mon: run
; membership follows the rarity tables' group split, not flavour.
; ---------------------------------------------------------------------------
FalknerPool:
	pool_mon PIDGEY
	pool_mon PIDGEOTTO
	pool_mon PIDGEOT
	pool_mon SPEAROW
	pool_mon FEAROW
	pool_mon DODUO
	pool_mon DODRIO
	pool_mon ZUBAT
	pool_mon GOLBAT
	pool_mon FARFETCHD
	pool_mon AERODACTYL
	pool_mon ARTICUNO
FalknerPool_Johto:
	pool_mon HOOTHOOT
	pool_mon NOCTOWL
	pool_mon CROBAT
	pool_mon MURKROW
	pool_mon SKARMORY
	pool_mon YANMA
	pool_mon GLIGAR
FalknerPool_Warp:
FalknerPool_End:

; The other 16 gym leaders' pools are the banded pools in
; data/trainers/band_pools.asm (BALANCE_PHASE5_PLAN.md F, 2026-09-29).
; The Elite Four's pools moved to PARTY_ROSTER.md ("## Elite Four", party roster
; Phase 7a, 2026-10-07): <Member>_Ace1 / _Fod1 in data/trainers/band_pools.asm.
; FalknerPool above stays: FalknerSpec2/3, the Phase 2 worked examples that the
; party-spec tests drive by name, still read it.
DEF BAND_POOL_PASS = 2
INCLUDE "data/trainers/band_pools.asm"

; Phase 7f stage-event characters: all five live in PARTY_ROSTER.md now (below).

; Jessie & James moved to the banded pools (PARTY_ROSTER.md "Wild-area
; trainers", party roster Phase 3, 2026-10-07): JessieJames_Fod<band> and
; JessieJames_Ace<band> in data/trainers/band_pools.asm.

; The Psychic, the Burglar, Nurse Joy and Officer Jenny moved to the banded pools
; (PARTY_ROSTER.md "Wild-area trainers", party roster Phase 3, 2026-10-07):
; <Prefix>_Fod<band> and <Prefix>_Ace<band> in data/trainers/band_pools.asm.

; The Champion rival's pool moved to PARTY_ROSTER.md ("## Champions", Rival3,
; party roster Phase 5, 2026-10-07): Rival3_Fod1 in data/trainers/band_pools.asm.
