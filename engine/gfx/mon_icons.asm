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
	cp YELLOW_LEGACY_ICON_VRAM_TILE
	jr nc, .uniqueIcon
	ld c, ICONOFFSET
	cp ICON_BALL << 2
	jr z, .editCoords
	cp ICON_HELIX << 2
	jr nz, .editTileIDS
; ICON_BALL and ICON_HELIX only shake up and down
.editCoords
	dec hl
	dec hl ; dec hl to the OAM y coord
	ld c, $1 ; amount to increase the y coord by
; otherwise, load a second sprite frame
.editTileIDS
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
.uniqueIcon
	; The streamed icons store four tiles per frame contiguously.
	ld c, 4
	jr .editTileIDS

; Party mon animations cycle between 2 frames.
; The members of the PartyMonSpeeds array specify the number of V-blanks
; that each frame lasts for green HP, yellow HP, and red HP in order.
; On the naming screen, the yellow HP speed is always used.
PartyMonSpeeds:
	db 5, 16, 32

LoadMonPartySpriteGfx:
; Load mon party sprite tile patterns into VRAM during V-blank.
	ld hl, MonPartySpritePointers
	ld a, $20
	call LoadAnimSpriteGfx
	ld a, [wMonPartySpriteSpecies]
	call GetYellowLegacyUniqueIcon
	ret nc
	ld d, h
	ld e, l
	ld hl, vSprites tile YELLOW_LEGACY_ICON_VRAM_TILE
	ld b, a
	ld c, 8
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

DEF YELLOW_LEGACY_ICON_VRAM_TILE EQU $80
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
	ld hl, MonPartySpritePointers
	ld a, $20
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
	push de
	ld a, [hli]
	ld c, a
	swap c
	ld b, $0
	ld a, [hli]
	ld e, [hl]
	inc hl
	ld d, [hl]
	pop hl
	call FarCopyData2
	pop hl
	pop bc
	ld a, $6
	add c
	ld c, a
	pop af
	dec a
	jr nz, .loop
	call LoadYellowLegacyPartyIcons
	jp EnableLCD

; Stream supported icons into a stable eight-tile range for each party slot.
; The category atlas remains resident for every unsupported species.
LoadYellowLegacyPartyIcons:
	ld hl, wPartySpecies
	xor a
.loop
	ldh [hPartyMonIndex], a
	ld a, [hli]
	cp $ff
	ret z
	push hl
	call LoadYellowLegacyPartyIcon
	pop hl
	ldh a, [hPartyMonIndex]
	inc a
	jr .loop

LoadYellowLegacyPartyIcon:
	call GetYellowLegacyUniqueIcon
	ret nc
	push af
	push hl
	ld hl, vSprites tile YELLOW_LEGACY_ICON_VRAM_TILE
	ld bc, YELLOW_LEGACY_ICON_SLOT_TILES tiles
	ldh a, [hPartyMonIndex]
	call AddNTimes
	ld d, h
	ld e, l
	pop hl
	pop af
	ld bc, 8 tiles
	jp FarCopyData

; Party reorder leaves the category atlas intact, so only the streamed slots
; need refreshing while the menu remains active.
ReloadYellowLegacyPartyIcons::
	ld hl, wPartySpecies
	xor a
.loop
	ldh [hPartyMonIndex], a
	ld a, [hli]
	cp $ff
	ret z
	push hl
	call GetYellowLegacyUniqueIcon
	jr nc, .next
	ld d, h
	ld e, l
	ld hl, vSprites tile YELLOW_LEGACY_ICON_VRAM_TILE
	ld bc, YELLOW_LEGACY_ICON_SLOT_TILES tiles
	ldh a, [hPartyMonIndex]
	call AddNTimes
	; Recover the source through the resolver after calculating the destination.
	push hl
	ldh a, [hPartyMonIndex]
	ld hl, wPartySpecies
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hl]
	call GetYellowLegacyUniqueIcon
	ld d, h
	ld e, l
	pop hl
	ld b, a
	ld c, 8
	call CopyVideoData
.next
	pop hl
	ldh a, [hPartyMonIndex]
	inc a
	jr .loop

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
	ld [wOAMBaseTile], a
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
	ld [wOAMBaseTile], a
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
