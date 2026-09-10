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

; Increase the player's calculated critical-hit damage by 20 percent. Called
; after CalculateDamage and before type, STAB, and random damage modifiers, so
; fixed-damage and zero-power moves remain excluded by their existing bypass.
BridgeApplyCriticalDamageBoost::
	ld a, [wCriticalHitOrOHKO]
	cp 1
	ret nz
	ld e, BRIDGE_EFFECT_CRITICAL_DAMAGE
	call BridgeHasGlobalEffect
	ret nc
	jp BridgeScaleDamage120

BridgeApplyStabDamageBoost::
	ldh a, [hWhoseTurn]
	and a
	ret nz
	; AdjustDamageForMoveType normally bypasses fixed-damage moves, but OHKO
	; effects return through its type-adjustment path with the OHKO flag set.
	; Do not scale that sentinel damage as ordinary STAB damage.
	ld a, [wCriticalHitOrOHKO]
	cp 2
	ret z
	ld a, [wPlayerMoveNum]
	cp COUNTER
	ret z
	ld e, BRIDGE_EFFECT_STAB_DAMAGE
	call BridgeHasGlobalEffect
	ret nc
	ld a, 110
	jp BridgeScaleDamage

; In/out: e = critical-hit threshold. Apply the two player-only run bonuses in
; their established order: Witch relative scaling, then Captain flat points.
BridgeAdjustCriticalThreshold::
	ldh a, [hWhoseTurn]
	and a
	ret nz
	ld a, [wWitchPrizesEarned]
	and 1 << (PRIZE_CRIT_BOOST - 1)
	jr z, .captain
	ld a, e
	srl a
	srl a
	add e
	jr nc, .storeWitch
	ld a, $ff
.storeWitch
	ld e, a
.captain
	push de
	ld e, BRIDGE_SELECTED_EFFECT_CRITICAL_RATE
	call BridgeActiveMonHasSelectedEffect
	pop de
	ret nc
	ld a, e
	add 25 percent + 1
	jr nc, .storeCaptain
	ld a, $ff
.storeCaptain
	ld e, a
	ret

; In/out: e = the already-scaled move accuracy threshold.
BridgeAdjustAccuracyThreshold::
	ldh a, [hWhoseTurn]
	and a
	ret nz
	ld a, [wWitchPrizesEarned]
	and 1 << (PRIZE_ACC_BOOST - 1)
	jr z, .bridge
	call .addTenPoints
.bridge
	push de
	ld e, BRIDGE_EFFECT_ACCURACY
	call BridgeHasGlobalEffect
	pop de
	ret nc
.addTenPoints
	ld a, e
	add 26
	jr nc, .store
	ld a, $ff
.store
	ld e, a
.done
	ret

; In/out: e = the move's ordinary flinch threshold.
BridgeAdjustFlinchThreshold::
	ldh a, [hWhoseTurn]
	and a
	ret nz
	ld a, [wLinkState]
	cp LINK_STATE_BATTLING
	ret z
	push de
	ld e, BRIDGE_SELECTED_EFFECT_FLINCH
	call BridgeActiveMonHasSelectedEffect
	pop de
	ret nc
	ld a, e
	add 20 percent + 1
	jr nc, .store
	ld a, $ff
.store
	ld e, a
	ret

BridgeApplyCuteDamageBoost::
	; The ordinary path already excludes status, Super Fang, and special fixed
	; damage before reaching AdjustDamageForMoveType. Keep the explicit guards
	; here as well for OHKO and AI/direct callers, whose base power is 1.
	ld a, [wCriticalHitOrOHKO]
	cp 2
	ret z
	ld a, [wPlayerMoveEffect]
	cp OHKO_EFFECT
	ret z
	cp SUPER_FANG_EFFECT
	ret z
	cp SPECIAL_DAMAGE_EFFECT
	ret z
	ld a, [wPlayerMoveNum]
	cp COUNTER
	ret z
	ld a, [wPlayerMovePower]
	and a
	ret z
	cp 60
	ret nc
	ld e, BRIDGE_EFFECT_CUTE_BOOST
	call BridgeHasGlobalEffect
	ret nc
	ld a, 150
	jp BridgeScaleDamage

; In: e = complete dual-type effectiveness multiplier from TypeEffectiveness.
BridgeApplySuperEffectiveDamageBoost::
	ld a, [wCriticalHitOrOHKO]
	cp 2
	ret z
	ld a, [wPlayerMoveNum]
	cp COUNTER
	ret z
	ld a, e
	cp SUPER_EFFECTIVE * 2
	ret c
	ld e, BRIDGE_EFFECT_SUPER_EFFECTIVE
	call BridgeHasGlobalEffect
	ret nc
	jp BridgeScaleDamage120

; Reset the current-action Repeat result. The previous successful move remains
; live until execution either publishes the actual move or the post-move hook
; confirms that no move occurred.
BridgeBeginRepeatAction::
	xor a
	ld [wBridgeRepeatState], a
	ld a, [wLinkState]
	cp LINK_STATE_BATTLING
	ret nz
	jr BridgeClearRepeatTracking

; Publish the actual move after disobedience has resolved it. Metronome and
; Mirror Move reach this seam first as wrapper moves and then again with their
; generated/copied move, so defer tracking on the wrapper pass.
BridgePrepareRepeatAction::
	ld a, [wLinkState]
	cp LINK_STATE_BATTLING
	jr z, BridgeClearRepeatTracking
	ld a, [wPlayerMoveEffect]
	cp METRONOME_EFFECT
	ret z
	cp MIRROR_MOVE_EFFECT
	ret z
	ld a, [wPlayerSelectedMove]
	and a
	jr z, BridgeClearRepeatTracking
	ld b, a                      ; actual move
	ld c, 1                      ; valid non-repeating move
	ld a, [wWitchPrevPlayerMove]
	cp b
	jr nz, .record
	ld a, [wWitchPrevPlayerSlot]
	ld d, a
	ld a, [wPlayerMonNumber]
	cp d
	jr nz, .record
	inc c                         ; same move and same party member
.record
	ld a, b
	ld [wWitchPrevPlayerMove], a
	ld a, [wPlayerMonNumber]
	ld [wWitchPrevPlayerSlot], a
	ld a, c
	ld [wBridgeRepeatState], a
	ret

BridgeClearRepeatTracking::
	xor a
	ld [wWitchPrevPlayerMove], a
	ld [wBridgeRepeatState], a
	ret

BridgeApplyRepeatDamageBoost::
	ld a, [wBridgeRepeatState]
	cp 2
	ret nz
	ld a, [wCriticalHitOrOHKO]
	cp 2
	ret z
	ld a, [wPlayerMovePower]
	and a
	ret z
	ld e, BRIDGE_EFFECT_REPEAT
	call BridgeHasGlobalEffect
	ret nc
	ld a, 115
	jr BridgeScaleDamage

BridgeApplyLifeOrbDamageBoost::
	ldh a, [hWhoseTurn]
	and a
	ret nz
	ld a, [wLinkState]
	cp LINK_STATE_BATTLING
	ret z
	ld a, [wCriticalHitOrOHKO]
	cp 2
	ret z
	ld a, [wPlayerMovePower]
	and a
	ret z
	ld e, BRIDGE_SELECTED_EFFECT_LIFE_ORB
	call BridgeActiveMonHasSelectedEffect
	ret nc
	ld a, 130
	jr BridgeScaleDamage

BridgeScaleDamage120::
	ld a, 120
BridgeScaleDamage:
	ldh [hMultiplier], a
	xor a
	ldh [hMultiplicand], a
	ld hl, wDamage
	ld a, [hli]
	ldh [hMultiplicand + 1], a
	ld a, [hld]
	ldh [hMultiplicand + 2], a
	call Multiply
	ld a, 100
	ldh [hDivisor], a
	ld b, 4
	call Divide
	ldh a, [hQuotient + 2]
	ld [hli], a
	ldh a, [hQuotient + 3]
	ld [hl], a
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
	call PrepareFusionAndBridgeRayCalcStats
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

; Recalculate a just-selected ray target without refilling it. hWhichPokemon
; identifies the party slot and a is the selected ray effect. Growth scales
; current HP by the same 1.125 multiplier as maximum HP, preserving its health
; percentage without granting a full heal.
BridgeRecalculateGrantedRayMon::
	push af
	ldh a, [hWhichPokemon]
	ld hl, wPartyMons
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	ld d, h
	ld e, l
	pop af
	cp BRIDGE_SELECTED_EFFECT_GROWTH_RAY
	jr nz, .currentHPReady
	push de
	call .boostCurrentHP
	pop de
.currentHPReady
	ld a, [de]
	ld [wCurSpecies], a
	push de
	call GetMonHeader
	pop de
	ld h, d
	ld l, e
	ld bc, MON_LEVEL
	add hl, bc
	ld a, [hl]
	ld [wCurEnemyLevel], a
	ld h, d
	ld l, e
	ld bc, MON_STATS
	add hl, bc
	ld d, h
	ld e, l
	ld bc, (MON_HP_EXP - 1) - MON_STATS
	add hl, bc
	ld b, 1
	push bc
	push hl
	call PrepareFusionAndBridgeRayCalcStats
	pop hl
	pop bc
	jp CalcStats
.boostCurrentHP
	ld h, d
	ld l, e
	ld bc, MON_HP
	add hl, bc
	ld a, [hli]
	ld b, a
	ld c, [hl]
	ld d, b
	ld e, c
	srl d
	rr e
	srl d
	rr e
	srl d
	rr e
	ld a, c
	add e
	ld c, a
	ld a, b
	adc d
	ld b, a
	ld a, c
	sub LOW(MAX_STAT_VALUE + 1)
	ld a, b
	sbc HIGH(MAX_STAT_VALUE + 1)
	jr c, .storeHP
	ld bc, MAX_STAT_VALUE
.storeHP
	ld [hl], c
	dec hl
	ld [hl], b
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

; Choose among every immediate evolution in the selected species' table.
; Requirements are intentionally ignored; EvolutionAfterBattle validates the
; chosen target again before evolving. Carry clear means the player declined
; every available branch or the species has no evolution.
MistStoneChooseEvolution::
; Species Groups Phase 2R: EEVEE is handled separately, and not for convenience.
;
; The menu below walks the mon's evolution entries and prompts "Evolve into X?"
; for each. That works when every entry names a different species. Eevee's eight
; entries do not: the five eeveelution FORMS reuse FLAREON, JOLTEON and VAPOREON
; as their species and differ only by a form index, so the player would be asked
; about FLAREON twice, JOLTEON three times and VAPOREON three times with no way
; to tell Leafeon from Flareon.
;
; It would also be wrong even if the player guessed right. The parser's Mist
; Stone branch matches on wEvoNewSpecies alone, so it always takes the FIRST
; entry with that species, while ApplyEvoStoneForm keys on wEvoStoneItemID -
; which is MIST_STONE here, not the stone that carries the form. Picking the
; Leafeon entry would hand back a plain Flareon.
;
; So Eevee rolls instead. The trick is to substitute a real stone into
; wEvoStoneItemID rather than special-case anything downstream: the ordinary
; EVOLVE_ITEM match then fires, and ApplyEvoStoneForm sets the right form, with
; no change to the parser, the evolution data or the form table.
	ld a, [wCurPartySpecies]
	cp EEVEE
	jr nz, .notEevee
	call Random           ; HOME; never BattleRandom outside battle
	and %00000111         ; 0-7, one per Eevee branch - uniform, 8 is a power of 2
	ld e, a
	ld d, 0
	ld hl, EeveeMistStones
	add hl, de
	ld a, [hl]
	ld [wEvoStoneItemID], a
	scf                   ; carry = "an evolution was chosen", same as the menu
	ret

.notEevee
	ld a, [wCurPartySpecies]
	dec a
	ld b, 0
	add a
	rl b
	ld c, a
	ld hl, EvosMovesPointerTable
	add hl, bc
	ld de, wEvoDataBuffer
	ld a, BANK(EvosMovesPointerTable)
	ld bc, 2
	call FarCopyData
	ld hl, wEvoDataBuffer
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld de, wEvoDataBuffer
	ld a, BANK(EvosMovesPointerTable)
	ld bc, wEvoDataBufferEnd - wEvoDataBuffer
	call FarCopyData
	ld hl, wEvoDataBuffer
.nextEvolution
	ld a, [hli]
	and a
	jr z, .noneChosen
	cp EVOLVE_ITEM
	jr nz, .skipRequirement
	inc hl                       ; item id
.skipRequirement
	inc hl                       ; minimum level
	ld a, [hli]                  ; target species
	ld [wEvoNewSpecies], a
	push hl
	ld [wNamedObjectIndex], a
	call GetMonName
	ld hl, MistStoneChoiceText
	call PrintText
	lb bc, 8, 15
	ld a, TWO_OPTION_MENU
	ld [wTextBoxID], a
	call DisplayTextBoxID
	ld a, [wMenuExitMethod]
	cp CHOSE_SECOND_ITEM
	pop hl
	jr z, .nextEvolution
	scf
	ret
.noneChosen
	and a
	ret

MistStoneChoiceText:
	text_far _MistStoneChoiceText
	text_end

EeveeMistStones:
; One stone per Eevee EVOLVE_ITEM entry, in the same order as EeveeEvosMoves.
; Keep the two in sync: this table's LENGTH is what the Random mask in
; MistStoneChooseEvolution assumes.
;
; Placed AFTER the routine on purpose: a global label between a routine's entry
; and its local labels re-scopes them (`.notEevee` became
; EeveeMistStones.notEevee and the link failed).
	db FIRE_STONE, THUNDER_STONE, WATER_STONE, LEAF_STONE
	db SUN_STONE,  DUSK_STONE,    ICE_STONE,   MOON_STONE
EeveeMistStonesEnd:
ASSERT EeveeMistStonesEnd - EeveeMistStones == 8, \
       "EeveeMistStones must hold exactly 8 entries - the Random mask assumes it"
