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

	; Hardcoded path for wild-area stage maps (4 independent random items,
	; sprite slots 1-4, see constants/toggle_constants.asm's
	; TOGGLE_WILD_AREA_POKEBALL_1-4 and custom_functions/
	; random_stage_selection.asm's IsWildAreaStageMap). Checked before the
	; generic rogue-stage path below so it can't collide with Route1-style
	; maps' existing slot 6-10 usage.
	;
	; TOGGLE_WILD_AREA_POKEBALL_1-4 are 4 consecutive const values, and
	; wRogueItem/2/3/4 are 4 consecutive dw's (ram/wram.asm) - index both
	; arithmetically off (slot-1) instead of branching 4 ways.
	farcall IsWildAreaStageMap
	jr z, .normalRoguePath
	ldh a, [hSpriteIndex]
	ld b, a
	dec b
	bit 7, b
	jr nz, .normalRoguePath          ; slot was 0 (player) - underflowed
	ld a, b
	cp 4
	jr nc, .normalRoguePath          ; slot was >4 or 0

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
	dec a
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