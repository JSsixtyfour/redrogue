StartSlotMachine:
	ld a, [wHiddenEventFunctionArgument]
	cp SLOTS_OUTOFORDER
	jr z, .printOutOfOrder
	cp SLOTS_OUTTOLUNCH
	jr z, .printOutToLunch
	cp SLOTS_SOMEONESKEYS
	jr z, .printSomeonesKeys
	ld a, 1
	ld [wCanPlaySlots], a
	and a
	ret z
	; Credit Exchange gate: refuse before any of the slot-machine setup runs.
	; wRogueFlagsBitfield2 bits 0-1 count pulls USED this run (cleared by
	; RogueOnBlackout); the per-spin metering lives in MainSlotMachineLoop.
	; This has to happen here rather than inside PromptUserToPlaySlots, and it
	; has to go out through the same tx_pre_id/DisplayTextID path the messages
	; below use: a bare PrintText from a hidden-object handler leaves the box
	; unopened and unclosed, which showed up as an invisible text box that
	; still swallowed sprites and locked the player until A.
	ld a, [wRogueFlagsBitfield2]
	and %00000011
	cp 3
	jr nc, .printNoPulls
	ld a, [wLuckySlotHiddenEventIndex]
	ld b, a
	ld a, [wHiddenEventIndex]
	inc a
	cp b
	jr z, .match
	ld a, 253
	jr .next
.match
	ld a, 250
.next
	ld [wSlotMachineSevenAndBarModeChance], a
	ldh a, [hLoadedROMBank]
	ld [wSlotMachineSavedROMBank], a
	call PromptUserToPlaySlots
	ret
.printOutOfOrder
	tx_pre_id GameCornerOutOfOrderText
	jr .printText
.printOutToLunch
	tx_pre_id GameCornerOutToLunchText
	jr .printText
.printSomeonesKeys
	tx_pre_id GameCornerSomeonesKeysText
.printText
	push af
	call EnableAutoTextBoxDrawing
	pop af
	call PrintPredefTextID
	ret

.printNoPulls
	tx_pre_id SlotsNoPullsLeftText
	jr .printText

; Own copy of the text stub: slot_machine.asm has its own for the mid-session
; case, but it sits in a different bank, and predef text runs in whatever bank
; is currently paged in (DisplayTextID skips the map-bank switch for predefs).
SlotsNoPullsLeftText::
	text_far _NoSlotPullsLeftText
	text_end

GameCornerOutOfOrderText::
	text_far _GameCornerOutOfOrderText
	text_end

GameCornerOutToLunchText::
	text_far _GameCornerOutToLunchText
	text_end

GameCornerSomeonesKeysText::
	text_far _GameCornerSomeonesKeysText
	text_end
