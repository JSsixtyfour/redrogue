; Saved location ownership for the single rental. This does not enable a
; provider: delivery and expiry will own the state transitions separately.
; Inputs use de/e because Bankswitch replaces a, bc and hl.

RentalResetRecord::
	ld hl, wRentalRecord
	ld bc, wMainDataEnd - wRentalRecord
	xor a
	jp FillMemory

; d = old owner, e = new owner. Preserve de for central mutation callers.
RentalMoveOwner::
	ld a, [wRentalOwner]
	and a
	ret z
	cp d
	ret nz
	ld a, e
	ld [wRentalOwner], a
	ret

; e = removed owner. Keep contract/opportunity state after release or loss.
RentalClearOwner::
	ld a, [wRentalOwner]
	cp e
	ret nz
	xor a
	ld [wRentalOwner], a
	ret

; d/e = inclusive compacted range.
RentalShiftOwnerDown::
	call RentalOwnerInRange
	ret nc
	dec [hl]
	ret

RentalShiftOwnerUp::
	call RentalOwnerInRange
	ret nc
	inc [hl]
	ret

RentalOwnerInRange:
	ld hl, wRentalOwner
	ld a, [hl]
	and a
	ret z
	cp d
	jr c, .outside
	cp e
	jr z, .inside
	ret nc
.inside
	scf
	ret
.outside
	and a
	ret

; Theft copies successfully before this hook, then RemovePokemon compacts.
RentalTrackTheft::
	ldh a, [hWhichPokemon]
	inc a
	ld d, a
	ld e, BRIDGE_SELECTED_OWNER_MAX + 1
	jp RentalMoveOwner

RentalTrackPartyRecovery::
	ld d, BRIDGE_SELECTED_OWNER_MAX + 1
	ld a, [wPartyCount]
	ld e, a
	jp RentalMoveOwner

RentalTrackBoxRecovery::
	ld a, [wCurrentBoxNum]
	and BOX_NUM_MASK
	ld e, a
	add a
	add a
	add e
	add a
	add a ; box * 20
	ld e, a
	ld a, [wBoxCount]
	dec a ; recovery appends, rather than front-inserting
	add e
	add BRIDGE_SELECTED_OWNER_BOX_BASE
	ld e, a
	ld d, BRIDGE_SELECTED_OWNER_MAX + 1
	jp RentalMoveOwner

; d/e = exchanged owners; either or both may have an independent bridge effect.
RentalSwapOwners::
	ld a, [wRentalOwner]
	and a
	ret z
	cp d
	jr z, .first
	cp e
	ret nz
	ld a, d
	jr .store
.first
	ld a, e
.store
	ld [wRentalOwner], a
	ret

; Carry when zero-based party slot e is the rental. Owner 0 is absent;
; box/daycare/stolen owners cannot match a valid party slot.
RentalIsPartySlot::
	ld a, e
	cp PARTY_LENGTH
	jr nc, .notRental
	inc a
	ld hl, wRentalOwner
	cp [hl]
	jr z, .rental
.notRental
	and a
	ret
.rental
	scf
	ret

; Called after the trade menu closes, before any trade flags or data change.
RentalRejectSelectedTrade::
	ldh a, [hWhichPokemon]
	ld e, a
	call RentalIsPartySlot
	ret nc
	jr RentalRejectAction

; Both fusion menus have closed; neither Pokemon has been altered yet.
RentalRejectFusion::
	ldh a, [hSpriteDataOffset]
	ld e, a
	call RentalIsPartySlot
	jr c, RentalRejectAction
	ldh a, [hSpriteHeight]
	ld e, a
	call RentalIsPartySlot
	ret nc
RentalRejectAction:
	ld hl, .text
	call PrintText
	scf
	ret
.text
	text "Rental POKEMON"
	line "can't be traded"
	cont "or fused!"
	prompt
