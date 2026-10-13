; Single-rental ownership, stable offers, delivery and zone-return settlement.
; The lobby receptionist uses the shared interaction; wild providers can reuse it.
; Inputs use de/e because Bankswitch replaces a, bc and hl.

DEF RENTAL_RESERVED EQU 1
DEF RENTAL_ACTIVE EQU 2
DEF BIT_RENTAL_OPPORTUNITY_USED EQU 0
DEF BIT_RENTAL_ZONE_ENTERED EQU 7

; Offer flag 0 latches identity/DVs; flag 1 latches the completed moveset.
; Both flags must be set before delivery can charge for the displayed offer.
DEF BIT_RENTAL_OFFER_IDENTITY EQU 0
DEF BIT_RENTAL_OFFER_MOVES EQU 1

; Repeated inspection of a latched offer consumes no RNG and preserves its
; identity. Clear the offer only at a completed logical opportunity,
; never merely on dialogue cancellation, bridge return, or lobby reload.
RentalPrepareOfferIdentity::
	call RentalCanPrepareOffer
	ret nc
	ld a, [wRentalOfferFlags]
	bit BIT_RENTAL_OFFER_IDENTITY, a
	jp nz, RentalValidateOfferIdentity
	ld a, [wCurEnemyLevel]
	push af
	ld a, [wCurPartySpecies]
	push af
	ld a, [wCurSpecies]
	push af
	ld a, [wFormContextSpecies]
	push af
	ld a, [wFormContextForm]
	push af
	call RentalClearOfferBytes
	call Random
	ld b, a
	ld e, 1
	ld a, SALESMAN_CLASS_POKEBALL_MAX
	cp b
	jr nc, .classReady
	inc e
	ld a, SALESMAN_CLASS_GREATBALL_MAX
	cp b
	jr nc, .classReady
	inc e
.classReady
	ld a, e
	ld [wRentalOfferClass], a
	rfarcall GetRewardMonLevel
	ld a, [wCurEnemyLevel]
	ld [wRentalOfferLevel], a
	ld a, [wRentalOfferClass]
	ld e, a
	rfarcall Random_Pokemon_Selection_Far
	ld a, d
	ld [wRentalOfferSpecies], a
	ld a, e
	ld [wRentalOfferForm], a
	call Random
	ld [wRentalOfferDVs], a
	call Random
	ld [wRentalOfferDVs + 1], a
	ld a, DV_BOOSTER
	ld [wCurItem], a
	rfarcall GetKeyItemPowerInE
	ld a, e
	and a
	jr z, .dvsReady
	dec a
	ld c, a
	ld b, 0
	ld hl, RentalDVFloorTable
	add hl, bc
	ld e, [hl]
	ld hl, wRentalOfferDVs
	ld a, [hl]
	call RentalApplyDVFloor
	ld [hli], a
	ld a, [hl]
	call RentalApplyDVFloor
	ld [hl], a
.dvsReady
	pop af
	ld [wFormContextForm], a
	pop af
	ld [wFormContextSpecies], a
	pop af
	ld [wCurSpecies], a
	pop af
	ld [wCurPartySpecies], a
	pop af
	ld [wCurEnemyLevel], a
	ld a, 1 << BIT_RENTAL_OFFER_IDENTITY
	ld [wRentalOfferFlags], a
	jr RentalValidateOfferIdentity

RentalCanPrepareOffer:
	ldh a, [hIsInBattle]
	and a
	ret nz
	ld a, [wRentalState]
	and a
	ret nz
	ld a, [wRentalOwner]
	and a
	ret nz
	scf
	ret

; Carry = coherent identity. Fail closed on corrupted latched fields rather
; than silently rerolling a displayed offer. Source/moves remain unfinished.
RentalValidateOfferIdentity:
	ld a, [wRentalOfferSpecies]
	and a
	ret z
	ld a, [wRentalOfferForm]
	cp 4
	jr nc, .invalid
	ld a, [wRentalOfferClass]
	dec a
	cp 3
	jr nc, .invalid
	ld a, [wRentalOfferLevel]
	and a
	ret z
	cp MAX_LEVEL + 1
	jr nc, .invalid
	scf
	ret
.invalid
	and a
	ret

RentalClearOfferIdentity::
	call RentalCanPrepareOffer
	ret nc
	call RentalClearOfferBytes
	scf
	ret
RentalClearOfferBytes:
	ld hl, wRentalOfferSpecies
	ld bc, wMainDataEnd - wRentalOfferSpecies
	xor a
	jp FillMemory

; Exact half of the salesman's BCD-thousands price, encoded at assembly time.
; Carry = quote in hMoney; no money/party mutation, no RNG or SRAM access.
RentalQuoteOffer::
	ld a, [wRentalOfferFlags]
	bit BIT_RENTAL_OFFER_IDENTITY, a
	jr z, .invalid
	call RentalValidateOfferIdentity
	ret nc
	ld a, [wRentalOfferClass]
	dec a
	ld e, a
	add a
	add e
	ld e, a
	ld d, 0
	ld hl, RentalPriceTable
	add hl, de
	ld de, hMoney
	ld bc, 3
	call CopyData
	scf
	ret
.invalid
	and a
	ret

RentalPriceTable:
	bcd3 (((SALESMAN_PRICE_POKEBALL_BCD >> 4) * 10 + (SALESMAN_PRICE_POKEBALL_BCD & $f)) * 1000) / 2
	bcd3 (((SALESMAN_PRICE_GREATBALL_BCD >> 4) * 10 + (SALESMAN_PRICE_GREATBALL_BCD & $f)) * 1000) / 2
	bcd3 (((SALESMAN_PRICE_ULTRABALL_BCD >> 4) * 10 + (SALESMAN_PRICE_ULTRABALL_BCD & $f)) * 1000) / 2

; Same packed-nibble rule/floors as AddPartyMon and GetRogueOfferDVsFloored.
; Capture the floor once so changing a key item later cannot change the offer.
RentalApplyDVFloor:
	push af
	and $f
	cp e
	jr nc, .lowReady
	ld a, e
.lowReady
	ld d, a
	pop af
	swap a
	and $f
	cp e
	jr nc, .highReady
	ld a, e
.highReady
	swap a
	or d
	ret
RentalDVFloorTable:
	db 6, 10, 13

; Complete a stable offer without creating a player mon or charging money.
; Enemy mon and the trainer/menu union are backed up on the 256-byte stack.
; Fixed assembly-time copies keep stack depth independent of counted loops.
; Header/learnset scratch is intentionally clobbered, as in identity generation.
DEF RENTAL_TRAINER_BACKUP_LENGTH EQU 32
ASSERT ((wPartyGenScratchEnd - wPartyGenScratch + 1) / 2) * 2 == RENTAL_TRAINER_BACKUP_LENGTH
ASSERT PARTYMON_STRUCT_LENGTH % 2 == 0
RentalPrepareOfferMoves::
	call RentalPrepareOfferIdentity
	ret nc
	ld a, [wRentalOfferFlags]
	bit BIT_RENTAL_OFFER_MOVES, a
	jp nz, RentalValidateOfferMoves
	ld a, [wCurEnemyLevel]
	push af
	ld a, [wCurPartySpecies]
	push af
	ld a, [wCurSpecies]
	push af
	ld a, [wFormContextSpecies]
	push af
	ld a, [wFormContextForm]
	push af
	ld a, [wEnemyPartyCount]
	push af
	ld a, [wEnemyMoveOrigins]
	push af
	ld hl, wEnemyMon1
	REPT PARTYMON_STRUCT_LENGTH / 2
	ld e, [hl]
	inc hl
	ld d, [hl]
	inc hl
	push de
	ENDR
; Include the adjacent byte in this even-sized backup; restore it unchanged.
	ld hl, wPartyGenScratch
	REPT RENTAL_TRAINER_BACKUP_LENGTH / 2
	ld e, [hl]
	inc hl
	ld d, [hl]
	inc hl
	push de
	ENDR
	ld hl, wEnemyMon1
	ld bc, PARTYMON_STRUCT_LENGTH
	xor a
	call FillMemory
	inc a
	ld [wEnemyPartyCount], a
	ld a, [wRentalOfferSpecies]
	ld [wEnemyMon1Species], a
	ld a, [wRentalOfferForm]
	swap a
	add a
	ld [wEnemyMon1CatchRate], a
	ld a, [wRentalOfferLevel]
	ld [wCurEnemyLevel], a
	ld [wEnemyMon1Level], a
	rfarcall RentalGenerateMovesForSlot
	ld hl, wEnemyMon1Moves
	ld de, wRentalOfferMoves
	ld bc, NUM_MOVES
	call CopyData
	ld hl, wPartyGenScratch + ((wPartyGenScratchEnd - wPartyGenScratch + 1) / 2) * 2 - 1
	REPT RENTAL_TRAINER_BACKUP_LENGTH / 2
	pop de
	ld [hl], d
	dec hl
	ld [hl], e
	dec hl
	ENDR
	ld hl, wEnemyMon1 + PARTYMON_STRUCT_LENGTH - 1
	REPT PARTYMON_STRUCT_LENGTH / 2
	pop de
	ld [hl], d
	dec hl
	ld [hl], e
	dec hl
	ENDR
	pop af
	ld [wEnemyMoveOrigins], a
	pop af
	ld [wEnemyPartyCount], a
	pop af
	ld [wFormContextForm], a
	pop af
	ld [wFormContextSpecies], a
	pop af
	ld [wCurSpecies], a
	pop af
	ld [wCurPartySpecies], a
	pop af
	ld [wCurEnemyLevel], a
	call RentalValidateOfferMoves
	ret nc
	ld hl, wRentalOfferFlags
	set BIT_RENTAL_OFFER_MOVES, [hl]
	scf
	ret

RentalValidateOfferMoves:
	call RentalValidateOfferIdentity
	ret nc
	ld hl, wRentalOfferMoves
	ld a, [hl]
	and a
	ret z
	ld b, NUM_MOVES
.check
	ld a, [hli]
	cp NUM_ATTACKS + 1
	jr nc, .invalid
	dec b
	jr nz, .check
	scf
	ret
.invalid
	and a
	ret

; Paid delivery API. Full parties append to the current box if it has room.
; Carry = success; e = owner slot on success, 1 unavailable, 2 invalid offer,
; 3 creation rejected, 4 insufficient money, 5 spawn pending, 6 party/box full.
; Failure is mutation-free
; except hMoney/scratch. Caller must provide a complete displayed offer.
RentalDeliverOffer::
	call RentalCanPrepareOffer
	ld e, 1
	ret nc
	ld a, [wRentalFlags]
	bit BIT_RENTAL_OPPORTUNITY_USED, a
	jp nz, .fail
	ld e, 2
	ld a, [wRentalOfferFlags]
	and 3
	cp 3
	jp nz, .fail
	call RentalValidateOfferMoves
	jp nc, .invalid
	ld e, 3
	ld a, [wPartyCount]
	cp PARTY_LENGTH
	jr c, .capacityReady
	ld e, 6
	ld a, [wBoxCount]
	cp MONS_PER_BOX
	jp nc, .fail
.capacityReady
	ld e, 5
	ld a, [wSpawnForm]
	and a
	jp nz, .fail
	ld a, [wSpawnDVSlot]
	and a
	jp nz, .fail
	call RentalQuoteOffer
	call HasEnoughMoney
	ld e, 4
	jp c, .fail
	ld a, [wPartyCount]
	cp PARTY_LENGTH
	jr c, .partyCreation
	call RentalCreateBoxOffer
	jp nc, .fail
	jr .created
.partyCreation
	ld a, [wMonDataLocation]
	push af
	ld a, $10                     ; player party, no blocking naming screen
	ld [wMonDataLocation], a
	ld a, [wRentalOfferSpecies]
	ld [wCurPartySpecies], a
	ld a, [wRentalOfferLevel]
	ld [wCurEnemyLevel], a
	ld a, [wRentalOfferForm]
	ld [wSpawnForm], a
	call AddPartyMon
	jr nc, .creationFailed
	pop af
	ld [wMonDataLocation], a
	call RentalFinalizeDeliveredMon
	ld a, [wPartyCount]
	ld e, a
.created
	ld a, e
	ld [wRentalOwner], a
; Re-quote after creation's scratch work, then charge exactly once. No money
; mutation occurs in AddPartyMon/finalization between preflight and this point.
	call RentalQuoteOffer
	ld hl, hMoney + 2
	ld de, wPlayerMoney + 2
	ld c, 3
	predef SubBCDPredef
	ld a, RENTAL_RESERVED
	ld [wRentalState], a
	xor a
	ld [wRentalZone], a
	ld hl, wRentalFlags
	set BIT_RENTAL_OPPORTUNITY_USED, [hl]
	call RentalRecordMapLoad
	ld e, 0
	scf
	ret
.creationFailed
	pop af
	ld [wMonDataLocation], a
	xor a
	ld [wSpawnForm], a
	ld [wSpawnDVSlot], a
	ld e, 3
	ret
.invalid
	ld e, 2
.fail
	and a
	ret

RentalDeliveredMonBase:
	ld a, [wPartyCount]
	dec a
	ld hl, wPartyMons
	ld bc, PARTYMON_STRUCT_LENGTH
	jp AddNTimes

RentalFinalizeDeliveredMon:
	call RentalDeliveredMonBase
	ld bc, MON_DVS
	add hl, bc
	ld d, h
	ld e, l
	ld hl, wRentalOfferDVs
	ld bc, 2
	call CopyData
	call RentalDeliveredMonBase
	ld bc, MON_MOVES
	add hl, bc
	ld d, h
	ld e, l
	ld hl, wRentalOfferMoves
	ld bc, NUM_MOVES
	call CopyData
	call RentalDeliveredMonBase
	ld bc, MON_MOVES
	add hl, bc
	ld b, NUM_MOVES
.pp
	push bc
	push hl
	ld e, [hl]
	ld a, e
	and a
	jr z, .ppReady
	rfarcall GetMoveMaxPPFar
.ppReady
	pop hl
	push hl
	ld bc, MON_PP - MON_MOVES
	add hl, bc
	ld [hl], e
	pop hl
	inc hl
	pop bc
	dec b
	jr nz, .pp
	call RentalDeliveredMonBase
	ld a, [hl]
	ld [wCurSpecies], a
	ld [wNamedObjectIndex], a
	call PublishFormContext
	call GetMonHeader
	call GetMonName
	ld hl, wPartyMonNicks
	ld a, [wPartyCount]
	dec a
	call SkipFixedLengthTextEntries
	ld d, h
	ld e, l
	ld hl, wNameBuffer
	ld bc, NAME_LENGTH
	call CopyData
	call RentalDeliveredMonBase
	ld bc, MON_MAXHP
	add hl, bc
	ld d, h
	ld e, l
	rfarcall PrepareFusionAndBridgeRayCalcStats
	ld hl, (MON_HP_EXP - 1) - MON_MAXHP
	add hl, de
	ld b, 0
	call CalcStats
	call RentalDeliveredMonBase
	push hl
	ld bc, MON_MAXHP
	add hl, bc
	ld a, [hli]
	ld d, a
	ld e, [hl]
	pop hl
	inc hl                        ; MON_HP
	ld [hl], d
	inc hl
	ld [hl], e
	ret

; Keep the variant renderer in its existing bank. e identifies the HUD side;
; the rental uses a separate cell and the actual player party slot.
DrawBattleOwnershipMarkers::
	push de
	rfarcall DrawBattleVariantMarker
	pop de
	ld a, e
	cp 1
	ret z
	ld a, [wPlayerMonNumber]
	ld e, a
	call RentalHasPartyMarker
	ret nc
	hlcoord 12, 8
	ld [hl], 'R'
	ret

RentalHasPartyMarker:
	ld a, [wRentalState]
	cp RENTAL_RESERVED
	jr z, .party
	cp RENTAL_ACTIVE
	jr nz, .absent
.party
	jp RentalIsPartySlot
.absent
	and a
	ret

; Same location mapping as BridgePrepareCalcStats' loaded-mon query.
; Place the marker immediately left of the HP label on the HP status page.
RentalDrawStatusMarker::
	hlcoord 10, 3
	ld [hl], ' '
	ld a, [wRentalState]
	cp RENTAL_RESERVED
	jr z, .location
	cp RENTAL_ACTIVE
	ret nz
.location
	ld a, [wMonDataLocation]
	and a ; PLAYER_PARTY_DATA
	jr z, .party
	cp BOX_DATA
	jr z, .box
	ld b, BRIDGE_SELECTED_OWNER_DAYCARE1
	cp DAYCARE_DATA
	jr z, .match
	inc b
	cp DAYCARE_DATA2
	ret nz
	jr .match
.party
	ldh a, [hWhichPokemon]
	cp PARTY_LENGTH
	ret nc
	inc a
	ld b, a
	jr .match
.box
	ldh a, [hWhichPokemon]
	cp MONS_PER_BOX
	ret nc
	ld e, a
	ld a, [wCurrentBoxNum]
	and $7f
	cp NUM_BOXES
	ret nc
	ld b, a
	ld a, 7
	inc b
.boxLoop
	dec b
	jr z, .boxSlot
	add MONS_PER_BOX
	jr .boxLoop
.boxSlot
	add e
	ld b, a
.match
	ld a, [wRentalOwner]
	cp b
	ret nz
	hlcoord 10, 3
	ld [hl], 'R'
	ret

; LoadMapData runs before graphics restoration. Only latch identity here;
; never open text, upgrade a daycare Pokemon, or save from this seam.
; An active contract keeps its root map across internal maps and reloads.
RentalRecordMapLoad::
	call GetCurMapStageClass
	and 3
	jr nz, .bind
	ldh a, [hCurMap]
	ld hl, .extraZones
.scan
	ld b, [hl]
	inc hl
	inc b
	ret z
	dec b
	cp b
	jr nz, .scan
.bind
	ld hl, wRentalFlags
	set BIT_RENTAL_ZONE_ENTERED, [hl]
	ld a, [wRentalState]
	cp RENTAL_RESERVED
	ret nz
	ldh a, [hCurMap]
	ld [wRentalZone], a
	ld a, RENTAL_ACTIVE
	ld [wRentalState], a
	ret
.extraZones
	; Cemetery floors are one area. A new in-area delivery binds on its
	; current floor; subsequent floor changes cannot rebind or consume it.
	db PROCEDURAL_CEMETERY_1, PROCEDURAL_CEMETERY_2
	db PROCEDURAL_CEMETERY_3, PROCEDURAL_CEMETERY_4
	db PEWTER_GYM, CERULEAN_GYM, VERMILION_GYM, CELADON_GYM
	db FUCHSIA_GYM, SAFFRON_GYM, CINNABAR_GYM, VIRIDIAN_GYM
	db VIOLET_GYM, AZALEA_GYM, GOLDENROD_GYM, ECRUTEAK_GYM
	db CIANWOOD_GYM, OLIVINE_GYM, MAHOGANY_GYM, BLACKTHORN_GYM
	db -1

; Loaded hub scripts call this BEFORE setting EVENT_ENTER_ROOM or selecting
; the next destination. A settlement save can therefore resume hub setup on
; Continue. Reserved rentals survive pre-use hub/Dorm/bridge visits.
RentalSettleZoneReturn::
	ldh a, [hCurMap]
	cp INDIGO_PLATEAU_LOBBY
	jr z, .settle
	cp REWARD_ROOM
	ret nz
.settle
	ld a, [wRentalState]
	cp RENTAL_ACTIVE
	jp nz, RentalAdvanceOpportunity
	call UpdateSprites
	call RentalSettleAndSave
	ret nc
	ld de, RentalTeamReadyText
	jr RentalSettlementPopup

 ; Advance only after a real ordinary zone was entered. No rental is required.
; Preserve a reserved contract and refuse pending run-end/corrupt ownership.
; Called again before settlement saves, so Continue cannot revive the old offer.
RentalAdvanceOpportunity::
	ld a, [wRentalState]
	and a
	ret nz
	ld a, [wRentalOwner]
	and a
	ret nz
	ld hl, wRentalFlags
	bit BIT_RENTAL_ZONE_ENTERED, [hl]
	ret z
	res BIT_RENTAL_ZONE_ENTERED, [hl]
	res BIT_RENTAL_OPPORTUNITY_USED, [hl]
	jp RentalClearOfferBytes

; Match RogueCreditPopupCheck's bounded map overlay lifecycle. Buffer3 is
; temporary screen storage, never saved contract state. Settlement has already
; saved before this notice, so reset/Continue cannot repeat the transaction.
RentalSettlementPopup::
	push de
	hlcoord 1, 1
	lb bc, 18, 5
	predef SaveScreenTileAreaToBuffer3
	hlcoord 1, 1
	ld b, 3
	ld c, 16
	call TextBoxBorder
	hlcoord 2, 2
	ld de, RentalEndedText
	call PlaceString
	pop de
	hlcoord 2, 3
	call PlaceString
	hlcoord 2, 4
	ld de, RentalSavedText
	call PlaceString
	; Use the ordinary text-window lifecycle. WRAM tiles alone are invisible
	; in the overworld (automatic transfer is off and WY is below the screen).
	; CloseTextDisplay consumes this saved bank before returning to our caller.
	ldh a, [hLoadedROMBank]
	push af
	ld hl, wAutoTextBoxDrawingControl
	ld a, [hl]
	push af
	set BIT_NO_AUTO_TEXT_BOX, [hl] ; the overlay already has its own border
	rfarcall DisplayTextIDInit
	pop af
	ld [wAutoTextBoxDrawingControl], a
	ld c, 90
	call DelayFrames
	hlcoord 1, 1
	lb bc, 18, 5
	predef LoadScreenTileAreaFromBuffer3
.restored
	jp CloseTextDisplay

RentalEndedText:
	db "RENTAL ENDED.@"
RentalTeamReadyText:
	db "TEAM HEALED.@"
RentalRunEndedText:
	db "NO OWNED #MON.@"
RentalSavedText:
	db "GAME SAVED.@"

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
	rfarcall SaveGameData
	ld de, RentalRunEndedText
	jp RentalSettlementPopup

; Archive records can become live owned Pokemon again. Settle a party rental
; before capture; holders outside the captured party are not being replaced.
RentalPrepareArchiveCapture::
	ld a, [wRentalOwner]
	and a
	jr z, .ownedParty
	cp PARTY_LENGTH + 1
	jr nc, .ownedParty
	call RentalSettleAndSave
	ret c
	xor a
	ld [wActionResultOrTookBattleTurn], a
	ret
.ownedParty
	scf
	ret

; A successful full-party overwrite discards only its old location pointer.
; Retain contract/opportunity metadata and every rental outside the party.
RentalOnPartyReplacement::
	ld a, [wRentalOwner]
	and a
	ret z
	cp PARTY_LENGTH + 1
	ret nc
	ld c, a
	xor a
	ld [wRentalOwner], a
	; Full-party restore bypasses RemovePokemon, just like daycare reclamation.
	; Fall through to discard the outgoing rental's independent bridge effect.

; c = discarded owner. Leave every other Pokemon's bridge effects unchanged.
RentalClearBridgeOwner:
	ld hl, wBridgeSelectedEffects
	ld b, BRIDGE_SELECTED_RECORD_COUNT
.effects
	ld a, [hl]
	cp c
	jr nz, .nextEffect
	xor a
	ld [hli], a
	ld [hl], a
	dec hl
.nextEffect
	inc hl
	inc hl
	dec b
	jr nz, .effects
	ret

; Same-size replacement of both debug bridge-clear calls; no new bank-$38
; bytes. Rebuilt debug parties cannot inherit either kind of old ownership.
RentalPrepareDebugParty::
	call RentalOnPartyReplacement
	rfarjp BridgeClearSelectedEffects

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
	ld a, [wRentalOwner]
	and a
	jr z, .done ; owned daycare retrieval already moved its effects to the party
	ld c, a
	call RentalClearBridgeOwner
	xor a
	ld [wRentalOwner], a
.done
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
	; Match fusion's post-removal reset: the old selected row may no longer
	; exist, and daycare recovery may also have used the party menu.
	ld [wPartyAndBillsPCSavedMenuItem], a
	ld [wRentalState], a
	ld [wRentalZone], a
	call RentalAdvanceOpportunity
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

; e = curated origin ID. Carry = official Stadium rental provenance.
; Bitmap is local to this bank; no text-label heuristics at runtime.
RentalIsStadiumOrigin::
	ld a, e
	and 7
	ld c, a
	ld a, e
	srl a
	srl a
	srl a
	ld e, a
	ld d, 0
	ld hl, RentalStadiumOrigins
	add hl, de
	ld a, [hl]
	inc c
.shift
	srl a
	dec c
	jr nz, .shift
	ret

INCLUDE "data/trainers/rental_origins.asm"

; Shared loaded-map interaction. Caller owns the ordinary text-window lifecycle.
; Preserve the text_asm cursor across generation, menus and delivery.
RentalInteraction::
	push bc
	call RentalInteractionBody
	; Each terminal message already waits via prompt. Do not wait twice.
	call DisableWaitingAfterTextDisplay
	pop bc
	ret

RentalInteractionBody:
	call RentalCanPrepareOffer
	ld hl, RentalUnavailableText
	jp nc, PrintText
	ld a, [wRentalFlags]
	bit BIT_RENTAL_OPPORTUNITY_USED, a
	ld hl, RentalUsedText
	jp nz, PrintText
	call RentalPrepareOfferMoves
	ld hl, RentalUnavailableText
	jp nc, PrintText
	call RentalQuoteOffer
	ld hl, RentalUnavailableText
	jp nc, PrintText
	ld hl, hMoney
	ld de, wPriceTemp
	ld bc, 3
	call CopyData
	ld a, [wRentalOfferSpecies]
	ld [wNamedObjectIndex], a
	ld [wFormContextSpecies], a
	ld a, [wRentalOfferForm]
	ld [wFormContextForm], a
	call GetMonName
	ld hl, RentalOfferText
	call PrintText
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
	ld hl, RentalDeclinedText
	jp nz, PrintText
	; Revalidates every precondition and re-quotes after menu scratch use.
	call RentalDeliverOffer
	jr c, .delivered
	ld a, e
	cp 3
	ld hl, RentalPartyFullText
	jp z, PrintText
	cp 6
	ld hl, RentalBoxFullText
	jp z, PrintText
	cp 4
	ld hl, RentalNoMoneyText
	jp z, PrintText
	ld hl, RentalUnavailableText
	jp PrintText
.delivered
	ld a, SFX_PURCHASE
	call PlaySoundWaitForCurrent
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	ld a, [wRentalOwner]
	cp 7
	ld hl, RentalDeliveredText
	jp c, PrintText
	ld hl, RentalBoxDeliveredText
	jp PrintText

RentalOfferText:
	text "Rent this #MON?"
	para "@"
	text_ram wNameBuffer
	text_start
	line "Level @"
	text_decimal wRentalOfferLevel, 1, 3
	text_start
	para "One zone: ¥@"
	text_bcd wPriceTemp, 3 | LEADING_ZEROES | LEFT_ALIGN
	text_start
	line "Rent it?"
	prompt
RentalDeliveredText:
	text "Rental is ready!"
	line "Enjoy your zone!"
	prompt
RentalDeclinedText:
	text "Come back later!"
	prompt
RentalUnavailableText:
	text "No rental is"
	line "available now."
	prompt
RentalUsedText:
	text "You've rented for"
	line "this opportunity."
	prompt
RentalPartyFullText:
	text "Make room in your"
	line "party first."
	prompt
RentalNoMoneyText:
	text "Not enough money!"
	prompt

; Two lobby-only fixed poses share the otherwise unused 12-tile base 10.
; d = candidate full-sheet slot; e = picture ID. Return e = image base.
RentalResolveSpriteSlot::
	ld a, e
	cp SPRITE_LOBBY_MOVE_TUTOR
	ld e, 13
	ret z
	cp SPRITE_LOBBY_RENTAL_OFFICIAL
	ld e, 14
	ret z
	ld e, d
	cp FIRST_EXTRA_WALKING_SPRITE
	ret nc
	cp FIRST_STILL_SPRITE
	ret c
	ldh a, [hFourTileSpriteCount]
	add 11
	ld e, a
	ret

RentalSmallSpriteDestination::
	ldh a, [hVRAMSlot]
	cp 13
	ld hl, vSprites tile $6c
	ret z
	cp 14
	ld hl, vSprites tile $70
	ret z
	ld hl, vSprites tile $7c
	ldh a, [hFourTileSpriteCount]
	and a
	ret nz
	ld hl, vSprites tile $78
	inc a
	ldh [hFourTileSpriteCount], a
	ret

RentalBoxFullText:
	text "Your party and"
	line "PC box are full!"
	prompt

; Full-party delivery borrows the final slot only while synchronous creation
; runs, then appends its boxed representation and restores the owned mon.
; No menus, owner-transfer hooks or removal routines run on the borrowed slot.
RentalCreateBoxOffer:
	ld a, [wBoxCount]
	push af
	ld hl, wPartyMon6
	REPT 22
	ld e, [hl]
	inc hl
	ld d, [hl]
	inc hl
	push de
	ENDR
	ld hl, wPartyMon6OT
	REPT 5
	ld e, [hl]
	inc hl
	ld d, [hl]
	inc hl
	push de
	ENDR
	ld a, [hl]
	push af
	ld hl, wPartyMon6Nick
	REPT 5
	ld e, [hl]
	inc hl
	ld d, [hl]
	inc hl
	push de
	ENDR
	ld a, [hl]
	push af
	ld a, [wMonDataLocation]
	push af
	ld a, 5
	ld [wPartyCount], a
	ld a, $10
	ld [wMonDataLocation], a
	ld a, [wRentalOfferSpecies]
	ld [wCurPartySpecies], a
	ld a, [wRentalOfferLevel]
	ld [wCurEnemyLevel], a
	ld a, [wRentalOfferForm]
	ld [wSpawnForm], a
	call AddPartyMon
	jr nc, .failed
	call RentalFinalizeDeliveredMon
	pop af
	ld [wMonDataLocation], a
	ld a, [wBoxCount]
	ld hl, wBoxMons
	ld bc, BOXMON_STRUCT_LENGTH
	call AddNTimes
	push hl
	ld d, h
	ld e, l
	ld hl, wPartyMon6
	ld bc, BOXMON_STRUCT_LENGTH
	call CopyData
	pop hl
	ld bc, MON_BOX_LEVEL
	add hl, bc
	ld a, [wPartyMon6Level]
	ld [hl], a
	ld a, [wBoxCount]
	ld hl, wBoxMonOT
	call SkipFixedLengthTextEntries
	ld d, h
	ld e, l
	ld hl, wPartyMon6OT
	ld bc, NAME_LENGTH
	call CopyData
	ld a, [wBoxCount]
	ld hl, wBoxMonNicks
	call SkipFixedLengthTextEntries
	ld d, h
	ld e, l
	ld hl, wPartyMon6Nick
	ld bc, NAME_LENGTH
	call CopyData
	ld a, [wBoxCount]
	ld e, a
	ld d, 0
	ld hl, wBoxSpecies
	add hl, de
	ld a, [wRentalOfferSpecies]
	ld [hli], a
	ld [hl], $ff
	ld hl, wBoxCount
	inc [hl]
	jr .restore
.failed
	pop af
	ld [wMonDataLocation], a
	xor a
	ld [wSpawnForm], a
	ld [wSpawnDVSlot], a
.restore
	ld hl, wPartyMon6Nick + 10
	pop af
	ld [hl], a
	dec hl
	REPT 5
	pop de
	ld [hl], d
	dec hl
	ld [hl], e
	dec hl
	ENDR
	ld hl, wPartyMon6OT + 10
	pop af
	ld [hl], a
	dec hl
	REPT 5
	pop de
	ld [hl], d
	dec hl
	ld [hl], e
	dec hl
	ENDR
	ld hl, wPartyMon6 + 43
	REPT 22
	pop de
	ld [hl], d
	dec hl
	ld [hl], e
	dec hl
	ENDR
	ld a, [wPartyMon6Species]
	ld [wPartySpecies + 5], a
	ld a, PARTY_LENGTH
	ld [wPartyCount], a
	pop de ; d = original box count
	ld a, [wBoxCount]
	cp d
	ld e, 3
	ret z
	ld a, [wCurrentBoxNum]
	and BOX_NUM_MASK
	ld b, a
	ld a, [wBoxCount]
	dec a
	ld e, a
	ld a, b
	add a
	add a
	ld b, a
	add a
	add a
	add b
	add e
	add 7
	ld e, a
	scf
	ret

RentalBoxDeliveredText:
	text "Rental is ready!"
	line "Sent to PC box."
	prompt
