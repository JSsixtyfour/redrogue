ParalyzeEffect_:
	ld hl, wEnemyMonStatus
	ld de, wPlayerMoveType
	ldh a, [hWhoseTurn]
	and a
	jp z, .next
	ld hl, wBattleMonStatus
	ld de, wEnemyMoveType
.next
	ld a, [hl]
	and a ; does the target already have a status ailment?
	jr nz, .didntAffect
; AI Overhaul Phase 2a companion fix: Thunder Wave (PARALYZE_EFFECT) is the
; only status-inflicting effect left that did not respect a Substitute -
; FreezeBurnParalyzeEffect (the side-effect version attached to Body Slam
; etc.) already checks it a few lines away in effects.asm, but this dedicated
; 100%-chance handler never did. Same hole shape as the sleep/leech-seed
; fixes already closed in Shin Red import Phase 4; closed the same way.
; callfar because this file assembles into "Battle Engine 8", a different
; bank from CheckTargetSubstitute. Flags survive the far call untouched (the
; bank-restore cleanup in Bankswitch uses only ld/ldh, which do not affect
; flags), so the jr nz below sees CheckTargetSubstitute's own result.
	callfar CheckTargetSubstitute
	jr nz, .didntAffect
; check if the target is immune due to types
	ld a, [de]
	cp ELECTRIC
	jr nz, .hitTest
	ld b, h
	ld c, l
	inc bc
	ld a, [bc]
	cp GROUND
	jr z, .doesntAffect
	inc bc
	ld a, [bc]
	cp GROUND
	jr z, .doesntAffect
.hitTest
	push hl
	callfar MoveHitTest
	pop hl
	ld a, [wMoveMissed]
	and a
	jr nz, .didntAffect
	set PAR, [hl]
	callfar QuarterSpeedDueToParalysis
	ld c, 30
	call DelayFrames
	callfar PlayCurrentMoveAnimation
	jpfar PrintMayNotAttackText
.didntAffect
	ld c, 50
	call DelayFrames
	jpfar PrintDidntAffectText
.doesntAffect
	ld c, 50
	call DelayFrames
	jpfar PrintDoesntAffectText
