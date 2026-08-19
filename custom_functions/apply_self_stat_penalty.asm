; Shin Red import Phase 4 (4.7). Declares its own floating SECTION - the
; "Battle Core" section (engine/battle/core.asm + engine/battle/effects.asm)
; had no room left for this logic inline. Reached by farcall from
; StatModifierUpEffect's .applyBadgeBoostsAndStatusPenalties
; (engine/battle/effects.asm).

SECTION "Self-Target Stat Penalty", ROMX

; Stat-ups are always self-targeted in Gen 1, but
; QuarterSpeedDueToParalysis/HalveAttackDueToBurn (engine/battle/core.asm)
; both apply their penalty to the OPPONENT of whoever's turn it is.
; Unconditionally calling both (the old behavior) hit the wrong side and
; applied both penalties regardless of which stat actually rose - e.g. a
; paralyzed mon using Agility re-applied its own speed cut to its opponent
; instead of itself. Invert hWhoseTurn so the penalty function lands on the
; self, and dispatch on the move effect so only the matching stat's penalty
; runs. Farcalls back into "Battle Core" for the penalty functions
; themselves, since this routine lives in a different bank from them.
;
; Clobbers af, de. Caller (in "Battle Core") preserves de around the farcall.
ApplySelfTargetStatPenalty::
	ld de, wPlayerMoveEffect
	ldh a, [hWhoseTurn]
	and a
	jr z, .selfTargetEffect
	ld de, wEnemyMoveEffect
.selfTargetEffect
	ldh a, [hWhoseTurn]
	xor 1
	ldh [hWhoseTurn], a
	ld a, [de]
	cp ATTACK_UP1_EFFECT
	jr z, .selfBurnPenalty
	cp ATTACK_UP2_EFFECT
	jr z, .selfBurnPenalty
	cp SPEED_UP1_EFFECT
	jr z, .selfParPenalty
	cp SPEED_UP2_EFFECT
	jr z, .selfParPenalty
	jr .selfPenaltyDone
.selfBurnPenalty
	farcall HalveAttackDueToBurn
	jr .selfPenaltyDone
.selfParPenalty
	farcall QuarterSpeedDueToParalysis
.selfPenaltyDone
	ldh a, [hWhoseTurn]
	xor 1
	ldh [hWhoseTurn], a
	ret
