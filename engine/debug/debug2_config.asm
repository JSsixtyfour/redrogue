; ============================================================================
; Debug 2 configuration screen (debug builds only).
;
; Replaces the five blind DisplayChooseQuantityMenu number prompts that used to
; fire in sequence during Debug 2's new-game setup: a battle count, an AI tier
; (Debug2ChooseAITier), an encounter selector and two door indices (the last
; three inside Debug2ApplyRoundState). Those prompts had no labels, no way back
; and no way to see what had already been picked.
;
; This is one screen on the shared option-page engine
; (engine/menus/options_menu.asm), so every row is labelled, reversible and
; visible at once. Every row is a CUSTOM row - numbers and context-dependent
; destination lists do not fit the engine's plain masked-enum shape - except
; UPGRADES, which calls the option screen's CHEAT routines directly so the two
; screens can never disagree about what "Timewarp + Johto" means.
;
; STATE. Every byte this screen edits already exists and is allocated in EVERY
; build, not just _DEBUG: wBattleCount, wAIDebugTierOverride and the two
; wDebug2ForcedDoor bytes. ROM may differ between builds; WRAM must not, or the
; release and debug .sym files disagree and the PyBoy harness writes the wrong
; addresses. That is the reasoning already recorded at ram/wram.asm's
; wAIDebugTierOverride.
;
; Door 1's bits 6-7 carry the encounter selector (STATUS) and its low five bits
; the destination index, exactly as before - no re-encoding was needed. Five
; bits covers the longest list (22 routes) and STATUS already said which KIND of
; destination was in play; it just was not being used to choose between lists.
;
; ORDER OF OPERATIONS. This screen runs BEFORE Debug2ApplyRoundState, which
; still derives badge count, the gym/route flag and the Victory Road state from
; wBattleCount. It no longer prompts for anything, and it must not clobber
; wDebug2ForcedDoor1, which this screen has already written.
; ============================================================================

IF DEF(_DEBUG)

; Deliberately a FRAGMENT of the option engine's section rather than a section of
; its own: the engine reaches this screen's row routines through `jp hl`, which
; cannot cross a bank. Sharing the section keeps every such pointer in-bank.
; In a release build the IF above drops the whole fragment.
SECTION FRAGMENT "Options Menu", ROMX

DEF DBG2_STATUS_MASK  EQU %11000000
DEF DBG2_STATUS_SHIFT EQU 6
DEF DBG2_DOOR_MASK    EQU %00011111

DEF DBG2_STATUS_NORMAL    EQU 0
DEF DBG2_STATUS_GIFT      EQU 1
DEF DBG2_STATUS_MINIBOSS  EQU 2
DEF DBG2_STATUS_WILD_AREA EQU 3
DEF DBG2_NUM_STATUS       EQU 4

DEF DBG2_MIN_BATTLES EQU 1
DEF DBG2_MAX_BATTLES EQU 99
DEF DBG2_MAX_AI      EQU 4

; ----------------------------------------------------------------------------
; Entry point. Reached by farcall from PrepareNewGameDebug's Debug 2 path.
; ----------------------------------------------------------------------------
Debug2ConfigMenu::
	ld hl, Debug2PageSet
	jp OptionsMenuEngine

; ============================================================================
; Rows
; ============================================================================

Debug2PageSet:
	db 1
	dw Debug2Page

; rows, box height, CANCEL Y, row table, prompt column, prompt
Debug2Page:
	optpage 6, 9, 12, Debug2Rows, 0, 0

; label, screen Y, value column, draw routine, cycle routine
Debug2Rows:
	optrow_custom Debug2BattlesLabel,  1, 17, Debug2DrawBattles,  Debug2CycleBattles
	optrow_custom Debug2AILabel,       2, 18, Debug2DrawAI,       Debug2CycleAI
	optrow_custom Debug2StatusLabel,   4,  8, Debug2DrawStatus,   Debug2CycleStatus
	optrow_custom Debug2Door1Label,    5,  8, Debug2DrawDoor1,    Debug2CycleDoor1
	optrow_custom Debug2Door2Label,    6,  8, Debug2DrawDoor2,    Debug2CycleDoor2
; Shares the option screen's CHEAT row wholesale - one implementation, two
; callers, so the two screens cannot drift apart.
	optrow_custom Debug2UpgradesLabel, 8,  9, OptDrawCheat,       OptCycleCheat

; ============================================================================
; BATTLES - a plain 1-99 count. Everything else Debug 2 derives (badge count,
; the gym/route flag, Victory Road) still comes from this one number, in
; Debug2ApplyRoundState.
; ============================================================================

Debug2DrawBattles:
	ld de, wBattleCount
	lb bc, 1, 2
	jp PrintNumber

Debug2CycleBattles:
	ld hl, wBattleCount
	call Debug2StepValue
	cp DBG2_MAX_BATTLES + 1
	jr z, .wrapToBottom
	cp DBG2_MIN_BATTLES - 1
	jr z, .wrapToTop
	jr .store
.wrapToBottom
	ld a, DBG2_MIN_BATTLES
	jr .store
.wrapToTop
	ld a, DBG2_MAX_BATTLES
.store
	ld [wBattleCount], a
; The door lists are keyed off the battle count as well as STATUS (it decides
; gym-next versus route-next), so a change here can shorten the list under a
; door index that is already set.
	jp Debug2ClampDoors

; ============================================================================
; AI - 0 resolves the tier normally from the battle count; 1-4 force T0-T3.
; ============================================================================

Debug2DrawAI:
	ld de, wAIDebugTierOverride
	lb bc, 1, 1
	jp PrintNumber

Debug2CycleAI:
	ld hl, wAIDebugTierOverride
	call Debug2StepValue
	cp DBG2_MAX_AI + 1
	jr z, .wrapToBottom
	inc a ; $ff means it stepped below 0
	jr z, .wrapToTop
	dec a
	jr .store
.wrapToBottom
	xor a
	jr .store
.wrapToTop
	ld a, DBG2_MAX_AI
.store
	ld [wAIDebugTierOverride], a
	ret

; ============================================================================
; STATUS - which KIND of encounter the next lobby visit is forced to. Shown
; with both the number the old prompt used and the name it stands for.
; ============================================================================

Debug2DrawStatus:
	push hl
	call Debug2GetStatus
	ld e, a
	ld d, 0
	ld hl, Debug2StatusValues
	add hl, de
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld d, h
	ld e, l
	pop hl
	jp PlaceString

Debug2CycleStatus:
	call Debug2GetStatus
	ld c, a
	ldh a, [hJoy5]
	bit B_PAD_RIGHT, a
	ld a, c
	jr nz, .stepRight
	dec a
	jr .wrap
.stepRight
	inc a
.wrap
	and DBG2_NUM_STATUS - 1
	ASSERT DBG2_NUM_STATUS == 4
	; rebuild door 1 with the new status, keeping its destination index.
	; Bits 0-1 -> bits 6-7, which is two rotates RIGHT, not left.
	rrca
	rrca
	ld c, a
	ld a, [wDebug2ForcedDoor1]
	and DBG2_DOOR_MASK
	or c
	ld [wDebug2ForcedDoor1], a
; A different STATUS means a different destination list, and usually a shorter
; one: an index of 20 chosen under NORMAL would otherwise survive into MINIBOSS
; and read 17 entries past a 3-entry table.
	call Debug2ClampDoors
; STATUS owns what both door rows display, so redraw them too. The engine only
; redraws the row the cursor is on.
	ldh a, [hCurrentMenuItem]
	push af
	ld a, DBG2_ROW_DOOR1
	ldh [hCurrentMenuItem], a
	call OptDrawValue
	ld a, DBG2_ROW_DOOR2
	ldh [hCurrentMenuItem], a
	call OptDrawValue
	pop af
	ldh [hCurrentMenuItem], a
	ret

DEF DBG2_ROW_DOOR1 EQU 3
DEF DBG2_ROW_DOOR2 EQU 4

Debug2StatusValues:
	dw Debug2StatusNormalText
	dw Debug2StatusGiftText
	dw Debug2StatusMiniBossText
	dw Debug2StatusWildText

; ============================================================================
; DOOR 1 / DOOR 2 - a destination WITHIN the kind STATUS selected, or RANDOM.
;
; This is what "the doors should fluctuate depending on Special Status as well
; as battle count" means: index 3 is the third route under NORMAL, the third
; gift room under GIFT and the third wild-area type under WILD AREA. Before
; this, a door index was only ever resolved against the route or gym table, and
; SelectAndPatchLobbyExit threw the indices away entirely whenever STATUS was
; set, so bridge rooms and wild areas could not be picked at all.
; ============================================================================

Debug2DrawDoor1:
	ld de, wDebug2ForcedDoor1
	jr Debug2DrawDoor

Debug2DrawDoor2:
	ld de, wDebug2ForcedDoor2
Debug2DrawDoor:
	ld a, [de]
	and DBG2_DOOR_MASK
	jp Debug2PlaceDoorName

Debug2CycleDoor1:
	ld hl, wDebug2ForcedDoor1
	jr Debug2CycleDoor

Debug2CycleDoor2:
	ld hl, wDebug2ForcedDoor2
Debug2CycleDoor:
	push hl
	ld a, [hl]
	and DBG2_DOOR_MASK
	ld c, a
	call Debug2DoorListCount ; b = how many destinations this STATUS offers
	ldh a, [hJoy5]
	bit B_PAD_RIGHT, a
	ld a, c
	jr nz, .stepRight
	and a
	jr nz, .stepLeft
	ld a, b ; wrap past RANDOM to the last destination
	inc a
.stepLeft
	dec a
	jr .store
.stepRight
	inc a
	cp b
	jr z, .store
	jr c, .store
	xor a ; past the last destination: back to RANDOM
.store
	ld c, a
	pop hl
	ld a, [hl]
	and ~DBG2_DOOR_MASK & $ff ; keep STATUS in door 1's top bits
	or c
	ld [hl], a
	ret

; ============================================================================
; Shared helpers
; ============================================================================

; Returns a = the current STATUS, 0-3. Clobbers af.
Debug2GetStatus::
	ld a, [wDebug2ForcedDoor1]
	and DBG2_STATUS_MASK
	rlca
	rlca
	ret

; hl = a byte. Returns a = that byte stepped one in hJoy5's direction, WITHOUT
; clamping - the caller decides what its own limits are. Clobbers af.
Debug2StepValue:
	ldh a, [hJoy5]
	bit B_PAD_RIGHT, a
	ld a, [hl]
	jr nz, .up
	dec a
	ret
.up
	inc a
	ret

; Clamps both door indices into the current STATUS's list. Called whenever
; STATUS or the battle count changes, since either can shorten the list.
; Clobbers af, bc, de, hl.
Debug2ClampDoors::
	call Debug2DoorListCount ; b = destination count
	ld hl, wDebug2ForcedDoor1
	call .clampOne
	ld hl, wDebug2ForcedDoor2
.clampOne
	ld a, [hl]
	and DBG2_DOOR_MASK
	cp b
	ret c        ; below the count: in range
	ret z        ; exactly the count: the last valid 1-based index
	ld a, [hl]
	and ~DBG2_DOOR_MASK & $ff
	ld [hl], a   ; out of range: fall back to RANDOM
	ret

; Returns b = the number of selectable destinations for the current STATUS.
; Valid door values are 0 (RANDOM) through b inclusive, 1-based into the list.
; Clobbers af. Preserves de, hl.
Debug2DoorListCount::
	push hl
	call Debug2DoorList
	pop hl
	ret

; Returns b = destination count and hl = the name pointer table for the current
; STATUS (0 if that table has not been written yet). Clobbers af, de.
Debug2DoorList::
	call Debug2GetStatus
	cp DBG2_STATUS_GIFT
	jr z, .gift
	cp DBG2_STATUS_MINIBOSS
	jr z, .miniBoss
	cp DBG2_STATUS_WILD_AREA
	jr z, .wildArea
; NORMAL: routes or gyms, exactly as _PickNextStage would choose between them.
; Debug2ApplyRoundState has not run yet, so derive the same gym-next test it
; uses - battle count mod 10 >= 6 - rather than reading BIT_ROGUE_GYM_NEXT.
	ld a, [wBattleCount]
.mod10
	cp 10
	jr c, .haveRemainder
	sub 10
	jr .mod10
.haveRemainder
	cp 6
	jr nc, .gym
	ld b, NUM_STAGE_MAPS
	ld hl, Debug2RouteNames
	ret
.gym
	ld b, NUM_BADGES
	ld hl, Debug2GymNames
	ret
.gift
	ld b, NUM_BRIDGE_ROOMS
	ld hl, Debug2GiftNames
	ret
.miniBoss
	ld b, NUM_MINIBOSS_TYPES
	ld hl, Debug2MiniBossNames
	ret
.wildArea
	ld b, NUM_WILD_AREA_TYPES
	ld hl, Debug2WildAreaNames
	ret

; a = a 1-based destination index (0 = RANDOM), hl = the value cell.
; Draws that destination's name, padded to DBG2_NAME_WIDTH.
DEF DBG2_NAME_WIDTH EQU 11

Debug2PlaceDoorName:
	and a
	jr z, .random
	ld c, a
	push hl
	push bc
	call Debug2DoorList ; hl = the name table
	pop bc
	ld a, h
	or l
	jr z, .noTable
	dec c ; 1-based index -> 0-based table entry
	ld b, 0
	add hl, bc
	add hl, bc
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld d, h
	ld e, l
	pop hl
	jp PlaceString
; Phase C3 has not written this list's names yet. Draw a placeholder rather
; than dereferencing a null table; the index still drives the force, so the row
; remains usable.
.noTable
	pop hl
	ld de, Debug2UnnamedText
	jp PlaceString
.random
	ld de, Debug2RandomText
	jp PlaceString

; ============================================================================
; Text
; ============================================================================

Debug2BattlesLabel:  db "BATTLES@"
Debug2AILabel:       db "AI@"
Debug2StatusLabel:   db "STATUS@"
Debug2Door1Label:    db "DOOR 1@"
Debug2Door2Label:    db "DOOR 2@"
Debug2UpgradesLabel: db "UPGRADES@"

; width 11, column 8. The number the old prompt used is kept alongside the name
; so an existing muscle-memory value still reads the same.
Debug2StatusNormalText:   db "1 NORMAL   @"
Debug2StatusGiftText:     db "2 GIFT     @"
Debug2StatusMiniBossText: db "3 MINIBOSS @"
Debug2StatusWildText:     db "4 WILD AREA@"

Debug2RandomText:  db "RANDOM     @"
Debug2UnnamedText: db "- SEE INDEX@"

; ----------------------------------------------------------------------------
; Destination name tables, indexed 0-based by (door index - 1) and kept in step
; with the map table each one mirrors.
;
; PHASE C3 (the mechanical half of this phase) writes the three long ones. Each
; string is DBG2_NAME_WIDTH characters, left-padded so short names right-align
; the way every other value on these screens does, and each table must stay
; index-aligned with its map table or a door will name one place and open on
; another:
;   Debug2RouteNames  22 entries, mirroring RogueStageMapTable
;                     (custom_functions/random_stage_selection.asm)
;   Debug2GymNames     8 entries, mirroring GymMapByBadge (same file)
;   Debug2GiftNames   14 entries, mirroring BridgeRoomMaps
;                     (custom_functions/bridge_selection.asm)
; Define each as a label followed by NUM `dw` entries, then replace the matching
; `EQU 0` below with the label. While a table is 0 the row draws
; Debug2UnnamedText instead, so the build stays green either way.
; ----------------------------------------------------------------------------
DEF Debug2RouteNames EQU 0
DEF Debug2GymNames   EQU 0
DEF Debug2GiftNames  EQU 0

; These two are short enough to be worth writing inline.
; KEEP IN SYNC with MINIBOSS_RIVAL/GIOVANNI/KARATE (constants/ram_constants.asm).
Debug2MiniBossNames:
	dw Debug2MiniBossRivalText
	dw Debug2MiniBossGiovanniText
	dw Debug2MiniBossKarateText

Debug2MiniBossRivalText:    db "      RIVAL@"
Debug2MiniBossGiovanniText: db "   GIOVANNI@"
Debug2MiniBossKarateText:   db "     KARATE@"

; KEEP IN SYNC with WildAreaTypeMaps (custom_functions/wild_area_selection.asm).
Debug2WildAreaNames:
	dw Debug2WildCaveText
	dw Debug2WildForestText
	dw Debug2WildCemeteryText
	dw Debug2WildFacilityText

Debug2WildCaveText:     db "       CAVE@"
Debug2WildForestText:   db "     FOREST@"
Debug2WildCemeteryText: db "   CEMETERY@"
Debug2WildFacilityText: db "   FACILITY@"

ENDC
