MarkTownVisitedAndLoadToggleableObjects::
	ldh a, [hCurMap]
	cp FIRST_ROUTE_MAP
	jr nc, .notInTown
	ld c, a
	ld b, FLAG_SET
	ld hl, wTownVisitedFlag   ; mark town as visited (for flying)
	predef FlagActionPredef
.notInTown
	ld hl, ToggleableObjectMapPointers
	ldh a, [hCurMap]
	ld b, $0
	ld c, a
	add hl, bc
	add hl, bc
	ld a, [hli] ; load toggleable objects pointer in hl
	ld h, [hl]
	ld l, a
	push hl
	ld de, ToggleableObjectStates ; calculate difference between out pointer and the base pointer
	ld a, l
	sub e
	jr nc, .noCarry
	dec h
.noCarry
	ld l, a
	ld a, h
	sub d
	ld h, a
	; divide difference by 3, resulting in the global offset (number of toggleable items before ours)
	ld a, h
	ldh [hDividend], a
	ld a, l
	ldh [hDividend+1], a
	xor a
	ldh [hDividend+2], a
	ldh [hDividend+3], a
	ld a, $3
	ldh [hDivisor], a
	ld b, $2
	call Divide
	ldh a, [hCurMap]
	ld b, a
	ldh a, [hDividend+3]
	ld c, a                    ; store global offset in c
	ld de, wToggleableObjectList
	pop hl
.writeToggleableObjectsListLoop
	ld a, [hli]
	cp -1
	jr z, .done     ; end of list
	cp b
	jr nz, .done    ; not for current map anymore
	ld a, [hli]
	inc hl
	ld [de], a                 ; write (map-local) sprite ID
	inc de
	ld a, c
	inc c
	ld [de], a                 ; write (global) toggleable object index
	inc de
	jr .writeToggleableObjectsListLoop
.done
	ld a, -1
	ld [de], a                 ; write sentinel
	; Reset random item flag when entering a roguelike stage
	call IsRogueStageMap
	ret z
	ld hl, wToggleableObjectFlags
	ld c, TOGGLE_STAGE_RANDOM_ITEM
	ld b, FLAG_RESET
	call ToggleableObjectFlagAction
	ret

InitializeToggleableObjectsFlags:
	ld hl, wToggleableObjectFlags
	ld bc, wToggleableObjectFlagsEnd - wToggleableObjectFlags
	xor a
	call FillMemory ; clear toggleable objects flags
	ld hl, ToggleableObjectStates
	xor a
	ld [wToggleableObjectCounter], a
.toggleableObjectsLoop
	ld a, [hli]
	cp -1 ; end of list
	ret z
	push hl
	inc hl
	ld a, [hl]
	cp OFF
	jr nz, .skip
	ld hl, wToggleableObjectFlags
	ld a, [wToggleableObjectCounter]
	ld c, a
	ld b, FLAG_SET
	call ToggleableObjectFlagAction ; set flag if object is toggled off
.skip
	ld hl, wToggleableObjectCounter
	inc [hl]
	pop hl
	inc hl
	inc hl
	jr .toggleableObjectsLoop

; tests if current object is toggled off/has been hidden
IsObjectHidden:
	ldh a, [hCurrentSpriteOffset]
	swap a
	ld b, a                         ; b = sprite slot number
	; Hardcoded check for roguelike pokeball slots (6-9) on stage maps
	cp 6
	jr z, .checkMaybeRoguePB
	cp 7
	jr z, .checkMaybeRoguePB
	cp 8
	jr z, .checkMaybeRoguePB
	cp 9
	jr z, .checkMaybeRoguePB
	jr .normalCheck
.checkMaybeRoguePB
	push bc
	call IsRogueStageMap
	pop bc
	jr z, .normalCheck              ; Z set = not a stage map
	ld c, TOGGLE_STAGE_RANDOM_ITEM  ; slot 6 = random item
	ld a, b
	cp 6
	jr z, .checkRewardBit
	ld c, TOGGLE_ROGUE_REWARD_POKEBALL_1
	cp 7
	jr z, .checkRewardBit
	ld c, TOGGLE_ROGUE_REWARD_POKEBALL_2
	cp 8
	jr z, .checkRewardBit
	ld c, TOGGLE_ROGUE_REWARD_POKEBALL_3
.checkRewardBit
	ld b, FLAG_TEST
	ld hl, wToggleableObjectFlags
	call ToggleableObjectFlagAction
	ld a, c
	and a
	jr nz, .hidden
	jr .notHidden
.normalCheck
	ld hl, wToggleableObjectList
.loop
	ld a, [hli]
	cp -1
	jr z, .notHidden                ; not toggleable -> not hidden
	cp b
	ld a, [hli]
	jr nz, .loop
	ld c, a
	ld b, FLAG_TEST
	ld hl, wToggleableObjectFlags
	call ToggleableObjectFlagAction
	ld a, c
	and a
	jr nz, .hidden
.notHidden
	xor a
.hidden
	ldh [hIsToggleableObjectOff], a
	ret

; Returns: Z clear if current map is a roguelike stage, Z set if not
IsRogueStageMap:
	ldh a, [hCurMap]
	ld hl, RogueStageMapTable
.stageLoop
	ld c, [hl]
	inc hl
	inc c
	jr z, .notStage                 ; c was $FF (end of table)
	dec c
	cp c
	jr nz, .stageLoop
	xor a
	inc a                           ; a = 1, Z clear = is a stage map
	ret
.notStage
	xor a                           ; a = 0, Z set = not a stage map
	ret

RogueStageMapTable:
	db ROUTE_1
	db ROUTE_3
	db ROUTE_5
	db ROUTE_6
	db ROUTE_9
	db ROUTE_12
	db ROUTE_13
	db ROUTE_15
	db ROUTE_17
    db ROUTE_24
	db ROUTE_25
    db VIRIDIAN_FOREST
	db DIGLETTS_CAVE
	db MT_MOON_1F
	db ROCK_TUNNEL_1F
	db ROCKET_HIDEOUT_B1F
	db POKEMON_TOWER_2F
	db POKEMON_TOWER_7F
	db SS_ANNE_B1F
	db SS_ANNE_BOW
	db POWER_PLANT
	db SILPH_CO_1F
	db POKEMON_MANSION_1F
	db SEAFOAM_ISLANDS_1F
	db VICTORY_ROAD_1F
	db -1

DEF NUM_STAGE_MAPS EQU 25 ; must match RogueStageMapTable entry count above
; Stage selection logic lives in custom_functions/random_stage_selection.asm

; adds toggleable object (items, leg. pokemon, etc.) to the map
; [wToggleableObjectIndex]: index of the toggleable object to be added (global index)
ShowObject:
ShowObject2:
	ld hl, wToggleableObjectFlags
	ld a, [wToggleableObjectIndex]
	ld c, a
	ld b, FLAG_RESET
	call ToggleableObjectFlagAction   ; reset "removed" flag
	jp UpdateSprites

; removes toggleable object (items, leg. pokemon, etc.) from the map
; [wToggleableObjectIndex]: index of the toggleable object to be removed (global index)
HideObject:
	ld hl, wToggleableObjectFlags
	ld a, [wToggleableObjectIndex]
	ld c, a
	ld b, FLAG_SET
	call ToggleableObjectFlagAction   ; set "removed" flag
	jp UpdateSprites

ToggleableObjectFlagAction:
; identical to FlagAction

	push hl
	push de
	push bc

	; bit
	ld a, c
	ld d, a
	and 7
	ld e, a

	; byte
	ld a, d
	srl a
	srl a
	srl a
	add l
	ld l, a
	jr nc, .ok
	inc h
.ok

	; d = 1 << e (bitmask)
	inc e
	ld d, 1
.shift
	dec e
	jr z, .shifted
	sla d
	jr .shift
.shifted

	ld a, b
	and a
	jr z, .reset
	cp FLAG_TEST
	jr z, .read

; set
	ld a, [hl]
	ld b, a
	ld a, d
	or b
	ld [hl], a
	jr .done

.reset
	ld a, [hl]
	ld b, a
	ld a, d
	xor $ff
	and b
	ld [hl], a
	jr .done

.read
	ld a, [hl]
	ld b, a
	ld a, d
	and b

.done
	pop bc
	pop de
	pop hl
	ld c, a
	ret
