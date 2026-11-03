; ShowPokedexMenu, its list (HandlePokedexListMenu) and side menu
; (HandlePokedexSideMenu) moved to custom_functions/form_dex.asm (bank $27) on
; 2026-11-03, when the list became every identity (species + forms, 303 rows,
; "split by kind"). This bank had 3 bytes left. Still here, reached by predef:
; ShowPokedexData (the species page), PokedexToIndex, IndexToPokedex.

; tests if a pokemon's bit is set in the seen or owned pokemon bit fields
; INPUT:
; [wPokedexNum] = pokedex number
; hl = address of bit field
IsPokemonBitSet:
	ld a, [wPokedexNum]
	dec a
	ld c, a
	ld b, FLAG_TEST
	predef FlagActionPredef
	ld a, c
	and a
	ret

; function to display pokedex data from outside the pokedex
ShowPokedexData:
	call GBPalWhiteOutWithDelay3
	call ClearScreen
	call UpdateSprites
	callfar LoadPokedexTilePatterns ; load pokedex tiles

; function to display pokedex data from inside the pokedex
ShowPokedexDataInternal:
	ld hl, wStatusFlags2
	set BIT_NO_AUDIO_FADE_OUT, [hl]
	ld a, $33 ; 3/7 volume
	ldh [rAUDVOL], a
	call GBPalWhiteOut ; zero all palettes
	call ClearScreen
	ld a, [wPokedexNum]
	ld [wCurPartySpecies], a
	push af
	ld b, SET_PAL_POKEDEX
	call RunPaletteCommand
	pop af
	ld [wPokedexNum], a
	ldh a, [hTileAnimations]
	push af
	xor a
	ldh [hTileAnimations], a

	hlcoord 0, 0
	ld de, 1
	lb bc, $64, SCREEN_WIDTH
	call DrawTileLine ; draw top border

	hlcoord 0, 17
	ld b, $6f
	call DrawTileLine ; draw bottom border

	hlcoord 0, 1
	ld de, 20
	lb bc, $66, $10
	call DrawTileLine ; draw left border

	hlcoord 19, 1
	ld b, $67
	call DrawTileLine ; draw right border

	ld a, $63 ; upper left corner tile
	ldcoord_a 0, 0
	ld a, $65 ; upper right corner tile
	ldcoord_a 19, 0
	ld a, $6c ; lower left corner tile
	ldcoord_a 0, 17
	ld a, $6e ; lower right corner tile
	ldcoord_a 19, 17

	hlcoord 0, 9
	ld de, PokedexDataDividerLine
	call PlaceString ; draw horizontal divider line

	hlcoord 9, 6
	ld de, HeightWeightText
	call PlaceString

	; Reward INFO preview (reward_offer_info.asm): name the offer as its form.
	; No-op outside a preview, as are the three hooks below.
	farcall RewardInfoPublishForm
	call GetMonName
	hlcoord 9, 2
	call PlaceString

	ld hl, PokedexEntryPointers
	ld a, [wPokedexNum]
	dec a
	ld e, a
	ld d, 0
	add hl, de
	add hl, de
	ld a, [hli]
	ld e, a
	ld d, [hl] ; de = address of pokedex entry

	hlcoord 9, 4
	call PlaceString ; print species name

	ld h, b
	ld l, c
	push de
	ld a, [wPokedexNum]
	push af
	call IndexToPokedex

	hlcoord 2, 8
	ld a, '№'
	ld [hli], a
	ld a, '<DOT>'
	ld [hli], a
	ld de, wPokedexNum
	lb bc, LEADING_ZEROES | 1, 3
	call PrintNumber ; print pokedex number

	ld hl, wPokedexOwned
	call IsPokemonBitSet
	pop af
	ld [wPokedexNum], a
	ld a, [wCurPartySpecies]
	ld [wCurSpecies], a
	pop de

	push af
	push bc
	push de
	push hl

	; A reward INFO preview goes straight to page 2: wipe page 1's category
	; and HT/WT labels before the palette comes up so they never flash.
	ld a, [wRewardInfoSlot]
	and a
	jr z, .notPreview
	hlcoord 9, 4
	lb bc, 5, 10
	call ClearScreenArea
.notPreview
	call Delay3
	call GBPalNormal
	farcall RewardInfoPublishForm ; the form's sprite, types and bars
	call GetMonHeader ; load pokemon picture location
	hlcoord 1, 1
	call LoadFlippedFrontSpriteByMonIndex ; draw pokemon picture
	ld a, [wRewardInfoSlot]
	and a
	jr z, .playCry
	pop hl
	pop de
	pop bc
	pop af
	jp .drawPageTwo ; plays the cry once the page is up
.playCry
	ld a, [wCurPartySpecies]
	call PlayCry

	pop hl
	pop de
	pop bc
	pop af

	ld a, c
	and a
	jp z, .waitForButtonPress ; if the pokemon has not been owned, don't print the height, weight, or description
	inc de ; de = address of feet (height)
	ld a, [de] ; reads feet, but a is overwritten without being used
	hlcoord 12, 6
	lb bc, 1, 2
	call PrintNumber ; print feet (height)
	ld a, '′'
	ld [hl], a
	inc de
	inc de ; de = address of inches (height)
	hlcoord 15, 6
	lb bc, LEADING_ZEROES | 1, 2
	call PrintNumber ; print inches (height)
	ld a, '″'
	ld [hl], a
; now print the weight (note that weight is stored in tenths of pounds internally)
	inc de
	inc de
	inc de ; de = address of upper byte of weight
	push de
; put weight in big-endian order at hDexWeight
	ld hl, hDexWeight
	ld a, [hl] ; save existing value of [hDexWeight]
	push af
	ld a, [de] ; a = upper byte of weight
	ld [hli], a ; store upper byte of weight in [hDexWeight]
	ld a, [hl] ; save existing value of [hDexWeight + 1]
	push af
	dec de
	ld a, [de] ; a = lower byte of weight
	ld [hl], a ; store lower byte of weight in [hDexWeight + 1]
	ld de, hDexWeight
	hlcoord 11, 8
	lb bc, 2, 5 ; 2 bytes, 5 digits
	call PrintNumber ; print weight
	hlcoord 14, 8
	ldh a, [hDexWeight + 1]
	sub 10
	ldh a, [hDexWeight]
	sbc 0
	jr nc, .next
	ld [hl], '0' ; if the weight is less than 10, put a 0 before the decimal point
.next
	inc hl
	ld a, [hli]
	ld [hld], a ; make space for the decimal point by moving the last digit forward one tile
	ld [hl], '<DOT>' ; decimal point tile
	pop af
	ldh [hDexWeight + 1], a ; restore original value of [hDexWeight + 1]
	pop af
	ldh [hDexWeight], a ; restore original value of [hDexWeight]
	pop hl
	inc hl ; hl = address of pokedex description text
	bccoord 1, 11
	ld a, %10
	ldh [hClearLetterPrintingDelayFlags], a
	call TextCommandProcessor ; print pokedex description text
	xor a
	ldh [hClearLetterPrintingDelayFlags], a
	CheckEvent EVENT_GOT_POKEDEX
	jr z, .waitForButtonPress ; don't show page 2 while displaying Oak's starters
.waitForButtonPress2
	call JoypadLowSensitivity
	ldh a, [hJoy5]
	and PAD_A | PAD_B
	jr z, .waitForButtonPress2
	ld a, SFX_PRESS_AB
	call PlaySound
	hlcoord 1, 11
	lb bc, 5, 18
	call ClearScreenArea ; clear below the sprite
	hlcoord 9, 4
	lb bc, 5, 10
	call ClearScreenArea ; clear category, height and weight
	ld c, 20
	call DelayFrames
.drawPageTwo
	; TYPE/ takes the category's row, so the two types land on rows 6 and 8
	; (where HT and WT were) instead of the second one on the divider at row 9.
	hlcoord 9, 4
	ld de, PokedexTypeText
	call PlaceString
	; A Pokedex entry identifies a species, not an owned mon instance. Clear
	; the stale per-instance variant flags while PrintMonType reads base types,
	; then restore the byte for the caller.
	ld a, [wLoadedMon + MON_CATCH_RATE]
	push af
	xor a
	ld [wLoadedMon + MON_CATCH_RATE], a
	hlcoord 10, 6
	predef PrintMonType
	pop af
	ld [wLoadedMon + MON_CATCH_RATE], a
	call PrintBaseStats
	farcall PrintRewardOfferDVs
	ld a, [wRewardInfoSlot]
	and a
	jr z, .waitForButtonPress
	ld a, [wCurPartySpecies]
	call PlayCry
.waitForButtonPress
	call JoypadLowSensitivity
	ldh a, [hJoy5]
	and PAD_A | PAD_B
	jr z, .waitForButtonPress
	pop af
	ldh [hTileAnimations], a
	call GBPalWhiteOut
	call ClearScreen
	call RunDefaultPaletteCommand
	call LoadTextBoxTilePatterns
	; GBPalWhiteOut zeroed rOBP1 and GBPalNormal only restores BGP/OBP0, but it
	; rebuilds the CGB OBJ 4-7 palettes from rOBP1. The standard red overworld
	; ball is OBJ 7 (ball_rarity.asm), so restore the overworld value first.
	ld a, %11100000 ; 3200, FadePal4's rOBP1
	ldh [rOBP1], a
	call GBPalNormal
	ld hl, wStatusFlags2
	res BIT_NO_AUDIO_FADE_OUT, [hl]
	ld a, $77 ; max volume
	ldh [rAUDVOL], a
	ret

PrintBaseStats:
	ldh a, [hUILayoutFlags]
	push af
	set BIT_SINGLE_SPACED_LINES, a
	ldh [hUILayoutFlags], a
	hlcoord 2, 11
	ld de, PokedexStatsText
	call PlaceString
	pop af
	ldh [hUILayoutFlags], a

	ld c, NUM_STATS
	hlcoord 10, 11
.loopStats
	push bc
	push hl
	ld a, NUM_STATS
	sub c
	ld c, a
	ld b, 0
	ld hl, wMonHBaseStats
	add hl, bc
	ld a, [hl]
	srl a
	cp $3f
	ld e, 0
	jr c, .lessThan128
	sub $3f
	ld e, 8
.lessThan128
	ld c, a
	pop hl
	ld b, 8
.loopFullTile
	ld a, c
	sub 8
	jr c, .partialTile
	ld c, a
	ld a, $48
	add e
	ld [hli], a
	dec b
	jr nz, .loopFullTile
	jr .done
.partialTile
	add 8 + $40
	add e
	ld [hli], a
	dec b
	jr z, .done
	ld a, $40
	add e
.loopEmptyTile
	ld [hli], a
	dec b
	jr nz, .loopEmptyTile
.done
	ld de, SCREEN_WIDTH - 8
	add hl, de
	pop bc
	dec c
	jr nz, .loopStats
	ret

HeightWeightText:
	db   "HT  ?′??″"
	next "WT   ???lb@"

PokedexTypeText:
	db "TYPE/@"

PokedexStatsText:
	db   "HEALTH"
	next "ATTACK"
	next "DEFENSE"
	next "SPEED"
	next "SPECIAL@"

; horizontal line that divides the pokedex text description from the rest of the data
PokedexDataDividerLine:
	db $68, $69, $6B, $69, $6B, $69, $6B, $69, $6B, $6B
	db $6B, $6B, $69, $6B, $69, $6B, $69, $6B, $69, $6A
	db "@"

; draws a line of tiles
; INPUT:
; b = tile ID
; c = number of tile ID's to write
; de = amount to destination address after each tile (1 for horizontal, 20 for vertical)
; hl = destination address
DrawTileLine:
	push bc
	push de
.loop
	ld [hl], b
	add hl, de
	dec c
	jr nz, .loop
	pop de
	pop bc
	ret

INCLUDE "data/pokemon/dex_entries.asm"

PokedexToIndex:
	; converts the Pokédex number at [wPokedexNum] to an index
	push bc
	push hl
	ld a, [wPokedexNum]
	ld b, a
	ld c, 0
	ld hl, PokedexOrder

.loop ; go through the list until we find an entry with a matching dex number
	inc c
	ld a, [hli]
	cp b
	jr nz, .loop

	ld a, c
	ld [wPokedexNum], a
	pop hl
	pop bc
	ret

IndexToPokedex:
	; converts the index number at [wPokedexNum] to a Pokédex number
	push bc
	push hl
	ld a, [wPokedexNum]
	dec a
	ld hl, PokedexOrder
	ld b, 0
	ld c, a
	add hl, bc
	ld a, [hl]
	ld [wPokedexNum], a
	pop hl
	pop bc
	ret

INCLUDE "data/pokemon/dex_order.asm"
