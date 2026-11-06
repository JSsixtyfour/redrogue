; Special collection: PC RECORDS' list of the forms the Pokedex leaves out
; (RECORDS_PC_PLAN_2026-11-03.md). Part of the "Dex Forms" section, bank $30.
;
; Credit happens only on real acquisition, and only from three seams:
;   ApplySpecialForm         every authored gift, once delivered (never wEnemyMon)
;   DexRegisterCaught        an optional encounter's mon, once the ball works
;   DexRegisterMon           Armored Mewtwo, OWNED only
; Rentals register seen-only and so never reach it. A package is identified by
; species + BIT_SPECIAL_FORM; every evolution stage is the same identity.
;
; Inputs ride in d/e across a farcall. The bits are kept for life, like the Dex.

MACRO special_package ; species, id
	db \1, \2
ENDM

; Species -> identity, for a mon carrying BIT_SPECIAL_FORM. A species not listed
; (the move-tutor finalizers: Ekans, Oddish, Bulbasaur, Squirtle) is no identity.
; test_special_collection.py checks this against SpecialFormCaps and friends.
SpecialPackageRows:
	special_package CUBONE,     SPECIAL_THICK_CLUB
	special_package MAROWAK,    SPECIAL_THICK_CLUB
	special_package PIKACHU,    SPECIAL_LIGHT_BALL
	special_package MACHOP,     SPECIAL_NO_GUARD
	special_package MACHOKE,    SPECIAL_NO_GUARD
	special_package MACHAMP,    SPECIAL_NO_GUARD
	special_package HITMONLEE,  SPECIAL_LIMBER
	special_package HITMONCHAN, SPECIAL_MYSTIC
	special_package FARFETCHD,  SPECIAL_ALWAYS_CRIT
	special_package NIDORAN_F,  SPECIAL_QUICK_CLAW
	special_package NIDORINA,   SPECIAL_QUICK_CLAW
	special_package NIDOQUEEN,  SPECIAL_QUICK_CLAW
	special_package GROWLITHE,  SPECIAL_INTIMIDATE
	special_package ARCANINE,   SPECIAL_INTIMIDATE
	special_package BUTTERFREE, SPECIAL_PINK
	special_package DITTO,      SPECIAL_SUPER_DITTO
	special_package ONIX,       SPECIAL_CRYSTAL
	special_package SNORLAX,    SPECIAL_ICE
	special_package CHARMANDER, SPECIAL_DRAGON
	special_package CHARMELEON, SPECIAL_DRAGON
	special_package CHARIZARD,  SPECIAL_DRAGON
	special_package PSYDUCK,    SPECIAL_PSYCHIC
	special_package GOLDUCK,    SPECIAL_PSYCHIC
	db 0

; (species, form) -> identity, for the form records that are no Dex entries.
SpecialFormRows:
	db MEWTWO, ARMORED_MEWTWO_FORM, SPECIAL_ARMORED_MEWTWO
	db 0

; ---------------------------------------------------------------------------
; SpecialCreditStruct  IN: de = party, box or battle struct. CLOBBERS: all
; ---------------------------------------------------------------------------
SpecialCreditStruct::
	ld a, [de]
	ld b, a
	ld hl, MON_CATCH_RATE
	add hl, de
	ld c, [hl]
	; fall through

; IN: b = species, c = its MON_CATCH_RATE flag byte. CLOBBERS: all
SpecialCreditFlags:
	bit BIT_SPECIAL_FORM, c
	ret z
	ld hl, SpecialPackageRows
.loop
	ld a, [hli]
	and a
	ret z
	cp b
	ld a, [hli]
	jr nz, .loop
	; fall through

; IN: a = identity. CLOBBERS: af, c, e, hl
SpecialSetBit:
	ld c, a
	ld hl, wSpecialCollected
	call DexBitAddr
	or [hl]
	ld [hl], a
	ret

; ---------------------------------------------------------------------------
; SpecialCreditForm  IN: d = species, e = form 1..3. Preserves bc, de.
; ---------------------------------------------------------------------------
SpecialCreditForm:
	push bc
	push de
	ld hl, SpecialFormRows
.loop
	ld a, [hli]
	and a
	jr z, .done
	cp d
	ld a, [hli]
	ld b, [hl]
	inc hl
	jr nz, .loop
	cp e
	jr nz, .loop
	ld a, b
	call SpecialSetBit
.done
	pop de
	pop bc
	ret

; IN: a = identity. OUT: nz = collected, c = the identity. Preserves b, d.
SpecialIsCollected:
	ld c, a
	ld hl, wSpecialCollected
	call DexBitAddr
	and [hl]
	ret

; IN: a = identity. OUT: hl -> its SpecialEntries row. Preserves de.
SpecialEntryAddr:
	ld l, a
	ld h, 0
	ld b, h
	ld c, l
	add hl, hl
	add hl, hl
	add hl, hl
	add hl, bc                   ; * SPECIAL_ENTRY_SIZE
	ld bc, SpecialEntries
	add hl, bc
	ret

; ---------------------------------------------------------------------------
; SpecialCollectionMenu: the list, farcalled from RoomRecordsMenu. The caller
; follows it with ReloadMapData, because each page's pic overwrites Dorm tiles.
; ---------------------------------------------------------------------------
SpecialCollectionMenu::
	ld hl, wStatusFlags5
	set BIT_NO_TEXT_DELAY, [hl]
	ldh a, [hUILayoutFlags]
	push af
	set BIT_DOUBLE_SPACED_MENU, a ; its sense is inverted: set = single-spaced
	set BIT_SINGLE_SPACED_LINES, a
	ldh [hUILayoutFlags], a
	ldh a, [hUpdateSpritesEnabled]
	push af
	ldh a, [hTileAnimations]
	push af
	xor a
	ldh [hTileAnimations], a
	ld [wSpriteFlipped], a
	ldh [hUpdateSpritesEnabled], a
	call ClearSprites
	xor a
	push af                      ; the cursor, carried across the pages
.list
	call SpecialDrawList
	pop af
	ldh [hCurrentMenuItem], a
	ld [wLastMenuItem], a
	xor a
	ld [wMenuWatchMovingOutOfBounds], a
	ld hl, wTopMenuItemY
	ld a, 1
	ld [hli], a
	ld [hl], a                   ; wTopMenuItemX
	ld a, NUM_SPECIAL_IDENTITIES - 1
	ld [wMaxMenuItem], a
	ld a, PAD_A | PAD_B
	ld [wMenuWatchedKeys], a
	call HandleMenuInput
	bit B_PAD_B, a
	jr nz, .exit
	ldh a, [hCurrentMenuItem]
	push af
	call SpecialShowPage
	jr .list
.exit
	pop af
	ldh [hTileAnimations], a
	pop af
	ldh [hUpdateSpritesEnabled], a
	pop af
	ldh [hUILayoutFlags], a
	ld hl, wStatusFlags5
	res BIT_NO_TEXT_DELAY, [hl]
	xor a
	ld [wWholeScreenPaletteMonForm], a
	call GBPalWhiteOutWithDelay3
	call ClearScreen
	call RunDefaultPaletteCommand
	call UpdateSprites           ; the room's sprites, cleared on entry
	jp GBPalNormal

SpecialDrawList:
	call GBPalWhiteOutWithDelay3
	call ClearScreen
	call RunDefaultPaletteCommand
	hlcoord 1, 0
	ld de, .Title
	call PlaceString
	ld hl, wSpecialCollected
	ld c, NUM_SPECIAL_IDENTITIES
	call DexCountBits
	ld [wBuffer], a
	hlcoord 15, 0
	ld de, wBuffer
	lb bc, 1, 2
	call PrintNumber
	ld de, .OutOf
	call PlaceString
	ld c, 0
	hlcoord 2, 1
.row
	push bc
	push hl
	ld a, c
	call SpecialIsCollected
	ld de, SpecialUnknownName
	jr z, .place
	ld a, c
	call SpecialEntryAddr
	ld bc, SPECIAL_ENTRY_NAME
	add hl, bc
	ld a, [hli]
	ld e, a
	ld d, [hl]
.place
	pop hl
	push hl
	call PlaceString
	pop hl
	ld bc, SCREEN_WIDTH
	add hl, bc
	pop bc
	inc c
	ld a, c
	cp NUM_SPECIAL_IDENTITIES
	jr c, .row
	jp GBPalNormal
.Title
	db "SPECIAL FORMS@"
.OutOf
	ASSERT NUM_SPECIAL_IDENTITIES == 15
	db "/15@"

; ---------------------------------------------------------------------------
; SpecialShowPage: one entry. IN: a = identity. Modelled on LeaguePCShowMon: a
; whole-screen palette and vFrontPic, so it needs no Pokedex tiles or context.
; ---------------------------------------------------------------------------
SpecialShowPage:
	push af                      ; [identity]
	call GBPalWhiteOutWithDelay3
	call ClearScreen
	hlcoord 0, 0
	lb bc, 16, 18
	call TextBoxBorder
	pop af
	push af
	call SpecialEntryAddr
	ld a, [hli]                  ; species
	ld [wCurPartySpecies], a
	ld [wCurSpecies], a
	ld [wBattleMonSpecies2], a
	ld [wWholeScreenPaletteMonSpecies], a
	ld [wFormContextSpecies], a
	ld a, [hli]                  ; form
	ld [wFormContextForm], a
	ld d, a
	ld e, [hl]                   ; palette, 0 = the form's own
	pop af
	push af
	push de
	call SpecialIsCollected      ; preserves d, not e
	pop de
	push af                      ; [identity, z = a shadow]
	jr nz, .palette
	lb de, 0, 0                  ; a shadow gives nothing away
.palette
	ld a, e
	and a
	jr z, .formPalette
	or $80                       ; GetFormPalette: e names a palette
	ld d, a
.formPalette
	ld a, d
	ld [wWholeScreenPaletteMonForm], a
	lb bc, SET_PAL_POKEMON_WHOLE_SCREEN, 0
	call RunPaletteCommand
	hlcoord 1, 1
	call GetMonHeader
	call LoadFrontSpriteByMonIndex
	pop af
	push af
	call z, SpecialShadowPic
	call GBPalNormal
	pop af                       ; z = a shadow
	jr nz, .collected
	pop af                       ; [identity] dropped
	hlcoord 1, 9
	ld de, SpecialUnknownName
	call PlaceString
	hlcoord 1, 11
	ld de, .NotYet
	call PlaceString
	jr .wait
.collected
	pop af
	call SpecialEntryAddr
	ld bc, SPECIAL_ENTRY_NAME
	add hl, bc
	ld a, [hli]
	ld e, a
	ld a, [hli]
	ld d, a
	push hl
	hlcoord 1, 9
	call PlaceString
	pop hl
	ld a, [hli]                  ; where it comes from
	ld e, a
	ld a, [hli]
	ld d, a
	push hl
	hlcoord 9, 2
	push de
	ld de, .Found
	call PlaceString
	pop de
	hlcoord 9, 3
	call PlaceString
	pop hl
	ld a, [hli]                  ; what makes it special
	ld e, a
	ld d, [hl]
	hlcoord 1, 11
	call PlaceString
	ld a, [wCurPartySpecies]
	call PlayCry
.wait
	jp WaitForTextScrollButtonPress
.Found
	db "FOUND AT:@"
.NotYet
	db "Not collected yet.@"

; A fully black shadow of the 56x56 pic in vFrontPic. Every non-white pixel becomes
; color 3, the darkest shade. Then every pixel with an opaque pixel on both sides
; horizontally AND vertically does too: a pic's body is mostly color 0, the same as
; the background, so this is what makes it solid. Unlike a flood fill, it does not
; leak through a gap in the outline, and an open concave pocket stays open.
;
; The screen is whited out here, so the LCD can go off unseen, which also opens all
; of VRAM. Each row's and column's first and last opaque pixel go in vBackPic, which
; nothing draws from on this screen: ReloadMapData restores its tiles on leaving
; (wTempPic would be wrong, it shares wOverworldMap). About 6 frames.
DEF PIC_PIXELS EQU PIC_WIDTH * 8
DEF SHADOW_ROW_MIN EQUS "vBackPic"
DEF SHADOW_COL_MIN EQUS "(vBackPic + 2 * PIC_PIXELS)"
	ASSERT HIGH(vBackPic) == HIGH(vBackPic + 4 * PIC_PIXELS - 1), "indexed by low byte alone"

SpecialShadowPic:
	call DisableLCD
	ld hl, vFrontPic
	ld bc, PIC_SIZE * 8          ; 8 rows per tile, 2 bytes per row
.flatten
	ld a, [hli]
	or [hl]
	ld [hld], a
	ld [hli], a
	inc hl
	dec bc
	ld a, b
	or c
	jr nz, .flatten
	ld hl, SHADOW_ROW_MIN        ; rows, then columns: min = $ff, max = 0
	ld c, 2
.clearArrays
	ld b, PIC_PIXELS
	ld a, $ff
.clearMin
	ld [hli], a
	dec b
	jr nz, .clearMin
	ld b, PIC_PIXELS
	xor a
.clearMax
	ld [hli], a
	dec b
	jr nz, .clearMax
	dec c
	jr nz, .clearArrays
	ld b, 0
	call .eachPixel              ; measure
	ld b, 1
	call .eachPixel              ; fill
	jp EnableLCD

; Column by column, as the tiles are laid out. e = x, d = its bit, c = y,
; hl -> the pixel's first plane; b = 0 measures, 1 fills.
.eachPixel
	ld hl, vFrontPic
	ld e, 0
.tileColumn
	ld d, $80
.column
	push hl
	ld c, 0
.pixel
	bit 0, b
	jr nz, .tryFill
	ld a, [hl]
	and d
	call nz, .measure
	jr .nextPixel
.tryFill
	call .fill
.nextPixel
	inc hl
	inc hl
	inc c
	ld a, c
	cp PIC_PIXELS
	jr nz, .pixel
	pop hl
	inc e
	srl d
	jr nz, .column
	push bc
	ld bc, PIC_HEIGHT tiles
	add hl, bc
	pop bc
	ld a, e
	cp PIC_PIXELS
	jr nz, .tileColumn
	ret

; x and y only ascend, so the first hit is the min and the latest is the max.
.measure
	push hl
	ld h, HIGH(vBackPic)
	ld a, LOW(SHADOW_ROW_MIN)
	add c
	ld l, a
	ld a, [hl]
	inc a
	jr nz, .rowSeen
	ld [hl], e
.rowSeen
	ld a, PIC_PIXELS
	add l
	ld l, a
	ld [hl], e
	ld a, LOW(SHADOW_COL_MIN)
	add e
	ld l, a
	ld a, [hl]
	inc a
	jr nz, .columnSeen
	ld [hl], c
.columnSeen
	ld a, PIC_PIXELS
	add l
	ld l, a
	ld [hl], c
	pop hl
	ret

.fill
	push hl
	ld h, HIGH(vBackPic)
	ld a, LOW(SHADOW_ROW_MIN)
	add c
	ld l, a
	ld a, e
	cp [hl]
	jr c, .outside
	jr z, .outside               ; on the edge: already opaque
	ld a, PIC_PIXELS
	add l
	ld l, a
	ld a, e
	cp [hl]
	jr nc, .outside
	ld a, LOW(SHADOW_COL_MIN)
	add e
	ld l, a
	ld a, c
	cp [hl]
	jr c, .outside
	jr z, .outside
	ld a, PIC_PIXELS
	add l
	ld l, a
	ld a, c
	cp [hl]
	jr nc, .outside
	pop hl
	ld a, [hl]
	or d
	ld [hli], a
	ld [hld], a
	ret
.outside
	pop hl
	ret

SpecialUnknownName:
	db "?????@"

INCLUDE "data/pokemon/special_collection.asm"
