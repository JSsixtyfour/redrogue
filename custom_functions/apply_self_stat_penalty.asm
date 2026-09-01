; Shin Red import Phase 4 (4.7). Declares its own floating SECTION - the
; "Battle Core" section (engine/battle/core.asm + engine/battle/effects.asm)
; had no room left for this logic inline. Reached by farcall from
; StatModifierUpEffect's .applyBadgeBoostsAndStatusPenalties
; (engine/battle/effects.asm).
;
; 2026-09-01: now holds BOTH directions. The section name predates
; ApplyTargetStatPenalty at the bottom of this file, which serves the stat-DOWN
; path (AI Overhaul follow-up F4) and is not self-targeted. Kept as-is because
; ROM_BIBLE.md's 2026-08-26 floater-churn entry names this section by name.

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

; AI Overhaul follow-up F4, 2026-09-01. The stat-DOWN counterpart of
; ApplySelfTargetStatPenalty above, reached by jpfar from StatModifierDownEffect's
; .ApplyBadgeBoostsAndStatusPenalties (engine/battle/effects.asm) - see the long
; comment at that call site for the bug this fixes.
;
; Two deliberate differences from the routine above, both consequences of
; direction rather than style:
;   1. hWhoseTurn is NOT inverted. Gen 1 stat-down moves target the opponent,
;      and QuarterSpeedDueToParalysis/HalveAttackDueToBurn already act on "the
;      opponent of whoever's turn it is", so the default is already correct.
;   2. The _SIDE_EFFECT variants are included. There is no stat-up side effect
;      in Gen 1, but Aurora Beam, Acid, Bubble/Constrict and Psychic all lower a
;      stat as a rider and reach the same UpdateLoweredStat path.
;
; Everything not listed leaves both penalties alone, which is the whole point:
; re-dividing a stat that was never recalculated is what the bug was.
; Clobbers af, de.
ApplyTargetStatPenalty::
	ld de, wPlayerMoveEffect
	ldh a, [hWhoseTurn]
	and a
	jr z, .gotEffect
	ld de, wEnemyMoveEffect
.gotEffect
	ld a, [de]
	cp ATTACK_DOWN1_EFFECT
	jr z, .burnPenalty
	cp ATTACK_DOWN2_EFFECT
	jr z, .burnPenalty
	cp ATTACK_DOWN_SIDE_EFFECT
	jr z, .burnPenalty
	cp SPEED_DOWN1_EFFECT
	jr z, .parPenalty
	cp SPEED_DOWN2_EFFECT
	jr z, .parPenalty
	cp SPEED_DOWN_SIDE_EFFECT
	jr z, .parPenalty
	ret
.burnPenalty
	farcall HalveAttackDueToBurn
	ret
.parPenalty
	farcall QuarterSpeedDueToParalysis
	ret
