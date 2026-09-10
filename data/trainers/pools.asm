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

; Pool ids, in table order. A spec's `pool_id` indexes this table.
	const_def
	const POOL_FALKNER
DEF NUM_TRAINER_POOLS EQU const_value

TrainerPoolTable::
	table_width POOL_TABLE_ENTRY_SIZE, TrainerPoolTable
	trainer_pool FalknerPool
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
; MEWTWO is here to exercise BIT_PSPEC_ALLOW_UBER from both sides - FalknerSpec2
; must never draw it and FalknerSpec3 must be able to. ⚠ PHASE 3: delete this
; entry when writing Falkner's real pool. It is off-theme and only earns its
; place while this is the one pool in the tree.
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
	pool_mon MEWTWO ; RARITY_TIER_UBER; see the header note. Phase 3: remove.
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
