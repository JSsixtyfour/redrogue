UpdateSpriteFacingOffsetAndDelayMovement::
	; This runs on hCurrentSpriteOffset, which is a leftover from the per-frame
	; sprite update loop (_UpdateSprites) - the last/highest slot processed, NOT
	; necessarily the sprite the player is interacting with. If that slot holds
	; an off-screen/unloaded sprite (IMAGEINDEX = $ff), skip: putting it into
	; delayed-movement status (2) makes UpdateNPCSprite route to
	; UpdateSpriteMovementDelay, which skips InitializeSpriteScreenPosition, so
	; the sprite is drawn visible-but-unpositioned until the delay drains (the
	; Victory Road boulder ghost). A talked-to sprite is always visible
	; (interaction skips $ff sprites), so this never changes a real interaction.
	ld h, HIGH(wSpriteStateData1)
	ldh a, [hCurrentSpriteOffset]
	add SPRITESTATEDATA1_IMAGEINDEX
	ld l, a
	ld a, [hl]
	inc a
	ret z ; invisible sprite -> don't delay it
	ld h, HIGH(wSpriteStateData2)
	ldh a, [hCurrentSpriteOffset]
	add $8
	ld l, a
	ld a, $7f ; maximum movement delay
	ld [hl], a ; x#SPRITESTATEDATA2_MOVEMENTDELAY
	dec h ; HIGH(wSpriteStateData1)
	ldh a, [hCurrentSpriteOffset]
	add $9
	ld l, a
	ld a, [hld] ; x#SPRITESTATEDATA1_FACINGDIRECTION
	ld b, a
	xor a
	ld [hld], a ; x#SPRITESTATEDATA1_ANIMFRAMECOUNTER
	ld [hl], a ; x#SPRITESTATEDATA1_INTRAANIMFRAMECOUNTER
	ldh a, [hCurrentSpriteOffset]
	add SPRITESTATEDATA1_IMAGEINDEX
	ld l, a
	ld a, [hl] ; x#SPRITESTATEDATA1_IMAGEINDEX
	or b ; or in the facing direction
	ld [hld], a
	ld a, $2 ; delayed movement status
	ld [hl], a ; x#SPRITESTATEDATA1_MOVEMENTSTATUS
	ret
