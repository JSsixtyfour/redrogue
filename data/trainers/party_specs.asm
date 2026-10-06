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
; The "how many of each, at different gyms" control. Quotas are dealt to the
; slots that have no override STRONGEST SOURCE FIRST (MSRC_SET down to
; MSRC_LEARNSET), so when a row asks for more units than the team has slots, it
; is the weakest units that are dropped, never the curated sets. Any slot no
; quota reaches takes the row's fallback source.
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
; \12     = fallback, an MSRC_* below MSRC_SET. Two jobs: the source of every
;           slot no quota reaches, and the source an MSRC_SET slot rolls when no
;           curated record fits this mon even after the level window widens
;           (see PartyGenApplySetMoveset). One column for both on purpose: "what
;           this row rolls when it has nothing more specific to say".
;
; The macro also records each row's quota total as QUOTA_SUM_OF_MIX_<row>, which
; gym_round_spec asserts against the team size of every round that uses it.
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
DEF NUM_MIX_ROWS_SEEN = 0
MACRO mix
	db \1, \2, \3, \4, \5, \6
	db \7, \8, \9
	DEF QUOTA_SUM_OF_MIX_{d:NUM_MIX_ROWS_SEEN} EQU \1 + \2 + \3 + \4 + \5 + \6
	SHIFT 9
	dw \1                   ; require_flags (was param 10)
	dw \2                   ; forbid_flags  (was param 11)
	ASSERT \3 < MSRC_SET, "a mix's fallback must be a rollable source below MSRC_SET"
	db \3                   ; fallback      (was param 12)
	DEF NUM_MIX_ROWS_SEEN += 1
ENDM
DEF MIX_ENTRY_SIZE EQU 14
DEF MIX_FALLBACK_OFFSET EQU 13

; --- The difficulty grid (Phase 5) -----------------------------------------
; Thirteen rows: three trainer KINDS by four BANDS, plus a sets-only row for the
; Elite Four. Every kind uses the same bands, the ones the gym leader's species
; pools use (GYM_BAND_ROUNDS, data/trainers/gym_band_pools.asm):
;
;   kind \ band        gyms 1-2       gyms 3-4       gyms 5-6       gyms 7-8
;   route trainer      ROUTE_EARLY    ROUTE_MID      ROUTE_LATE     ROUTE_FINAL
;   final route / gym  TRAINER_EARLY  TRAINER_MID    TRAINER_LATE   TRAINER_FINAL
;   gym leader         GYM_EARLY      GYM_MID        GYM_LATE       ELITE
;   mini-boss / rival  (the gym leader row of the same band)
;
;   Elite Four         E4_SETS at every tier
;
; A roster trainer's band is the band of the gym it is fought on the way to
; (RogueBandIndex). <KIND>_BAND<n>_MIX below is the ONE place a band's row is
; named: gym_round_spec reads the GYM ones for the leader's own spec, and
; RosterMixByKindAndBand / GymMixByBand (rogue_build_party.asm) are generated
; from them, so no two readers can disagree about a band.
;
; MIX_ELITE keeps its Phase 2 name rather than becoming MIX_GYM_FINAL: it is
; referenced by name in a dozen comments and five tests, and the
; genuinely-Elite-Four row is MIX_E4_SETS.
	const_def
	const MIX_ROUTE_EARLY     ; 0
	const MIX_ROUTE_MID       ; 1
	const MIX_ROUTE_LATE      ; 2
	const MIX_ROUTE_FINAL     ; 3
	const MIX_TRAINER_EARLY   ; 4
	const MIX_TRAINER_MID     ; 5
	const MIX_TRAINER_LATE    ; 6
	const MIX_TRAINER_FINAL   ; 7
	const MIX_GYM_EARLY       ; 8
	const MIX_GYM_MID         ; 9
	const MIX_GYM_LATE        ; 10
	const MIX_ELITE           ; 11
	const MIX_E4_SETS         ; 12
DEF NUM_MOVESET_MIXES EQU const_value

; Bands. A band is GYM_BAND_ROUNDS consecutive gyms; the leader's species pools
; (Ace/Fod/Off<band>) and every kind's moveset row are keyed on it.
DEF GYM_BAND_ROUNDS     EQU 2
DEF NUM_GYM_BANDS       EQU 4
DEF ROUTE_BAND1_MIX     EQU MIX_ROUTE_EARLY   ; gyms 1-2
DEF ROUTE_BAND2_MIX     EQU MIX_ROUTE_MID     ; gyms 3-4
DEF ROUTE_BAND3_MIX     EQU MIX_ROUTE_LATE    ; gyms 5-6
DEF ROUTE_BAND4_MIX     EQU MIX_ROUTE_FINAL   ; gyms 7-8
DEF TRAINER_BAND1_MIX   EQU MIX_TRAINER_EARLY
DEF TRAINER_BAND2_MIX   EQU MIX_TRAINER_MID
DEF TRAINER_BAND3_MIX   EQU MIX_TRAINER_LATE
DEF TRAINER_BAND4_MIX   EQU MIX_TRAINER_FINAL
DEF GYM_BAND1_MIX       EQU MIX_GYM_EARLY
DEF GYM_BAND2_MIX       EQU MIX_GYM_MID
DEF GYM_BAND3_MIX       EQU MIX_GYM_LATE
DEF GYM_BAND4_MIX       EQU MIX_ELITE

; READING THE ROWS: a row is "these few units, then the fallback for every
; other slot". Quotas are dealt strongest source first and the fallback fills
; whatever is left, so a row says the same thing to a 2-mon team and a 6-mon
; one, and no unit depends on the team reaching some size. Rule of thumb, held
; by tests (test_difficulty_grid.py): a row's quota total fits the SMALLEST team
; its band fields - roster sizes come from data/balance/trainer_levels.asm, gym
; sizes from GYM_R<n>_MONS (also asserted at build time in gym_round_spec).
;
;   ROUTE_EARLY    vanilla learnset
;   ROUTE_MID      1 random, rest learnset
;   ROUTE_LATE     1 random+TM (tm_cap 1), 1 random, rest learnset
;   ROUTE_FINAL    2 random+TM (tm_cap 1), 1 random, rest learnset
;                  Route rows fall back to the VANILLA learnset, never the full
;                  one: MSRC_LEARNSET_FULL draws uniformly from every level-up
;                  move, so it is variety, not difficulty, and can come out
;                  softer than the four most recent moves.
;   TRAINER_EARLY  all random                          (unchanged: the old "3
;                  random" on teams that never exceed 3)
;   TRAINER_MID    1 random+TM, rest random            (the old row's TM slot
;                  only reached a 6th mon, which rounds 3-5 never field)
;   TRAINER_LATE   1 curated set, 1 random+TM, rest random
;   TRAINER_FINAL  1 curated set, rest random+TM       (the old rounds 6-8 row,
;                  with its set always landing; sets now NORMAL or HARD so the
;                  curated mon is no softer than its random+TM teammates)
;   GYM_EARLY  2 mons: ace set (NORMAL), one full learnset. Most gym 1-2 aces
;              have no curated set at levels 11-18, so the fallback is the
;              plain level-up roll, keeping the opening gyms soft.
;   GYM_MID    3 mons: ace set (NORMAL only), one random, one random+TM, all on
;              RANK_ROW_NORMAL with tm_cap 2.
;   GYM_LATE   4 mons: two sets (NORMAL or HARD), one random+TM, one TM-only.
;   ELITE      5-6 mons: three sets (HARD or ELITE), one random+TM, one
;              TM-only; gym 8's sixth mon takes the random+TM fallback.
;
; THE LADDER. rank_row never falls band to band within a kind:
;
;   band       gyms 1-2  gyms 3-4  gyms 5-6  gyms 7-8
;   route      BAD       EASY      NORMAL    HARD
;   trainer    EASY      NORMAL    HARD      HARD
;   leader     NORMAL    NORMAL    HARD      ELITE
;
; Routes sit between the gyms on either side of them: a band's route is no
; softer than the previous band's gym trainers and no harder than its own
; leader. Gyms 3-4 routes stay on EASY, just under the gym 2 leader, so the
; step from gym 2 to the gym 3-4 trainers is not doubled up on the routes.
; Within a band, route <= trainer <= leader, and where two of them share a
; rank_row the tougher one names a stronger source (route FINAL random+TM vs
; trainer FINAL curated set). All of this is held by test_difficulty_grid.py. It is deliberately NOT the lever
; AITierByRound pulls - that one scales how well the AI uses a moveset, this
; one scales what is in the moveset.
;
; Explosion is forbidden on the ROUTE rows at every band and allowed from the
; gym-trainer rows up. A random route battle ending to a one-shot Selfdestruct
; reads as a feel-bad; the same move on a gym trainer is a threat the player
; walked into knowingly.
MovesetMixTable::
	table_width MIX_ENTRY_SIZE, MovesetMixTable
	;   learn full rand rTM TMonly set  tier_mask                rank_row        tm_cap require         forbid              fallback
	mix     0,   0,   0,   0,  0,   0,  0,                       RANK_ROW_BAD,    0,   0,              MOVEFLAG_EXPLOSION, MSRC_LEARNSET       ; ROUTE_EARLY
	mix     0,   0,   1,   0,  0,   0,  0,                       RANK_ROW_EASY,   0,   0,              MOVEFLAG_EXPLOSION, MSRC_LEARNSET       ; ROUTE_MID
	mix     0,   0,   1,   1,  0,   0,  0,                       RANK_ROW_NORMAL, 1,   0,              MOVEFLAG_EXPLOSION, MSRC_LEARNSET       ; ROUTE_LATE
	mix     0,   0,   1,   2,  0,   0,  0,                       RANK_ROW_HARD,   1,   0,              MOVEFLAG_EXPLOSION, MSRC_LEARNSET       ; ROUTE_FINAL
	mix     0,   0,   0,   0,  0,   0,  0,                       RANK_ROW_EASY,   0,   0,              0,                  MSRC_RANDOM         ; TRAINER_EARLY
	mix     0,   0,   0,   1,  0,   0,  0,                       RANK_ROW_NORMAL, 2,   0,              0,                  MSRC_RANDOM         ; TRAINER_MID
	mix     0,   0,   0,   1,  0,   1,  TIER_EASY | TIER_NORMAL, RANK_ROW_HARD,   2,   0,              0,                  MSRC_RANDOM         ; TRAINER_LATE
	mix     0,   0,   0,   0,  0,   1,  TIER_NORMAL | TIER_HARD, RANK_ROW_HARD,   3,   0,              0,                  MSRC_RANDOM_TM      ; TRAINER_FINAL
	mix     0,   1,   0,   0,  0,   1,  TIER_NORMAL,             RANK_ROW_NORMAL, 2,   0,              0,                  MSRC_RANDOM         ; GYM_EARLY
	mix     0,   0,   1,   1,  0,   1,  TIER_NORMAL,             RANK_ROW_NORMAL, 2,   0,              0,                  MSRC_RANDOM         ; GYM_MID
	mix     0,   0,   0,   1,  1,   2,  TIER_NORMAL | TIER_HARD, RANK_ROW_HARD,   3,   0,              0,                  MSRC_RANDOM_TM      ; GYM_LATE
	mix     0,   0,   0,   1,  1,   3,  TIER_HARD | TIER_ELITE,  RANK_ROW_ELITE,  4,   MOVEFLAG_SLEEP, 0,                  MSRC_RANDOM_TM      ; ELITE
	mix     0,   0,   0,   0,  0,   6,  TIER_ELITE,              RANK_ROW_ELITE,  4,   MOVEFLAG_SLEEP, 0,                  MSRC_RANDOM_TM      ; E4_SETS
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
	db 1 ; BIT_POVR_POOL    - pool id
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
;   round    1..8, from wBattleCount / ROUND_BATTLES. Sets team size and levels.
;   variant  three per round, the rand(3).
;   wTrainerNo = (round - 1) * 3 + variant + 1, variants A/B/C = 0/1/2.
;
; GYM LEADERS (banded design, 2026-09-29, see gym_round_spec below): the three
; variants of a round share ONE record, and the ace is rolled from the band's
; ace pool rather than pinned. The variant now only moves the off-type mon to a
; different slot. Until then each variant pinned a different signature ace
; (A primary, B none, C secondary); the ace pool replaces that with a list the
; designer controls directly.
;
; NO wTrainerNo 1 HOLE ANY MORE. Until 2026-09-29 round 1 variant A was a
; `dw 0` on every gym leader, so a third of gym 1 fights used the old authored
; team in data/trainers/parties.asm. The gym leaders now follow the Elite Four
; (below): a full 24-entry list, so RogueBuildParty never declines for any
; wTrainerNo InitGymBattle hands out and the .SkipTrainer landmine above cannot
; fire. The authored leader teams in parties.asm are unreachable, except
; GiovanniData 25-27 (past the end of his list).
;
; THE ELITE FOUR HAVE NO HOLE (Trainer Revamp, 2026-09-23). The seven E4
; classes and the Champion rival cover wTrainerNo 1 with a spec too, because
; their authored round-1 team was the same fixed 4-5 mon list on every run - the
; "E4 teams aren't random" report. Their authored data in parties.asm is now
; unreachable. The .SkipTrainer landmine above cannot fire for them either way:
; a full list means RogueBuildParty never declines.
;
; POOLS ARE GATED BY SPECIES GROUPS, aces included: a gym ace is a pool draw,
; so its Johto/Warp entries drop out of a run that has not unlocked them. That
; is why every Kanto leader's Ace list keeps at least one Kanto entry. An E4
; ace is still a pin and, like an authored team, shows exactly what was written.
; ===========================================================================

DEF NUM_ROUND_VARIANTS EQU 3        ; InitGymBattle's own `ld c, 3`
DEF NUM_GYM_ROUNDS     EQU 8
DEF NUM_GYM_TEAMS      EQU NUM_GYM_ROUNDS * NUM_ROUND_VARIANTS
DEF NUM_E4_TIERS       EQU 4        ; InitElite4Battle, wBattleCount E4_FIRST_BATTLECOUNT..+3 (69..72)
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
;
; The table above is the ORIGINAL shipped curve. The live values are the
; GYM_R<round>_* constants in constants/balance_constants.asm; tune them there.
DEF GYM_SPEC_FLAGS EQU (1 << BIT_PSPEC_NO_DUPES) | (1 << BIT_PSPEC_ACE_LAST)

; BANDED DESIGN (BALANCE_PHASE5_PLAN.md workstream F, 2026-09-29). Rounds are
; grouped into bands of GYM_BAND_ROUNDS (gyms 1-2, 3-4, 5-6, 7-8), and each band
; has three pools per leader in data/trainers/gym_band_pools.asm:
;
;   Ace<band>  the LAST slot rolls from it, via a BIT_POVR_POOL override. Its
;              entries are POOL_FORM_KEEP, so the ace is used as written.
;   Fod<band>  the spec's own pool: every other slot, evolved by level.
;   Off<band>  from band 2: a BIT_POVR_POOL override on PARTY_GEN_OFFTYPE_SLOT.
;              One slot per team draws from it, and a fodder slot that finds
;              every on-type species taken falls back to it.
;
; The round variants no longer differ in the record: all three wTrainerNo of a
; round point at ONE record per round. The off-type mon's POSITION still
; differs by variant, because PartyGenSlotPoolId derives it from wTrainerNo.
; This replaced 23 records per leader (4.6 KB for the 17) with 8.
;
; The band also picks the moveset row, through GYM_BAND<n>_MIX (defined with
; the mix ids above), and the band's row must fit every team in the band: its
; quota total may not exceed the round's team size, or a unit would be dropped.
; GYM_BAND_ROUNDS and NUM_GYM_BANDS are defined with the mix ids too, because
; every trainer kind's band is cut on them, not only the leader's.
ASSERT NUM_GYM_BANDS * GYM_BAND_ROUNDS == NUM_GYM_ROUNDS, \
	"NUM_GYM_BANDS bands of GYM_BAND_ROUNDS rounds must cover every gym round"

; \1 = label prefix (also the pool-name prefix), \2 = round 1..8, \3 = extra
; spec flags applied from round 7 on.
MACRO gym_round_spec
	DEF _rnd = \2
	DEF _band = (_rnd - 1) / GYM_BAND_ROUNDS + 1
	; Team size and level curve: GYM_R<round>_* in constants/balance_constants.asm.
	DEF _n = GYM_R{d:_rnd}_MONS
	DEF _bl = GYM_R{d:_rnd}_BASE
	DEF _st = GYM_R{d:_rnd}_STEP
	DEF _mix = GYM_BAND{d:_band}_MIX
	ASSERT QUOTA_SUM_OF_MIX_{d:_mix} <= _n, \
		"gym round {d:_rnd}: mix {d:_mix} deals {d:QUOTA_SUM_OF_MIX_{d:_mix}} units to a {d:_n}-mon team"
	DEF _flags = GYM_SPEC_FLAGS
	IF _rnd >= 7
	DEF _flags = _flags | (\3)
	ENDC
	party_spec _n, _bl, _st, POOL_BAND_\1_Fod{d:_band}, _mix, _flags
	slot_override _n - 1, 1 << BIT_POVR_POOL
	db POOL_BAND_\1_Ace{d:_band}
	IF _band >= 2
	slot_override PARTY_GEN_OFFTYPE_SLOT, 1 << BIT_POVR_POOL
	db POOL_BAND_\1_Off{d:_band}
	ENDC
	db PARTY_SPEC_OVERRIDES_END
ENDM

; \1 = label prefix. The 24-entry pointer list: every wTrainerNo points at its
; round's record, wTrainerNo 1 included (the authored-team hole was removed
; 2026-09-29, so gym 1 always uses the banded pools).
MACRO gym_leader_pointers
\1Specs::
	db NUM_GYM_TEAMS
	FOR t, 1, NUM_GYM_TEAMS + 1
	DEF _r = (t - 1) / NUM_ROUND_VARIANTS + 1
	dw \1Round{d:_r}
	ENDR
ENDM

; \1 = label prefix, \2 = extra spec flags from round 7 on.
MACRO gym_leader_records
	FOR r, 1, NUM_GYM_ROUNDS + 1
\1Round{d:r}:
	gym_round_spec \1, r, \2
	ENDR
ENDM

; The Elite Four grid is FOUR tiers, not eight rounds: InitElite4Battle derives
; the tier linearly from wBattleCount E4_FIRST_BATTLECOUNT..+3 (69-72) rather
; than from the round grid gym leaders use, so an E4-only character needs 12
; teams and asking it for 24
; is a bug, not extra headroom. Six mons (was five), levels 52-62 at tier 1
; through 55-65 at tier 4: the ace at tier 4 lands on 65, the Champion rival's
; ace level, which is what Champion Lance draws (ChampionsRoom.asm, wTrainerNo
; 10-12). The base moved from 52 + tier to 51 + tier along with the sixth slot so
; the ace stayed within one level of the shipped rosters' 62.
;
; \1 = wTrainerNo, \2 = pool, \3/\4 = primary ace species and form spec,
; \5/\6 = secondary. Forms are parameters here and not on the gym macro
; because both shipping E4 secondaries need one: there is no ESPEON or UMBREON
; species in this tree, they are JOLTEON forms 1 and 2.
;
; Phase 5 moved these off MIX_ELITE and onto MIX_E4_SETS, the plan's "sets
; only, ELITE mask" row. Every slot draws a curated set, and a species with no
; TIER_ELITE record near this level falls back to the row's MSRC_RANDOM_TM under
; RANK_ROW_ELITE - the documented MSRC_SET degradation, and the reason the tier
; mask can be this narrow without any slot coming out empty.
;
; There is no tier ladder here, unlike the gym rows: all four E4 tiers are
; within 3 levels of each other, so the same row serves all of them and the
; ladder lives in the levels instead.
DEF E4_TEAM_SIZE EQU 6

MACRO e4_team_spec
	DEF _t    = \1
	DEF _tier = (_t - 1) / NUM_ROUND_VARIANTS + 1
	DEF _var  = (_t - 1) % NUM_ROUND_VARIANTS
	party_spec E4_TEAM_SIZE, E4_BASE_LEVEL + _tier, E4_LEVEL_STEP, \2, MIX_E4_SETS, GYM_SPEC_FLAGS
	IF _var == 0
	slot_override E4_TEAM_SIZE - 1, 1 << BIT_POVR_SPECIES
	db \3, \4
	ELIF _var == 2
	slot_override E4_TEAM_SIZE - 1, 1 << BIT_POVR_SPECIES
	db \5, \6
	ENDC
	db PARTY_SPEC_OVERRIDES_END
ENDM

MACRO e4_member_pointers
\1Specs::
	db NUM_E4_TEAMS
	FOR t, 1, NUM_E4_TEAMS + 1      ; no wTrainerNo 1 hole - see above
	dw \1Spec{d:t}
	ENDR
ENDM

MACRO e4_member_records
	FOR t, 1, NUM_E4_TEAMS + 1
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
	ELIF n == KOGA_E4
	dw KogaE4Specs
	ELIF n == LORELEI
	dw LoreleiSpecs
	ELIF n == BRUNO
	dw BrunoSpecs
	ELIF n == AGATHA
	dw AgathaSpecs
	ELIF n == LANCE
	dw LanceSpecs
	ELIF n == RIVAL3
	dw Rival3Specs
	ELIF n == JESSIE_JAMES
	dw JessieJamesSpecs
	ELIF n == PSYCHIC_TR
	dw PsychicSpecs
	ELIF n == BURGLAR
	dw BurglarSpecs
	ELIF n == NURSE_JOY
	dw NurseJoySpecs
	ELIF n == OFFICER_JENNY
	dw OfficerJennySpecs
	ELSE
	dw 0
	ENDC
ENDR
	assert_table_length NUM_TRAINERS

; ---------------------------------------------------------------------------
; Falkner. His rounds are banded like everyone's.
;
; FalknerSpec2/3 below are the two specs Phase 2 built and verified against the
; running ROM. No (class, wTrainerNo) reaches them any more (until 2026-09-29
; they were Falkner's round 1 B and C); they stay as TEST FIXTURES, built via
; RogueBuildPartyFromSpecPtr, because they exercise a species pin, a level pin,
; literal moves and the uber flag that no shipping record uses. They are also
; still the clearest reading of the record format.
;
; Note the override fields appear in BIT ORDER (species, level, moves) - the
; parser consumes them that way, so a different order silently misreads.
; ---------------------------------------------------------------------------
	gym_leader_pointers Falkner
	gym_leader_records  Falkner, 0

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
; The eight Kanto gym leaders. Their pools are data/trainers/gym_band_pools.asm
; (Brock_Ace1 .. Giovanni_Off4); the only argument left here is the extra spec
; flags from round 7, 0 for everyone since no gym pool lists an uber.
; ---------------------------------------------------------------------------
	gym_leader_pointers Brock
	gym_leader_records  Brock, 0

	gym_leader_pointers Misty
	gym_leader_records  Misty, 0

	gym_leader_pointers LtSurge
	gym_leader_records  LtSurge, 0

	gym_leader_pointers Erika
	gym_leader_records  Erika, 0

	gym_leader_pointers Koga
	gym_leader_records  Koga, 0

	gym_leader_pointers Blaine
	gym_leader_records  Blaine, 0

	gym_leader_pointers Sabrina
	gym_leader_records  Sabrina, 0

; GiovanniData carries 27 authored teams, three more than the 24 a gym leader
; can be asked for. wTrainerNo 25-27 are unreachable through InitGymBattle and
; stay authored; nothing here touches them.
	gym_leader_pointers Giovanni
	gym_leader_records  Giovanni, 0

; ---------------------------------------------------------------------------
; The seven remaining Johto gym leaders, plus Janine. Phase 7 only draws these
; when BIT_GROUP_JOHTO is enabled, so their ace pools may be Johto-only.
;
; Morty and Clair have few on-type lines, so their fodder pools carry themed
; off-type species (Agatha-style "spooky" for Morty, Lance-style dragons for
; Clair) and the off-type fallback covers the rest.
; ---------------------------------------------------------------------------
	gym_leader_pointers Bugsy
	gym_leader_records  Bugsy, 0

	gym_leader_pointers Whitney
	gym_leader_records  Whitney, 0

	gym_leader_pointers Morty
	gym_leader_records  Morty, 0

	gym_leader_pointers Chuck
	gym_leader_records  Chuck, 0

	gym_leader_pointers Jasmine
	gym_leader_records  Jasmine, 0

	gym_leader_pointers Pryce
	gym_leader_records  Pryce, 0

	gym_leader_pointers Clair
	gym_leader_records  Clair, 0

	gym_leader_pointers Janine
	gym_leader_records  Janine, 0

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

; ---------------------------------------------------------------------------
; KOGA_E4 - the Elite Four Koga, a SEPARATE class from the gym KOGA.
;
; The two roles need different grids: the gym Koga is 24 records indexed by
; ROUND, while InitElite4Battle hands out wTrainerNo 1-12 on the four-tier E4
; grid. On one shared class an Elite Four Koga would have fielded his gym
; rounds 1-4 - about level 15 against a level 55 party - through BOTH the spec
; path and the authored KogaData fallback.
;
; Because he is his own class, this is the Will/Karen shape verbatim: no macro
; of his own, no offset arithmetic, and InitElite4Battle needs no branch. He
; draws from POOL_KOGA_E4, his own pool since the Trainer Revamp split the two
; roles (Articuno is E4-only, Beedrill gym-only). Aces: Crobat, and Galarian
; Weezing (WEEZING form 1).
; ---------------------------------------------------------------------------
	e4_member_pointers KogaE4
	e4_member_records  KogaE4, POOL_KOGA_E4, CROBAT, 0, WEEZING, 1 ; Galarian

; ---------------------------------------------------------------------------
; The Kanto Elite Four (Trainer Revamp, 2026-09-23). Until now they had no
; spec list at all, so every tier fielded the same authored five - LANCE's
; list also serves Champion Lance, who draws wTrainerNo 10-12 (tier 4).
; Aces: A is each member's shipped ace, C a second signature.
; ---------------------------------------------------------------------------
	e4_member_pointers Lorelei
	e4_member_records  Lorelei, POOL_LORELEI, LAPRAS,    0, CLOYSTER,  0

	e4_member_pointers Bruno
	e4_member_records  Bruno,   POOL_BRUNO,   MACHAMP,   0, HITMONTOP, 0

	e4_member_pointers Agatha
	e4_member_records  Agatha,  POOL_AGATHA,  GENGAR,    0, MAROWAK,   1 ; Alolan

	e4_member_pointers Lance
	e4_member_records  Lance,   POOL_LANCE,   DRAGONITE, 0, KINGDRA,   0

; ---------------------------------------------------------------------------
; RIVAL3, the Champion rival. ChampionsRoom.asm hands out wTrainerNo 1-5 and
; all five reach ONE record: the variety comes from the pool roll, not from
; five authored teams (Rival3Data in parties.asm is now unreachable).
;
; His ace is always his own selected starter: slot 5 pins
; RIVAL_STARTER_PLACEHOLDER, which PartyGenBuildSlot turns into wRivalStarter
; evolved to the slot's level (PatchRivalStarterSpecies). NO_RIVAL_STARTER keeps
; the five pool slots from drawing that same line again. Levels come from
; CHAMPION_BASE_LEVEL / CHAMPION_LEVEL_STEP (balance_constants.asm).
; ---------------------------------------------------------------------------
DEF NUM_RIVAL3_TEAMS EQU 5          ; ChampionsRoom.asm's `ld c, 5`

Rival3Specs::
	db NUM_RIVAL3_TEAMS
	REPT NUM_RIVAL3_TEAMS
	dw Rival3Spec
	ENDR

Rival3Spec:
	party_spec 6, CHAMPION_BASE_LEVEL, CHAMPION_LEVEL_STEP, POOL_RIVAL3, MIX_E4_SETS, \
	           GYM_SPEC_FLAGS | (1 << BIT_PSPEC_NO_RIVAL_STARTER)
	slot_override 5, 1 << BIT_POVR_SPECIES
	db RIVAL_STARTER_PLACEHOLDER, POOL_FORM_BASE
	db PARTY_SPEC_OVERRIDES_END

; ===========================================================================
; Phase 7f: procedural stage-event characters (PROCEDURAL_WILD_AREA_PLAN.md).
;
; These are not gym leaders - there is no round/variant grid, because
; InitGymBattle never touches them. StageEventApplyTrainers
; (custom_functions/stage_events.asm) drives wTrainerNo itself, computing it
; from wBattleCount with the exact same round formula
; custom_functions/func_enc_gen.asm's GetMiniBossTierPtr uses for
; trainer_difficulty_settings_miniboss (wBattleCount / 10, clamped to round
; 9) - a duplicated three-line clamp, not a cross-bank pointer, for the same
; reason PFRollMonClass/PCAbs are duplicated rather than shared: the routine
; that needs it lives in a different bank, and GetMiniBossTierPtr returns a
; pointer into ITS bank's own table, which cannot survive a farcall back out.
;
; One spec per round (1-9), matching that same 9-row table, so "scales like a
; mini-boss" is literally true here: base_level is that table's own min_level
; per round. Team size ramps 2/2/3/3/4/4/5/5/6, reaching a full team only at
; the final tier - these are a casual ambush, not a gym battle, so they start
; smaller than gym_team_spec's 2/2/3/3/4/4/5/6 ladder, which reaches 6 by
; round 7.
; ===========================================================================

; \1 = round (1-9). \2 = pool id. \3 = extra BIT_PSPEC_* flags beyond
; NO_DUPES (0 for none).
MACRO stage_event_team_spec
	DEF _r = \1
	; Team size and level: STAGE_EVENT_R<round>_* in constants/balance_constants.asm.
	DEF _n = STAGE_EVENT_R{d:_r}_MONS
	DEF _bl = STAGE_EVENT_R{d:_r}_BASE
	IF _r <= 2
	DEF _mix = MIX_ROUTE_EARLY
	ELIF _r <= 5
	DEF _mix = MIX_ROUTE_MID
	ELIF _r <= 8
	DEF _mix = MIX_ROUTE_LATE
	ELSE
	DEF _mix = MIX_TRAINER_LATE
	ENDC
	party_spec _n, _bl, STAGE_EVENT_LEVEL_STEP, \2, _mix, (1 << BIT_PSPEC_NO_DUPES) | \3
	db PARTY_SPEC_OVERRIDES_END
ENDM

; \1 = label prefix.
MACRO stage_event_pointers
\1Specs::
	db NUM_STAGE_EVENT_TIERS
	FOR t, 1, NUM_STAGE_EVENT_TIERS + 1
	dw \1Spec{d:t}
	ENDR
ENDM

; \1 = label prefix, \2 = pool id, \3 = extra flags (0 for none).
MACRO stage_event_records
	FOR t, 1, NUM_STAGE_EVENT_TIERS + 1
\1Spec{d:t}:
	stage_event_team_spec t, \2, \3
	ENDR
ENDM

DEF NUM_STAGE_EVENT_TIERS EQU 9 ; matches trainer_difficulty_settings_miniboss

	stage_event_pointers JessieJames
	stage_event_records  JessieJames, POOL_JESSIE_JAMES, 0

	stage_event_pointers Psychic
	stage_event_records  Psychic, POOL_PSYCHIC, 0

	stage_event_pointers Burglar
	stage_event_records  Burglar, POOL_BURGLAR, 0

	stage_event_pointers NurseJoy
	stage_event_records  NurseJoy, POOL_JOY, 0

	stage_event_pointers OfficerJenny
	stage_event_records  OfficerJenny, POOL_JENNY, 0
