; Sparse ownership for bridge effects that target one Pokémon.
;
; A selected effect is stored as one [owner, effect] pair in
; wBridgeSelectedEffects. BRIDGE_PER_RUN is two, so this registry costs four
; persistent bytes total and does not enlarge party_struct or box_struct.
; Owner 0 is empty. Party and box owners are location identifiers, not species
; identifiers, so duplicate species remain distinguishable and box changes do
; not require a scan of SRAM. Quick Claw (special Nidoran female) and
; Intimidating Presence (special Growlithe) are intrinsic special-form traits;
; they deliberately do not enter this registry.
;
; Public grant/query routines use e for an effect when a farcall may be used.
; BridgeGrantSelectedEffect expects hWhichPokemon to identify a party slot and
; returns carry set only when the record was created. A selected effect blocks
; any other selected effect on the same Pokémon; a full registry also refuses
; without changing either record.

; ============================================================
; Public selected-effect interface
; ============================================================

; In:  e = BRIDGE_SELECTED_EFFECT_*, hWhichPokemon = party slot (0..5)
; Out: carry set when the effect was recorded; clear on invalid/full/occupied.
BridgeGrantSelectedEffect::
	ld a, e
	cp BRIDGE_SELECTED_EFFECT_CRITICAL_RATE
	jr c, .reject
	cp NUM_BRIDGE_SELECTED_EFFECTS + 1
	jr nc, .reject
	ld d, a                      ; d = effect, survives the owner lookup

	ldh a, [hWhichPokemon]
	cp PARTY_LENGTH
	jr nc, .reject
	ld b, a
	ld a, [wPartyCount]
	cp b                         ; cannot target an empty party slot
	jr c, .reject
	jr z, .reject
	inc b                         ; party owner = slot + 1

	; Only one selected effect may occupy a given owner. This also makes a
	; repeated gift selection a safe no-op rather than a stackable bonus.
	ld a, b
	call BridgeFindSelectedRecordByOwner
	jr c, .reject

	; The scan is intentionally bounded by BRIDGE_SELECTED_RECORD_COUNT, not by
	; a sentinel. Reload the owner from hWhichPokemon after the scan; d keeps the
	; effect throughout, so no stack scratch is needed on either refusal path.
	call BridgeFindEmptySelectedRecord
	jr nc, .reject
	ldh a, [hWhichPokemon]
	inc a
	ld [hli], a
	ld [hl], d
	ld a, d
	cp BRIDGE_SELECTED_EFFECT_SHRINK_RAY
	jr z, .recalculateRay
	cp BRIDGE_SELECTED_EFFECT_GROWTH_RAY
	jr nz, .granted
.recalculateRay
	push de
	call BridgeRecalculateGrantedRayMon
	pop de
.granted
	scf
	ret
.reject
	and a
	ret

; In:  e = BRIDGE_SELECTED_EFFECT_*, hWhichPokemon = party slot (0..5)
; Out: carry set if this party mon owns that selected effect.
BridgeHasSelectedEffect::
	ld a, e
	cp BRIDGE_SELECTED_EFFECT_CRITICAL_RATE
	jr c, .notFound
	cp NUM_BRIDGE_SELECTED_EFFECTS + 1
	jr nc, .notFound
	ld d, a                      ; requested effect
	ldh a, [hWhichPokemon]
	cp PARTY_LENGTH
	jr nc, .notFound
	ld b, a
	ld a, [wPartyCount]
	cp b
	jr c, .notFound
	jr z, .notFound
	inc b
	ld a, b
	call BridgeSelectedEffectForOwner
	jr nc, .notFound
	cp d
	jr z, .found
.notFound
	and a
	ret
.found
	scf
	ret

; In: e = BRIDGE_SELECTED_EFFECT_*. Query the active player's party owner.
; Out: carry set only when that active mon owns the requested effect.
BridgeActiveMonHasSelectedEffect::
	ld d, e
	ld a, [wPlayerMonNumber]
	inc a
	call BridgeSelectedEffectForOwner
	ret nc
	cp d
	jr z, .found
	and a
	ret
.found
	scf
	ret

; In:  a = owner identifier
; Out: carry set and a = selected effect when found; clear otherwise.
; This is the location-oriented query for battle hooks that already know the
; active party/box/daycare owner. Malformed effect bytes are ignored.
BridgeSelectedEffectForOwner::
	and a
	jr z, .notFound
	cp BRIDGE_SELECTED_OWNER_MAX + 1
	jr nc, .notFound
	call BridgeFindSelectedRecordByOwner
	jr nc, .notFound
	inc hl
	ld a, [hl]
	cp BRIDGE_SELECTED_EFFECT_CRITICAL_RATE
	jr c, .notFound
	cp NUM_BRIDGE_SELECTED_EFFECTS + 1
	jr nc, .notFound
	scf
	ret
.notFound
	and a
	ret

; In:  hWhichPokemon = party slot (0..5)
; Out: carry set and a = selected effect when found; clear otherwise.
BridgeSelectedEffectForPartyMon::
	ldh a, [hWhichPokemon]
	cp PARTY_LENGTH
	ret nc
	ld b, a
	ld a, [wPartyCount]
	cp b
	ret c
	ret z
	inc b
	ld a, b
	jp BridgeSelectedEffectForOwner

; Prepare both dynamic-stat systems immediately before CalcStats. de must point
; at MON_STATS. Fusion is identified in the mon struct; rays are identified by
; the sparse owner registry and use one transient WRAM selector.
PrepareFusionAndBridgeRayCalcStats::
	call PrepareFusionCalcStats
	push de
	xor a
	ld [wBridgeRayCalcEffect], a

	; Real party structs can be identified directly from their MON_STATS pointer.
	ld hl, wPartyMon1Stats
	ld b, 1
.partyLoop
	ld a, d
	cp h
	jr nz, .nextParty
	ld a, e
	cp l
	jr z, .queryOwner
.nextParty
	ld a, l
	add PARTYMON_STRUCT_LENGTH
	ld l, a
	jr nc, .noPartyCarry
	inc h
.noPartyCarry
	inc b
	ld a, b
	cp PARTY_LENGTH + 1
	jr nz, .partyLoop

	; Box/daycare status pages calculate display-only stats in wLoadedMon.
	ld hl, wLoadedMonStats
	ld a, d
	cp h
	jr nz, .done
	ld a, e
	cp l
	jr nz, .done
	ld a, [wMonDataLocation]
	cp PLAYER_PARTY_DATA
	jr z, .loadedParty
	cp BOX_DATA
	jr z, .loadedBox
	cp DAYCARE_DATA
	jr z, .daycare1
	cp DAYCARE_DATA2
	jr z, .daycare2
	jr .done
.loadedParty
	ldh a, [hWhichPokemon]
	inc a
	ld b, a
	jr .queryOwner
.loadedBox
	ldh a, [hWhichPokemon]
	call BridgeSelectedOwnerFromCurrentBoxSlot
	ld b, a
	jr .queryOwner
.daycare1
	ld b, BRIDGE_SELECTED_OWNER_DAYCARE1
	jr .queryOwner
.daycare2
	ld b, BRIDGE_SELECTED_OWNER_DAYCARE2
.queryOwner
	ld a, b
	call BridgeSelectedEffectForOwner
	jr nc, .done
	cp BRIDGE_SELECTED_EFFECT_SHRINK_RAY
	jr z, .store
	cp BRIDGE_SELECTED_EFFECT_GROWTH_RAY
	jr nz, .done
.store
	ld [wBridgeRayCalcEffect], a
.done
	pop de
	ret

; Shrink Ray's Speed and Attack are ordinary stored derived stats. Evasion has
; no party-struct stat, so initialize that one component on battle entry.
BridgeApplyShrinkRayEvasion::
	ld a, [wLinkState]
	cp LINK_STATE_BATTLING
	ret z
	ld a, [wPlayerMonNumber]
	inc a
	call BridgeSelectedEffectForOwner
	ret nc
	cp BRIDGE_SELECTED_EFFECT_SHRINK_RAY
	ret nz
	ld hl, wPlayerMonEvasionMod
	ld a, [hl]
	cp $d
	ret z
	inc [hl]
	ret

; Clear the complete sparse registry. New-game initialization already clears
; wGameProgressFlags, but debug battle builders reconstruct party data in-place
; and must call this explicitly (see their hooks).
BridgeClearSelectedEffects::
	ld hl, wBridgeSelectedEffects
	ld b, BRIDGE_SELECTED_RECORD_SIZE * BRIDGE_SELECTED_RECORD_COUNT
	xor a
.loop
	ld [hli], a
	dec b
	jr nz, .loop
	ret

; ============================================================
; Location and registry helpers
; ============================================================

; In:  a = compact slot in the currently loaded box (0..19)
; Out: a = absolute selected-effect owner for that slot.
BridgeSelectedOwnerFromCurrentBoxSlot:
	ld d, a
	call BridgeSelectedCurrentBoxBase
	add d
	ret

; Out: a = absolute owner for slot 0 of the currently loaded box.
; wCurrentBoxNum bit 7 is a save/UI marker, so mask it before indexing.
BridgeSelectedCurrentBoxBase:
	ld a, [wCurrentBoxNum]
	and BOX_NUM_MASK
	ld c, a
	add a
	ld b, a                      ; 2*n
	add a                         ; 4*n
	ld e, a                      ; 4*n
	add a                         ; 8*n
	add a                         ; 16*n
	add e                         ; 20*n
	add BRIDGE_SELECTED_OWNER_BOX_BASE
	ret

; In:  a = owner (nonzero)
; Out: carry set and hl -> owner byte when found; clear otherwise.
; de is preserved so callers can keep source/destination owners across scans.
BridgeFindSelectedRecordByOwner:
	ld c, a
	ld hl, wBridgeSelectedEffects
	ld b, BRIDGE_SELECTED_RECORD_COUNT
.loop
	ld a, [hl]
	cp c
	jr z, .found
	inc hl
	inc hl
	dec b
	jr nz, .loop
	and a
	ret
.found
	scf
	ret

; Out: carry set and hl -> owner byte of an empty record; clear when full.
BridgeFindEmptySelectedRecord:
	ld hl, wBridgeSelectedEffects
	ld b, BRIDGE_SELECTED_RECORD_COUNT
.loop
	ld a, [hl]
	and a
	jr z, .found
	inc hl
	inc hl
	dec b
	jr nz, .loop
	and a
	ret
.found
	scf
	ret

; In:  b = source owner, c = destination owner
; Out: carry set when the record was moved; clear on invalid/missing/conflict.
; The destination must be empty. Refusing a conflict avoids silently replacing
; a different effect if a future mutation path is missed.
BridgeMoveSelectedOwner::
	ld a, b
	and a
	jr z, .failed
	cp BRIDGE_SELECTED_OWNER_MAX + 1
	jr nc, .failed
	ld a, c
	and a
	jr z, .failed
	cp BRIDGE_SELECTED_OWNER_MAX + 1
	jr nc, .failed
	ld d, b
	ld e, c
	ld a, d
	call BridgeFindSelectedRecordByOwner
	jr nc, .failed
	push hl                     ; source record
	ld a, e
	call BridgeFindSelectedRecordByOwner
	jr c, .conflict
	pop hl
	ld a, e
	ld [hl], a                 ; move the owner, leave the effect byte intact
	scf
	ret
.conflict
	pop hl
.failed
	and a
	ret

; In:  a = owner
; Out: carry set when an existing record was cleared; clear when absent.
BridgeClearSelectedOwner::
	and a
	ret z
	call BridgeFindSelectedRecordByOwner
	ret nc
	xor a
	ld [hli], a
	ld [hl], a
	scf
	ret

; In: b = first owner to shift, c = last owner inclusive
; Decrement all owners in this interval. Used after RemovePokemon compacts a
; party/current-box list. Registry records are bounded and no sentinel scan is
; possible because owner 0 is a valid empty marker.
BridgeShiftSelectedOwnersDown:
	ld a, c
	cp b
	jr c, .done
	ld hl, wBridgeSelectedEffects
	ld d, BRIDGE_SELECTED_RECORD_COUNT
.loop
	ld a, [hl]
	cp b
	jr c, .next
	cp c
	jr z, .shift
	jr nc, .next
.shift
	dec [hl]
.next
	inc hl
	inc hl
	dec d
	jr nz, .loop
.done
	ret

; In: b = first owner to shift, c = last owner inclusive
; Increment all owners in this interval. Used by SendNewMonToBox, which
; front-inserts a new mon and shifts the old current-box records right.
BridgeShiftSelectedOwnersUp:
	ld a, c
	cp b
	jr c, .done
	ld hl, wBridgeSelectedEffects
	ld d, BRIDGE_SELECTED_RECORD_COUNT
.loop
	ld a, [hl]
	cp b
	jr c, .next
	cp c
	jr z, .shift
	jr nc, .next
.shift
	inc [hl]
.next
	inc hl
	inc hl
	dec d
	jr nz, .loop
.done
	ret

; ============================================================
; Central mutation hooks
; ============================================================

; Called only after _MoveMon successfully appends its destination record.
; hWhichPokemon identifies the source for party/box moves. The destination is
; always the newly appended last slot, while daycare transfers use fixed owner
; identifiers. The following RemovePokemon call then compacts the source list;
; because the owner has already moved domains, the compaction hook cannot clear
; it accidentally.
BridgeTrackMoveMon::
	ld a, [wMoveMonType]
	cp BOX_TO_PARTY
	jr z, .boxToParty
	cp PARTY_TO_BOX
	jr z, .partyToBox
	cp DAYCARE_TO_PARTY
	jr z, .daycare1ToParty
	cp PARTY_TO_DAYCARE
	jr z, .partyToDaycare1
	cp DAYCARE_TO_PARTY2
	jr z, .daycare2ToParty
	cp PARTY_TO_DAYCARE2
	jr z, .partyToDaycare2
	ret
.boxToParty
	ldh a, [hWhichPokemon]
	call BridgeSelectedOwnerFromCurrentBoxSlot
	ld b, a
	ld a, [wPartyCount]        ; appended last slot + 1 = owner value
	ld c, a
	jp BridgeMoveSelectedOwner
.partyToBox
	ldh a, [hWhichPokemon]
	inc a
	ld b, a
	ld a, [wBoxCount]
	dec a                      ; appended last compact box slot
	call BridgeSelectedOwnerFromCurrentBoxSlot
	ld c, a
	jp BridgeMoveSelectedOwner
.daycare1ToParty
	ld b, BRIDGE_SELECTED_OWNER_DAYCARE1
	ld a, [wPartyCount]
	ld c, a
	jp BridgeMoveSelectedOwner
.partyToDaycare1
	ldh a, [hWhichPokemon]
	inc a
	ld b, a
	ld c, BRIDGE_SELECTED_OWNER_DAYCARE1
	jp BridgeMoveSelectedOwner
.daycare2ToParty
	ld b, BRIDGE_SELECTED_OWNER_DAYCARE2
	ld a, [wPartyCount]
	ld c, a
	jp BridgeMoveSelectedOwner
.partyToDaycare2
	ldh a, [hWhichPokemon]
	inc a
	ld b, a
	ld c, BRIDGE_SELECTED_OWNER_DAYCARE2
	jp BridgeMoveSelectedOwner

; Called after _RemovePokemon has compacted the selected party/current box.
; Clear the removed owner's record first, then shift the surviving owners after
; it down by one. Daycare records are not touched by party/box removal.
BridgeTrackRemovePokemon::
	ld a, [wRemoveMonFromBox]
	and a
	jr nz, .box
	ldh a, [hWhichPokemon]
	cp PARTY_LENGTH
	ret nc
	inc a                      ; original party owner
	push af
	call BridgeClearSelectedOwner
	pop af
	inc a                      ; first surviving owner after removed slot
	ld b, a
	ld c, PARTY_LENGTH
	jp BridgeShiftSelectedOwnersDown
.box
	ldh a, [hWhichPokemon]
	cp MONS_PER_BOX
	ret nc
	ld d, a                    ; compact slot being removed
	call BridgeSelectedCurrentBoxBase
	ld e, a                    ; owner for current-box slot 0
	ld a, d
	add e
	ld d, a                    ; original owner
	push de
	ld a, d
	call BridgeClearSelectedOwner
	pop de
	ld a, e
	add MONS_PER_BOX - 1
	ld c, a                    ; final owner in this box
	ld a, d
	inc a
	ld b, a                    ; first surviving owner
	jp BridgeShiftSelectedOwnersDown

; Called after SendNewMonToBox front-inserts a new mon into the current box.
; Existing records in slots 0..newCount-2 move one slot toward the tail. The
; inserted mon has no selected effect yet; future gift code must grant only
; after it has a stable destination.
BridgeTrackSendNewMonToBox::
	ld a, [wBoxCount]
	cp 2                         ; new count 1 means there is nothing to shift
	ret c
	dec a                        ; last old slot = new count - 2
	call BridgeSelectedCurrentBoxBase
	ld b, a                      ; base owner for slot 0
	ld a, [wBoxCount]
	sub 2
	add b
	ld c, a                      ; owner for last old slot
	jp BridgeShiftSelectedOwnersUp

; Party-menu swap. wSwappedMenuItem is the first selected party index at the
; end of SwitchPartyMon_InitVarOrSwapData, and hCurrentMenuItem is the second.
BridgeTrackPartySwap::
	ld a, [wSwappedMenuItem]
	ld b, a
	ldh a, [hCurrentMenuItem]
	ld c, a
	inc b
	inc c
	jp BridgeSwapSelectedOwners

; Bill's PC party-party swap. The menu values are direct party indices.
BridgeTrackBillsPCPartySwap::
	ld a, [wParentMenuItem]
	ld b, a
	ldh a, [hCurrentMenuItem]
	ld c, a
	inc b
	inc c
	jp BridgeSwapSelectedOwners

; Bill's PC box-box swap. The menu values include PARTY_LENGTH as the first
; box-grid index; subtract it before translating to an absolute box owner.
BridgeTrackBillsPCBoxSwap::
	ld a, [wParentMenuItem]
	sub PARTY_LENGTH
	call BridgeSelectedOwnerFromCurrentBoxSlot
	ld b, a
	ldh a, [hCurrentMenuItem]
	sub PARTY_LENGTH
	call BridgeSelectedOwnerFromCurrentBoxSlot
	ld c, a
	jp BridgeSwapSelectedOwners

; Bill's PC cross-domain swap. One selected grid value is in the party range
; and the other is in the box range. Both records remain in their mon's new
; location, independent of which side was the source.
BridgeTrackBillsPCCrossDomainSwap::
	ld a, [wParentMenuItem]
	cp PARTY_LENGTH
	jr nc, .boxSource
	inc a
	ld b, a                      ; party source owner
	ldh a, [hCurrentMenuItem]
	sub PARTY_LENGTH
	call BridgeSelectedOwnerFromCurrentBoxSlot
	ld c, a                      ; box destination owner
	jr BridgeSwapSelectedOwners
.boxSource
	sub PARTY_LENGTH
	call BridgeSelectedOwnerFromCurrentBoxSlot
	ld b, a                      ; box source owner
	ldh a, [hCurrentMenuItem]
	inc a
	ld c, a                      ; party destination owner
	; fall through

; In: b/c = owner identifiers. Exchange the two sparse records without
; allocating another byte of persistent state. Missing records are copied as
; empty, so this also handles a swap between an owned and unowned mon.
BridgeSwapSelectedOwners:
	ld a, b
	and a
	jr z, .done
	cp BRIDGE_SELECTED_OWNER_MAX + 1
	jr nc, .done
	ld a, c
	and a
	jr z, .done
	cp BRIDGE_SELECTED_OWNER_MAX + 1
	jr nc, .done
	ld d, b                      ; preserve owners across the first scan
	ld e, c
	ld a, d
	call BridgeFindSelectedRecordByOwner
	jr nc, .sourceEmpty

	; Source exists. Keep both owners and the source effect while probing the
	; destination. Stack words are used only as scratch, so no WRAM grows.
	push bc
	inc hl
	ld a, [hl]
	push af                      ; source effect
	ld a, e
	call BridgeFindSelectedRecordByOwner
	jr nc, .destinationEmpty
	inc hl
	ld a, [hl]
	push af                      ; destination effect
	pop af
	ld d, a                      ; destination effect
	pop af
	ld e, a                      ; source effect
	pop bc                       ; original source/destination owners
	ld [hl], e                   ; destination gets source effect
	ld a, b
	call BridgeFindSelectedRecordByOwner
	jr nc, .done                 ; defensive: source vanished unexpectedly
	inc hl
	ld a, d
	ld [hl], a                   ; source gets destination effect
	ret

.destinationEmpty
	; Source exists, destination does not. Discard the saved source effect and
	; move the source record's owner to the destination location.
	pop af
	pop bc
	ld a, b
	call BridgeFindSelectedRecordByOwner
	jr nc, .done
	ld [hl], c
	ret

.sourceEmpty
	; Source does not exist. If the destination does, move its record to source.
	ld a, e
	call BridgeFindSelectedRecordByOwner
	jr nc, .done
	ld [hl], d
.done
	ret
