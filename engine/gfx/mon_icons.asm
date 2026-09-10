AnimatePartyMon_ForceSpeed1:
	xor a
	ldh [hCurrentMenuItem], a
	ld b, a
	inc a
	jr GetAnimationSpeed

; wPartyMenuHPBarColors contains the party mon's health bar colors
; 0: green
; 1: yellow
; 2: red
AnimatePartyMon::
	ld hl, wPartyMenuHPBarColors
	ldh a, [hCurrentMenuItem]
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hl]

GetAnimationSpeed:
	ld c, a
	ld hl, PartyMonSpeeds
	add hl, bc
	ld a, [wOnSGB]
	xor $1
	add [hl]
	ld c, a
	add a
	ld b, a
	ld a, [wAnimCounter]
	and a
	jr z, .resetSprites
	cp c
	jr z, .animateSprite
.incTimer
	inc a
	cp b
	jr nz, .skipResetTimer
	xor a ; reset timer
.skipResetTimer
	ld [wAnimCounter], a
	jp DelayFrame
.resetSprites
	push bc
	ld hl, wMonPartySpritesSavedOAM
	ld de, wShadowOAM
	ld bc, OBJ_SIZE * 4 * PARTY_LENGTH
	call CopyData
	pop bc
	xor a
	jr .incTimer
.animateSprite
	push bc
	ld hl, wShadowOAMSprite00TileID
	ld bc, OBJ_SIZE * 4
	ldh a, [hCurrentMenuItem]
	call AddNTimes
	ld a, [hl]
	and 7
	cp 1
	jr z, .editCoords
	; Every ordinary slot owns four tiles for each animation frame.
	ld c, 4
	jr .editTiles
.editCoords
	dec hl
	dec hl
	ld c, 1
.editTiles
	ld b, 4
	ld de, OBJ_SIZE
.loop
	ld a, [hl]
	add c
	ld [hl], a
	add hl, de
	dec b
	jr nz, .loop
	pop bc
	ld a, c
	jr .incTimer

; Party mon animations cycle between 2 frames.
; The members of the PartyMonSpeeds array specify the number of V-blanks
; that each frame lasts for green HP, yellow HP, and red HP in order.
; On the naming screen, the yellow HP speed is always used.
PartyMonSpeeds:
	db 5, 16, 32

LoadMonPartySpriteGfx:
; Naming and trade screens use the first per-slot icon block.
	xor a
	ldh [hPartyMonIndex], a
	ld a, [wMonPartySpriteSpecies]
	call LoadPartyIconForSpecies
	; Trade's circle occupies the same legacy tiles it used before.
	ld de, TradeBubbleIconGFX
	ld hl, vSprites tile (ICON_TRADEBUBBLE << 2)
	lb bc, BANK(TradeBubbleIconGFX), 4
	call CopyVideoData
	ld de, TradeBubbleIconGFX tile 4
	ld hl, vSprites tile (ICONOFFSET + (ICON_TRADEBUBBLE << 2))
	lb bc, BANK(TradeBubbleIconGFX), 4
	jp CopyVideoData

LoadAnimSpriteGfx:
; Load animated sprite tile patterns into VRAM during V-blank. hl is the address
; of an array of structures that contain arguments for CopyVideoData and a is
; the number of structures in the array.
	ld bc, $0
.loop
	push af
	push bc
	push hl
	add hl, bc
	ld a, [hli]
	ld e, a
	ld a, [hli]
	ld d, a
	ld a, [hli]
	ld c, a
	ld a, [hli]
	ld b, a
	ld a, [hli]
	ld h, [hl]
	ld l, a
	call CopyVideoData
	pop hl
	pop bc
	ld a, $6
	add c
	ld c, a
	pop af
	dec a
	jr nz, .loop
	ret

DEF YELLOW_LEGACY_ICON_VRAM_TILE EQU $00
DEF YELLOW_LEGACY_ICON_SLOT_TILES EQU 8

; Input: a = internal species ID.
; Output when supported: carry set, a = source bank, hl = eight-tile icon.
; Unsupported species return carry clear and continue using the category atlas.
GetYellowLegacyUniqueIcon:
	cp EXEGGUTOR
	jr z, .exeggutor
	cp MEW
	jr z, .mew
	cp JOLTEON
	jr z, .jolteon
	cp DUGTRIO
	jr z, .dugtrio
	cp ARTICUNO
	jr z, .articuno
	cp PIKACHU
	jr z, .pikachu
	and a
	ret
.exeggutor
	ld hl, YellowLegacyIconExeggutor
	jr .found
.mew
	ld hl, YellowLegacyIconMew
	jr .found
.jolteon
	ld hl, YellowLegacyIconJolteon
	jr .found
.dugtrio
	ld hl, YellowLegacyIconDugtrio
	jr .found
.articuno
	ld hl, YellowLegacyIconArticuno
	jr .found
.pikachu
	ld hl, YellowLegacyIconPikachu
.found
	ld a, BANK(YellowLegacyIconExeggutor)
	scf
	ret

LoadMonPartySpriteGfxWithLCDDisabled:
; Load mon party sprite tile patterns into VRAM immediately by disabling the
; LCD.
	call DisableLCD
	call LoadPartyIconsBySlot
	jp EnableLCD

; The guide's slot layout uses exactly tiles $00-$2f. This is below the font at
; $80 and gives each party member four tiles for each of two frames.
LoadPartyIconsBySlot:
	ld hl, wPartySpecies
	xor a
.loop
	ldh [hPartyMonIndex], a
	ld a, [hli]
	cp $ff
	ret z
	push hl
	call LoadPartyIconForSpecies
	pop hl
	ldh a, [hPartyMonIndex]
	inc a
	jr .loop

; Input: a = internal species ID, hPartyMonIndex = destination slot.
LoadPartyIconForSpecies:
	call GetYellowLegacyUniqueIcon
	jr nc, .category
	ld d, h
	ld e, l
	ld b, a
	ld c, 8
	xor a
	jp CopyPartyIconChunk
.category
	call GetPartyMonSpriteID
	cp ICON_MON << 2
	jp z, LoadPartyIconMonster
	cp ICON_BALL << 2
	jp z, LoadPartyIconBall
	cp ICON_HELIX << 2
	jp z, LoadPartyIconHelix
	cp ICON_FAIRY << 2
	jp z, LoadPartyIconFairy
	cp ICON_BIRD << 2
	jp z, LoadPartyIconBird
	cp ICON_WATER << 2
	jp z, LoadPartyIconWater
	cp ICON_BUG << 2
	jp z, LoadPartyIconBug
	cp ICON_GRASS << 2
	jp z, LoadPartyIconGrass
	cp ICON_SNAKE << 2
	jp z, LoadPartyIconSnake
	cp ICON_QUADRUPED << 2
	jp z, LoadPartyIconQuadruped
	cp ICON_PIKACHU << 2
	jp z, LoadPartyIconPikachu
	jp LoadPartyIconChansey

MACRO load_party_icon_chunk
	ld de, \1 tile \2
	lb bc, BANK(\1), \3
	ld a, \4
	call CopyPartyIconChunk
ENDM

; Input: de = source, b = source bank, c = tile count, a = slot offset.
CopyPartyIconChunk:
	push bc
	push de
	push af
	ld hl, vSprites
	ld bc, YELLOW_LEGACY_ICON_SLOT_TILES tiles
	ldh a, [hPartyMonIndex]
	call AddNTimes
	pop af
	ld bc, 1 tiles
	call AddNTimes
	pop de
	pop bc
	ldh a, [rLCDC]
	bit B_LCDC_ENABLE, a
	jr nz, .videoCopy
	; With the LCD off there is no VBlank for CopyVideoData to wait on.
	push hl
	ld h, d
	ld l, e
	pop de
	ld a, b
	ld b, 0
	swap c
	jp FarCopyData
.videoCopy
	jp CopyVideoData

LoadPartyIconMonster:
	load_party_icon_chunk MonsterSprite, 12, 4, 0
	load_party_icon_chunk MonsterSprite, 0, 4, 4
	ret
LoadPartyIconBall:
	; Offset one marks the two legacy shake-only categories for AnimatePartyMon.
	load_party_icon_chunk PokeBallSprite, 0, 4, 1
	ret
LoadPartyIconHelix:
	load_party_icon_chunk PokeBallSprite, 4, 4, 1
	ret
LoadPartyIconFairy:
	load_party_icon_chunk FairySprite, 12, 4, 0
	load_party_icon_chunk FairySprite, 0, 4, 4
	ret
LoadPartyIconBird:
	load_party_icon_chunk BirdSprite, 12, 4, 0
	load_party_icon_chunk BirdSprite, 0, 4, 4
	ret
LoadPartyIconWater:
	load_party_icon_chunk SeelSprite, 0, 4, 0
	load_party_icon_chunk SeelSprite, 12, 4, 4
	ret
LoadPartyIconBug:
	load_party_icon_chunk BugIconFrame2, 0, 1, 0
	load_party_icon_chunk BugIconFrame2, 1, 1, 2
	load_party_icon_chunk BugIconFrame1, 0, 1, 4
	load_party_icon_chunk BugIconFrame1, 1, 1, 6
	ret
LoadPartyIconGrass:
	load_party_icon_chunk PlantIconFrame2, 0, 1, 0
	load_party_icon_chunk PlantIconFrame2, 1, 1, 2
	load_party_icon_chunk PlantIconFrame1, 0, 1, 4
	load_party_icon_chunk PlantIconFrame1, 1, 1, 6
	ret
LoadPartyIconSnake:
	load_party_icon_chunk SnakeIconFrame1, 0, 1, 0
	load_party_icon_chunk SnakeIconFrame1, 1, 1, 2
	load_party_icon_chunk SnakeIconFrame2, 0, 1, 4
	load_party_icon_chunk SnakeIconFrame2, 1, 1, 6
	ret
LoadPartyIconQuadruped:
	load_party_icon_chunk QuadrupedIconFrame1, 0, 1, 0
	load_party_icon_chunk QuadrupedIconFrame1, 1, 1, 2
	load_party_icon_chunk QuadrupedIconFrame2, 0, 1, 4
	load_party_icon_chunk QuadrupedIconFrame2, 1, 1, 6
	ret
LoadPartyIconPikachu:
	load_party_icon_chunk PikachuSprite, 12, 4, 0
	load_party_icon_chunk PikachuSprite, 0, 4, 4
	ret
LoadPartyIconChansey:
	load_party_icon_chunk ChanseySprite, 0, 4, 0
	load_party_icon_chunk ChanseySprite, 0, 4, 4
	ret

; A reorder changes which graphics belong to each eight-tile slot.
ReloadYellowLegacyPartyIcons::
	jp LoadPartyIconsBySlot

INCLUDE "data/icon_pointers.asm"

WriteMonPartySpriteOAMByPartyIndex:
; Write OAM blocks for the party mon in [hPartyMonIndex].
	push hl
	push de
	push bc
	ldh a, [hPartyMonIndex]
	ld hl, wPartySpecies
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hl]
	call GetYellowLegacyUniqueIcon
	jr c, .unique
	ldh a, [hPartyMonIndex]
	ld hl, wPartySpecies
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hl]
	call GetPartyMonSpriteID
	push af
	call GetYellowLegacyPartySlotBaseTile
	ld [wOAMBaseTile], a
	pop af
	call WriteMonPartySpriteOAM
	jr .done
.unique
	call GetYellowLegacyPartySlotBaseTile
	ld [wOAMBaseTile], a
	call WriteYellowLegacyMonPartySpriteOAM
.done
	pop bc
	pop de
	pop hl
	ret

WriteMonPartySpriteOAMBySpecies:
; Write OAM blocks for the party sprite of the species in
; [wMonPartySpriteSpecies].
	xor a
	ldh [hPartyMonIndex], a
	ld a, [wMonPartySpriteSpecies]
	call GetYellowLegacyUniqueIcon
	jr c, .unique
	ld a, [wMonPartySpriteSpecies]
	call GetPartyMonSpriteID
	push af
	xor a
	ld [wOAMBaseTile], a
	pop af
	jr WriteMonPartySpriteOAM
.unique
	ld a, YELLOW_LEGACY_ICON_VRAM_TILE
	ld [wOAMBaseTile], a
	jr WriteYellowLegacyMonPartySpriteOAM

GetYellowLegacyPartySlotBaseTile:
	ldh a, [hPartyMonIndex]
	add a
	add a
	add a
	add YELLOW_LEGACY_ICON_VRAM_TILE
	ret

WriteYellowLegacyMonPartySpriteOAM:
	ld c, $10
	ld h, HIGH(wShadowOAM)
	ldh a, [hPartyMonIndex]
	swap a
	ld l, a
	add $10
	ld b, a
	call WriteAsymmetricMonPartySpriteOAM
	jr CopyMonPartySpriteOAM

WriteMonPartySpriteOAM:
; Write the OAM blocks for the first animation frame into the OAM buffer and
; make a copy at wMonPartySpritesSavedOAM.
	push af
	cp ICON_BALL << 2
	jr z, .markShakeOnly
	cp ICON_HELIX << 2
	jr nz, .setup
.markShakeOnly
	ld hl, wOAMBaseTile
	inc [hl]
.setup
	ld c, $10
	ld h, HIGH(wShadowOAM)
	ldh a, [hPartyMonIndex]
	swap a
	ld l, a
	add $10
	ld b, a
	pop af
	cp ICON_HELIX << 2
	jr z, .helix
	call WriteSymmetricMonPartySpriteOAM
	jr .makeCopy
.helix
	call WriteAsymmetricMonPartySpriteOAM
; Make a copy of the OAM buffer with the first animation frame written so that
; we can flip back to it from the second frame by copying it back.
.makeCopy
	; fallthrough
CopyMonPartySpriteOAM:
	ld hl, wShadowOAM
	ld de, wMonPartySpritesSavedOAM
	ld bc, OBJ_SIZE * 4 * PARTY_LENGTH
	jp CopyData

; Bank-safe Bill's PC entry. A cannot carry the species through farcall because
; Bankswitch replaces it with the destination bank before entering the callee.
GetCurPartyMonSpriteID::
	ld a, [wCurPartySpecies]
	; fallthrough
GetPartyMonSpriteID:
	ld [wPokedexNum], a
	predef IndexToPokedex
	ld a, [wPokedexNum]
	ld c, a
	dec a
	srl a
	ld hl, MonPartyData
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hl]
	bit 0, c ; even or odd?
	jr nz, .skipSwap
	swap a ; use lower nybble if pokedex num is even
.skipSwap
	and $f0
	srl a ; value == ICON constant << 2
	srl a
	ld e, a ; bank-safe return for the Bill's PC BG-icon renderer
	ret

INCLUDE "data/pokemon/menu_icons.asm"

DEF INC_FRAME_1 EQUS "0, $20"
DEF INC_FRAME_2 EQUS "$20, $20"

BugIconFrame1:       INCBIN "gfx/icons/bug.2bpp",       INC_FRAME_1
PlantIconFrame1:     INCBIN "gfx/icons/plant.2bpp",     INC_FRAME_1
BugIconFrame2:       INCBIN "gfx/icons/bug.2bpp",       INC_FRAME_2
PlantIconFrame2:     INCBIN "gfx/icons/plant.2bpp",     INC_FRAME_2
SnakeIconFrame1:     INCBIN "gfx/icons/snake.2bpp",     INC_FRAME_1
QuadrupedIconFrame1: INCBIN "gfx/icons/quadruped.2bpp", INC_FRAME_1
SnakeIconFrame2:     INCBIN "gfx/icons/snake.2bpp",     INC_FRAME_2
QuadrupedIconFrame2: INCBIN "gfx/icons/quadruped.2bpp", INC_FRAME_2

TradeBubbleIconGFX:  INCBIN "gfx/trade/bubble.2bpp"
