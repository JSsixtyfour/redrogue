UpdateCinnabarGymGateTileBlocks::
	rfarjp UpdateCinnabarGymGateTileBlocks_

; hLoadedROMBank is written before rROMB at every switch: VBlank restores the bank from hLoadedROMBank,
; so an interrupt between the two in the other order maps the old bank back and runs garbage.
CheckForHiddenEventOrBookshelfOrCardKeyDoor::
	ldh a, [hLoadedROMBank]
	push af
	ldh a, [hJoyHeld]
	bit B_PAD_A, a
	jr z, .nothingFound
; A button is pressed
	ld a, BANK(CheckForHiddenEvent)
	ldh [hLoadedROMBank], a
	ld [rROMB], a
	call CheckForHiddenEvent
	ldh a, [hDidntFindAnyHiddenEvent]
	and a
	jr nz, .hiddenEventNotFound
	ld a, [wHiddenEventFunctionRomBank]
	ldh [hLoadedROMBank], a
	ld [rROMB], a
	ld de, .returnAddress
	push de
	jp hl
.returnAddress
	xor a
	jr .done
.hiddenEventNotFound
	rfarcall PrintBookshelfText
	ldh a, [hInteractedWithBookshelf]
	and a
	jr z, .done
.nothingFound
	ld a, $ff
.done
	ldh [hItemAlreadyFound], a
	pop af
	ldh [hLoadedROMBank], a
	ld [rROMB], a
	ret
