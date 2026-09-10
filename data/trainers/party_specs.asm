; Party specs: one record per (trainer class, wTrainerNo) saying how a team is
; built. Phase 2 of GYM_LEADER_EXPANSION_PLAN.md. Constants and the reasoning
; behind every field are in constants/party_spec_constants.asm.
;
; MIGRATION IS INCREMENTAL BY DESIGN. RogueBuildParty is consulted first and the
; existing authored/procedural paths in read_trainer_party.asm are the fallback,
; so a class may have specs for some wTrainerNo values and authored `db level,
; species` teams for the rest. A `dw 0` hole in a class's spec list means
; exactly that: no spec for this round, use the old path. That is what lets
; Phase 3 convert 19 characters one round at a time without a flag day.

; --- Moveset mixes ---------------------------------------------------------
; The "how many of each, at different gyms" control. Quotas sum to at most
; PARTY_LENGTH and are shuffled across the slots that have no override; a
; shortfall falls back to MSRC_LEARNSET, an overflow truncates.
;
; \1..\6 = quotas for MSRC_LEARNSET, MSRC_LEARNSET_FULL, MSRC_RANDOM,
;          MSRC_RANDOM_TM, MSRC_RANDOM_TM_ONLY, MSRC_SET - in MSRC_* order, so
;          the column and the constant cannot drift apart.
; \7      = set_tier_mask, which corpus grades MSRC_SET may draw from (0 = any)
; \8      = rank_row, a row of MoveRankWeightTable
; \9      = tm_cap, how many of a slot's four moves may be TM-ONLY moves under
;           MSRC_RANDOM_TM. A move that is both level-learnable and a TM does
;           not spend the cap, so tm_cap 4 makes it a fully unrestricted union.
; \10     = require_flags, \11 = forbid_flags (MOVEFLAG_* masks)
MACRO mix
	db \1, \2, \3, \4, \5, \6
	db \7, \8, \9
	dw \10
	dw \11
ENDM
DEF MIX_ENTRY_SIZE EQU 13

	const_def
	const MIX_ROUTE_EARLY
	const MIX_ROUTE_MID
	const MIX_GYM_EARLY
	const MIX_GYM_LATE
	const MIX_ELITE
DEF NUM_MOVESET_MIXES EQU const_value

MovesetMixTable::
	table_width MIX_ENTRY_SIZE, MovesetMixTable
	;   learn full rand rTM TMonly set   tier_mask               rank_row       tm_cap require        forbid
	mix     4,   0,   0,   0,  0,   0,   0,                      RANK_ROW_BAD,    0,   0,             MOVEFLAG_EXPLOSION
	mix     2,   1,   1,   0,  0,   0,   0,                      RANK_ROW_EASY,   1,   0,             MOVEFLAG_EXPLOSION
	mix     0,   1,   1,   1,  0,   1,   TIER_NORMAL,            RANK_ROW_NORMAL, 2,   0,             0
	mix     0,   0,   1,   1,  1,   2,   TIER_NORMAL | TIER_HARD, RANK_ROW_HARD,  3,   0,             0
	mix     0,   0,   1,   1,  1,   3,   TIER_HARD | TIER_ELITE, RANK_ROW_ELITE,  4,   MOVEFLAG_SLEEP, 0
	assert_table_length NUM_MOVESET_MIXES

; --- Slot override field widths --------------------------------------------
; Bytes consumed by each BIT_POVR_* field, in bit order. The parser walks bits
; 0..NUM_POVR_FIELDS-1 and consumes this many bytes per set bit, so adding a
; field is one const in party_spec_constants.asm plus one row here.
PartySpecOverrideFieldWidths::
	table_width 1, PartySpecOverrideFieldWidths
	db 2 ; BIT_POVR_SPECIES - species, form spec
	db 1 ; BIT_POVR_LEVEL   - absolute level
	db 1 ; BIT_POVR_SOURCE  - MSRC_*
	db 4 ; BIT_POVR_MOVES   - four literal move ids
	db 1 ; BIT_POVR_TYPE    - required type
	db 1 ; BIT_POVR_RARITY  - required rarity tier
	assert_table_length NUM_POVR_FIELDS

; --- Spec records ----------------------------------------------------------
; \1 = n_mons (1..PARTY_LENGTH), \2 = base level, \3 = per-slot level step
; (signed), \4 = pool id, \5 = mix id, \6 = BIT_PSPEC_* flags
MACRO party_spec
	db \1, \2, \3, \4, \5, \6
ENDM
DEF PARTY_SPEC_HEADER_SIZE EQU 6

; \1 = slot index (0-based), \2 = BIT_POVR_* flags. The optional bytes the flags
; name follow immediately, IN BIT ORDER.
MACRO slot_override
	db \1, \2
ENDM

; Per-class spec lists: `db count` then `count` x `dw`. wTrainerNo is 1-based, so
; entry i serves wTrainerNo i+1. A wTrainerNo of 0, or one past the count, or a
; `dw 0` hole all mean "no spec, use the authored path".
PartySpecPointers::
	table_width 2, PartySpecPointers
FOR n, 1, NUM_TRAINERS + 1
	IF n == FALKNER
	dw FalknerSpecs
	ELSE
	dw 0
	ENDC
ENDR
	assert_table_length NUM_TRAINERS

; ---------------------------------------------------------------------------
; Falkner - the Phase 2 worked example.
;
; wTrainerNo 1 is deliberately a `dw 0` hole, so his Phase 1 placeholder team
; still comes from data/trainers/parties.asm and
; test_new_leader_classes_build_their_placeholder_parties keeps passing. That
; makes this example prove BOTH paths coexist, which is the property Phase 3
; depends on, rather than just proving the new one works.
;
; wTrainerNo 2 exercises most of the model at once: a pool roll with no dupes,
; a positive level step, and an ace slot pinned by species, level AND explicit
; moves. Note the override fields appear in BIT ORDER (species, level, moves) -
; the parser consumes them that way, so a different order silently misreads.
; ---------------------------------------------------------------------------
FalknerSpecs::
	db 3
	dw 0 ; wTrainerNo 1 -> authored placeholder team
	dw FalknerSpec2
	dw FalknerSpec3

FalknerSpec2:
	party_spec 3, 13, 1, POOL_FALKNER, MIX_GYM_EARLY, \
	           (1 << BIT_PSPEC_NO_DUPES) | (1 << BIT_PSPEC_ACE_LAST)
	slot_override 2, (1 << BIT_POVR_SPECIES) | (1 << BIT_POVR_LEVEL) | (1 << BIT_POVR_MOVES)
	db PIDGEOT, POOL_FORM_BASE                                ; BIT_POVR_SPECIES
	db 17                                                     ; BIT_POVR_LEVEL
	db WING_ATTACK, SAND_ATTACK, QUICK_ATTACK, AGILITY        ; BIT_POVR_MOVES
	db PARTY_SPEC_OVERRIDES_END

; Identical to FalknerSpec2's pool and flags EXCEPT for BIT_PSPEC_ALLOW_UBER,
; and with no slot overrides so every slot rolls. It exists so the uber filter
; is tested from both sides rather than only in the direction that passes when
; the filter is broken: Spec2 must never draw MEWTWO, this must be able to.
; A filter that always rejected, or always accepted, fails one of the pair.
FalknerSpec3:
	party_spec 3, 13, 1, POOL_FALKNER, MIX_GYM_EARLY, \
	           (1 << BIT_PSPEC_ALLOW_UBER)
	db PARTY_SPEC_OVERRIDES_END
