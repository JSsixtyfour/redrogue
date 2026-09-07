; Run-global bridge effect storage interface.
;
; Public routines accept a BRIDGE_EFFECT_* index in e so callers may use
; farcall without losing the argument to Bankswitch. Both routines clobber
; af, bc, de, and hl. BridgeHasGlobalEffect returns carry set when owned.

BridgeGrantGlobalEffect::
	ld a, e
	cp NUM_BRIDGE_GLOBAL_EFFECTS
	ret nc
	call BridgeGlobalEffectAddressAndMask
	ld a, [hl]
	or d
	ld [hl], a

	; The witch expansion already owns the generalized 1.125x stat path.
	; Mirror the three bridge stat rewards into that field instead of creating
	; a second battle arithmetic implementation.
	ld a, e
	cp BRIDGE_EFFECT_ATTACK_BOOST
	jr z, .attack
	cp BRIDGE_EFFECT_DEFENSE_BOOST
	jr z, .defense
	cp BRIDGE_EFFECT_SPEED_BOOST
	ret nz
	ld hl, wEarnedStatBoosts
	set BIT_STAT_BOOST_SPEED, [hl]
	ret
.defense
	ld hl, wEarnedStatBoosts
	set BIT_STAT_BOOST_DEFENSE, [hl]
	ret
.attack
	ld hl, wEarnedStatBoosts
	set BIT_STAT_BOOST_ATTACK, [hl]
	ret

BridgeHasGlobalEffect::
	ld a, e
	cp NUM_BRIDGE_GLOBAL_EFFECTS
	ret nc
	call BridgeGlobalEffectAddressAndMask
	ld a, [hl]
	and d
	ret z
	scf
	ret

; e = BRIDGE_EFFECT_* index
; Returns hl = owning byte, d = bit mask. Preserves e.
BridgeGlobalEffectAddressAndMask:
	ld a, e
	and 7
	ld c, a
	ld d, 1
	jr z, .haveMask
.shiftMask
	sla d
	dec c
	jr nz, .shiftMask
.haveMask
	ld a, e
	srl a
	srl a
	srl a
	ld c, a
	ld b, 0
	ld hl, wBridgeGlobalEffects
	add hl, bc
	ret

; Far worker for the bridge menu's level-resolved Pokemon gifts.
; In: e = base species. Out: e = resolved species.
BridgeResolveEvolveSpeciesFar::
	ld d, e
	ld a, [wCurPartySpecies]
	push af
	push de
	farcall GetBridgeRewardMonLevelFar
	ld a, e
	ld [wCurEnemyLevel], a
	pop de
	ld a, d
	ld [wCurPartySpecies], a
	call EvolveMonByLevel
	ld a, [wCurPartySpecies]
	ld e, a
	pop af
	ld [wCurPartySpecies], a
	ret

; Far worker for party gift stat recalculation.
; In: de = party struct base. Recomputes stats and refills HP.
BridgeRecalcStatsFar::
	ld h, d
	ld l, e
	push hl
	ld a, [hl]
	ld [wCurSpecies], a
	call GetMonHeader
	pop hl
	push hl
	ld bc, MON_LEVEL
	add hl, bc
	ld a, [hl]
	ld [wCurEnemyLevel], a
	pop hl
	push hl
	ld bc, MON_STATS
	add hl, bc
	ld d, h
	ld e, l
	pop hl
	push hl
	ld bc, MON_HP_EXP - 1
	add hl, bc
	ld b, 1
	push bc
	push hl
	call PrepareFusionCalcStats
	pop hl
	pop bc
	call CalcStats
	pop hl
	push hl
	ld bc, MON_STATS
	add hl, bc
	ld a, [hli]
	ld b, a
	ld c, [hl]
	pop hl
	ld de, MON_HP
	add hl, de
	ld [hl], b
	inc hl
	ld [hl], c
	ret
