; Saved location ownership for the single rental. This does not enable a
; provider: delivery and expiry will own the state transitions separately.
; Inputs use de/e because Bankswitch replaces a, bc and hl.

RentalResetRecord::
	ld hl, wRentalRecord
	ld bc, wMainDataEnd - wRentalRecord
	xor a
	jp FillMemory

; Only the run-reset caller preserves this transient save request. New-game
; initialization continues to use RentalResetRecord unconditionally.
DEF RENTAL_RUN_END_SAVE_PENDING EQU $ff
RentalResetAtRunBoundary::
	ld a, [wRentalState]
	push af
	call RentalResetRecord
	pop af
	cp RENTAL_RUN_END_SAVE_PENDING
	ret nz
	ld [wRentalState], a
	ret

; Dorm first-load seam, after the ordinary credit popup and map restoration.
; The map check keeps a stale temporary marker from saving another context.
RentalFinishRunEndSave::
	ldh a, [hCurMap]
	cp SILPH_CO_DORM
	ret nz
	ld a, [wRentalState]
	cp RENTAL_RUN_END_SAVE_PENDING
	ret nz
	xor a
	ld [wRentalState], a
	rfarjp SaveGameData

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

; Read-only boxed fallback search. Carry = found, d = absolute box, e = slot.
; Current WRAM box first, then inactive boxes in numerical order. The rental
; never qualifies as its own replacement. Does not change the current box,
; any Pokemon, checksums or save data. SRAM is closed before returning.
RentalFindBoxFallback::
	ld a, [wCurrentBoxNum]
	and BOX_NUM_MASK
	ld d, a
	ld a, [wBoxCount]
	call .scanBox
	ret c
	ld a, [wCurrentBoxNum]
	bit BIT_HAS_CHANGED_BOXES, a
	jr z, .notFound ; inactive SRAM boxes do not exist until first box change
	ld d, 0
.boxLoop
	ld a, [wCurrentBoxNum]
	and BOX_NUM_MASK
	cp d
	jr z, .nextBox
	push de
	ld a, d
	ld b, BANK(sBox1)
	cp NUM_BOXES / 2
	jr c, .bankReady
	ld b, BANK(sBox7)
	sub NUM_BOXES / 2
.bankReady
	ld hl, .boxPointers
	add a
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ld a, b
	ld [rRAMB], a
	ld a, [hl] ; only read the box count, no banked calls while SRAM is open
	pop de
	call .scanBox
	push af
	xor a
	ld [rBMODE], a
	ld [rRAMG], a
	pop af
	ret c
.nextBox
	inc d
	ld a, d
	cp NUM_BOXES
	jr c, .boxLoop
.notFound
	and a
	ret
.scanBox
	and a
	ret z
	cp MONS_PER_BOX + 1
	jr nc, .badCount
	ld b, a
	ld e, 0
.slotLoop
	; Absolute owner = 7 + 20*box + slot. Preserve the candidate in de.
	ld a, d
	add a
	add a
	add d
	add a
	add a
	add e
	add BRIDGE_SELECTED_OWNER_BOX_BASE
	ld hl, wRentalOwner
	cp [hl]
	jr nz, .found
	inc e
	dec b
	jr nz, .slotLoop
.badCount
	and a
	ret
.found
	scf
	ret
.boxPointers
	dw sBox1, sBox2, sBox3, sBox4, sBox5, sBox6
	ASSERT sBox1 == sBox7 && sBox2 == sBox8 && sBox3 == sBox9
	ASSERT sBox4 == sBox10 && sBox5 == sBox11 && sBox6 == sBox12

; All-holder reclaim, including an inactive box. Transaction-only: raw box
; changes require a final full save. Preserve the player's selected box.
RentalReclaimAll::
	ld a, [wRentalOwner]
	cp BRIDGE_SELECTED_OWNER_BOX_BASE
	jp c, RentalReclaimAccessible
	cp BRIDGE_SELECTED_OWNER_DAYCARE1
	jp nc, RentalReclaimAccessible
	sub BRIDGE_SELECTED_OWNER_BOX_BASE
	ld e, a
	ld d, 0
.divideBox
	ld a, e
	cp MONS_PER_BOX
	jr c, .decoded
	sub MONS_PER_BOX
	ld e, a
	inc d
	jr .divideBox
.decoded
	ld a, [wCurrentBoxNum]
	and BOX_NUM_MASK
	cp d
	jp z, RentalReclaimAccessible
	ld a, [wCurrentBoxNum]
	bit BIT_HAS_CHANGED_BOXES, a
	jr z, .unavailable
	push af
	ld e, d
	rfarcall RentalExchangeBox
	call RentalReclaimAccessible
	pop af
	and BOX_NUM_MASK
	ld e, a
	rfarcall RentalExchangeBox
	scf
	ret
.unavailable
	and a
	ret

; After reclaim (owner 0), restore from current box then numerical boxes.
; Carry = healthy owned party available. Transaction-only for inactive boxes.
RentalRestoreBoxedParty::
	ld a, [wRentalOwner]
	and a
	jr nz, .failed
	ld a, [wPartyCount]
	and a
	jr nz, .heal
	call RentalFindBoxFallback
	ret nc
	ld a, [wCurrentBoxNum]
	and BOX_NUM_MASK
	cp d
	jr z, .current
	ld a, [wCurrentBoxNum]
	push af
	push de
	ld e, d
	rfarcall RentalExchangeBox
	pop de
	call .withdraw
	pop af
	and BOX_NUM_MASK
	ld e, a
	rfarcall RentalExchangeBox
	jr .checkParty
.current
	call .withdraw
.checkParty
	ld a, [wPartyCount]
	and a
	ret z
.heal
	predef HealParty
	scf
	ret
.failed
	and a
	ret
.withdraw
	ld a, e
	ldh [hWhichPokemon], a
	ld hl, wBoxSpecies
	ld d, 0
	add hl, de
	ld a, [hl]
	ld [wCurPartySpecies], a
	ld a, BOX_TO_PARTY
	ld [wMoveMonType], a
	call MoveMon
	ret c
	ld a, 1
	ld [wRemoveMonFromBox], a
	jp RemovePokemon

; Complete save-point settlement when owned party/boxed fallback exists.
; No candidate (including daycare-only fallback) returns NC BEFORE mutation.
; Daycare fallback/no-owned ending will extend this preflight separately.
RentalSettleBoxedAndSave::
	ld a, [wPartyCount]
	cp 2
	jr nc, .ready
	and a
	jr z, .needBox
	ld a, [wRentalOwner]
	cp 1
	jr nz, .ready
.needBox
	call RentalFindBoxFallback
	ret nc
.ready
	call RentalReclaimAll
	ret nc
	call RentalRestoreBoxedParty
	ret nc
	xor a
	ld [wRentalState], a
	ld [wRentalZone], a
	rfarcall SaveGameData
	scf
	ret

; Read-only final fallback, after the box search. e = daycare 0/1, carry found.
RentalFindDaycareFallback::
	ld a, [wRentalOwner]
	cp BRIDGE_SELECTED_OWNER_DAYCARE1
	jr z, .second
	ld a, [wDayCareInUse]
	and a
	ld e, 0
	jr nz, .found
.second
	ld a, [wRentalOwner]
	cp BRIDGE_SELECTED_OWNER_DAYCARE2
	jr z, .absent
	ld a, [wDayCareInUse2]
	and a
	ld e, 1
	jr nz, .found
.absent
	and a
	ret
.found
	scf
	ret

; e = occupied owned daycare slot. Match the voluntary lobby growth commit,
; MoveMon, and upgrade order; automatic payment never refuses a shortfall.
; Caller has reclaimed the rental and confirmed the party is empty.
RentalRetrieveDaycare::
	push de
	call RentalChargeDaycare
	pop de
	push de
	rfarcall GetRewardMonLevel
	pop de
	ld hl, wDayCareMonBoxLevel
	ld bc, wDayCareDepositBattleCount
	ld a, DAYCARE_DATA
	ld d, a
	ld a, e
	and a
	jr z, .slotReady
	ld hl, wDayCareMon2BoxLevel
	ld bc, wDayCareDepositBattleCount2
	ld d, DAYCARE_DATA2
.slotReady
	ld a, [hl]
	push af ; deposited level, retained across growth and MoveMon
	push de ; daycare index and data location
	ld a, [bc]
	ld b, a
	ld a, [wBattleCount]
	cp b
	jr z, .move
	ld a, [wCurEnemyLevel]
	cp [hl]
	jr c, .move
	jr z, .move
	ld [hl], a
	push af ; target level
	ld a, d
	ld [wMonDataLocation], a
	call LoadMonData
	pop af
	ld d, a
	rfarcall CalcExperience
	pop de
	push de
	ld hl, wDayCareMonExp
	ld a, e
	and a
	jr z, .expReady
	ld hl, wDayCareMon2Exp
.expReady
	ldh a, [hExperience]
	ld [hli], a
	ldh a, [hExperience + 1]
	ld [hli], a
	ldh a, [hExperience + 2]
	ld [hl], a
.move
	pop de
	push de
	ld a, [wDayCareMonSpecies]
	ld b, a
	ld a, e
	and a
	jr z, .speciesReady
	ld a, [wDayCareMon2Species]
	ld b, a
.speciesReady
	ld a, b
	ld [wCurPartySpecies], a
	ld a, DAYCARE_TO_PARTY
	ld b, a
	ld a, e
	and a
	jr z, .typeReady
	ld b, DAYCARE_TO_PARTY2
.typeReady
	ld a, b
	ld [wMoveMonType], a
	call MoveMon
	pop de
	pop af ; deposited level
	; Upgrade uses slot 1's scratch for either slot. Preserve the other slot.
	ld b, a
	ld a, [wDayCareStartLevel]
	push af
	ld a, b
	ld [wDayCareStartLevel], a
	push de
	call SaveScreenTilesToBuffer2
	rfarcall DaycareRetrieveUpgrade
	pop de
	pop af
	ld [wDayCareStartLevel], a
	; MoveMon has already transferred bridge-effect ownership to the party.
	ld a, e
	and a
	jp z, RentalReclaimDaycare.clearFirst
	jp RentalReclaimDaycare.clearSecond

; Full settlement entry. Valid owners are preflighted before any mutation.
; Success returns carry with an owned healed party and a full save. No owned
; candidate uses the normal nonreturning blackout/Dorm lifecycle instead.
RentalSettleAndSave::
	ld a, [wRentalState]
	and a
	ret z
	cp RENTAL_RUN_END_SAVE_PENDING
	jp z, .invalid
	ld a, [wRentalOwner]
	cp BRIDGE_SELECTED_OWNER_MAX + 2
	jp nc, .invalid
	; An inactive-box owner requires initialized SRAM boxes.
	cp BRIDGE_SELECTED_OWNER_BOX_BASE
	jr c, .ready
	cp BRIDGE_SELECTED_OWNER_DAYCARE1
	jr nc, .ready
	ld a, [wCurrentBoxNum]
	bit BIT_HAS_CHANGED_BOXES, a
	jr nz, .ready
	; Before the first box change, only the current WRAM box is valid.
	ld a, [wRentalOwner]
	sub BRIDGE_SELECTED_OWNER_BOX_BASE
	ld b, a
	ld a, [wCurrentBoxNum]
	and BOX_NUM_MASK
	ld e, a
	add a
	add a
	add e
	add a
	add a
	ld e, a
	ld a, b
	sub e
	cp MONS_PER_BOX
	jp nc, .invalid
.ready
	; Identify an owned survivor before destructive reclaim. Finders exclude
	; the exact rental location, even when its daycare would otherwise win.
	ld a, [wPartyCount]
	cp 2
	jr nc, .recover
	and a
	jr z, .needFallback
	ld a, [wRentalOwner]
	cp 1
	jr nz, .recover
.needFallback
	call RentalFindBoxFallback
	jr c, .recover
	call RentalFindDaycareFallback
	jr c, .recover
	call RentalReclaimAll
	ret nc
	jr .endRun
.recover
	call RentalReclaimAll
	ret nc
	call RentalRestoreBoxedParty
	jr c, .save
	call RentalFindDaycareFallback
	jr nc, .endRun
	call RentalRetrieveDaycare
	predef HealParty
.save
	xor a
	ld [wRentalState], a
	ld [wRentalZone], a
	rfarcall SaveGameData
	scf
	ret
.invalid
	and a
	ret
.endRun
	ld a, RENTAL_RUN_END_SAVE_PENDING
	ld [wRentalState], a
	jp HandleBlackOut
