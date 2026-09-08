; Bridge effects added after the original rogue section approached capacity.
; Every public entry is a farcall-safe leaf or restores the caller-visible
; result through de, the established Bankswitch-preserved register pair.

; In/out: e = an ordinary major-status side-effect threshold.
; Spiked Drink increases player-inflicted status chances by 20 percent
; relatively, saturating at $ff.
BridgeAdjustStatusChanceThreshold::
	ldh a, [hWhoseTurn]
	and a
	ret nz
	push de
	ld e, BRIDGE_EFFECT_STATUS_CHANCE
	farcall BridgeHasGlobalEffect
	pop de
	ret nc
	ld a, 6
	ldh [hMultiplier], a
	xor a
	ldh [hMultiplicand], a
	ldh [hMultiplicand + 1], a
	ld a, e
	ldh [hMultiplicand + 2], a
	call Multiply
	ld a, 5
	ldh [hDivisor], a
	ld b, 4
	call Divide
	ldh a, [hQuotient + 2]
	and a
	jr nz, .cap
	ldh a, [hQuotient + 3]
	ld e, a
.done
	ret
.cap
	ld e, $ff
	jr .done

; Apply poison to the current target. Direct Toxic and the player's Deadly
; Venom gift produce bad poison; enemy ordinary poison remains unchanged.
; Out: e = 1 for bad poison, 0 for ordinary poison.
BridgeInflictPoisonStatus::
	ldh a, [hWhoseTurn]
	and a
	jr nz, .enemy
	ld hl, wEnemyMonStatus
	set PSN, [hl]
	ld a, [wPlayerMoveNum]
	cp TOXIC
	jr z, .playerToxic
	ld e, BRIDGE_EFFECT_TOXIC_POISON
	farcall BridgeHasGlobalEffect
	jr nc, .ordinary
.playerToxic
	ld hl, wEnemyBattleStatus3
	ld de, wEnemyToxicCounter
	jr .toxic
.enemy
	ld hl, wBattleMonStatus
	set PSN, [hl]
	ld a, [wEnemyMoveNum]
	cp TOXIC
	jr nz, .ordinary
	ld hl, wPlayerBattleStatus3
	ld de, wPlayerToxicCounter
.toxic
	set BADLY_POISONED, [hl]
	xor a
	ld [de], a
	inc a
	ld e, a
	ret
.ordinary
	xor a
	ld e, a
	ret
