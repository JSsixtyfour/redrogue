; Per-move power grading for the party spec system's randomizers (Phase 2).
;
; ⚠ PROVISIONAL DATA, FINAL INTERFACE. The rank bytes below are a uniform
; placeholder; the OFF-LIST exclusions are real and final. Everything that reads
; this table reads it through RogueGetMoveRank, so replacing the data does not
; touch a line of engine code.
;
; The real grading is generated, one-shot and committed, by
; tools/reorder_move_ranks.py from
;   Red Rogue Files/red_rogue_comprehensive_package_v3_1_2026-09-08_FIXED/
;     00_CURRENT/red_rogue_gen1_move_rankings_v3_1_runtime_CORRECTED.asm
; which also carries the 16-bit MOVEFLAG_* mask per move. That file has one
; load-bearing defect the generator MUST fix first: despite its own header
; calling the table "Move-ID-indexed", its 167 rows are sorted by RANK
; DESCENDING, not by move id - row 1 is SUPER_TRANSFORM where move id 1 is
; POUND. Indexed by move id it would return a wrong-but-plausible rank for
; essentially every move, and it would assemble cleanly and run. That is exactly
; this repo's documented "table whose count assert passes while its rows are
; misaligned" failure mode. Every row carries its move name in a comment, so the
; fix is mechanical: parse (name, rank, flags), map name to id via
; constants/move_constants.asm, re-emit in id order, assert a dense range.
;
; Two name fixes belong in the same pass, the only two of the 167 that do not
; exist in this tree:
;   PSYCHIC -> PSYCHIC_M ($5E). PSYCHIC is not a move constant here;
;     PSYCHIC_TYPE is the type.
;   DELETE the ROAR row. Slot $2E was repurposed as SUPER_TRANSFORM
;     (constants/move_constants.asm:54), which the table already lists
;     separately. Keeping both would double-count one id.
; That leaves exactly NUM_ATTACKS + 1 rows.

; Moves excluded from EVERY randomizer pool, permanently and regardless of the
; grading data. This part is NOT provisional: a candidate whose rank reads
; MOVE_RANK_OFFLIST is skipped before it is ever weighted, so none of these can
; be selected. Without it a rank-weighted roll would happily hand a gym leader
; Splash, or Whirlwind (which does nothing to a trainer's mon in Gen 1), or
; Teleport (which fails in a trainer battle), or STRUGGLE.
DEF MOVE_RANK_DEFAULT EQU MOVE_RANK_C

MoveRankByID::
	table_width 1, MoveRankByID
FOR n, 0, NUM_ATTACKS + 1
	IF n == NO_MOVE || n == SPLASH || n == STRUGGLE || \
	   n == SUPER_TRANSFORM || n == TELEPORT || n == WHIRLWIND
	db MOVE_RANK_OFFLIST
	ELSE
	db MOVE_RANK_DEFAULT
	ENDC
ENDR
	assert_table_length NUM_ATTACKS + 1

; Selection weight per (difficulty row, move rank), as an ACCEPTANCE CHANCE OUT
; OF 64. The randomizer picks a candidate uniformly and then accepts it with
; this chance, retrying on rejection (see PartyGenWeightedPick). That is why the
; scale is out of 64 rather than a share of a total: rejection sampling is
; unbiased and needs only 8-bit maths, whereas summing weights over a ~70
; candidate pool would overflow a byte and force 16-bit accumulation plus a
; 16-bit modulo.
;
; Every row must contain at least one 64, or acceptance gets slow for a species
; whose whole candidate pool sits in a low-weight rank. A 0 makes that rank
; unreachable for that row.
;
; MOVE_RANK_OFFLIST is 0 in every row, which is belt and braces: the candidate
; filter already drops off-list moves before this table is consulted.
;
; The rows are provisional in the same sense as the ranks above - the shape
; Phase 5 tunes, not tuned values. They are deliberately NOT uniform, so a wrong
; row assignment shows up as a visible difficulty difference rather than as
; nothing at all.
MoveRankWeightTable::
	table_width NUM_MOVE_RANKS, MoveRankWeightTable
	;   F   D   C   B   A   S  off
	db 64, 48, 24,  8,  2,  1,  0 ; RANK_ROW_BAD
	db 48, 64, 40, 16,  6,  2,  0 ; RANK_ROW_EASY
	db 16, 32, 64, 48, 24, 10,  0 ; RANK_ROW_NORMAL
	db  6, 16, 40, 64, 56, 32,  0 ; RANK_ROW_HARD
	db  1,  4, 16, 40, 64, 64,  0 ; RANK_ROW_ELITE
	assert_table_length NUM_RANK_ROWS

; TM/HM move ids, indexed by wMonHLearnset bit position: bit i of that bitfield
; means "can learn TMMovesForPartyGen[i]" (the convention CanLearnTM establishes
; in engine/items/tms.asm, where the same counter indexes both).
;
; This is a SECOND emission of the same data as TechnicalMachines
; (data/moves/tmhm_moves.asm), which lives in bank $04. RogueBuildParty consults
; it once per TM candidate per rejection-sampling draw - hundreds of times per
; party - so a farcall per lookup was not viable, and 55 bytes in a bank with
; 12 KB free is the cheaper answer.
;
; It is NOT a maintenance hazard, because neither copy is hand-written: both are
; FOR loops over the same TM{02d:n}_MOVE constants from
; constants/item_constants.asm, which remains the single source of truth. Adding
; a TM there updates both. The ASSERT below fails the build if the two ever
; disagree in length.
TMMovesForPartyGen::
	table_width 1, TMMovesForPartyGen
FOR n, 1, NUM_TMS + 1
	db TM{02d:n}_MOVE
ENDR
FOR n, 1, NUM_HMS + 1
	db HM{02d:n}_MOVE
ENDR
	assert_table_length NUM_TM_HM
; Both this table and TechnicalMachines carry `assert_table_length NUM_TM_HM`,
; so a TM added to constants/item_constants.asm without regenerating one of them
; fails the build rather than desynchronising the two silently.
