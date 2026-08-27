PrintMenuItem:
	xor a
	ldh [hAutoBGTransferEnabled], a
	hlcoord 0, 5
	ld b, 6
	ld c, 9
	call TextBoxBorder
	ld a, [wPlayerDisabledMove]
	and a
	jr z, .notDisabled
	swap a
	and $f
	ld b, a
	ldh a, [hCurrentMenuItem]
	cp b
	jr nz, .notDisabled
	hlcoord 1, 8
	ld de, DisabledText
	call PlaceString
	jp .moveDisabled
.notDisabled
	ld hl, hCurrentMenuItem
	dec [hl]
	xor a
	ldh [hWhoseTurn], a
	ld hl, wBattleMonMoves
	ldh a, [hCurrentMenuItem]
	ld c, a
	ld b, $0 ; which item in the menu is the cursor pointing to? (0-3)
	add hl, bc ; point to the item (move) in memory
	ld a, [hl]
	ld [wPlayerSelectedMove], a ; update wPlayerSelectedMove even if the move
	                            ; isn't actually selected (just pointed to by the cursor)
	ld a, [wPlayerMonNumber]
	ldh [hWhichPokemon], a
	ld a, BATTLE_MON_DATA
	ld [wMonDataLocation], a
	; GetCurrentMove is in Battle Core, which is a different ROM bank.
	; Besides using wNameBuffer, it writes the move ID through
	; wNamedObjectIndex, which aliases wMaxPP. Calculate both PP values only
	; after this farcall has finished clobbering shared scratch.
	farcall GetCurrentMove
	callfar GetMaxPP
	ld hl, hCurrentMenuItem
	ld c, [hl]
	inc [hl]
	ld b, $0
	ld hl, wBattleMonPP
	add hl, bc
	ld a, [hl]
	and PP_MASK
	ld [wBattleMenuCurrentPP], a
; print the move information box
	hlcoord 1, 6
	ld de, TypeText
	call PlaceString
	hlcoord 1, 10
	ld de, PPText
	call PlaceString
	hlcoord 4, 10
	ld de, wBattleMenuCurrentPP
	lb bc, 1, 2
	call PrintNumber
	hlcoord 6, 10
	ld [hl], '/'
	hlcoord 7, 10
	ld de, wMaxPP
	lb bc, 1, 2
	call PrintNumber
	; Type and type effectiveness share the first row.  Keep the
	; effectiveness readout separate from the damage path: the preview is
	; intentionally type-only and does not include RoguePrismDamageBoost.
	farcall PreviewTypeMatchup
	ld a, e
	ld d, a
	ld a, [wPlayerMovePower]
	and a
	jp z, .noPower
	ld a, d
	cp NO_EFFECT
	jr z, .effectiveness0
	cp NOT_VERY_EFFECTIVE
	jr z, .effectivenessQuarter
	cp NOT_VERY_EFFECTIVE * 2
	jr z, .effectivenessHalf
	cp EFFECTIVE * 2
	jr z, .effectivenessNeutral
	cp SUPER_EFFECTIVE * 2
	jr z, .effectivenessDouble
	cp SUPER_EFFECTIVE * 4
	jr z, .effectivenessQuad
	ld de, EffectivenessNeutralText
	jr .printEffectiveness
.effectiveness0
	ld de, Effectiveness0Text
	jr .printEffectiveness
.effectivenessQuarter
	ld de, EffectivenessQuarterText
	jr .printEffectiveness
.effectivenessHalf
	ld de, EffectivenessHalfText
	jr .printEffectiveness
.effectivenessNeutral
	ld de, EffectivenessNeutralText
	jr .printEffectiveness
.effectivenessDouble
	ld de, EffectivenessDoubleText
	jr .printEffectiveness
.effectivenessQuad
	ld de, EffectivenessQuadText
.printEffectiveness
	hlcoord 6, 6
	call PlaceString
	hlcoord 2, 7
	predef PrintMoveType

.power
	hlcoord 1, 8
	ld de, PowerText
	call PlaceString
	ld a, [wPlayerMovePower]
	ld de, wPlayerMovePower
	hlcoord 6, 8
	lb bc, 1, 3
	call PrintNumber

.accuracy
	hlcoord 1, 9
	ld de, AccuracyText
	call PlaceString
	; Move accuracy is stored as a percent-scaled byte (100% = 255).
	; Add 255 before dividing to round acc * 100 / 256.
	ld a, [wPlayerMoveAccuracy]
	ld c, a
	ld b, 0
	ld hl, 255
	ld a, 100
	call AddNTimes
	ld a, h
	ld [wStringBuffer], a
	hlcoord 6, 9
	ld de, wStringBuffer
	lb bc, 1, 3
	call PrintNumber
	ld [hl], '%'

.crit
	hlcoord 1, 11
	ld de, CritText
	call PlaceString
	farcall CalcCritRate
	jr c, .guaranteedCrit
	; A zero-power move returns Z from CalcCritRate and is handled by
	; .noPower, so a non-guaranteed result here has a real threshold in e.
	ld a, e
	ld c, a
	ld b, 0
	ld hl, 255
	ld a, 100
	call AddNTimes
	ld a, h
	ld [wStringBuffer], a
	hlcoord 6, 11
	ld de, wStringBuffer
	lb bc, 1, 3
	call PrintNumber
	ld [hl], '%'
	jr .moveDisabled

.guaranteedCrit
	ld a, 100
	ld [wStringBuffer], a
	hlcoord 6, 11
	ld de, wStringBuffer
	lb bc, 1, 3
	call PrintNumber
	ld [hl], '%'
	jr .moveDisabled

.noPower
	hlcoord 6, 6
	ld de, NoPowerText
	call PlaceString
	hlcoord 2, 7
	predef PrintMoveType
	; Status moves have no damage/effectiveness/crit rate to preview.
	hlcoord 1, 8
	ld de, PowerText
	call PlaceString
	hlcoord 6, 8
	ld de, NoPowerText
	call PlaceString
	hlcoord 1, 9
	ld de, AccuracyText
	call PlaceString
	; Accuracy remains meaningful for status moves, so it is still shown.
	ld a, [wPlayerMoveAccuracy]
	ld c, a
	ld b, 0
	ld hl, 255
	ld a, 100
	call AddNTimes
	ld a, h
	ld [wStringBuffer], a
	hlcoord 6, 9
	ld de, wStringBuffer
	lb bc, 1, 3
	call PrintNumber
	ld [hl], '%'
	hlcoord 1, 11
	ld de, CritText
	call PlaceString
	hlcoord 6, 11
	ld de, NoPowerText
	call PlaceString
.moveDisabled
	ld a, $1
	ldh [hAutoBGTransferEnabled], a
	jp Delay3

DisabledText:
	db "disabled!@"

TypeText:
	db "TYPE@"

PowerText:
	db "PWR@"

AccuracyText:
	db "ACC@"

PPText:
	db "PP@"

CritText:
	db "CRIT@"

NoPowerText:
	db "-@"

Effectiveness0Text:
	db "x0@"

EffectivenessQuarterText:
	db "x1/4@"

EffectivenessHalfText:
	db "x1/2@"

EffectivenessNeutralText:
	db "x1@"

EffectivenessDoubleText:
	db "x2@"

EffectivenessQuadText:
	db "x4@"
