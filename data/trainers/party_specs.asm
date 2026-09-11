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
MACRO e4_team_spec
	DEF _t    = \1
	DEF _tier = (_t - 1) / NUM_ROUND_VARIANTS + 1
	DEF _var  = (_t - 1) % NUM_ROUND_VARIANTS
	party_spec 5, 52 + _tier, 2, \2, MIX_ELITE, GYM_SPEC_FLAGS
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
