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

; Apply the persistent attributes for a just-delivered level-resolved bridge
; Pokemon. In: e = BRIDGE_MON_FINALIZE_* id. GivePokemon front-inserts boxed
; gifts at wBoxMon1, while party gifts occupy the final party slot.
BridgeFinalizeGiftMonFar::
	ld b, e
	ld a, [wAddedToParty]
	and a
	jr z, .boxed
	ld a, [wPartyCount]
	dec a
	ld hl, wPartyMons
	ld de, PARTYMON_STRUCT_LENGTH
.partyLoop
	and a
	jr z, .haveStruct
	add hl, de
	dec a
	jr .partyLoop
.boxed
	ld hl, wBoxMon1
.haveStruct
	ld d, h
	ld e, l
	ld a, b
	and a
	ret z
	call ApplySpecialForm
	ld a, b
	cp BRIDGE_MON_FINALIZE_SPECIAL
	ret z
	cp BRIDGE_MON_FINALIZE_FARFETCHD
	jr z, .perfect
	cp BRIDGE_MON_FINALIZE_QUICK_CLAW
	ret z                         ; marker + species family supplies C6 behavior
	cp BRIDGE_MON_FINALIZE_INTIMIDATE
	jr z, .intimidate
	cp BRIDGE_MON_FINALIZE_SUPER_FANG
	ld a, SUPER_FANG
	jr z, .move
	ld a, b
	cp BRIDGE_MON_FINALIZE_SPORE
	ld a, SPORE
	jr z, .move
	ld a, b
	cp BRIDGE_MON_FINALIZE_EARTHQUAKE
	ld a, EARTHQUAKE
	jr z, .move
	ld a, b
	cp BRIDGE_MON_FINALIZE_AMNESIA
	ld a, AMNESIA
	jr z, .move
	; Dragon Charmander family: preserve Fire as type 1 and store Dragon as
	; type 2. BIT_TYPE_VARIANT gives the existing display/battle read paths a
	; persistent indication that the stored secondary type is intentional.
	ld hl, MON_CATCH_RATE
	add hl, de
	set BIT_TYPE_VARIANT, [hl]
	ld hl, MON_TYPE1
	add hl, de
	ld [hl], FIRE
	inc hl
	ld [hl], DRAGON
	ret

.intimidate
	call .perfectDVs
	call .maxStatExp
	ld a, QUICK_ATTACK
	call .replaceFirstMove
	jr .recalcIfParty
.perfect
	call .perfectDVs
.recalcIfParty
	ld a, [wAddedToParty]
	and a
	ret z
	jp BridgeRecalcStatsFar
.move
	jp .replaceFirstMove

.perfectDVs
	push de
	ld h, d
	ld l, e
	ld bc, MON_DVS
	add hl, bc
	ld a, $ff
	ld [hli], a
	ld [hl], a
	pop de
	ret

.maxStatExp
	push de
	ld h, d
	ld l, e
	ld bc, MON_HP_EXP
	add hl, bc
	ld b, 10
	ld a, $ff
.statLoop
	ld [hli], a
	dec b
	jr nz, .statLoop
	pop de
	ret

; In: a = move, de = shared party/box struct base. Replace slot 1 and reload
; PP for the complete resulting moveset while preserving the struct pointer.
.replaceFirstMove
	push de
	ld h, d
	ld l, e
	ld bc, MON_MOVES
	add hl, bc
	ld [hl], a
	push hl
	ld h, d
	ld l, e
	ld bc, MON_PP - 1
	add hl, bc
	ld d, h
	ld e, l
	pop hl
	predef LoadMovePPs
	pop de
	ret
