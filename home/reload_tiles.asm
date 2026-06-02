; reloads text box tile patterns, current map view, and tileset tile patterns
ReloadMapData::
	ldh a, [hLoadedROMBank]
	push af
	ldh a, [hCurMap]
	call SwitchToMapRomBank
	call DisableLCD
	call LoadTextBoxTilePatterns
	call LoadCurrentMapView
	call LoadTilesetTilePatternData
	call EnableLCD
	pop af
	ldh [hLoadedROMBank], a
	ld [rROMB], a
	ret

; reloads tileset tile patterns
ReloadTilesetTilePatterns::
	ldh a, [hLoadedROMBank]
	push af
	ldh a, [hCurMap]
	call SwitchToMapRomBank
	call DisableLCD
	call LoadTilesetTilePatternData
	call EnableLCD
	pop af
	ldh [hLoadedROMBank], a
	ld [rROMB], a
	ret

; shows the town map and lets the player choose a destination to fly to
ChooseFlyDestination::
	ld hl, wStatusFlags4
	res BIT_NO_BATTLES, [hl]
	farjp LoadTownMap_Fly

; causes the text box to close without waiting for a button press after displaying text
DisableWaitingAfterTextDisplay::
	ld a, $01
	ld [wNoWaitAfterText], a
	ret

; Load all 24 follower sprite tiles into VRAM.
; If LCD is OFF: direct copy (fast) — used at map entry / ReloadMapSpriteTilePatterns.
; If LCD is ON:  CopyVideoData (HBlank-safe, ~2 frames per 12 tiles) — used after text/menu close.
; This mirrors how Yellow's LoadSpriteGraphics handles LCD state.
; Standing tiles → $80C0 (slot 1 standing, always safe from font tiles)
; Walking  tiles → $88C0 (slot 1 walking; font will overwrite, hooks restore them)
; Saves bank+addr to wFollowerSpriteBank/Addr for ReloadFollowerSprite.
; INPUT: a = ROM bank, hl = sprite data address (24-tile sprite, 384 bytes)
LoadFollowerSprite::
	ld [wFollowerSpriteBank], a
	ld a, l
	ld [wFollowerSpriteAddrLo], a
	ld a, h
	ld [wFollowerSpriteAddrHi], a
	ldh a, [rLCDC]
	bit B_LCDC_ENABLE, a
	jr nz, .lcdOn

.lcdOff ; direct copy — safe when LCD is disabled
	ld a, [wFollowerSpriteBank]
	call BankswitchHome
	ld de, $80C0
	ld bc, 12 * 16
.copyStanding
	ld a, [hli]
	ld [de], a
	inc de
	dec bc
	ld a, b
	or c
	jr nz, .copyStanding
	ld de, $88C0
	ld bc, 12 * 16
.copyWalking
	ld a, [hli]
	ld [de], a
	inc de
	dec bc
	ld a, b
	or c
	jr nz, .copyWalking
	jp BankswitchBack

.lcdOn ; direct copy for standing tiles only — fast single-frame write avoids
	; the CopyVideoData multi-frame flicker that corrupts NPC sprites on screen.
	; Walking tiles ($88C0) skipped to avoid corrupting font mid-display.
	ld a, [wFollowerSpriteBank]
	call BankswitchHome
	ld de, $80C0
	ld bc, 12 * 16
.copyStandingLCDOn
	ld a, [hli]
	ld [de], a
	inc de
	dec bc
	ld a, b
	or c
	jr nz, .copyStandingLCDOn
	jp BankswitchBack

; If a follower is active, reload its sprite into VRAM slots 1 ($80C0 + $88C0).
; Must be called after any map sprite reload since those overwrite slot 1.
; Uses Bankswitch to call FollowerSelectSprite (bank 3) from here (HOME bank).
ReloadFollowerSprite::
	ld a, [wFollowerActive]
	and a
	ret z
	ld hl, FollowerSelectSprite
	ld b, BANK(FollowerSelectSprite)
	jp Bankswitch
