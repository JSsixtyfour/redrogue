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

; Automatic cleanup only. e = daycare slot (0 or 1).
; Quote the normal $500 per started ROUND_BATTLES in hMoney, then charge
; min(balance, quote). No prompts, refusal or debt; voluntary scripts unchanged.
; Clobbers hMoney and hItemPrice (existing transaction scratch).
RentalChargeDaycare::
	ld hl, wDayCareDepositBattleCount
	ld a, e
	and a
	jr z, .depositReady
	ld hl, wDayCareDepositBattleCount2
.depositReady
	ld a, [wBattleCount]
	sub [hl] ; match the ordinary daycare's byte-wrap elapsed-battle policy
	ld b, 0
	jr z, .roundsReady
	dec a
	inc b
.roundLoop
	cp ROUND_BATTLES
	jr c, .roundsReady
	sub ROUND_BATTLES
	inc b
	jr .roundLoop
.roundsReady
	xor a
	ldh [hMoney], a
	ldh [hMoney + 1], a
	ldh [hMoney + 2], a
	ldh [hItemPrice], a
	ldh [hItemPrice + 2], a
	ld a, DAYCARE_PRICE_PER_ROUND_BCD
	ldh [hItemPrice + 1], a
	ld a, b
	and a
	ret z
.priceLoop
	push bc
	ld hl, hItemPrice + 2 ; predef changes ROM bank, so source must be RAM
	ld de, hMoney + 2
	ld c, 3
	predef AddBCDPredef
	pop bc
	dec b
	jr nz, .priceLoop
	call HasEnoughMoney
	jr c, .shortfall
	ld hl, hMoney + 2
	ld de, wPlayerMoney + 2
	ld c, 3
	predef SubBCDPredef
	ret
.shortfall
	xor a
	ld [wPlayerMoney], a
	ld [wPlayerMoney + 1], a
	ld [wPlayerMoney + 2], a
	ret

; Reclaim only a rental currently owned by a daycare. Carry = reclaimed.
; Preserve the used-opportunity and contract/offer bytes; clear only location.
; Caller owns expiry state and subsequent owned-party fallback separately.
RentalReclaimDaycare::
	ld a, [wRentalOwner]
	cp BRIDGE_SELECTED_OWNER_DAYCARE1
	jr z, .first
	cp BRIDGE_SELECTED_OWNER_DAYCARE2
	jr z, .second
	and a
	ret
.first
	ld a, [wDayCareInUse]
	and a
	jr z, .clearFirst
	ld e, 0
	call RentalChargeDaycare
.clearFirst
	ld hl, wDayCareInUse
	ld bc, wDayCareInUse2 - wDayCareInUse
	xor a
	call FillMemory
	ld [wDayCareDepositBattleCount], a
	ld hl, wDayCareStartLevel
	jr .clearCost
.second
	ld a, [wDayCareInUse2]
	and a
	jr z, .clearSecond
	ld e, 1
	call RentalChargeDaycare
.clearSecond
	ld hl, wDayCareInUse2
	ld bc, wStolenSaveSnapshot - wDayCareInUse2
	xor a
	call FillMemory
	ld [wDayCareDepositBattleCount2], a
	ld hl, wDayCareStartLevel2
.clearCost
	ld bc, 6 ; start level, growth, total cost and per-round scratch
	xor a
	call FillMemory
.clearOwner
	xor a
	ld [wRentalOwner], a
	scf
	ret

; Reclaim a live party/current-box/daycare/stolen rental. Carry = location
; settled, including an already-removed mon. Other contract bytes survive.
; Inactive boxes return NC unchanged: their raw SRAM transaction is separate.
; Caller must restore/heal an owned party before returning player control.
RentalReclaimAccessible::
	ld a, [wRentalOwner]
	and a
	jr z, .settled
	cp PARTY_LENGTH + 1
	jr c, .party
	cp BRIDGE_SELECTED_OWNER_DAYCARE1
	jr c, .box
	cp BRIDGE_SELECTED_OWNER_DAYCARE2 + 1
	jp c, RentalReclaimDaycare
	cp BRIDGE_SELECTED_OWNER_MAX + 1
	jr z, .stolen
	and a ; invalid location: do not delete an unrelated Pokemon
	ret
.party
	dec a
	ldh [hWhichPokemon], a
	ld b, a
	ld a, [wPartyCount]
	cp b
	jr z, .settled
	jr c, .settled
	xor a
	ld [wRemoveMonFromBox], a
	call RemovePokemon
	jr .settled
.box
	sub BRIDGE_SELECTED_OWNER_BOX_BASE
	ld e, a
	ld d, 0 ; quotient = box number; remainder = slot
.boxLoop
	ld a, e
	cp MONS_PER_BOX
	jr c, .boxReady
	sub MONS_PER_BOX
	ld e, a
	inc d
	jr .boxLoop
.boxReady
	ld a, [wCurrentBoxNum]
	and BOX_NUM_MASK
	cp d
	jr nz, .inactive
	ld a, e
	ldh [hWhichPokemon], a
	ld a, [wBoxCount]
	cp e
	jr z, .settled
	jr c, .settled
	ld a, 1
	ld [wRemoveMonFromBox], a
	call RemovePokemon
	jr .settled
.inactive
	and a
	ret
.stolen
	; Raw holder becomes empty now; the saved theft snapshot is deliberately
	; untouched, so Continue can restore the pre-settlement owner AND holder.
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ld a, BANK(sStolenRecord)
	ld [rRAMB], a
	ld a, [sStolenKind]
	cp STOLEN_MON ; never erase an item due to stale location metadata
	jr nz, .closeStolen
	ld hl, sStolenRecord
	ld bc, sStolenRecordEnd - sStolenRecord
	xor a
	call FillMemory
.closeStolen
	xor a
	ld [rBMODE], a
	ld [rRAMG], a
.settled
	xor a
	ld [wRentalOwner], a
	scf
	ret
