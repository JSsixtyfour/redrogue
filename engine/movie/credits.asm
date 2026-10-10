; A normal Champion clear shows the Hall of Fame only. The credits roll only
; after the final AI victory (scripts/AILair.asm) and from the title menu.
HallOfFamePC:
	farjp AnimateHallOfFame

; Title menu CREDITS (MainMenuCredits in engine/menus/main_menu.asm). Ends in
; a soft reset back to the title screen, like the end of a run.
MainMenuCredits_::
	farcall AIVictoryCredits
	ld c, 60
	call DelayFrames
	call WaitForTextScrollButtonPress
	jp Init

; AIVictoryCredits (engine/movie/hall_of_fame.asm) enters here after reproducing
; the screen state AnimateHallOfFame leaves, so the AI victory rolls the
; credits without recording another Hall of Fame team.
HallOfFameCredits::
	call ClearScreen
	ld c, 100
	call DelayFrames
	call DisableLCD
	ld hl, vFont
	ld bc, ($80 tiles) / 2
	call ShiftFontColorIndex
	ld hl, vChars2 tile $60
	ld bc, ($20 tiles) / 2
	call ShiftFontColorIndex
	ld hl, vChars2 tile $7e
	ld bc, TILE_SIZE
	ld a, $ff ; solid black
	call FillMemory
	hlcoord 0, 0
	call FillFourRowsWithBlack
	hlcoord 0, 14
	call FillFourRowsWithBlack
	ld a, %11000000
	ldh [rBGP], a
    call UpdateGBCPal_BGP
	call EnableLCD
	ld a, SFX_STOP_ALL_MUSIC
	call PlaySoundWaitForCurrent
	ld c, BANK(Music_Credits)
	ld a, MUSIC_CREDITS
	call PlayMusic
	ld c, 128
	call DelayFrames
	xor a
	ld [wNumCreditsMonsDisplayed], a
	; SELECT starts "held" so a press already down on entry doesn't toggle;
	; START starts unarmed for the same reason (the title menu watches START).
	ld a, 1 << BIT_CREDITS_SELECT_HELD
	ld [wCreditsFlags], a
	jp Credits

FadeInCredits:
	ld hl, HoFGBPalettes
	ld b, 4
.loop
	ld a, [hli]
	ldh [rBGP], a
    call UpdateGBCPal_BGP
	ld c, 5
	call CreditsDelayFrames
	dec b
	jr nz, .loop
	ret

; DelayFrames for the roll: wait c frames, counting CREDITS_FAST_STEP per frame
; while SELECT's fast mode is on, and returning at once when START asks to skip.
; Preserves b, de and hl (FadeInCredits and Credits keep state in them).
CreditsDelayFrames:
	call DelayFrame
	call CreditsReadInput
	bit BIT_CREDITS_SKIP, a
	ret nz
	bit BIT_CREDITS_FAST, a
	jr nz, .fast
	dec c
	jr nz, CreditsDelayFrames
	ret
.fast
	ld a, c
	sub CREDITS_FAST_STEP
	ret c
	ret z
	ld c, a
	jr CreditsDelayFrames

; Update wCreditsFlags from hJoyInput (VBlank's ReadJoypad keeps it current).
; START skips only after it has been seen released; SELECT toggles on each new
; press. Returns the new flags in a. Preserves bc, de and hl.
CreditsReadInput:
	push bc
	ldh a, [hJoyInput]
	ld b, a
	ld a, [wCreditsFlags]
	ld c, a
	bit B_PAD_START, b
	jr nz, .startDown
	set BIT_CREDITS_START_ARMED, c
	jr .select
.startDown
	bit BIT_CREDITS_START_ARMED, c
	jr z, .select
	set BIT_CREDITS_SKIP, c
.select
	bit B_PAD_SELECT, b
	jr z, .selectUp
	bit BIT_CREDITS_SELECT_HELD, c
	jr nz, .store
	set BIT_CREDITS_SELECT_HELD, c
	ld a, c
	xor 1 << BIT_CREDITS_FAST
	ld c, a
	jr .store
.selectUp
	res BIT_CREDITS_SELECT_HELD, c
.store
	ld a, c
	ld [wCreditsFlags], a
	pop bc
	ret

DisplayCreditsMon:
	xor a
	ldh [hAutoBGTransferEnabled], a
	call SaveScreenTilesToBuffer1
	call FillMiddleOfScreenWithWhite

	; display the next monster from CreditsMons
	ld hl, wNumCreditsMonsDisplayed
	ld c, [hl] ; how many monsters have we displayed so far?
	inc [hl]
	ld b, 0
	ld hl, CreditsMons
	add hl, bc ; go that far in the list of monsters and get the next one
	ld a, [hl]
	ld [wCurPartySpecies], a
	ld [wCurSpecies], a
	hlcoord 8, 6
	call GetMonHeader
	call LoadFrontSpriteByMonIndex
	ld hl, vBGMap0 + $c
	call CreditsCopyTileMapToVRAM
	xor a
	ldh [hAutoBGTransferEnabled], a
	call LoadScreenTilesFromBuffer1
	ld hl, vBGMap0
	call CreditsCopyTileMapToVRAM
	ld a, $A7
	ldh [rWX], a
	ld hl, vBGMap1
	call CreditsCopyTileMapToVRAM
	call FillMiddleOfScreenWithWhite
	ld a, %11111100 ; make the mon a black silhouette
	ldh [rBGP], a
    call UpdateGBCPal_BGP

; scroll the mon left by one tile 7 times
	ld bc, 7
.scrollLoop1
	call ScrollCreditsMonLeft
	dec c
	jr nz, .scrollLoop1

; scroll the mon left by one tile 20 times
; This time, we have to move the window left too in order to hide the text that
; is wrapping around to the right side of the screen.
	ld c, 20
.scrollLoop2
	call ScrollCreditsMonLeft
	ldh a, [rWX]
	sub 8
	ldh [rWX], a
	dec c
	jr nz, .scrollLoop2

	xor a
	ldh [hWY], a
	ld a, %11000000
	ldh [rBGP], a
    call UpdateGBCPal_BGP
	ret

INCLUDE "data/credits/credits_mons.asm"

ScrollCreditsMonLeft:
	ld h, b
	ld l, $20
	call ScrollCreditsMonLeft_SetSCX
	ld h, $0
	ld l, $70
	call ScrollCreditsMonLeft_SetSCX
	ld a, b
	add $8
	ld b, a
	ret

ScrollCreditsMonLeft_SetSCX:
	ldh a, [rLY]
	cp l
	jr nz, ScrollCreditsMonLeft_SetSCX
	ld a, h
	ldh [rSCX], a
.loop
	ldh a, [rLY]
	cp h
	jr z, .loop
	ret

HoFGBPalettes:
	dc 3, 0, 0, 0
	dc 3, 1, 0, 0
	dc 3, 2, 0, 0
	dc 3, 3, 0, 0

CreditsCopyTileMapToVRAM:
	ld a, l
	ldh [hAutoBGTransferDest], a
	ld a, h
	ldh [hAutoBGTransferDest + 1], a
	ld a, 1
	ldh [hAutoBGTransferEnabled], a
	jp Delay3

ShiftFontColorIndex:
; Zero every second byte at hl, writing a total of bc bytes.
; When used on VRAM font characters that contain only black and white shades,
; it shifts the color index: black -> light gray, allowing palette-controlled
; text fade-in during the Credits roll, while the black bars remain solid.
	ld [hl], 0
	inc hl
	inc hl
	dec bc
	ld a, b
	or c
	jr nz, ShiftFontColorIndex
	ret

FillFourRowsWithBlack:
	ld bc, SCREEN_WIDTH * 4
	ld a, $7e
	jp FillMemory

FillMiddleOfScreenWithWhite:
	hlcoord 0, 4
	ld bc, SCREEN_WIDTH * 10
	ld a, ' '
	jp FillMemory

Credits:
	ld de, CreditsOrder
	push de
.nextCreditsScreen
	pop de
	hlcoord 9, 6
	push hl
	call FillMiddleOfScreenWithWhite
	pop hl
.nextCreditsCommand
	ld a, [de]
	inc de
	push de
	cp CRED_TEXT_FADE_MON
	jr z, .fadeInTextAndShowMon
	cp CRED_TEXT_MON
	jr z, .showTextAndShowMon
	cp CRED_TEXT_FADE
	jr z, .fadeInText
	cp CRED_TEXT
	jr z, .showText
	cp CRED_COPYRIGHT
	jr z, .showCopyrightText
	cp CRED_THE_END
	jr z, .showTheEnd
	push hl
	push hl
	; 16-bit index: the string ids passed 127 with the Red Rogue sections
	ld c, a
	ld b, 0
	ld hl, CreditsTextPointers
	add hl, bc
	add hl, bc
	ld e, [hl]
	inc hl
	ld d, [hl]
	ld a, [de]
	inc de
	ld c, a
	ld b, -1
	pop hl
	add hl, bc
	call PlaceString
	pop hl
	ld bc, SCREEN_WIDTH * 2
	add hl, bc
	pop de
	jr .nextCreditsCommand
.fadeInTextAndShowMon
	call FadeInCredits
	ld c, 90
	jr .next1
.showTextAndShowMon
	ld c, 110
.next1
	call CreditsDelayFrames
	; START skips at a screen boundary, before a mon scroll can start. The
	; stack holds the one pushed de that .showTheEnd pops.
	ld a, [wCreditsFlags]
	bit BIT_CREDITS_SKIP, a
	jr nz, .showTheEnd
	call DisplayCreditsMon
	jr .nextCreditsScreen
.fadeInText
	call FadeInCredits
	ld c, 120
	jr .next2
.showText
	ld c, 140
.next2
	call CreditsDelayFrames
	ld a, [wCreditsFlags]
	bit BIT_CREDITS_SKIP, a
	jr nz, .showTheEnd
	jr .nextCreditsScreen
.showCopyrightText
	push de
	farcall LoadCopyrightTiles
	pop de
	pop de
	jr .nextCreditsCommand
.showTheEnd
	; Music_Credits loops now that the roll outlasts it: fade it out here, the
	; same way HoFFadeOutScreenAndMusic does.
	ld a, 10
	ld [wAudioFadeOutCounterReloadValue], a
	ld [wAudioFadeOutCounter], a
	ld a, $ff
	ld [wAudioFadeOutControl], a
	ld c, 16
	call DelayFrames
	call FillMiddleOfScreenWithWhite
	pop de
	ld de, TheEndGfx
	ld hl, vChars2 tile $60
	lb bc, BANK(TheEndGfx), (TheEndGfxEnd - TheEndGfx) / TILE_SIZE
	call CopyVideoDataPaced ; paced, as pureRGB
	hlcoord 4, 8
	ld de, TheEndTextString
	call PlaceString
	hlcoord 4, 9
	inc de
	call PlaceString
	jp FadeInCredits

TheEndTextString:
; "T H E  E N D"
	db $60," ",$62," ",$64,"  ",$64," ",$66," ",$68,"@"
	db $61," ",$63," ",$65,"  ",$65," ",$67," ",$69,"@"

INCLUDE "data/credits/credits_order.asm"

INCLUDE "data/credits/credits_text.asm"

TheEndGfx:
	INCBIN "gfx/credits/the_end.2bpp"
TheEndGfxEnd:
