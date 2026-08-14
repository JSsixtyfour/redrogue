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
; STATUS: shell. It draws, takes input and exits; there are no toggle rows yet.
; Rows land here as their features do - AUDIO mixing with the Yellow audio
; backport, INST. TXT with the text-speed work (the mechanism for that one
; already exists: BIT_NO_TEXT_DELAY in wStatusFlags5, honoured by
; home/print_text.asm).
;
; ADDING A TOGGLE ROW:
;   1. Claim a bit in wOptions2 and document it in ram/wram.asm's comment.
;   2. Add a label string below and PlaceString it at hlcoord 1, <row>.
;   3. Print its ON/OFF value from that bit at a fixed column.
;   4. Add the row to the cursor's up/down range and toggle the bit on LEFT/
;      RIGHT or A, mirroring DisplayOptionMenu's .cursorInBattleAnimation.
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
	ld de, ExtraOptionsEmptyText
	call PlaceString
	hlcoord 2, 16
	ld de, ExtraOptionsCancelText
	call PlaceString
	ld a, $01
	ldh [hAutoBGTransferEnabled], a
	call Delay3
.loop
	call JoypadLowSensitivity
	ldh a, [hJoy5]
	and PAD_A | PAD_B | PAD_START | PAD_SELECT
	jr z, .loop
	ld a, SFX_PRESS_AB
	call PlaySound
	call LoadScreenTilesFromBuffer2
	ret

ExtraOptionsTitleText:
	db "EXTRA OPTIONS@"

ExtraOptionsEmptyText:
	db "(none yet)@"

ExtraOptionsCancelText:
	db "CANCEL@"
