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

; In: e = BRIDGE_STATUS_CHECK_*. Carry is set when the status attempt on the
; defending mon must be blocked. Bridge selected effects only guard the player's
; mon (enemy turn). PARALYSIS also checks the SF2_NO_PARALYSIS special form
; (Limber Hitmonlee) on whichever side is defending: enemies carry special
; forms too (GetEnemyCatchRateByte).
BridgePlayerTargetBlocksStatus::
	ld d, e
	ld a, [wLinkState]
	cp LINK_STATE_BATTLING
	jr z, .allowed
	ldh a, [hWhoseTurn]
	and a
	jr z, .playerAttacking
	push de
	ld e, BRIDGE_SELECTED_EFFECT_STATUS_IMMUNITY
	farcall BridgeActiveMonHasSelectedEffect
	pop de
	jr c, .blocked
	ld a, d
	cp BRIDGE_STATUS_CHECK_PARALYSIS
	jr z, .paralysis
	and a
	jr nz, .allowed
	ld e, BRIDGE_SELECTED_EFFECT_POISON_IMMUNITY
	farcall BridgeActiveMonHasSelectedEffect
	jr c, .blocked
	jr .allowed
.playerAttacking
	ld a, d
	cp BRIDGE_STATUS_CHECK_PARALYSIS
	jr nz, .allowed
	ld de, wEnemyMon
	jr .checkLimber
.paralysis
	; Limber (Karate Dojo Hitmonlee): a special form, not a selected effect
	ld de, wBattleMon
.checkLimber
	farcall GetSpecialFormCaps2   ; e = SF2_* caps
	bit SF2_NO_PARALYSIS, e
	jr nz, .blocked
.allowed
	and a
	ret
.blocked
	scf
	ret

; Rest targets its user rather than the opposing mon, so it needs a separate
; player-side predicate from BridgePlayerTargetBlocksStatus.
BridgePlayerRestIsBlocked::
	ldh a, [hWhoseTurn]
	and a
	ret nz
	ld a, [wLinkState]
	cp LINK_STATE_BATTLING
	jr z, .allowed
	ld e, BRIDGE_SELECTED_EFFECT_STATUS_IMMUNITY
	farcall BridgeActiveMonHasSelectedEffect
	ret
.allowed
	and a
	ret

; In/out: de = healing amount. Nurturing Care applies to player healing moves,
; recovery items, draining, and Leech Seed, but not full-party service healing.
BridgeScalePlayerHealingMoveAmount::
	ldh a, [hWhoseTurn]
	and a
	ret nz
BridgeScaleGeneralHealingAmount::
	ld a, [wBridgeGlobalEffects + (BRIDGE_EFFECT_HEALING / 8)]
	bit BRIDGE_EFFECT_HEALING % 8, a
	ret z
	ld a, 110
	jr BridgeScaleHealingDE

; In/out: de = drain/Leech Seed healing amount. Verdant Drain and Nurturing
; Care stack multiplicatively in that order.
BridgeScaleDrainHealingAmount::
	ld a, [wBridgeGlobalEffects + (BRIDGE_EFFECT_DRAINING / 8)]
	bit BRIDGE_EFFECT_DRAINING % 8, a
	jr z, .nurturing
	ld a, 130
	call BridgeScaleHealingDE
.nurturing
	jp BridgeScaleGeneralHealingAmount

; In: a = percentage multiplier, de = 16-bit amount. Out: de = scaled amount.
BridgeScaleHealingDE:
	ldh [hMultiplier], a
	xor a
	ldh [hMultiplicand], a
	ld a, d
	ldh [hMultiplicand + 1], a
	ld a, e
	ldh [hMultiplicand + 2], a
	call Multiply
	ld a, 100
	ldh [hDivisor], a
	ld b, 4
	call Divide
	ldh a, [hQuotient + 2]
	ld d, a
	ldh a, [hQuotient + 3]
	ld e, a
.done
	ret

; Adds Leech Seed's bc healing amount to the opposing battler. This complete
; routine moved out of Battle Core to make room for its bank-aware call seam.
; Its sole caller preserves the live victim-HP pointer around the farcall.
; In: de = healing amount. Bankswitch does not preserve bc.
HandlePoisonBurnLeechSeed_IncreaseEnemyHP::
	ldh a, [hWhoseTurn]
	and a
	jr z, .healAmountReady
	call BridgeScaleDrainHealingAmount
.healAmountReady
	ld b, d
	ld c, e
	ld hl, wEnemyMonMaxHP
	ldh a, [hWhoseTurn]
	and a
	jr z, .playersTurn
	ld hl, wBattleMonMaxHP
.playersTurn
	ld a, [hli]
	ld [wHPBarMaxHP + 1], a
	ld a, [hl]
	ld [wHPBarMaxHP], a
	ld de, wBattleMonHP - wBattleMonMaxHP
	add hl, de
	ld a, [hl]
	ld [wHPBarOldHP], a
	add c
	ld [hld], a
	ld [wHPBarNewHP], a
	ld a, [hl]
	ld [wHPBarOldHP + 1], a
	adc b
	ld [hli], a
	ld [wHPBarNewHP + 1], a
	ld a, [wHPBarMaxHP]
	ld c, a
	ld a, [hld]
	sub c
	ld a, [wHPBarMaxHP + 1]
	ld b, a
	ld a, [hl]
	sbc b
	jr c, .noOverfullHeal
	ld a, b
	ld [hli], a
	ld [wHPBarNewHP + 1], a
	ld a, c
	ld [hl], a
	ld [wHPBarNewHP], a
.noOverfullHeal
	ldh a, [hWhoseTurn]
	xor 1
	ldh [hWhoseTurn], a
	farcall UpdateCurMonHPBar
	ldh a, [hWhoseTurn]
	xor 1
	ldh [hWhoseTurn], a
	ret

; Mom's SECOND CHANCE restores KO Defiance's single charge, but only while
; that key item is in the active loadout and its charge has been spent.
BridgeMomSecondChanceFar::
	call BridgeMomSecondChanceEligibleFar
	ret nc
	ld a, 1
	ld [wKODefianceUsages], a
	scf
	ret

; Out: carry set only when KO Defiance is active and has zero charges.
; Preserve wCurItem because it aliases wCurPartySpecies.
BridgeMomSecondChanceEligibleFar::
	ld a, [wKODefianceUsages]
	and a
	ret nz
	ld a, [wCurItem]
	push af
	ld a, KO_DEFIANCE
	ld [wCurItem], a
	farcall IsKeyItemActive
	jr z, .inactive
	pop af
	ld [wCurItem], a
	scf
	ret
.inactive
	pop af
	ld [wCurItem], a
	and a
	ret

; ---------------------------------------------------------------------------
; Enemy-side catch-rate flags. LoadEnemyMonData rebuilds a trainer mon from its
; species header and zeroes wEnemyMonCatchRate, so these two routines carry the
; party struct's whole flag byte across (ghost, fusion, type variant, special
; form, shiny, form). _AddPartyMon builds that byte from scratch, so it never
; holds a raw species catch rate. A ghost/type variant's type lives in the
; struct's own MON_TYPE2 and is copied over the header's type 2.
; Lives here, not beside GetSpecialFormCaps in "rogue": that bank is nearly
; full, and both routines are reached by farcall anyway.
; ---------------------------------------------------------------------------
	ASSERT MON_TYPE2 + 1 == MON_CATCH_RATE

; LoadEnemyMonData .copyTypes (TOUCH 2), after both types are written.
; OUTPUT: e = the byte to store at wEnemyMonCatchRate. For a variant, also
;         overwrites wEnemyMonType2 with the struct's stored type.
; CLOBBERS: af, bc, hl, e  (d preserved)
GetEnemyCatchRateByte::
	ldh a, [hIsInBattle]
	cp 2                   ; trainer battle?
	jr nz, .wild
	ld hl, wEnemyMon1CatchRate
	ldh a, [hWhichPokemon] ; not wEnemyMonPartyPos: see GetEnemySpawnForm
	ld bc, wEnemyMon2 - wEnemyMon1
	call AddNTimes
	ld a, [hl]
	ld e, a
	and (1 << BIT_GHOST_VARIANT) | (1 << BIT_TYPE_VARIANT)
	jr z, .done
	dec hl                 ; MON_TYPE2
	ld a, [hl]
	ld [wEnemyMonType2], a
	jr .done
.wild
	ld a, [wSpawnForm]     ; a wild mon has no struct: form only
	and NUM_FORM_SLOTS
	rrca                   ; 0-3 -> bits 5-6
	rrca
	rrca
	ld e, a
.done                      ; single exit (test_karate_dojo_forms hooks it)
	ret

; LoadEnemyMonData TOUCH 1: the usual form publish, then arm _CalcStats'
; Mystic swap from the trainer mon's party struct, for the CalcStats a few
; lines later in .calcEnemyStats (nothing between them runs CalcStats, and
; _CalcStats clears the flag byte when it finishes).
; CLOBBERS: all
PublishEnemyFormAndStatContext::
	farcall PublishEnemyFormContext
	ldh a, [hIsInBattle]
	cp 2
	ret nz
	ld hl, wEnemyMons
	ldh a, [hWhichPokemon]
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	ld d, h
	ld e, l
	farcall GetSpecialFormCaps2   ; e = SF2_* caps
	bit SF2_SWAP_ATK_SPC, e
	ret z
	ld hl, wBridgeCalcEffectFlags
	set BRIDGE_CALC_SWAP_ATK_SPC, [hl]
	ret
