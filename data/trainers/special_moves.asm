; Fixed moves for one specific team: ReadTrainer applies this table after every
; team path (party specs and rosters included), so a row overwrites whatever
; moves that team rolled. It checks nothing, so a row can duplicate a move the
; mon already knows or give it one it cannot learn. Use it only on a team whose
; species are fixed: the wTrainerNo it is keyed on does not fix them for a pool.
;
; A gym leader's wTrainerNo is (round - 1) * 3 + 1 + variant (InitGymBattle), and
; a stage event's is its round tier (StageEventRoundTier).
;
; Entry format:
;	db trainerclass, trainerid
;	repeat { db partymon location, partymon move, move id } ; both 1-based
;	db 0
;
; Example:
;	db BROCK, 1
;	db 2, 3, BIDE ; second mon's third move
;	db 0
;
; The table is empty: every vanilla and Yellow Legacy row was removed 2026-11-04
; (SPECIAL_TRAINER_MOVES_AUDIT_2026-11-04.md), since they all landed on rolled
; teams. New rows go above the terminator.

SpecialTrainerMoves:
	db -1 ; end
