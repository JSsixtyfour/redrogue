RestoreScreenTilesAndReloadTilePatterns::
	call ClearSprites
	ld a, $1
	ldh [hUpdateSpritesEnabled], a
	call ReloadMapSpriteTilePatterns
	call LoadScreenTilesFromBuffer2
	call LoadTextBoxTilePatterns
	call RunDefaultPaletteCommand
	jr Delay3

GBPalWhiteOutWithDelay3::
	call GBPalWhiteOut

Delay3::
; The bg map is updated each frame in thirds.
; Wait three frames to let the bg map fully update.
	ld c, 3
	jp DelayFrames

GBPalNormal::
; Reset BGP and OBP0.
	ld a, %11100100 ; 3210
	ldh [rBGP], a
	ld a, %11010000 ; 3100
	ldh [rOBP0], a
	call UpdateGBCPal_BGP
	call UpdateGBCPal_OBP0
	call UpdateGBCPal_OBP1
	ret

GBPalWhiteOut::
; White out all palettes.
	xor a
	ldh [rBGP], a
	ldh [rOBP0], a
	ldh [rOBP1], a
	call UpdateGBCPal_BGP
	call UpdateGBCPal_OBP0
	call UpdateGBCPal_OBP1
	ret

RunDefaultPaletteCommand::
	ld b, SET_PAL_DEFAULT
RunPaletteCommand::
; Shin Red import Phase 3: this early-return used to test wOnSGB alone, which
; made EVERY palette command a no-op on a plain GBC (SGB=0, CGB=1) - the single
; blocking edit for the CGB path. Now runs for either.
; NOTE: do not "optimize" this by ORing the two adjacent flags through hl. hl is
; part of predef_jump's contract (GetPredefPointer stashes it into wPredefHL)
; and b already holds the palette command, so neither register is free here.
	ld a, [wOnSGB]
	and a
	jr nz, .run
	ld a, [wOnCGB]
	and a
	ret z
.run
	predef_jump _RunPaletteCommand

GetHealthBarColor::
; Return at hl the palette of
; an HP bar e pixels long.
	ld a, e
	cp 27
	ld d, 0 ; green
	jr nc, .gotColor
	cp 10
	inc d ; yellow
	jr nc, .gotColor
	inc d ; red
.gotColor
	ld [hl], d
	ret

; Preserve Shin Red's all-register contract while keeping the CGB checks and
; conversion work out of the full HOME section. The three targets live
; together in engine/gfx/palettes.asm.
UpdateGBCPal_BGP::
	push af
	push hl
	ld hl, UpdateGBCPal_BGP_
	jr UpdateGBCPal_Dispatch

UpdateGBCPal_OBP0::
	push af
	push hl
	ld hl, UpdateGBCPal_OBP0_
	jr UpdateGBCPal_Dispatch

UpdateGBCPal_OBP1::
	push af
	push hl
	ld hl, UpdateGBCPal_OBP1_

UpdateGBCPal_Dispatch:
	push bc
	push de
	ld b, BANK(UpdateGBCPal_BGP_)
	ASSERT BANK(UpdateGBCPal_BGP_) == BANK(UpdateGBCPal_OBP0_)
	ASSERT BANK(UpdateGBCPal_BGP_) == BANK(UpdateGBCPal_OBP1_)
	call Bankswitch
	pop de
	pop bc
	pop hl
	pop af
	ret
