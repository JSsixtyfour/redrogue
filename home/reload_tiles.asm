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

; Load all 24 follower sprite tiles into VRAM (Yellow: Pikachu at slot 2, $80C0).
; IMAGEBASEOFFSET=2 → tile base = (2-1)*12 = $0C → VRAM $80C0.
; If LCD is OFF: direct copy (fast) — used at map entry / ReloadMapSpriteTilePatterns.
; If LCD is ON:  CopyVideoData (HBlank-safe) — used after text/menu close.
; Standing tiles → $80C0 (IMAGEBASEOFFSET=2: vNPCSprites + 1*$C0)
; Walking  tiles → $88C0 ($80C0 + $800)
; INPUT: a = ROM bank, hl = sprite data address (24-tile sprite, 384 bytes)
LoadFollowerSprite::
	ld b, a                 ; b = ROM bank (preserved across LCD check)
	ldh a, [rLCDC]
	bit B_LCDC_ENABLE, a
	jr nz, .lcdOn

.lcdOff ; direct copy — safe when LCD is disabled
	ld a, b
	call BankswitchHome
	ld de, $80C0            ; slot 2 standing tiles (IMAGEBASEOFFSET=2, tile $0C)
	ld bc, 12 * 16
.copyStanding
	ld a, [hli]
	ld [de], a
	inc de
	dec bc
	ld a, b
	or c
	jr nz, .copyStanding
	ld de, $88C0            ; slot 2 walking tiles ($80C0 + $800)
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

.lcdOn ; CopyVideoData (HBlank-safe) for both standing and walking tiles
	ld d, h
	ld e, l                 ; de = sprite source start
	push de                 ; save for walking tiles calculation
	push bc                 ; save b (ROM bank) across first CopyVideoData call
	ld hl, $80C0            ; slot 2 standing VRAM
	ld c, 12                ; 12 tiles
	call CopyVideoData      ; b=bank, c=12, de=source, hl=dest
	pop bc                  ; restore b = ROM bank
	pop de                  ; restore de = sprite source start
	ld a, e
	add 12 * 16             ; advance source by $C0 bytes (12 standing tiles)
	ld e, a
	jr nc, .noCarry
	inc d
.noCarry
	ld hl, $88C0            ; slot 2 walking VRAM
	ld c, 12
	jp CopyVideoData        ; tail call — b still holds ROM bank

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
