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
	call BridgeGiftMaxStatExp
	ld a, QUICK_ATTACK
	call BridgeGiftReplaceFirstMove
	jr .recalcIfParty
.perfect
	call .perfectDVs
.recalcIfParty
	ld a, [wAddedToParty]
	and a
	ret z
	jp BridgeRecalcStatsFar
.move
	jp BridgeGiftReplaceFirstMove

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

; Oak's Expert Training. Max every party mon's five stat-experience words and
; recalculate its stored stats. HP is restored to approximately the same
; proportion using the engine's established 48-pixel HP-bar ratio; a fainted
; mon remains at zero HP.
BridgeOakExpertTrainingFar::
	ld a, [wPartyCount]
	and a
	ret z
	ld b, a
	ld de, wPartyMon1
.loop
	push bc
	push de
	call .trainOne
	pop de
	ld hl, PARTYMON_STRUCT_LENGTH
	add hl, de
	ld d, h
	ld e, l
	pop bc
	dec b
	jr nz, .loop
	ret

.trainOne
	push de                      ; preserve struct base
	ld h, d
	ld l, e
	ld bc, MON_HP
	add hl, bc
	ld a, [hli]
	ld b, a
	ld c, [hl]                   ; bc = old current HP
	ld a, b
	or c
	jr z, .fainted
	ld h, d
	ld l, e
	ld de, MON_MAXHP
	add hl, de
	ld d, [hl]
	inc hl
	ld e, [hl]                   ; de = old maximum HP
	call .hpRatio                ; e = old HP proportion, 1..48
	ld a, e
	jr .haveRatio
.fainted
	xor a
.haveRatio
	pop de                       ; struct base
	push af                      ; saved HP ratio
	push de
	call BridgeGiftMaxStatExp
	call BridgeRecalcStatsFar
	pop de
	pop af
	and a
	jr z, .storeZero
	ldh [hMultiplier], a
	ld h, d
	ld l, e
	ld bc, MON_MAXHP
	add hl, bc
	xor a
	ldh [hMultiplicand], a
	ld a, [hli]
	ldh [hMultiplicand + 1], a
	ld a, [hl]
	ldh [hMultiplicand + 2], a
	call Multiply
	ld a, 48
	ldh [hDivisor], a
	ld b, 4
	call Divide
	ld h, d
	ld l, e
	ld bc, MON_HP
	add hl, bc
	ldh a, [hQuotient + 2]
	ld [hli], a
	ldh a, [hQuotient + 3]
	ld [hl], a
	ret
.storeZero
	ld h, d
	ld l, e
	ld bc, MON_HP
	add hl, bc
	xor a
	ld [hli], a
	ld [hl], a
	ret

; Established GetHPBarLength arithmetic, kept local because that routine is
; ROMX bank $03 and bc/de cannot cross a farcall. In: bc=current, de=maximum.
; Out: e=ratio in forty-eighths, with nonzero HP clamped to at least one.
.hpRatio
	push hl
	xor a
	ld hl, hMultiplicand
	ld [hli], a
	ld a, b
	ld [hli], a
	ld a, c
	ld [hli], a
	ld [hl], 48
	call Multiply
	ld a, d
	and a
	jr z, .ratioMaxFitsByte
	srl d
	rr e
	srl d
	rr e
	ldh a, [hMultiplicand + 1]
	ld b, a
	ldh a, [hMultiplicand + 2]
	srl b
	rr a
	srl b
	rr a
	ldh [hMultiplicand + 2], a
	ld a, b
	ldh [hMultiplicand + 1], a
.ratioMaxFitsByte
	ld a, e
	ldh [hDivisor], a
	ld b, 4
	call Divide
	ldh a, [hMultiplicand + 2]
	ld e, a
	pop hl
	and a
	ret nz
	ld e, 1
	ret

BridgeGiftMaxStatExp:
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
BridgeGiftReplaceFirstMove:
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
