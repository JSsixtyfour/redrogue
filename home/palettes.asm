RestoreScreenTilesAndReloadTilePatterns::
	call ClearSprites
	ld a, $1
	ldh [hUpdateSpritesEnabled], a
	call ReloadMapSpriteTilePatterns
	call LoadScreenTilesFromBuffer2
	call LoadTextBoxTilePatterns
	; Reveal AFTER the bg map has finished transferring, not before it.
	;
	; LoadScreenTilesFromBuffer2 above only refills wTileMap; that reaches VRAM
	; in thirds over the next three frames, which is exactly what Delay3 waits
	; for. Meanwhile ReloadMapSpriteTilePatterns and LoadTextBoxTilePatterns have
	; already swapped the VRAM tile patterns, so during those three frames the
	; visible bg map still holds the OUTGOING screen's tile IDs drawn with the
	; INCOMING screen's patterns. Party-menu HP bars render as "CLLLLLLL".
	;
	; Vanilla got away with running the palette command first because on DMG the
	; white-out left rBGP at $00 and the command translated through it, so the
	; screen stayed white either way. That no longer holds here: on CGB this
	; command reaches LoadEnhancedOverworldPaletteCommand, which deliberately
	; rewrites rBGP from FadePal4 and writes real colours straight into palette
	; RAM (see func_enhancedcolor.asm, the "Oak's final fade" comment). Palette
	; RAM is what the hardware draws from, so that defeats the white-out and the
	; three-frame window becomes visible.
	;
	; Verified in BGB: at this call BGP0-3 read 7FFF/7FFF/7FFF/7FFF, and by the
	; time LoadGBPal is reached they read 7FFF/015F/0015/0C63 etc. Deferring the
	; reveal past Delay3 keeps the window hidden. Same shape as the reorder in
	; CloseTextDisplay: finish the redraw, then show it.
	call Delay3
	jp RunDefaultPaletteCommand

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
