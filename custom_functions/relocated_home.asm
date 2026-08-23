; custom_functions/relocated_home.asm
;
; Vanilla HOME routines relocated to ROMX to reclaim ROM0/HOME space for the
; procedural-cave merge (master's HOME bank was ~full; the procedural load hooks
; need ~26 bytes there). Each routine here is a self-contained leaf whose only
; cross-references are to HOME (always-mapped) targets, so it runs correctly from
; any bank; each HOME call site is converted to farcall.

SECTION "Relocated HOME Routines", ROMX

; Moved from home/overworld.asm. Ends in `jp AdvancePlayerSprite` (HOME target,
; always mapped -> safe from ROMX). Both callers in EnterMap's movement path are
; converted to farcall (the conditional one via jr z + farcall).
DoBikeSpeedup::
	ld a, [wNPCMovementScriptPointerTableNum]
	and a
	ret nz
	ldh a, [hCurMap]
	cp ROUTE_17 ; Cycling Road
	jr nz, .goFaster
	ldh a, [hJoyHeld]
	and PAD_UP | PAD_LEFT | PAD_RIGHT
	ret nz
.goFaster
	jp AdvancePlayerSprite

; Argument-free graphics setup routines moved from HOME. Their original labels
; remain as far-jump stubs, so callers keep the same interface. These bodies
; either use bank-aware helpers or tail-jump back into always-mapped HOME code.
LoadFontTilePatterns_::
	ldh a, [rLCDC]
	bit B_LCDC_ENABLE, a
	jr nz, .on
	ld hl, FontGraphics
	ld de, vFont
	ld bc, FontGraphicsEnd - FontGraphics
	ld a, BANK(FontGraphics)
	jp FarCopyDataDouble
.on
	ld de, FontGraphics
	ld hl, vFont
	lb bc, BANK(FontGraphics), (FontGraphicsEnd - FontGraphics) / TILE_1BPP_SIZE
	jp CopyVideoDataDouble

LoadTextBoxTilePatterns_::
	ldh a, [rLCDC]
	bit B_LCDC_ENABLE, a
	jr nz, .on
	ld hl, TextBoxGraphics
	ld de, vChars2 tile $60
	ld bc, TextBoxGraphicsEnd - TextBoxGraphics
	ld a, BANK(TextBoxGraphics)
	jp FarCopyData2
.on
	ld de, TextBoxGraphics
	ld hl, vChars2 tile $60
	lb bc, BANK(TextBoxGraphics), (TextBoxGraphicsEnd - TextBoxGraphics) / TILE_SIZE
	jp CopyVideoData

LoadHpBarAndStatusTilePatterns_::
	ldh a, [rLCDC]
	bit B_LCDC_ENABLE, a
	jr nz, .on
	ld hl, HpBarAndStatusGraphics
	ld de, vChars2 tile $62
	ld bc, HpBarAndStatusGraphicsEnd - HpBarAndStatusGraphics
	ld a, BANK(HpBarAndStatusGraphics)
	jp FarCopyData2
.on
	ld de, HpBarAndStatusGraphics
	ld hl, vChars2 tile $62
	lb bc, BANK(HpBarAndStatusGraphics), (HpBarAndStatusGraphicsEnd - HpBarAndStatusGraphics) / TILE_SIZE
	jp CopyVideoData

ReloadMapSpriteTilePatterns_::
	ld hl, wFontLoaded
	ld a, [hl]
	push af
	res BIT_FONT_LOADED, [hl]
	push hl
	xor a
	ld [wSpriteSetID], a
	call DisableLCD
	farcall InitMapSprites
	call EnableLCD
	pop hl
	pop af
	ld [hl], a
	call LoadPlayerSpriteGraphics
	call LoadFontTilePatterns_
	jp UpdateSprites

ResetPlayerSpriteData_::
	ld hl, wSpriteStateData1
	call .ClearSpriteData
	ld hl, wSpriteStateData2
	call .ClearSpriteData
	ld a, $1
	ld [wSpritePlayerStateData1PictureID], a
	ld [wSpritePlayerStateData2ImageBaseOffset], a
	ld hl, wSpritePlayerStateData1YPixels
	ld [hl], $3c
	inc hl
	inc hl
	ld [hl], $40
	ret
.ClearSpriteData
	ld bc, SPRITESTATEDATA1_LENGTH
	ASSERT SPRITESTATEDATA2_LENGTH == SPRITESTATEDATA1_LENGTH
	xor a
	jp FillMemory

; Fade code is also argument-free and self-contained. FadePal1-FadePal8 stay
; in HOME because func_gamma.asm reads FadePal4 directly from another bank.
LoadGBPal_::
	ld a, [wMapPalOffset]
	ld b, a
	ld hl, FadePal4
	ld a, l
	sub b
	ld l, a
	jr nc, .ok
	dec h
.ok
	ld a, [hli]
	ldh [rBGP], a
	ld a, [hli]
	ldh [rOBP0], a
	ld a, [hli]
	ldh [rOBP1], a
	call UpdateGBCPal_BGP
	call UpdateGBCPal_OBP0
	call UpdateGBCPal_OBP1
	ret

GBFadeInFromBlack_::
	farcall GBCFadeInFromBlack
	ld hl, FadePal1
	ld b, 4
	jr GBFadeIncCommon_

GBFadeOutToWhite_::
	farcall GBCFadeOutToWhite
	ld hl, FadePal6
	ld b, 3

GBFadeIncCommon_:
	ld a, [hli]
	ldh [rBGP], a
	ld a, [hli]
	ldh [rOBP0], a
	ld a, [hli]
	ldh [rOBP1], a
	call UpdateGBCPal_BGP
	call UpdateGBCPal_OBP0
	call UpdateGBCPal_OBP1
	ld c, 8
	call DelayFrames
	dec b
	jr nz, GBFadeIncCommon_
	ret

GBFadeOutToBlack_::
	farcall GBCFadeOutToBlack
	ld hl, FadePal4 + 2
	ld b, 4
	jr GBFadeDecCommon_

GBFadeInFromWhite_::
	farcall GBCFadeInFromWhite
	ld hl, FadePal7 + 2
	ld b, 3

GBFadeDecCommon_:
	ld a, [hld]
	ldh [rOBP1], a
	ld a, [hld]
	ldh [rOBP0], a
	ld a, [hld]
	ldh [rBGP], a
	call UpdateGBCPal_BGP
	call UpdateGBCPal_OBP0
	call UpdateGBCPal_OBP1
	ld c, 8
	call DelayFrames
	dec b
	jr nz, GBFadeDecCommon_
	ret

; These two bank1 helpers are reached through far-jump stubs. Keeping the
; stubs preserves callers in the main-menu and Oak-speech code while giving
; the debug-only bank1 payload enough headroom to link.
InitOptions_::
	ld a, 1 << BIT_FAST_TEXT_DELAY
	ld [wLetterPrintingDelayFlags], a
	ld a, TEXT_DELAY_FAST
	ld [wOptions], a
	xor a
	ld [wOptions2], a
	ldh a, [hGBC]
	and a
	ret z
	ldh a, [rIE]
	push af
	xor a
	ldh [rIE], a
	ldh a, [rSVBK]
	push af
	ld a, 2
	ldh [rSVBK], a
	ld a, [w2GBCFlags]
	set 5, a
	ld [w2GBCFlags], a
	ld a, 1
	ldh [rSVBK], a
	pop af
	ldh [rSVBK], a
	pop af
	ldh [rIE], a
	ret

CheckForPlayerNameInSRAM_::
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ASSERT BANK(sPlayerName) == BMODE_ADVANCED
	ld [rRAMB], a
	ld b, NAME_LENGTH
	ld hl, sPlayerName
.loop
	ld a, [hli]
	cp '@'
	jr z, .found
	dec b
	jr nz, .loop
	xor a
	ld [rRAMG], a
	ld [rBMODE], a
	and a
	ret
.found
	xor a
	ld [rRAMG], a
	ld [rBMODE], a
	scf
	ret
