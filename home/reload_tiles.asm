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
	ldh [hNoWaitAfterText], a
	ret

; Load a follower sprite into VRAM slot 1 (standing + walking tile areas).
; Safe to call from any ROM bank -- runs from HOME bank, handles bank switch internally.
; INPUT: a = ROM bank containing sprite, hl = sprite data address (24 tiles, 384 bytes)
; Copies tiles 0-11 (standing) to $80C0, tiles 12-23 (walking) to $88C0.
LoadFollowerSprite::
	call BankswitchHome         ; switch to sprite bank (a), saves current bank
	ld de, $80C0                ; VRAM slot 1 standing tiles
	ld bc, 12 * 16
.copyStanding
	ld a, [hli]
	ld [de], a
	inc de
	dec bc
	ld a, b
	or c
	jr nz, .copyStanding
	ld de, $88C0                ; VRAM slot 1 walking tiles
	ld bc, 12 * 16
.copyWalking
	ld a, [hli]
	ld [de], a
	inc de
	dec bc
	ld a, b
	or c
	jr nz, .copyWalking
	jp BankswitchBack           ; restore original bank and return
