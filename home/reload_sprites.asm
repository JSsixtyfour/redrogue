; Copy the current map's sprites' tile patterns to VRAM again after they have
; been overwritten by other tile patterns.
ReloadMapSpriteTilePatterns::
	ld hl, wFontLoaded
	ld a, [hl]
	push af
	res BIT_FONT_LOADED, [hl]
	push hl
	xor a
	ld [wSpriteSetID], a
	call DisableLCD
	farcall InitMapSprites
	call ReloadFollowerSprite    ; all 24 tiles while LCD is off (direct copy, safe)
	call EnableLCD
	pop hl
	pop af
	ld [hl], a
	call LoadPlayerSpriteGraphics
	call LoadFontTilePatterns    ; font overwrites $88C0 walking tiles (accepted)
	jp UpdateSprites

; If a follower is active, reload its sprite into VRAM slot 1.
; Must be called after any map sprite reload since those overwrite slot 1.
; Uses Bankswitch to call FollowerSelectSprite (bank 3) from here (HOME bank).
