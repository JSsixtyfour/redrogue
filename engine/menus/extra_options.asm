; ============================================================================
; Extra options menu (Shin Red import, Phase 0).
;
; Reached by pressing SELECT on the normal OPTION screen - see the .extraMenu
; hook in DisplayOptionMenu (engine/menus/main_menu.asm). SELECT was previously
; masked off and did nothing there (`and ~PAD_SELECT`), so this claims an input
; that was genuinely free.
;
; State lives in wOptions2, NOT in spare wOptions bits. wOptions has no safely
; usable spare bits: home/print_text.asm reads it with `and $f` (four bits, not
; the three TEXT_DELAY_MASK implies), and SetCursorPositionsFromOptions does
; `and $3f` then IsInArray over TextSpeedOptionData, so a nonzero value in bits
; 3-5 walks past that table's terminator. See wOptions2's comment in ram/wram.asm.
;
; STATUS: one row (AUDIO, Phase 2.11). INST. TXT lands here with the
; text-speed work (the mechanism for that one already exists: BIT_NO_TEXT_DELAY
; in wStatusFlags5, honoured by home/print_text.asm).
;
; AUDIO row: LEFT/RIGHT cycles wOptions2 bits 4-5 (SOUND_MASK2, see
; constants/audio_constants.asm) through MONO/EARPHONE1/EARPHONE2/EARPHONE3,
; consumed by Audio1_ApplyMonoStereo (audio/engine_1.asm). With only one row
; on this menu so far, LEFT/RIGHT cycles it directly rather than needing a
; moving cursor between rows - there is nothing else to navigate to yet.
;
; ADDING A SECOND TOGGLE ROW:
;   1. Claim a bit in wOptions2 and document it in ram/wram.asm's comment.
;   2. Add a label string below and PlaceString it at hlcoord 1, <row>.
;   3. Print its value at a fixed column (mirror .drawAudioValue).
;   4. At that point LEFT/RIGHT can no longer apply to "the" row unconditionally
;      - add an up/down cursor (mirroring DisplayOptionMenu's
;      .cursorInBattleAnimation/PlaceUnfilledArrowMenuCursor) so LEFT/RIGHT
;      knows which row it's editing.
; The caller re-runs DisplayOptionMenu on return, so there is no need to redraw
; the normal option screen from here.
; ============================================================================

SECTION "Extra Options Menu", ROMX

DisplayExtraOptionMenu::
	call SaveScreenTilesToBuffer2 ; the caller's OPTION screen; restored below so
	                              ; the redraw it does afterwards has a clean base
	call ClearScreen
	call Delay3
	hlcoord 0, 0
	ld b, 2
	ld c, 18
	call TextBoxBorder
	hlcoord 1, 2
	ld de, ExtraOptionsTitleText
	call PlaceString
	hlcoord 1, 5
	ld de, ExtraOptionsAudioLabelText
	call PlaceString
	call .drawAudioValue
	hlcoord 2, 16
	ld de, ExtraOptionsCancelText
	call PlaceString
	ld a, $01
	ldh [hAutoBGTransferEnabled], a
	call Delay3
.loop
	call JoypadLowSensitivity
	ldh a, [hJoy5]
	ld b, a
	and PAD_A | PAD_B | PAD_START | PAD_SELECT
	jr nz, .exit
	ld a, b
	and PAD_LEFT | PAD_RIGHT
	jr z, .loop
	ld b, a
	ld a, SFX_PRESS_AB
	call PlaySound
	ld a, [wOptions2]
	ld d, a
	and SOUND_MASK2
	swap a ; bits 4-5 (SOUND_MASK2) -> bits 0-1
	bit B_PAD_RIGHT, b
	jr nz, .cycleRight
	dec a
	and $3
	jr .cycleDone
.cycleRight
	inc a
	and $3
.cycleDone
	swap a ; bits 0-1 -> bits 4-5
	ld e, a
	ld a, d
	and ~SOUND_MASK2 & $ff
	or e
	ld [wOptions2], a
	call .drawAudioValue
	jr .loop
.exit
	ld a, SFX_PRESS_AB
	call PlaySound
	call LoadScreenTilesFromBuffer2
	ret

; Prints the current AUDIO mode at a fixed 9-char-wide column so a shorter
; name (MONO) fully overwrites a longer one (EARPHONEn) left behind by the
; previous draw.
.drawAudioValue
	hlcoord 8, 5
	ld a, [wOptions2]
	and SOUND_MASK2
	swap a
	ld e, a
	ld d, 0
	push hl
	ld hl, .valueTextTable
	add hl, de
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld d, h
	ld e, l
	pop hl
	call PlaceString
	ret

.valueTextTable
	dw ExtraOptionsAudioMonoText
	dw ExtraOptionsAudioEarphone1Text
	dw ExtraOptionsAudioEarphone2Text
	dw ExtraOptionsAudioEarphone3Text

ExtraOptionsTitleText:
	db "EXTRA OPTIONS@"

ExtraOptionsAudioLabelText:
	db "AUDIO@"

ExtraOptionsAudioMonoText:
	db "MONO     @"

ExtraOptionsAudioEarphone1Text:
	db "EARPHONE1@"

ExtraOptionsAudioEarphone2Text:
	db "EARPHONE2@"

ExtraOptionsAudioEarphone3Text:
	db "EARPHONE3@"

ExtraOptionsCancelText:
	db "CANCEL@"
