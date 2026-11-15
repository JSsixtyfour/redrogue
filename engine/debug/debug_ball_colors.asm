; Standalone, unsaved CGB palette workbench entered from the title debug menu.
; It owns wTileMapBackup while open: RGB[3], selected channel, gamma, then
; 24 bytes at +8 for three OBJ palettes. No screen-backup consumer runs here.
; FarCopyData uses wBuffer, PrintNumber uses its normal number scratch, and
; GBCGamma uses wRGB; none overlap this private screen-lifetime workspace.
; Opt in with make ball_colors; ordinary debug builds omit the entire screen.
IF DEF(_DEBUG) && DEF(_BALL_COLORS)
SECTION "Debug Ball Colors", ROMX, BANK[$10]

DEF DBC_RGB EQUS "wTileMapBackup"
DEF DBC_CHANNEL EQUS "wTileMapBackup + 3"
DEF DBC_GAMMA EQUS "wTileMapBackup + 4"
DEF DBC_PALS EQUS "wTileMapBackup + 8"

DebugBallColors::
	ldh a, [hGBC]
	and a
	ret z
	ld a, [wOptions2]
	push af
	set BIT_ENHANCED_COLORS, a
	ld [wOptions2], a
	ld a, [wOptions3]
	push af
	ldh a, [hUpdateSpritesEnabled]
	push af
	ld a, $ff ; leave our explicit OAM alone, including on the first VBlank
	ldh [hUpdateSpritesEnabled], a
	ldh a, [rLCDC]
	push af
	call ClearSprites
	call ClearScreen
	xor a
	ld [DBC_CHANNEL], a
	ld [DBC_GAMMA], a
	call DebugBallColorsReset
	call DisableLCD
	xor a
	ldh [rVBK], a
	ld a, BANK(PokeBallSprite)
	ld hl, PokeBallSprite
	ld de, vChars0
	ld bc, 4 tiles
	call FarCopyData
	ld hl, DebugBallColorsOAM
	ld de, wShadowOAM
	ld bc, DebugBallColorsOAM.end - DebugBallColorsOAM
	call CopyData
	; This dedicated screen uses bank-0 graphics and palette 0 for all BG cells.
	ld a, 1
	ldh [rVBK], a
	ld hl, vBGMap0
	ld bc, 2 * TILEMAP_AREA
	xor a
	call FillMemory
	xor a
	ldh [rVBK], a
	ldh a, [rLCDC]
	res B_LCDC_OBJ_SIZE, a ; four 8x8 tiles per ball, as in the overworld
	set B_LCDC_OBJS, a
	ldh [rLCDC], a
	call EnableLCD
	call DebugBallColorsDraw
.input
	call DelayFrame
	call JoypadLowSensitivity
	ldh a, [hJoy5]
	bit B_PAD_B, a
	jp nz, .exit
	bit B_PAD_START, a
	jr z, .notReset
	call DebugBallColorsReset
	jr .redraw
.notReset
	bit B_PAD_A, a
	jr z, .notGamma
	ld a, [DBC_GAMMA]
	xor 1
	ld [DBC_GAMMA], a
	jr .redraw
.notGamma
	ld b, a
	ld a, [DBC_CHANNEL]
	bit B_PAD_DOWN, b
	jr z, .notDown
	inc a
	cp 3
	jr c, .channel
	xor a
	jr .channel
.notDown
	bit B_PAD_UP, b
	jr z, .value
	dec a
	cp $ff
	jr nz, .channel
	ld a, 2
.channel
	ld [DBC_CHANNEL], a
	jr .redraw
.value
	ld e, a
	ld d, 0
	ld hl, DBC_RGB
	add hl, de
	ld a, [hl]
	bit B_PAD_RIGHT, b
	jr z, .notRight
	inc a
	jr .store
.notRight
	bit B_PAD_LEFT, b
	jr z, .input
	dec a
.store
	and 31
	ld [hl], a
.redraw
	call DebugBallColorsDraw
	jr .input
.exit
	call ClearSprites
	call DelayFrame ; upload hidden OAM before restoring the original sprite mode
	pop af
	ldh [rLCDC], a
	pop af
	ldh [hUpdateSpritesEnabled], a
	pop af
	ld [wOptions3], a
	pop af
	ld [wOptions2], a
	call RunDefaultPaletteCommand
	ret

DebugBallColorsReset:
	; Seed from the current real Master top, so later palette edits stay in sync.
	ld a, BANK(BallRarityPalettes)
	ld hl, BallRarityPalettes + 2 * PAL_SIZE + 2
	ld de, DBC_RGB
	ld bc, 2
	call FarCopyData
	ld a, [DBC_RGB]
	ld e, a
	ld a, [DBC_RGB + 1]
	ld d, a
	farcall GetRGB
	ld hl, wRGB
	ld de, DBC_RGB
	ld bc, 3
	jp CopyData

DebugBallColorsDraw:
	; The title menu is double-spaced. Our labels, values, and help are not.
	; Own this setting explicitly, then restore it before returning.
	ldh a, [hUILayoutFlags]
	push af
	set BIT_SINGLE_SPACED_LINES, a
	ldh [hUILayoutFlags], a
	; Blanking the old digits prevents 10 -> 9 leaving a stale tens digit.
	; Keep the screen visible while editing instead of clearing it each tick.
	hlcoord 3, 7
	ld a, ' '
	ld [hl], a
	ld [wTileMap + 8 * SCREEN_WIDTH + 3], a
	ld [wTileMap + 9 * SCREEN_WIDTH + 3], a
	hlcoord 9, 7
	call .blankNumber
	hlcoord 9, 8
	call .blankNumber
	hlcoord 9, 9
	call .blankNumber
	hlcoord 4, 0
	ld de, .title
	call PlaceString
	hlcoord 1, 2
	ld de, .great
	call PlaceString
	hlcoord 7, 2
	ld de, .master
	call PlaceString
	hlcoord 14, 2
	ld de, .ultra
	call PlaceString
	hlcoord 5, 7
	ld de, .channels
	call PlaceString
	hlcoord 9, 7
	ld de, DBC_RGB
	lb bc, 1, 2
	call PrintNumber
	hlcoord 9, 8
	ld de, DBC_RGB + 1
	lb bc, 1, 2
	call PrintNumber
	hlcoord 9, 9
	ld de, DBC_RGB + 2
	lb bc, 1, 2
	call PrintNumber
	hlcoord 3, 7
	ld a, [DBC_CHANNEL]
	ld de, SCREEN_WIDTH
.cursor
	and a
	jr z, .cursorDone
	add hl, de
	dec a
	jr .cursor
.cursorDone
	ld [hl], '▶'
	hlcoord 1, 11
	ld de, .gammaOff
	ld a, [DBC_GAMMA]
	and a
	jr z, .gammaLabel
	ld de, .gammaOn
.gammaLabel
	call PlaceString
	hlcoord 1, 13
	ld de, .help
	call PlaceString
	pop af
	ldh [hUILayoutFlags], a
	jp DebugBallColorsPalettes
.blankNumber
	ld [hli], a
	ld [hl], a
	ret
.title: db "BALL COLORS@"
.great: db "GREAT@"
.master: db "MASTER@"
.ultra: db "ULTRA@"
.channels:
	db "R"
	next "G"
	next "B@"
.gammaOff: db "A: GAMMA OFF@"
.gammaOn: db "A: GAMMA ON @"
.help:
	db "UP/DOWN: CHANNEL"
	next "LEFT/RIGHT: VALUE"
	next "START: RESET"
	next "B: BACK@"

DebugBallColorsPalettes:
	ld a, BANK(BallRarityPalettes)
	ld hl, BallRarityPalettes
	ld de, DBC_PALS
	ld bc, 3 * PAL_SIZE
	call FarCopyData
	; Encode the candidate using the same helper as the production gamma path.
	ld hl, DBC_RGB
	ld de, wRGB
	ld bc, 3
	call CopyData
	ld de, 0
	farcall WriteRGB
	ld hl, DBC_PALS + 2 * PAL_SIZE + 2
	ld [hl], e
	inc hl
	ld [hl], d
	; Apply overworld OBP0's 3,1,0,0 mapping to the physical OBJ palette:
	; shade 1 -> white, shade 2 -> colored top, shade 3 -> outline.
	ld hl, DBC_PALS
	ld b, 3
.map
	ld a, [hli]
	ld e, a
	ld a, [hli]
	ld d, a
	ld a, [hl]
	ld [hl], e
	inc hl
	ld c, [hl]
	ld [hl], d
	inc hl
	ld [hli], a
	ld [hl], c
	inc hl
	inc hl
	inc hl
	dec b
	jr nz, .map
	ld hl, wOptions3
	res BIT_GBC_GAMMA, [hl]
	ld a, [DBC_GAMMA]
	and a
	jr z, .upload
	set BIT_GBC_GAMMA, [hl]
	ld hl, DBC_PALS
	ld b, 12
.gamma
	ld a, [hli]
	ld e, a
	ld a, [hld]
	ld d, a
	push hl
	push bc
	predef GBCGamma
	pop bc
	pop hl
	ld [hl], e
	inc hl
	ld [hl], d
	inc hl
	dec b
	jr nz, .gamma
.upload
	; Start at the beginning of a fresh VBlank, with interrupts masked for
	; this short 24-byte transfer. No palette port accesses during mode 3.
	di
.visible
	ldh a, [rLY]
	cp LY_VBLANK
	jr nc, .visible
.vblank
	ldh a, [rLY]
	cp LY_VBLANK
	jr c, .vblank
	ld a, BGPI_AUTOINC
	ldh [rOCPS], a
	ld hl, DBC_PALS
	ld b, 3 * PAL_SIZE
.copy
	ld a, [hli]
	ldh [rOCPD], a
	dec b
	jr nz, .copy
	ei
	ret

; The source sheet is row-major: TL, TR, BL, BR. Physical palette indices
; are Great=0, Ultra=1, Master=2; screen order is Great, Master, Ultra.
DebugBallColorsOAM:
	db 48, 24, 0, 0, 48, 32, 1, 0, 56, 24, 2, 0, 56, 32, 3, 0
	db 48, 72, 0, 2, 48, 80, 1, 2, 56, 72, 2, 2, 56, 80, 3, 2
	db 48, 128, 0, 1, 48, 136, 1, 1, 56, 128, 2, 1, 56, 136, 3, 1
.end
DebugBallColorsEnd::
ENDC
