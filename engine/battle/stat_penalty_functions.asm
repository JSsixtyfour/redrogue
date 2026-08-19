; does nothing since no stats are ever selected (barring glitches)
DoubleSelectedStats::
	ldh a, [hWhoseTurn]
	and a
	ld a, [wPlayerStatsToDouble]
	ld hl, wBattleMonAttack + 1
	jr z, .notEnemyTurn
	ld a, [wEnemyStatsToDouble]
	ld hl, wEnemyMonAttack + 1
.notEnemyTurn
	ld c, 4
	ld b, a
.loop
	srl b
	call c, .doubleStat
	inc hl
	inc hl
	dec c
	ret z
	jr .loop

.doubleStat
	ld a, [hl]
	add a
	ld [hld], a
	ld a, [hl]
	rl a
	ld [hli], a
	ret

; does nothing since no stats are ever selected (barring glitches)
HalveSelectedStats:
	ldh a, [hWhoseTurn]
	and a
	ld a, [wPlayerStatsToHalve]
	ld hl, wBattleMonAttack
	jr z, .notEnemyTurn
	ld a, [wEnemyStatsToHalve]
	ld hl, wEnemyMonAttack
.notEnemyTurn
	ld c, 4
	ld b, a
.loop
	srl b
	call c, .halveStat
	inc hl
	inc hl
	dec c
	ret z
	jr .loop

.halveStat
	ld a, [hl]
	srl a
	ld [hli], a
	rr [hl]
	or [hl]
	jr nz, .nonzeroStat
	ld [hl], 1
.nonzeroStat
	dec hl
	ret

; Shin Red import Phase 5: shared helper that reverses the burn/paralysis stat
; penalty applied by HalveAttackDueToBurn / QuarterSpeedDueToParalysis
; (engine/battle/core.asm) before a status-curing item clears the ailment.
; Must be called BEFORE the caller clears wBattleMonStatus/wEnemyMonStatus -
; this reads that byte to decide what (if anything) to undo. Accurate to
; within the same rounding slack as the halving it reverses (0 to -1 on burn,
; 0 to -3 on paralysis, since a quartered odd value can't round back exactly).
; Callers must force hWhoseTurn to whichever side owns the mon being cured -
; this only ever targets one side's active mon, never "whoever's turn it is".
UndoBurnParStats::
	ldh a, [hWhoseTurn]
	and a
	ld hl, wBattleMonStatus
	ld de, wPlayerStatsToDouble
	jr z, .checkBurn
	ld hl, wEnemyMonStatus
	ld de, wEnemyStatsToDouble
.checkBurn
	ld a, [hl]
	and 1 << BRN
	jr z, .checkParalysis
	ld a, %0001 ; attack is the 1st of the 4 selectable stats (bit 0)
	ld [de], a
	call DoubleSelectedStats
	jr .done
.checkParalysis
	ld a, [hl]
	and 1 << PAR
	jr z, .done
	ld a, %0100 ; speed is the 3rd of the 4 selectable stats (bit 2)
	ld [de], a
	call DoubleSelectedStats
	call DoubleSelectedStats ; twice: paralysis quarters speed, burn only halves attack
.done
	xor a
	ld [de], a ; reset the stat-select bits
	ret

; Thin wrappers so item_effects.asm's two call sites (both of which always
; target the player's own active mon, regardless of whose turn it actually
; is) don't each need to save/force/restore hWhoseTurn inline - that
; boilerplate is cheap here but "bank3" (item_effects.asm) has no slack for
; it duplicated twice. AICureStatus in trainer_ai.asm has its own equivalent
; below for the enemy side.
UndoBurnParStatsForPlayer::
	ldh a, [hWhoseTurn]
	push af
	xor a
	ldh [hWhoseTurn], a
	call UndoBurnParStats
	pop af
	ldh [hWhoseTurn], a
	ret

UndoBurnParStatsForEnemy::
	ldh a, [hWhoseTurn]
	push af
	ld a, 1
	ldh [hWhoseTurn], a
	call UndoBurnParStats
	pop af
	ldh [hWhoseTurn], a
	ret
