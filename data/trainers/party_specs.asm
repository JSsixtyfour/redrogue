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
;
; ⚠ RGBDS's `\<digit>` substitution only reaches \1-\9 - `\10` parses as `\1`
; (parameter 1) followed by a LITERAL character "0", not as parameter 10. An
; earlier version of this macro wrote `dw \10` / `dw \11` directly and it
; assembled without error, silently emitting garbage (row 0's `\1` is 4, so
; `\10` rendered as the number 40, `\11` as 41) into every row's
; require_flags/forbid_flags - found 2026-09-10 while wiring up require_flags,
; by dumping the built ROM's actual table bytes against the source. `SHIFT 9`
; is the standard fix: it discards the first 9 arguments, so what was
; parameter 10 becomes \1 and what was parameter 11 becomes \2.
MACRO mix
	db \1, \2, \3, \4, \5, \6
	db \7, \8, \9
	SHIFT 9
	dw \1                   ; require_flags (was param 10)
	dw \2                   ; forbid_flags  (was param 11)
ENDM
DEF MIX_ENTRY_SIZE EQU 13

; --- The difficulty grid (Phase 5) -----------------------------------------
; Ten rows, in the shape the plan's Phase 5 table describes: three trainer
; KINDS by three ROUND BANDS, plus a sets-only row for the Elite Four.
;
;   kind \ band        rounds 1-2        rounds 3-5        rounds 6-8
;   route trainer      ROUTE_EARLY       ROUTE_MID         ROUTE_LATE
;   final route / gym  TRAINER_EARLY     TRAINER_MID       TRAINER_LATE
;   gym leader         GYM_EARLY         GYM_LATE          ELITE
;   mini-boss / rival  (the gym leader row of the same band)
;   Elite Four         E4_SETS at every tier
;
; The first two kinds reach their row through RogueRosterMixId, which derives
; kind and band from wBattleCount. The leader rows are selected by the spec
; record the round already picks (gym_team_spec), so they need no lookup.
;
; MIX_ELITE keeps its Phase 2 name rather than becoming MIX_GYM_ELITE: it is
; the gym leader's rounds 6-8 row, it is referenced by name in a dozen comments
; and five tests, and the genuinely-Elite-Four row is MIX_E4_SETS.
	const_def
	const MIX_ROUTE_EARLY     ; 0
	const MIX_ROUTE_MID       ; 1
	const MIX_ROUTE_LATE      ; 2
	const MIX_TRAINER_EARLY   ; 3
	const MIX_TRAINER_MID     ; 4
	const MIX_TRAINER_LATE    ; 5
	const MIX_GYM_EARLY       ; 6
	const MIX_GYM_LATE        ; 7
	const MIX_ELITE           ; 8
	const MIX_E4_SETS         ; 9
DEF NUM_MOVESET_MIXES EQU const_value

; Reading the rows: a quota that is not spent falls back to MSRC_LEARNSET, so
; "6 learnset" and "no quotas at all" build the same team. The explicit 6 on
; MIX_ROUTE_EARLY says "vanilla on purpose" rather than "not filled in yet".
;
; rank_row rises with the band on every kind, and with the kind at every band:
; BAD/EASY/NORMAL down the route column, EASY/NORMAL/HARD down the trainer
; column, NORMAL/HARD/ELITE down the leader column. That is the whole
; difficulty ladder in one readable diagonal, and it is deliberately NOT the
; lever AITierByRound pulls - that one scales how well the AI uses a moveset,
; this one scales what is in the moveset.
;
; Explosion is forbidden on the three ROUTE rows at every band and allowed from
; the gym-trainer rows up. A random route battle ending to a one-shot
; Selfdestruct reads as a feel-bad; the same move on a gym trainer is a threat
; the player walked into knowingly.
MovesetMixTable::
	table_width MIX_ENTRY_SIZE, MovesetMixTable
	;   learn full rand rTM TMonly set  tier_mask                rank_row        tm_cap require         forbid
	mix     6,   0,   0,   0,  0,   0,  0,                       RANK_ROW_BAD,    0,   0,              MOVEFLAG_EXPLOSION
	mix     0,   0,   1,   0,  0,   0,  0,                       RANK_ROW_EASY,   0,   0,              MOVEFLAG_EXPLOSION
	mix     0,   3,   3,   0,  0,   0,  0,                       RANK_ROW_NORMAL, 0,   0,              MOVEFLAG_EXPLOSION
	mix     0,   0,   3,   0,  0,   0,  0,                       RANK_ROW_EASY,   0,   0,              0
	mix     0,   0,   5,   1,  0,   0,  0,                       RANK_ROW_NORMAL, 2,   0,              0
	mix     0,   0,   0,   5,  0,   1,  TIER_EASY | TIER_NORMAL, RANK_ROW_HARD,   3,   0,              0
	mix     0,   1,   1,   1,  0,   1,  TIER_NORMAL,             RANK_ROW_NORMAL, 2,   0,              0
	mix     0,   0,   1,   1,  1,   2,  TIER_NORMAL | TIER_HARD, RANK_ROW_HARD,   3,   0,              0
	mix     0,   0,   1,   1,  1,   3,  TIER_HARD | TIER_ELITE,  RANK_ROW_ELITE,  4,   MOVEFLAG_SLEEP, 0
	mix     0,   0,   0,   0,  0,   6,  TIER_ELITE,              RANK_ROW_ELITE,  4,   MOVEFLAG_SLEEP, 0
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

; --- Mix-only pseudo-specs (Phase 5) ---------------------------------------
; One spec record per MovesetMixTable row, carrying NOTHING but the mix id.
;
; RogueApplyMixToParty re-uses the whole Phase 2 source-assignment and moveset
; machinery on a party that some OTHER path already built - GetRandRoster's
; rarity-class roll, or BuildMiniBossTeam's curated list. That machinery reads
; the mix id, the BIT_PSPEC_* flags and the slot-override list back out of a
; spec record through wPartyGenSpecPtr, so the cheapest way to drive it is to
; hand it a real record that happens to describe nothing else.
;
; Every field but the mix id is zero and is genuinely unread on this path:
;
;   n_mons       superseded by wPartyGenNMons, which RogueApplyMixToParty sets
;                from wEnemyPartyCount (the party already exists, so the count
;                is a measurement rather than an instruction)
;   base, step   levels are already final; the applier reads each mon's own
;                MON_LEVEL into wCurEnemyLevel instead
;   pool         no species is rolled
;   flags        0, so no ACE_LAST claim and no NO_DUPES retry
;   overrides    PARTY_SPEC_OVERRIDES_END immediately - there are none
;
; 7 bytes x NUM_MOVESET_MIXES. Generated by FOR rather than written out, so a
; new mix row cannot be added without its pseudo-spec appearing with it.
DEF MIX_ONLY_SPEC_SIZE EQU PARTY_SPEC_HEADER_SIZE + 1

MixOnlySpecs::
	table_width MIX_ONLY_SPEC_SIZE, MixOnlySpecs
	FOR m, NUM_MOVESET_MIXES
	party_spec 0, 0, 0, 0, m, 0
	db PARTY_SPEC_OVERRIDES_END
	ENDR
	assert_table_length NUM_MOVESET_MIXES


; ===========================================================================
; Phase 3: every gym leader and Elite Four member gets full round coverage.
;
; WHY FULL COVERAGE IS MANDATORY, not a nicety. InitGymBattle picks
; wTrainerNo = (round - 1) * 3 + 1 + rand(3), so a class wired into gym
; rotation is asked for all 24 values. RogueBuildParty declines any round with
; no spec and control falls into the TrainerDataPointers lookup, whose
; .SkipTrainer scans forward through wTrainerNo - 1 terminators - past the end
; of a short class's data and into the NEXT class's. Measured 2026-09-10:
; wTrainerNo 2 on a class with one authored team produced a level-53 Bruno
; party. So partial coverage is worse than none, and Phase 7 cannot wire a
; leader into rotation until its coverage is complete.
;
; THE SHAPE, three levels:
;
;   round    1..8, from wBattleCount / 10. Sets team size and levels.
;   variant  three per round, the rand(3). Sets who the ace is.
;   wTrainerNo = (round - 1) * 3 + variant + 1, variants A/B/C = 0/1/2.
;
; WHY VARIANTS DIFFER ONLY IN THEIR ACE. Under the old authored system the
; three variants were the ONLY source of variety, so each was a separately
; written team. Here every non-ace slot already rolls from the leader's pool,
; so three identical specs would already produce three different teams. What
; the pool roll cannot give is a recognisable identity, so that is what the
; variants carry:
;
;   A  the leader's PRIMARY signature pinned as the ace (Falkner -> Pidgeot)
;   B  no pin at all - the whole team rolls, ace included
;   C  the leader's SECONDARY signature pinned as the ace
;
; so a leader is recognisable about two thirds of the time and can still
; surprise. A pin costs 5 bytes over the 6-byte header; B costs 1.
;
; WHY wTrainerNo 1 IS A HOLE FOR EVERY CHARACTER. Round 1 variant A is left as
; `dw 0` deliberately, on all 19, so it keeps resolving through the authored
; path in data/trainers/parties.asm. Three things fall out of that:
;
;   - .SkipTrainer does ZERO skips at wTrainerNo 1, so it lands on the class's
;     FIRST authored team and cannot walk into the next class. The landmine
;     above needs a team to exist; at index 1 every class has one.
;   - the Phase 1 placeholder teams and the eight Kanto leaders' hand-authored
;     round-1 teams stay live content instead of becoming dead bytes.
;   - test_new_leader_classes_build_their_placeholder_parties and
;     test_spec_and_authored_team_coexist_on_one_class keep working unchanged.
;     That test is the only thing proving the eleven new classes landed at the
;     same index in all six NUM_TRAINERS-keyed tables, which assert_table_length
;     cannot see; it drives wTrainerNo 1, so the hole is what keeps it alive.
;
; ACE PINS ARE NOT GATED BY SPECIES GROUPS, and that is deliberate and
; consistent: an authored team shows exactly what you wrote, which is already
; how TRAINERPARTY_FORMS teams behave and how FalknerData's placeholder team
; already shows HOOTHOOT and NOCTOWL on a fresh Kanto save. Only the POOL ROLL
; is group-filtered. The convention followed below is that the eight Kanto
; leaders pin only Kanto-run species, because Phase 7 can draw them in a
; Kanto-only run; the eleven Johto characters may pin from either run, because
; Phase 7 only draws them when Johto is enabled.
; ===========================================================================

DEF NUM_ROUND_VARIANTS EQU 3        ; InitGymBattle's own `ld c, 3`
DEF NUM_GYM_ROUNDS     EQU 8
DEF NUM_GYM_TEAMS      EQU NUM_GYM_ROUNDS * NUM_ROUND_VARIANTS
DEF NUM_E4_TIERS       EQU 4        ; InitElite4Battle, wBattleCount 86..89
DEF NUM_E4_TEAMS       EQU NUM_E4_TIERS * NUM_ROUND_VARIANTS

; Every gym leader shares one team-size and level curve. MEASURED from the
; eight shipped Kanto rosters rather than invented - all eight are identical
; round for round, which is what makes one shared curve the right answer:
;
;   round    1     2     3     4     5     6     7     8
;   mons     2     2     3     3     4     4     5     6
;   levels 12-14 18-21 18-24 24-29 37-43 37-43 40-47 42-50
;
; base + slot * step reproduces both endpoints exactly on every round but 4,
; which lands 25-29 against the authored 24-29.
DEF GYM_SPEC_FLAGS EQU (1 << BIT_PSPEC_NO_DUPES) | (1 << BIT_PSPEC_ACE_LAST)

; \1 = wTrainerNo. Derives round and variant from it, so the record and the
; pointer that reaches it cannot describe different rounds.
; \2 = pool id, \3/\4 = primary ace for rounds 1-3 / 4-8, \5/\6 = secondary
; ace for the same split, \7 = extra spec flags applied from round 7 on.
;
; The early/late ace split exists because a PINNED species is never passed
; through ScaleTrainer_evolution - defeating the pin is the whole point of
; BIT_POVR_SPECIES - so a leader whose ace should grow across the run has to
; name both stages.
MACRO gym_team_spec
	DEF _t   = \1
	DEF _rnd = (_t - 1) / NUM_ROUND_VARIANTS + 1
	DEF _var = (_t - 1) % NUM_ROUND_VARIANTS
	IF _rnd == 1
	DEF _n = 2
	DEF _bl = 12
	DEF _st = 2
	DEF _mix = MIX_GYM_EARLY
	ELIF _rnd == 2
	DEF _n = 2
	DEF _bl = 18
	DEF _st = 3
	DEF _mix = MIX_GYM_EARLY
	ELIF _rnd == 3
	DEF _n = 3
	DEF _bl = 18
	DEF _st = 3
	DEF _mix = MIX_GYM_LATE
	ELIF _rnd == 4
	DEF _n = 3
	DEF _bl = 25
	DEF _st = 2
	DEF _mix = MIX_GYM_LATE
	ELIF _rnd == 5
	DEF _n = 4
	DEF _bl = 37
	DEF _st = 2
	DEF _mix = MIX_GYM_LATE
	ELIF _rnd == 6
	DEF _n = 4
	DEF _bl = 37
	DEF _st = 2
	DEF _mix = MIX_ELITE
	ELIF _rnd == 7
	DEF _n = 5
	DEF _bl = 39
	DEF _st = 2
	DEF _mix = MIX_ELITE
	ELSE
	DEF _n = 6
	DEF _bl = 40
	DEF _st = 2
	DEF _mix = MIX_ELITE
	ENDC
	DEF _flags = GYM_SPEC_FLAGS
	IF _rnd >= 7
	DEF _flags = _flags | (\7)
	ENDC
	party_spec _n, _bl, _st, \2, _mix, _flags
	IF _var == 0
	slot_override _n - 1, 1 << BIT_POVR_SPECIES
	IF _rnd <= 3
	db \3, POOL_FORM_ROLL
	ELSE
	db \4, POOL_FORM_ROLL
	ENDC
	ELIF _var == 2
	slot_override _n - 1, 1 << BIT_POVR_SPECIES
	IF _rnd <= 3
	db \5, POOL_FORM_ROLL
	ELSE
	db \6, POOL_FORM_ROLL
	ENDC
	ENDC
	db PARTY_SPEC_OVERRIDES_END
ENDM

; \1 = label prefix. Emits the pointer list only; the records it names come
; from gym_leader_records. Split in two so Falkner can keep the two Phase 2
; worked examples as its round 1 B and C records (FalknerSpec2 / FalknerSpec3,
; below) while generating rounds 2-8 exactly like everyone else.
MACRO gym_leader_pointers
\1Specs::
	db NUM_GYM_TEAMS
	dw 0                            ; wTrainerNo 1 - the authored-team hole
	FOR t, 2, NUM_GYM_TEAMS + 1
	dw \1Spec{d:t}
	ENDR
ENDM

; \1 = label prefix, \2..\7 as gym_team_spec, \8 = first wTrainerNo to emit
; (optional, default 2 - pass a higher value when earlier records are written
; by hand).
MACRO gym_leader_records
	DEF _first = 2
	IF _NARG >= 8
	DEF _first = \8
	ENDC
	FOR t, _first, NUM_GYM_TEAMS + 1
\1Spec{d:t}:
	gym_team_spec t, \2, \3, \4, \5, \6, \7
	ENDR
ENDM

; The Elite Four grid is FOUR tiers, not eight rounds: InitElite4Battle derives
; the tier linearly from wBattleCount 86-89 rather than from the /10 round grid
; gym leaders use, so an E4-only character needs 12 teams and asking it for 24
; is a bug, not extra headroom. Levels land 53-61 at tier 1 through 56-64 at
; tier 4, bracketing the shipped Lorelei/Bruno/Agatha/Lance rosters (53-62).
;
; \1 = wTrainerNo, \2 = pool, \3/\4 = primary ace species and form spec,
; \5/\6 = secondary. Forms are parameters here and not on the gym macro
; because both shipping E4 secondaries need one: there is no ESPEON or UMBREON
; species in this tree, they are JOLTEON forms 1 and 2.
;
; Phase 5 moved these off MIX_ELITE and onto MIX_E4_SETS, the plan's "sets
; only, ELITE mask" row. Every slot draws a curated set, and a species with no
; TIER_ELITE record at this level falls back to MSRC_RANDOM under
; RANK_ROW_ELITE - the documented MSRC_SET degradation, and the reason the tier
; mask can be this narrow without any slot coming out empty.
;
; There is no tier ladder here, unlike the gym rows: all four E4 tiers are
; within 3 levels of each other, so the same row serves all of them and the
; ladder lives in the levels instead.
MACRO e4_team_spec
	DEF _t    = \1
	DEF _tier = (_t - 1) / NUM_ROUND_VARIANTS + 1
	DEF _var  = (_t - 1) % NUM_ROUND_VARIANTS
	party_spec 5, 52 + _tier, 2, \2, MIX_E4_SETS, GYM_SPEC_FLAGS
	IF _var == 0
	slot_override 4, 1 << BIT_POVR_SPECIES
	db \3, \4
	ELIF _var == 2
	slot_override 4, 1 << BIT_POVR_SPECIES
	db \5, \6
	ENDC
	db PARTY_SPEC_OVERRIDES_END
ENDM

MACRO e4_member_pointers
\1Specs::
	db NUM_E4_TEAMS
	dw 0                            ; wTrainerNo 1 - the authored-team hole
	FOR t, 2, NUM_E4_TEAMS + 1
	dw \1Spec{d:t}
	ENDR
ENDM

MACRO e4_member_records
	FOR t, 2, NUM_E4_TEAMS + 1
\1Spec{d:t}:
	e4_team_spec t, \2, \3, \4, \5, \6
	ENDR
ENDM

; Per-class spec lists. wTrainerNo is 1-based, so entry i serves wTrainerNo
; i + 1. A wTrainerNo of 0, one past the count, or a `dw 0` hole all mean "no
; spec, use the authored path".
;
; Keyed by the class CONSTANT rather than written out as 61 positional rows on
; purpose: assert_table_length proves this table has NUM_TRAINERS entries but
; cannot see a row sitting at the wrong index, which is this repo's documented
; misaligned-table failure mode. Matching on `n == BROCK` is immune to it, and
; stays correct if the class ids are ever renumbered.
PartySpecPointers::
	table_width 2, PartySpecPointers
FOR n, 1, NUM_TRAINERS + 1
	IF n == BROCK
	dw BrockSpecs
	ELIF n == MISTY
	dw MistySpecs
	ELIF n == LT_SURGE
	dw LtSurgeSpecs
	ELIF n == ERIKA
	dw ErikaSpecs
	ELIF n == KOGA
	dw KogaSpecs
	ELIF n == BLAINE
	dw BlaineSpecs
	ELIF n == SABRINA
	dw SabrinaSpecs
	ELIF n == GIOVANNI
	dw GiovanniSpecs
	ELIF n == FALKNER
	dw FalknerSpecs
	ELIF n == BUGSY
	dw BugsySpecs
	ELIF n == WHITNEY
	dw WhitneySpecs
	ELIF n == MORTY
	dw MortySpecs
	ELIF n == CHUCK
	dw ChuckSpecs
	ELIF n == JASMINE
	dw JasmineSpecs
	ELIF n == PRYCE
	dw PryceSpecs
	ELIF n == CLAIR
	dw ClairSpecs
	ELIF n == JANINE
	dw JanineSpecs
	ELIF n == WILL
	dw WillSpecs
	ELIF n == KAREN
	dw KarenSpecs
	ELSE
	dw 0
	ENDC
ENDR
	assert_table_length NUM_TRAINERS

; ---------------------------------------------------------------------------
; Falkner - also the Phase 2 worked example, which is why he is the one class
; whose round 1 is hand-written.
;
; wTrainerNo 1 is the hole every character has. wTrainerNo 2 and 3 are the two
; specs Phase 2 built and verified against the running ROM; they are kept
; verbatim as round 1's B and C variants because five PyBoy tests drive them by
; name and by number. They are also still the clearest reading of the record
; format, so rounds 2-8 are generated below and these two stay as documentation.
;
; Note the override fields appear in BIT ORDER (species, level, moves) - the
; parser consumes them that way, so a different order silently misreads.
; ---------------------------------------------------------------------------
	gym_leader_pointers Falkner
	gym_leader_records  Falkner, POOL_FALKNER, PIDGEOTTO, PIDGEOT, DODUO, FEAROW, 0, 4

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
; the filter is broken. A filter that always rejected, or always accepted,
; fails one of the pair.
;
; The flag has no gameplay effect here any more: FalknerPool's MEWTWO was a
; fixture for this same test and Phase 3 removed it, as the Phase 2 handoff
; asked. test_uber_filter_reads_the_spec_flag drives PartyGenPoolCandidateOk
; directly with wCurPartySpecies written by hand, so it never needed the pool
; entry - only this flags byte. SabrinaSpecs is where ALLOW_UBER is real
; content instead.
FalknerSpec3:
	party_spec 3, 13, 1, POOL_FALKNER, MIX_GYM_EARLY, \
	           (1 << BIT_PSPEC_ALLOW_UBER)
	db PARTY_SPEC_OVERRIDES_END

; ---------------------------------------------------------------------------
; The eight Kanto gym leaders. Aces come from each pool's KANTO run only, since
; Phase 7 can draw these eight in a Kanto-only run where the Johto entries are
; filtered out of the roll; pinning a Johto species would show one anyway.
;
; Each primary/secondary pair is taken from that leader's own shipped roster,
; so the rolled teams keep the arcs the authored ones had: Brock still ends on
; Rhydon or Aerodactyl, Blaine on Arcanine or Rapidash.
; ---------------------------------------------------------------------------
	gym_leader_pointers Brock
	gym_leader_records  Brock,    POOL_BROCK,     ONIX,       RHYDON,    KABUTO,     AERODACTYL, 0

	gym_leader_pointers Misty
	gym_leader_records  Misty,    POOL_MISTY,     STARYU,     STARMIE,   SEADRA,     LAPRAS,     0

	gym_leader_pointers LtSurge
	gym_leader_records  LtSurge,  POOL_LT_SURGE,  VOLTORB,    RAICHU,    MAGNEMITE,  ELECTRODE,  0

	gym_leader_pointers Erika
	gym_leader_records  Erika,    POOL_ERIKA,     GLOOM,      VILEPLUME, WEEPINBELL, VICTREEBEL, 0

	gym_leader_pointers Koga
	gym_leader_records  Koga,     POOL_KOGA,      KOFFING,    WEEZING,   GRIMER,     MUK,        0

	gym_leader_pointers Blaine
	gym_leader_records  Blaine,   POOL_BLAINE,    GROWLITHE,  ARCANINE,  PONYTA,     RAPIDASH,   0

; Sabrina is the one leader whose pool holds RARITY_TIER_UBER species (MEW and
; MEWTWO), so she is the one who gets BIT_PSPEC_ALLOW_UBER, and only from round
; 7. Every other leader passes 0 there and can never draw one however its pool
; is edited later.
	gym_leader_pointers Sabrina
	gym_leader_records  Sabrina,  POOL_SABRINA,   KADABRA,    ALAKAZAM,  DROWZEE,    HYPNO,      1 << BIT_PSPEC_ALLOW_UBER

; GiovanniData carries 27 authored teams, three more than the 24 a gym leader
; can be asked for. wTrainerNo 25-27 are unreachable through InitGymBattle and
; stay authored; nothing here touches them.
	gym_leader_pointers Giovanni
	gym_leader_records  Giovanni, POOL_GIOVANNI,  NIDORINO,   NIDOKING,  RHYHORN,    RHYDON,     0

; ---------------------------------------------------------------------------
; The seven remaining Johto gym leaders, plus Janine. Phase 7 only draws these
; when BIT_GROUP_JOHTO is enabled, so their aces may come from either run - and
; several must, since the signature IS a Johto species (Whitney's Miltank,
; Jasmine's Steelix, Clair's Kingdra, Janine's Crobat, Morty's Misdreavus).
;
; Morty, Jasmine and Clair have four-species pools, which is authentic rather
; than an oversight - the Gen 2 originals field three distinct species between
; them - but it does mean their round 7-8 teams lean on BIT_PSPEC_NO_DUPES's
; bounded-then-accept degrade. That is the documented behaviour, not a hang.
; ---------------------------------------------------------------------------
	gym_leader_pointers Bugsy
	gym_leader_records  Bugsy,    POOL_BUGSY,     BUTTERFREE, SCYTHER,   BEEDRILL,   PINSIR,     0

	gym_leader_pointers Whitney
	gym_leader_records  Whitney,  POOL_WHITNEY,   CLEFAIRY,   MILTANK,   RATICATE,   CLEFABLE,   0

	gym_leader_pointers Morty
	gym_leader_records  Morty,    POOL_MORTY,     HAUNTER,    GENGAR,    GASTLY,     MISDREAVUS, 0

	gym_leader_pointers Chuck
	gym_leader_records  Chuck,    POOL_CHUCK,     MACHOKE,    MACHAMP,   PRIMEAPE,   HITMONLEE,  0

	gym_leader_pointers Jasmine
	gym_leader_records  Jasmine,  POOL_JASMINE,   MAGNETON,   STEELIX,   MAGNEMITE,  FORRETRESS, 0

	gym_leader_pointers Pryce
	gym_leader_records  Pryce,    POOL_PRYCE,     DEWGONG,    PILOSWINE, SEEL,       DEWGONG,    0

	gym_leader_pointers Clair
	gym_leader_records  Clair,    POOL_CLAIR,     DRAGONAIR,  DRAGONITE, DRATINI,    KINGDRA,    0

	gym_leader_pointers Janine
	gym_leader_records  Janine,   POOL_JANINE,    GOLBAT,     CROBAT,    VENONAT,    VENOMOTH,   0

; ---------------------------------------------------------------------------
; Will and Karen are Elite Four only and get TWELVE teams, not 24 - see the
; e4_team_spec note. Each pins its Gen 2 signature as the A ace and its
; eeveelution as the C ace; neither eeveelution is a species in this tree, so
; both go in as a JOLTEON form index.
; ---------------------------------------------------------------------------
	e4_member_pointers Will
	e4_member_records  Will,  POOL_WILL,  XATU,     POOL_FORM_ROLL, JOLTEON, 1 ; Espeon

	e4_member_pointers Karen
	e4_member_records  Karen, POOL_KAREN, HOUNDOOM, POOL_FORM_ROLL, JOLTEON, 2 ; Umbreon
