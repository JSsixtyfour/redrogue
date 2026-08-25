; Shared AI predicates (AI_OVERHAUL_PLAN.md Phase 2b): the HP-tier vocabulary
; that most AI_SMART heuristics are expressed in, plus the repeated-move
; tracking those heuristics read.
;
; INCLUDEd into "Battle Engine 7" (bank $0E), the same bank as trainer_ai.asm
; and every AILayer* routine. This is mandatory, not stylistic: the layer
; dispatch reaches layers with a plain same-bank `jp hl`, so everything a layer
; calls in a hot path must be co-located. See ai_score_helpers.asm's header and
; ROM_BIBLE.md's 2026-08-25 entry for the full reasoning and the bugs that
; came from getting this wrong in Phase 2a.
;
; WHY THESE EXIST: pokecrystal expresses roughly thirty AI_SMART handlers in
; about six lines each, and the reason it can is that "am I below half HP" is
; one call rather than an open-coded 16-bit compare every time. Porting the
; handlers without porting this vocabulary first would mean thirty
; opportunities to get a 16-bit comparison subtly wrong.
;
; All six are integer-only: they compare (currentHP << n) against maxHP rather
; than dividing maxHP, so there is no division, no rounding, and no dependence
; on hDivisor/hQuotient (which other battle code uses and which the existing
; AICheckIfHPBelowFraction does clobber).

; Core comparison. Not called directly by heuristics; use the named wrappers.
; INPUT:  hl = pointer to current HP (big-endian dw)
;         de = pointer to max HP (big-endian dw)
;         b  = number of times to double current HP before comparing (0/1/2)
; OUTPUT: carry SET if (currentHP << b) < maxHP
; Clobbers af, bc, de, hl.
AIHPShiftCompare:
	ld a, [hli]
	ld c, [hl]
	ld h, a
	ld l, c ; hl = current HP
	inc b   ; so the loop below handles a shift count of 0 correctly
.shiftLoop
	dec b
	jr z, .compare
	add hl, hl
	jr nc, .shiftLoop
; Overflowed 16 bits. Max HP is capped at 999 by the stat system, so a value
; that has already exceeded 65535 is unambiguously greater - report "not less"
; without touching memory further.
	and a
	ret
.compare
	ld a, [de]
	inc de
	ld b, a
	ld a, [de]
	ld c, a ; bc = max HP
	ld a, l
	sub c
	ld a, h
	sbc b   ; carry set iff hl < bc
	ret

; --- Enemy side (the AI's own mon) ---

; Carry set if the enemy is at full HP.
; Current HP can never exceed max, so "not less than max" is exactly "at max".
AIEnemyHPAtMax::
	ld hl, wEnemyMonHP
	ld de, wEnemyMonMaxHP
	ld b, 0
	call AIHPShiftCompare
	ccf
	ret

; Carry set if the enemy is strictly below half HP.
AIEnemyHPBelowHalf::
	ld hl, wEnemyMonHP
	ld de, wEnemyMonMaxHP
	ld b, 1
	jp AIHPShiftCompare

; Carry set if the enemy is strictly below a quarter HP.
AIEnemyHPBelowQuarter::
	ld hl, wEnemyMonHP
	ld de, wEnemyMonMaxHP
	ld b, 2
	jp AIHPShiftCompare

; --- Player side (the AI's target) ---
; These read wBattleMon* directly rather than going through the ai_core.asm
; accessor seam, because HP is not part of the information model the seam
; hides: Phase 7 limits what the AI knows about the player's MOVES and
; status/type, not their visible HP bar, which is on screen either way.

; Carry set if the player is at full HP.
AIPlayerHPAtMax::
	ld hl, wBattleMonHP
	ld de, wBattleMonMaxHP
	ld b, 0
	call AIHPShiftCompare
	ccf
	ret

; Carry set if the player is strictly below half HP.
AIPlayerHPBelowHalf::
	ld hl, wBattleMonHP
	ld de, wBattleMonMaxHP
	ld b, 1
	jp AIHPShiftCompare

; Carry set if the player is strictly below a quarter HP.
AIPlayerHPBelowQuarter::
	ld hl, wBattleMonHP
	ld de, wBattleMonMaxHP
	ld b, 2
	jp AIHPShiftCompare

; --- Repeated-move / anti-spam tracking -----------------------------------
; Maintains wAILastMovePower, wAILastMoveNum and wAISameMoveCount, which Phase 1
; allocated but nothing wrote. Called once per AI decision, from the top of
; AIEnemyTrainerChooseMoves, BEFORE any ReadMove call in the scoring layers.
;
; That ordering is the whole trick and is why this needs no core.asm edit:
;   - wEnemyMovePower still holds the power of the move the enemy executed LAST
;     turn, because ReadMove (which overwrites the wEnemyMove* block) has not
;     run yet this cycle. This is ShinRed's technique, verbatim.
;   - wEnemySelectedMove likewise still holds LAST turn's selection, because
;     SelectEnemyMove only writes it at its `.done` label, after this routine
;     has already returned (verified: engine/battle/core.asm, `.done` /
;     `ld [wEnemySelectedMove], a` sits below the AI call site).
;
; Consumed by AI_SMART: wAILastMovePower drives anti-spam (do not follow a
; 0-power move with another 0-power move), and wAISameMoveCount drives
; repeated-move fatigue (ExtremeYellow's idea: discourage a move only after it
; has already been used several times in a row, so ordinary sensible repetition
; is not punished).
;
; Clobbers af, hl.
AITrackLastMove::
	ld a, [wEnemyMovePower]
	ld [wAILastMovePower], a

	ld a, [wEnemySelectedMove]
	ld hl, wAILastMoveNum
	cp [hl]
	jr nz, .differentMove
; Same move as last turn: bump the streak, saturating so it cannot wrap around
; to zero during a very long stall and silently cancel the fatigue penalty.
	ld a, [wAISameMoveCount]
	cp $ff
	jr z, .done
	inc a
	ld [wAISameMoveCount], a
	ret
.differentMove
	ld [hl], a ; remember the new move
	xor a
	ld [wAISameMoveCount], a
.done
	ret
