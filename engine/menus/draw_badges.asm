DrawBadges:
; Draw 4x2 gym leader faces, with the faces replaced by
; badges if they are owned. Used in the player status screen.

; In Japanese versions, names are displayed above faces.
; Instead of removing relevant code, the name graphics were erased.
; However, I removed this as per the Pret Tutorial

; Tile ids for face/badge graphics.
	ld de, wBadgeOrFaceTiles
	ld hl, .FaceBadgeTiles
	ld bc, NUM_BADGES
	call CopyData

; Booleans for each badge.
	ld hl, wTempObtainedBadgesBooleans
	ld bc, NUM_BADGES
	xor a
	call FillMemory

; Alter these based on owned badges.
; The mask is per SLOT, not per badge bit: DrawTrainerInfo has already blitted
; wBadgeSlotOrder[i]'s block into VRAM slot i, and slots fill in defeat order
; while badge bits are set in scattered order. Returned in e because farcall
; destroys a/b/c/h/l on both sides. Done before de/hl are loaded for that reason.
	farcall RogueCardEarnedSlotMask
	ld b, e
	ld de, wTempObtainedBadgesBooleans
	ld hl, wBadgeOrFaceTiles
	ld c, NUM_BADGES
.CheckBadge
	srl b
	jr nc, .NextBadge
	ld a, [hl]
	add 4 ; Badge graphics are after each face
	ld [hl], a
	ld a, 1
	ld [de], a
.NextBadge
	inc hl
	inc de
	dec c
	jr nz, .CheckBadge

; Which slot, if any, draws the revealed leader's name. Asked for here rather
; than handed over by RogueBlitCardBadges, which already knows: wBadgeNameTile
; shares a UNION with wTrainerInfoTextBoxWidth, and DrawTrainerInfo writes that
; AFTER the blit, so a value left there would not survive to this point.
; Returned in e because farcall destroys a/b/c/h/l on both sides.
	farcall RogueCardRevealedSlotForDraw

; Draw two rows of badges.
	ld hl, wBadgeNumberTile
	ld a, $d8 ; [1]
	ld [hli], a
	ld [hl], e ; wBadgeNameTile: counts down to 0 on the revealed slot

	hlcoord 2, 11
	ld de, wTempObtainedBadgesBooleans
	call .DrawBadgeRow

	hlcoord 2, 14
	ld de, wTempObtainedBadgesBooleans + 4
	; fallthrough

.DrawBadgeRow
; Draw 4 badges.

	ld c, 4
.DrawBadge
	push de
	push hl

; Badge no.
	ld a, [wBadgeNumberTile]
	ld [hli], a
	inc a
	ld [wBadgeNumberTile], a

; hl is now the name column. wBadgeNameTile counts down one per slot from the
; revealed slot index, so it reads 0 on exactly that cell; $FF means "no reveal"
; and cannot reach 0 in eight steps. The `inc a` restores the pre-decrement
; value AND sets Z from it, which is the whole test.
	ld a, [wBadgeNameTile]
	dec a
	ld [wBadgeNameTile], a
	inc a
	jr nz, .noName
	push hl
	ld a, CARD_NAME_VRAM_TILE
	ld [hli], a
	inc a
	ld [hli], a
	inc a
	ld [hl], a
	pop hl
.noName
	inc hl

.PlaceBadge
	ld de, SCREEN_WIDTH - 1
	add hl, de
	ld a, [wBadgeOrFaceTiles]
	call .PlaceTiles
	add hl, de
	call .PlaceTiles

; Shift badge array back one byte.
	push bc
	ld hl, wBadgeOrFaceTiles + 1
	ld de, wBadgeOrFaceTiles
	ld bc, NUM_BADGES
	call CopyData
	pop bc

	pop hl
	ld de, 4
	add hl, de

	pop de
	inc de
	dec c
	jr nz, .DrawBadge
	ret

.PlaceTiles
	ld [hli], a
	inc a
	ld [hl], a
	inc a
	ret

.FaceBadgeTiles
	db $20, $28, $30, $38, $40, $48, $50, $58

; GymLeaderFaceAndBadgeTileGraphics moved out of this file, and out of bank $03,
; on 2026-09-10 (Phase 1c). The sheet grew from 8 leader blocks to 17 and no
; longer fits here: the pinned "bank3" section had 542 bytes left inside its own
; span against a 1,152-byte growth. It is pure data, blitted by DrawTrainerInfo
; through an explicit BANK() + FarCopyData2, so it is bank-independent.
; It now lives in gfx/trainer_card_art.asm, bank $3C.
