; Pokedex Forms list and form data page (2026-11-03, Pokedex forms Checkpoint D).
;
; SELECT on the ordinary Pokedex list opens this list (predef FormDexMenu, from
; engine/menus/pokedex.asm). Every DEX_FORM_* identity has a row: the base
; species' Pokedex number, a ball when owned, the form's name when seen and
; dashes otherwise. A on a seen row opens the form's own data page: the form's
; name, sprite, palette, types and base stats, and (when owned) its category,
; height, weight and description from FormDexEntryPointers.
;
; Self-contained in bank $27: the base data page (ShowPokedexDataInternal, bank
; $10) has no room for a second identity kind, so the parts of it this page
; needs are copied here rather than hooked. The only shared state is
; wRewardInfoSlot = $80 | id while the page is up, which tells SetPal_Pokedex's
; palette hook (RewardInfoFormPalette) to use the form's palette; 1-3 there still
; mean a reward INFO preview. No new RAM.
;
; State: the base list's wListScrollOffset / hCurrentMenuItem / wLastMenuItem are
; pushed on entry and restored on exit, so the ordinary list comes back exactly
; where the player left it. The Forms list uses the same bytes while it is open.

DEF FORM_DEX_ROWS EQU 7
DEF FORM_DEX_MAX_SCROLL EQU NUM_DEX_FORMS - FORM_DEX_ROWS
	ASSERT NUM_DEX_FORMS > FORM_DEX_ROWS

FormDexMenu::
	ld a, [wListScrollOffset]
	push af
	ldh a, [hCurrentMenuItem]
	push af
	ld a, [wLastMenuItem]
	push af
	xor a
	ld [wListScrollOffset], a
	ldh [hCurrentMenuItem], a
	ld [wLastMenuItem], a

.redraw
	xor a
	ldh [hAutoBGTransferEnabled], a
	call ClearScreen
	ld b, SET_PAL_GENERIC
	call RunPaletteCommand
	callfar LoadPokedexTilePatterns
	call FormDexDrawFrame

.loop
	xor a
	ldh [hAutoBGTransferEnabled], a
	hlcoord 1, 2
	lb bc, 14, 13
	call ClearScreenArea
	hlcoord 1, 3
	ld a, [wListScrollOffset]
	ld c, a
	ld b, FORM_DEX_ROWS
.rows
	push bc
	push hl
	call FormDexDrawRow
	pop hl
	ld de, 2 * SCREEN_WIDTH
	add hl, de
	pop bc
	inc c
	dec b
	jr nz, .rows
	ld a, 1
	ldh [hAutoBGTransferEnabled], a
	call Delay3
	call GBPalNormal

	ld hl, wTopMenuItemY
	ld a, 3
	ld [hli], a ; top menu item Y
	xor a
	ld [hli], a ; top menu item X
	inc a
	ld [wMenuWatchMovingOutOfBounds], a
	inc hl ; wTileBehindCursor
	ld a, FORM_DEX_ROWS - 1
	ld [hli], a ; max menu item ID
	ld [hl], PAD_LEFT | PAD_RIGHT | PAD_B | PAD_A | PAD_SELECT
	call HandleMenuInput
	bit B_PAD_B, a
	jr nz, .exit
	bit B_PAD_SELECT, a
	jr nz, .exit
	bit B_PAD_UP, a
	jr nz, .up
	bit B_PAD_DOWN, a
	jr nz, .down
	bit B_PAD_RIGHT, a
	jr nz, .pageDown
	bit B_PAD_LEFT, a
	jr nz, .pageUp
	; A: open the row's data page, if that identity has been seen
	ld a, [wListScrollOffset]
	ld b, a
	ldh a, [hCurrentMenuItem]
	add b
	ld c, a
	ld hl, wPokedexFormSeen
	call FormDexTestBit
	jr z, .toLoop
	call FormDexShowData
	jp .redraw

.up
	ld a, [wListScrollOffset]
	and a
	jr z, .toLoop
	dec a
	jr .setScroll
.down
	ld a, [wListScrollOffset]
	cp FORM_DEX_MAX_SCROLL
	jr nc, .toLoop
	inc a
	jr .setScroll
.pageDown
	ld a, [wListScrollOffset]
	add FORM_DEX_ROWS
	cp FORM_DEX_MAX_SCROLL + 1
	jr c, .setScroll
	ld a, FORM_DEX_MAX_SCROLL
	jr .setScroll
.pageUp
	ld a, [wListScrollOffset]
	sub FORM_DEX_ROWS
	jr nc, .setScroll
	xor a
.setScroll
	ld [wListScrollOffset], a
.toLoop
	jp .loop

.exit
	pop af
	ld [wLastMenuItem], a
	pop af
	ldh [hCurrentMenuItem], a
	pop af
	ld [wListScrollOffset], a
	xor a
	ldh [hAutoBGTransferEnabled], a
	jp ClearScreen

; The list's static parts: dividers, title, form seen/owned counts, key hints.
FormDexDrawFrame:
	hlcoord 15, 8
	ld a, '─'
	ld [hli], a
	ld [hli], a
	ld [hli], a
	ld [hli], a
	ld [hli], a
	hlcoord 14, 0
	ld [hl], $71 ; vertical line tile
	hlcoord 14, 1
	call FormDexVerticalLine
	hlcoord 14, 9
	call FormDexVerticalLine
	hlcoord 1, 1
	ld de, FormDexTitleText
	call PlaceString
	hlcoord 16, 2
	ld de, FormDexSeenText
	call PlaceString
	hlcoord 16, 5
	ld de, FormDexOwnText
	call PlaceString
	hlcoord 15, 10
	ld de, FormDexHintText
	call PlaceString
	farcall DexFormCounts ; d = seen, e = owned
	push de
	ld a, d
	ld [wNumSetBits], a
	ld de, wNumSetBits
	hlcoord 16, 3
	lb bc, 1, 3
	call PrintNumber
	pop de
	ld a, e
	ld [wNumSetBits], a
	ld de, wNumSetBits
	hlcoord 16, 6
	lb bc, 1, 3
	jp PrintNumber

FormDexVerticalLine: ; DrawPokedexVerticalLine
	ld c, 9
	ld de, SCREEN_WIDTH
	ld a, $71
.loop
	ld [hl], a
	add hl, de
	xor 1 ; toggle between vertical line tile and box tile
	dec c
	jr nz, .loop
	ret

; One list row. IN: c = identity id, hl = the row's column 1 (the name row; the
; base species' number goes on the row above, as in the ordinary list).
FormDexDrawRow:
	push hl
	push bc
	ld e, c
	farcall DexFormKeyOf ; d = species, e = form
	pop bc
	push bc
	push de
	ld a, d
	ld [wPokedexNum], a
	predef IndexToPokedex
	pop de
	pop bc
	pop hl
	push hl
	push bc
	push de
	ld bc, -SCREEN_WIDTH
	add hl, bc
	ld de, wPokedexNum
	lb bc, LEADING_ZEROES | 1, 3
	call PrintNumber
	pop de
	pop bc
	pop hl
	inc hl
	inc hl ; column 3: owned ball
	push hl
	ld hl, wPokedexFormOwned
	call FormDexTestBit
	pop hl
	ld a, ' '
	jr z, .noBall
	ld a, $72 ; pokeball tile
.noBall
	ld [hli], a ; column 4: name
	push hl
	ld hl, wPokedexFormSeen
	call FormDexTestBit
	jr nz, .name
	ld de, FormDexDashes
	jr .place
.name
	; the form's own name: GetMonName honours a pending form context
	ld a, d
	ld [wNamedObjectIndex], a
	ld [wFormContextSpecies], a
	ld a, e
	ld [wFormContextForm], a
	call GetMonName ; de = wNameBuffer
	xor a
	ld [wFormContextSpecies], a ; never leave a context pending
.place
	pop hl
	jp PlaceString

; IN: hl = flag array, c = bit. OUT: nz if set. Preserves bc, de.
FormDexTestBit:
	push bc
	ld a, c
	srl a
	srl a
	srl a
	add l
	ld l, a
	jr nc, .noCarry
	inc h
.noCarry
	ld a, c
	and 7
	ld b, a
	inc b
	ld a, [hl]
.shift
	dec b
	jr z, .test
	rrca
	jr .shift
.test
	pop bc
	and 1
	ret

; Publish identity [wRewardInfoSlot] & $7F as the pending form context, for the
; next GetMonName or GetMonHeader (each consumes or ignores it). OUT: a = species.
FormDexPublish:
	ld a, [wRewardInfoSlot]
	and $7f
	ld e, a
	farcall DexFormKeyOf
	ld a, e
	ld [wFormContextForm], a
	ld a, d
	ld [wFormContextSpecies], a
	ret

; ---------------------------------------------------------------------------
; FormDexShowData: one identity's data page. IN: c = DEX_FORM_* id (seen).
; Follows ShowPokedexDataInternal (engine/menus/pokedex.asm) line for line where
; it can; differences are commented.
; ---------------------------------------------------------------------------
FormDexShowData:
	ld a, c
	or $80
	ld [wRewardInfoSlot], a ; form palette in SetPal_Pokedex; cleared on exit
	ld hl, wStatusFlags2
	set BIT_NO_AUDIO_FADE_OUT, [hl]
	ld a, $33 ; 3/7 volume
	ldh [rAUDVOL], a
	call GBPalWhiteOut ; zero all palettes
	call ClearScreen
	call FormDexPublish ; a = species
	xor a
	ld [wFormContextSpecies], a ; only the species is wanted here
	ld a, d
	ld [wCurPartySpecies], a
	ld [wPokedexNum], a
	ld b, SET_PAL_POKEDEX
	call RunPaletteCommand
	ldh a, [hTileAnimations]
	push af
	xor a
	ldh [hTileAnimations], a

	hlcoord 0, 0
	ld de, 1
	lb bc, $64, SCREEN_WIDTH
	call FormDexTileLine ; top border
	hlcoord 0, 17
	ld b, $6f
	call FormDexTileLine ; bottom border
	hlcoord 0, 1
	ld de, 20
	lb bc, $66, $10
	call FormDexTileLine ; left border
	hlcoord 19, 1
	ld b, $67
	call FormDexTileLine ; right border
	ld a, $63 ; upper left corner tile
	ldcoord_a 0, 0
	ld a, $65 ; upper right corner tile
	ldcoord_a 19, 0
	ld a, $6c ; lower left corner tile
	ldcoord_a 0, 17
	ld a, $6e ; lower right corner tile
	ldcoord_a 19, 17
	hlcoord 0, 9
	ld de, FormDexDividerLine
	call PlaceString
	hlcoord 9, 6
	ld de, FormDexHeightWeightText
	call PlaceString

	call FormDexPublish
	ld [wNamedObjectIndex], a
	call GetMonName
	xor a
	ld [wFormContextSpecies], a
	hlcoord 9, 2
	call PlaceString ; the form's name

	ld a, [wRewardInfoSlot]
	and $7f
	ld e, a
	ld d, 0
	ld hl, FormDexEntryPointers
	add hl, de
	add hl, de
	ld a, [hli]
	ld e, a
	ld d, [hl] ; de = this identity's entry
	hlcoord 9, 4
	call PlaceString ; category; de -> its terminator

	; № + the base species' Pokedex number (a form has no number of its own)
	push de
	ld a, [wCurPartySpecies]
	ld [wPokedexNum], a
	predef IndexToPokedex
	hlcoord 2, 8
	ld a, '№'
	ld [hli], a
	ld a, '<DOT>'
	ld [hli], a
	ld de, wPokedexNum
	lb bc, LEADING_ZEROES | 1, 3
	call PrintNumber
	ld a, [wCurPartySpecies]
	ld [wPokedexNum], a
	ld [wCurSpecies], a
	ld a, [wRewardInfoSlot]
	and $7f
	ld c, a
	ld hl, wPokedexFormOwned
	call FormDexTestBit
	pop de
	push af ; nz = owned

	push de
	call Delay3
	call GBPalNormal
	call FormDexPublish ; the form's sprite, types and base stats
	call GetMonHeader
	xor a
	ld [wFormContextSpecies], a
	hlcoord 1, 1
	call LoadFlippedFrontSpriteByMonIndex
	ld a, [wCurPartySpecies]
	call PlayCry
	pop de

	pop af
	jp z, .waitForButtonPress ; not owned: name and sprite only, as for a species
	inc de ; de = feet
	hlcoord 12, 6
	lb bc, 1, 2
	call PrintNumber ; feet
	ld a, '′'
	ld [hl], a
	inc de
	inc de ; de = inches
	hlcoord 15, 6
	lb bc, LEADING_ZEROES | 1, 2
	call PrintNumber ; inches
	ld a, '″'
	ld [hl], a
	; weight, stored little-endian in tenths of pounds
	inc de
	inc de
	inc de ; de = weight high byte
	push de
	ld hl, hDexWeight
	ld a, [hl]
	push af
	ld a, [de]
	ld [hli], a
	ld a, [hl]
	push af
	dec de
	ld a, [de]
	ld [hl], a
	ld de, hDexWeight
	hlcoord 11, 8
	lb bc, 2, 5
	call PrintNumber
	hlcoord 14, 8
	ldh a, [hDexWeight + 1]
	sub 10
	ldh a, [hDexWeight]
	sbc 0
	jr nc, .next
	ld [hl], '0' ; below 1.0 lb, a 0 before the decimal point
.next
	inc hl
	ld a, [hli]
	ld [hld], a ; make room for the decimal point
	ld [hl], '<DOT>'
	pop af
	ldh [hDexWeight + 1], a
	pop af
	ldh [hDexWeight], a
	pop hl
	inc hl ; hl = description text
	bccoord 1, 11
	ld a, %10
	ldh [hClearLetterPrintingDelayFlags], a
	call TextCommandProcessor
	xor a
	ldh [hClearLetterPrintingDelayFlags], a
.waitForButtonPress2
	call JoypadLowSensitivity
	ldh a, [hJoy5]
	and PAD_A | PAD_B
	jr z, .waitForButtonPress2
	ld a, SFX_PRESS_AB
	call PlaySound
	hlcoord 1, 11
	lb bc, 5, 18
	call ClearScreenArea ; below the sprite
	hlcoord 9, 4
	lb bc, 5, 10
	call ClearScreenArea ; category, height and weight
	ld c, 20
	call DelayFrames
	; page two: types and base stats, as the ordinary page draws them
	hlcoord 9, 4
	ld de, FormDexTypeText
	call PlaceString
	ld a, [wLoadedMon + MON_CATCH_RATE]
	push af
	xor a
	ld [wLoadedMon + MON_CATCH_RATE], a
	hlcoord 10, 6
	predef PrintMonType
	pop af
	ld [wLoadedMon + MON_CATCH_RATE], a
	call FormDexBaseStats
.waitForButtonPress
	call JoypadLowSensitivity
	ldh a, [hJoy5]
	and PAD_A | PAD_B
	jr z, .waitForButtonPress
	pop af
	ldh [hTileAnimations], a
	xor a
	ld [wRewardInfoSlot], a
	call GBPalWhiteOut
	call ClearScreen
	call RunDefaultPaletteCommand
	call LoadTextBoxTilePatterns
	ld a, %11100000 ; FadePal4's rOBP1 (see ShowPokedexDataInternal)
	ldh [rOBP1], a
	call GBPalNormal
	ld hl, wStatusFlags2
	res BIT_NO_AUDIO_FADE_OUT, [hl]
	ld a, $77 ; max volume
	ldh [rAUDVOL], a
	ret

; PrintBaseStats (engine/menus/pokedex.asm), for the header GetMonHeader loaded.
FormDexBaseStats:
	ldh a, [hUILayoutFlags]
	push af
	set BIT_SINGLE_SPACED_LINES, a
	ldh [hUILayoutFlags], a
	hlcoord 2, 11
	ld de, FormDexStatsText
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

FormDexTileLine: ; DrawTileLine: b = tile, c = count, de = step, hl = start
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

FormDexTitleText:
	db "FORMS@"
FormDexSeenText:
	db "SEEN@"
FormDexOwnText:
	db "OWN@"
FormDexHintText:
	db   "B/SEL"
	next "BACK@"
FormDexDashes:
	db "----------@"
FormDexHeightWeightText:
	db   "HT  ?′??″"
	next "WT   ???lb@"
FormDexTypeText:
	db "TYPE/@"
FormDexStatsText:
	db   "HEALTH"
	next "ATTACK"
	next "DEFENSE"
	next "SPEED"
	next "SPECIAL@"
FormDexDividerLine:
	db $68, $69, $6B, $69, $6B, $69, $6B, $69, $6B, $6B
	db $6B, $6B, $69, $6B, $69, $6B, $69, $6B, $69, $6A
	db "@"

INCLUDE "data/pokemon/dex_form_entries.asm"
