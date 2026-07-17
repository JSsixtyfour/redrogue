PickUpItem:
	call EnableAutoTextBoxDrawing

	ldh a, [hSpriteIndex]
	ld b, a
	ld hl, wToggleableObjectList
.toggleableObjectsListLoop
	ld a, [hli]
	cp $ff
	ret z
	cp b
	jr z, .isToggleable
	inc hl
	jr .toggleableObjectsListLoop

.isToggleable
	ld a, [hl]
	ldh [hToggleableObjectIndex], a

	ld hl, wMapSpriteExtraData
	ldh a, [hSpriteIndex]
	dec a
	add a
	ld d, 0
	ld e, a
	add hl, de
	ld a, [hl]
	ld b, a ; item
	ld c, 1 ; quantity
	call GiveItem
	jr nc, .BagFull

	ldh a, [hToggleableObjectIndex]
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, 1
	ldh [hNoWaitAfterText], a
	ld hl, FoundItemText
	jr .print

.BagFull
	ld hl, NoMoreRoomForItemText
.print
	call PrintText
	ret

FoundItemText:
	text_far _FoundItemText
	sound_get_item_1
	text_end

NoMoreRoomForItemText:
	text_far _NoMoreRoomForItemText
	text_end

RandomPickUpItem:
	call EnableAutoTextBoxDrawing

	; Cemetery maps: one pokeball at slot 1 per map.
	; Item stored in wRogueItem by PCemFinalizeMap.
	; NOTE: farcall returns Z flag correctly but clobbers 'a' on bank restore,
	; so we check Z flag immediately and look up toggle via ldh (not farcall).
	farcall IsCemeteryMap   ; Z clear = is cemetery (Z flag survives farcall)
	jr z, .notCemetery
	ldh a, [hSpriteIndex]
	cp 1
	jr nz, .notCemetery
	ld a, [wRogueItem]
	ld b, a
	ld c, 1
	call GiveItem
	jp nc, .BagFull
	; Inline toggle lookup - can't use farcall here since it clobbers 'a'
	ldh a, [hCurMap]
	cp PROCEDURAL_CEMETERY_1
	ld a, TOGGLE_CEMETERY_1_POKEBALL
	jr z, .gotCemToggle
	ldh a, [hCurMap]
	cp PROCEDURAL_CEMETERY_2
	ld a, TOGGLE_CEMETERY_2_POKEBALL
	jr z, .gotCemToggle
	ldh a, [hCurMap]
	cp PROCEDURAL_CEMETERY_3
	ld a, TOGGLE_CEMETERY_3_POKEBALL
	jr z, .gotCemToggle
	ld a, TOGGLE_CEMETERY_4_POKEBALL
.gotCemToggle
	ld [wToggleableObjectIndex], a
	predef HideObject
	; Mark this floor's item as collected in SRAM so it stays hidden on re-entry
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	xor a
	ld [rRAMB], a
	; Compute bit mask for current cemetery floor (bit 0-3 = floor 0-3)
	ldh a, [hCurMap]
	ld b, 1                     ; bit 0 = CEMETERY_1
	cp PROCEDURAL_CEMETERY_1
	jr z, .cemGotMask
	sla b                       ; bit 1 = CEMETERY_2
	cp PROCEDURAL_CEMETERY_2
	jr z, .cemGotMask
	sla b                       ; bit 2 = CEMETERY_3
	cp PROCEDURAL_CEMETERY_3
	jr z, .cemGotMask
	sla b                       ; bit 3 = CEMETERY_4
.cemGotMask
	ld a, [sProcCemeteryItemGot]
	or b
	ld [sProcCemeteryItemGot], a
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ld [rRAMG], a
	ld a, 1
	ldh [hNoWaitAfterText], a
	ld hl, FoundItemText
	jp .print
.notCemetery

	; Hardcoded path for wild-area stage maps (4 independent random items,
	; sprite slots 2-5 - boss is slot 1 and not a pickup item).
	; TOGGLE_WILD_AREA_POKEBALL_1-4 are 4 consecutive const values, and
	; wRogueItem/2/3/4 are 4 consecutive dw's - both indexed arithmetically
	; off (slot-2) instead of branching 4 ways.
	farcall IsWildAreaStageMap
	jr z, .normalRoguePath
	ldh a, [hSpriteIndex]
	ld b, a
	sub 2                            ; b was slot; a = slot-2 (item index 0-3)
	bit 7, a
	jr nz, .normalRoguePath          ; underflowed: was slot 0 or 1 (boss/player)
	cp 4
	jr nc, .normalRoguePath          ; was slot 6+ (not a wild pokeball)
	ld b, a                          ; b = item index 0-3

	ld hl, wRogueItem
	sla b
	ld c, b
	ld b, 0
	add hl, bc
	ld a, [hl]
	ld b, a
	ld c, 1
	call GiveItem
	jr nc, .BagFull
	ldh a, [hSpriteIndex]
	sub 2
	add a, TOGGLE_WILD_AREA_POKEBALL_1
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, 1
	ldh [hNoWaitAfterText], a
	ld hl, FoundItemText
	jr .print

.normalRoguePath
	; Hardcoded path for roguelike stage maps (random item always at sprite slot 6)
	farcall IsRogueStageMap
	jr z, .normalPickup
	ldh a, [hSpriteIndex]
	cp 6
	jr nz, .normalPickup

	; bail out if this ball has already been collected (prevents double-give
	; if this object's interaction fires more than once, e.g. re-entering
	; the stage re-shows the sprite via RogueRefresh)
	;ld hl, wToggleableObjectFlags
	;ld c, TOGGLE_STAGE_RANDOM_ITEM
	;ld b, FLAG_TEST
	;call ToggleableObjectFlagAction
	;and a
	;ret nz

	ld a, [wRogueItem]
	ld b, a
	ld c, 1
	call GiveItem
	jr nc, .BagFull
	ld a, TOGGLE_STAGE_RANDOM_ITEM
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, 1
	ldh [hNoWaitAfterText], a
	ld hl, FoundItemText
	jr .print

.normalPickup
	ldh a, [hSpriteIndex]
	ld b, a
	ld hl, wToggleableObjectList
.toggleableObjectsListLoop
	ld a, [hli]
	cp $ff
	ret z
	cp b
	jr z, .isToggleable
	inc hl
	jr .toggleableObjectsListLoop

.isToggleable
	ld a, [hl]
	ldh [hToggleableObjectIndex], a
	ld a, [wRogueItem]
	ld b, a
	ld c, 1
	call GiveItem
	jr nc, .BagFull

	ldh a, [hToggleableObjectIndex]
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, 1
	ldh [hNoWaitAfterText], a
	ld hl, FoundItemText
	jr .print

.BagFull
	ld hl, NoMoreRoomForItemText
.print
	call PrintText
	ret