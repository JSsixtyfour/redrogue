SubstituteEffect_:
	ld c, 50
	call DelayFrames
	ld hl, wBattleMonMaxHP
	ld de, wPlayerSubstituteHP
	ld bc, wPlayerBattleStatus2
	ldh a, [hWhoseTurn]
	and a
	jr z, .notEnemy
	ld hl, wEnemyMonMaxHP
	ld de, wEnemySubstituteHP
	ld bc, wEnemyBattleStatus2
.notEnemy
	ld a, [bc]
	bit HAS_SUBSTITUTE_UP, a ; user already has substitute?
	jr nz, .alreadyHasSubstitute
; quarter health to remove from user
; assumes max HP is 1023 or lower
	push bc
	ld a, [hli]
	ld b, [hl]
	srl a
	rr b
	srl a
	rr b ; max hp / 4
	push de
	ld de, wBattleMonHP - wBattleMonMaxHP
	add hl, de ; point hl to current HP low byte
	pop de
	ld a, b
	ld [de], a ; save copy of HP to subtract in wPlayerSubstituteHP/wEnemySubstituteHP
	ld a, [hld]
; subtract [max hp / 4] to current HP
	sub b
	ld d, a
	ld a, [hl]
	sbc 0
	pop bc
	jr c, .notEnoughHP ; underflow means user would be left with negative health
	; Shin Red import Phase 4 (4.10): also fail if the result is exactly 0 HP,
	; not just negative. shinpokered's own fix here (inc d / dec d / jr z) is wrong
	; - it tests only d, the LOW byte, so it misfires whenever the result is
	; exactly 256, 512 or 768 HP (any mon with maxHP >= 342). e is provably dead
	; here - its last use was addressing wPlayerSubstituteHP/wEnemySubstituteHP
	; above, which already completed - so it is free to hold the high byte while
	; both bytes are ORed together.
	ld e, a
	or d
	ld a, e
	jr z, .notEnoughHP
; user has 0 or more HP
	ld [hli], a ; save resulting HP after subtraction into current HP
	ld [hl], d
	ld h, b
	ld l, c
	set HAS_SUBSTITUTE_UP, [hl]
	ld a, [wOptions]
	bit BIT_BATTLE_ANIMATION, a
	ld hl, PlayCurrentMoveAnimation
	ld b, BANK(PlayCurrentMoveAnimation)
	jr z, .animationEnabled
	ld hl, AnimationSubstitute
	ld b, BANK(AnimationSubstitute)
.animationEnabled
	call Bankswitch ; jump to routine depending on animation setting
	ld hl, SubstituteText
	call PrintText
	jpfar DrawHUDsAndHPBars
.alreadyHasSubstitute
	ld hl, HasSubstituteText
	jr .printText
.notEnoughHP
	ld hl, TooWeakSubstituteText
.printText
	jp PrintText

SubstituteText:
	text_far _SubstituteText
	text_end

HasSubstituteText:
	text_far _HasSubstituteText
	text_end

TooWeakSubstituteText:
	text_far _TooWeakSubstituteText
	text_end
