DisplayEffectiveness:
; Multi-hit moves print this once, on the first hit (ShinRed's behaviour).
; TwoToFiveAttacksEffect sets ATTACKING_MULTIPLE_TIMES from
; AlwaysHappenSideEffects, which runs AFTER this call, so the bit is still
; clear on the first hit and set on every later one. Both faint paths clear it,
; so it can't carry over into the next move.
	ld hl, wPlayerBattleStatus1
	ldh a, [hWhoseTurn]
	and a
	jr z, .gotAttackerStatus
	ld hl, wEnemyBattleStatus1
.gotAttackerStatus
	bit ATTACKING_MULTIPLE_TIMES, [hl]
	nop ; CONTROL
	ld a, [wDamageMultipliers]
	and $7F
	cp EFFECTIVE
	ret z
	ld hl, SuperEffectiveText
	jr nc, .done
	ld hl, NotVeryEffectiveText
.done
	jp PrintText

SuperEffectiveText:
	text_far _SuperEffectiveText
	text_end

NotVeryEffectiveText:
	text_far _NotVeryEffectiveText
	text_end
