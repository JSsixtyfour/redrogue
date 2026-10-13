; Enemy send-out and party-menu reload share the normal front-pic loader.
LoadEnemyFrontSprite::
	call LoadMonFrontSprite
	; fall through

; Match the player's fusion diagonal without borrowing vBackPic (the player's
; live sprite). Stage the secondary in the existing SRAM sprite buffers and
; overwrite only the six lower-right column runs of the primary in vFrontPic.
; AnimationFlashMonPic also calls this after restoring the normal picture.
; Transform keeps its replacement picture, even when the original was fused.
MergeFinalAIFusionFrontPic::
	ldh a, [hIsInBattle]
	cp 2
	ret nz
	ld a, [wTrainerClass]
	cp FINAL_AI
	ret nz
	ld a, [wEnemyBattleStatus3]
	bit TRANSFORMED, a
	ret nz
	ld a, [wEnemyMonCatchRate]
	bit BIT_FUSION, a
	ret z
	ld a, [wFinalAISecondarySpecies]
	and a
	ret z
	ld a, [wCurPartySpecies]
	push af
	ld a, [wCurSpecies]
	push af
	ld a, [wFinalAISecondaryForm]
	ld [wFormContextForm], a
	ld a, [wFinalAISecondarySpecies]
	ld [wFormContextSpecies], a
	ld [wCurPartySpecies], a
	ld [wCurSpecies], a
	call GetMonHeader
	; InterlaceMergeSpriteBuffers already produces its final 2bpp image here.
	; Its final CopyVideoData is an in-place copy, leaving VRAM untouched.
	ld de, sSpriteBuffer1
	call LoadMonFrontSprite
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	xor a
	ld [rRAMB], a
	ld hl, vFrontPic + 13 * TILE_SIZE
	ld de, sSpriteBuffer1 + 13 * TILE_SIZE
	ld c, 1
.column
	ldh a, [hLoadedROMBank]
	ld b, a
	call CopyVideoData
	ld a, l
	add 6 * TILE_SIZE
	ld l, a
	jr nc, .destReady
	inc h
.destReady
	ld a, e
	add 6 * TILE_SIZE
	ld e, a
	jr nc, .sourceReady
	inc d
.sourceReady
	inc c
	ld a, c
	cp 7
	jr nz, .column
	pop af
	ld [wCurSpecies], a
	pop af
	ld [wCurPartySpecies], a
	ld hl, wEnemyMon
	call PublishFormContext
	jp GetMonHeader

; animates the mon "growing" out of the pokeball
AnimateSendingOutMon:
	ld a, [wPredefHL]
	ld h, a
	ld a, [wPredefHL + 1]
	ld l, a
	ldh a, [hStartTileID]
	ldh [hBaseTileID], a
	ld b, $4c
	ldh a, [hIsInBattle]
	and a
	jr z, .notInBattle
	add b
	ld [hl], a
	call Delay3
	ld bc, -(SCREEN_WIDTH * 2 + 1)
	add hl, bc
	ld a, 1
	ld [wDownscaledMonSize], a
	lb bc, 3, 3
	predef CopyDownscaledMonTiles
	ld c, 4
	call DelayFrames
	ld bc, -(SCREEN_WIDTH * 2 + 1)
	add hl, bc
	xor a
	ld [wDownscaledMonSize], a
	lb bc, 5, 5
	predef CopyDownscaledMonTiles
	ld c, 5
	call DelayFrames
	ld bc, -(SCREEN_WIDTH * 2 + 1)
	jr .next
.notInBattle
	ld bc, -(SCREEN_WIDTH * 6 + 3)
.next
	add hl, bc
	ldh a, [hBaseTileID]
	add $31
	jr CopyUncompressedPicToHL

CopyUncompressedPicToTilemap:
	ld a, [wPredefHL]
	ld h, a
	ld a, [wPredefHL + 1]
	ld l, a
	ldh a, [hStartTileID]
CopyUncompressedPicToHL::
	lb bc, 7, 7
	ld de, SCREEN_WIDTH
	push af
	ld a, [wSpriteFlipped]
	and a
	jr nz, .flipped
	pop af
.loop
	push bc
	push hl
.innerLoop
	ld [hl], a
	add hl, de
	inc a
	dec c
	jr nz, .innerLoop
	pop hl
	inc hl
	pop bc
	dec b
	jr nz, .loop
	ret

.flipped
	push bc
	ld b, 0
	dec c
	add hl, bc
	pop bc
	pop af
.flippedLoop
	push bc
	push hl
.flippedInnerLoop
	ld [hl], a
	add hl, de
	inc a
	dec c
	jr nz, .flippedInnerLoop
	pop hl
	dec hl
	pop bc
	dec b
	jr nz, .flippedLoop
	ret

LoadMonBackPic:
; Assumes the monster's attributes have
; been loaded with GetMonHeader.
	ld a, [wBattleMonSpecies2]
	ld [wCurPartySpecies], a
	hlcoord 1, 5
	ld b, 7
	ld c, 8
	call ClearScreenArea
	ld hl, wMonHBackSprite - wMonHeader
	call UncompressMonSprite
	predef ScaleSpriteByTwo
	ld de, vBackPic
	call InterlaceMergeSpriteBuffers ; combine the two buffers to a single 2bpp sprite
	ld hl, vSprites
	ld de, vBackPic
	ld c, (2 * SPRITEBUFFERSIZE) / TILE_SIZE ; count of 16-byte chunks to be copied
	ldh a, [hLoadedROMBank]
	ld b, a
	; The source is VRAM, which the HBlank copier cannot read safely.
	jp CopyVideoDataPaced
