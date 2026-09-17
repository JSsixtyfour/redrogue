; custom_functions/wild_area_selection.asm
; Wild-area door layer for the unified special-encounter roll (see miniboss.asm's
; SpecialEncounterRollAndAssign). No-repeat rotation over the four rollable types
; (Cave/Forest/Cemetery/Facility), tracked in wWildAreaState.

; type id (0-3) -> lobby door ENTRY map id. Cemetery enters at floor 1.
WildAreaTypeMaps:
	db PROCEDURAL_CAVE_1      ; WILD_AREA_CAVE
	db PROCEDURAL_FOREST      ; WILD_AREA_FOREST
	db PROCEDURAL_CEMETERY_1  ; WILD_AREA_CEMETERY
	db PROCEDURAL_FACILITY    ; WILD_AREA_FACILITY

; type id (0-3) -> its offered-this-cycle bit mask.
WildAreaTypeBit:
	db %001                   ; WILD_AREA_CAVE
	db %010                   ; WILD_AREA_FOREST
	db %100                   ; WILD_AREA_CEMETERY
	db %10000000              ; WILD_AREA_FACILITY

; ============================================================
; StageEventRoll  (Phase 7a)
; Rolls this lobby selection's stage event into wStageEvent: STAGE_EVENT_CHANCE
; out of 256 that anything happens at all, then a uniform pick over the wired
; types (1..STAGE_EVENT_MAX_ROLLABLE). The phase field is left at
; STAGE_EVENT_PHASE_WAITING and bit 5 clear, which is the correct starting
; state for every type.
;
; Called from SpecialEncounterRollAndAssign's .doWildArea, AFTER
; WildAreaPickAndAssign has settled the type and the doors, rather than from
; inside WildAreaPickAndAssign itself - that routine carries the forced/
; choosable flag in carry across its whole body, and there is no point in it
; where a clobbering call is free. Both routines live in the "rogue" section,
; so this is a plain call.
;
; wStageEvent is already zeroed by the clear at the top of
; SpecialEncounterRollAndAssign, so the two early returns here leave
; STAGE_EVENT_NONE behind without writing anything.
; Clobbers a/bc/hl. Preserves de.
; ============================================================
StageEventRoll:
	call Random                   ; a = 0..255
	cp STAGE_EVENT_CHANCE
	ret nc                        ; no event on this wild area
	ld c, STAGE_EVENT_MAX_ROLLABLE
	call Rangerandom              ; a = [0, MAX_ROLLABLE-1]
	inc a                         ; -> [1, MAX_ROLLABLE]; 0 is STAGE_EVENT_NONE
	ld [wStageEvent], a
	ret

; ============================================================
; StageEventStageSprites  (Phase 7b)
; Publishes the overworld sprite each stage-event NPC slot should wear into
; sStageEventSprite6/7, for ProcBossPatchStageSprite to install into PICTUREID
; in the window between LoadMapHeader and InitMapSprites.
;
; Called from a wild area's PRELOAD rather than its finalize, because the
; sprite has to be staged before the map is ever loaded, and the preload is the
; only hook guaranteed to run before the first load and to re-run per lobby
; assignment.
;
; A slot's table entry of 0 means "no NPC in this slot", and that is load
; bearing rather than conventional: LoadMapSpriteTilePatterns skips a slot
; whose PICTUREID is 0 (`and a / jp z, .nextSpriteSlot`), so an unused slot
; costs no VRAM tile-pattern slot at all. Hence the no-event path writes 0/0
; explicitly instead of leaving the previous assignment's sprites staged.
;
; SRAM: re-asserted to bank 0 here rather than trusted from the caller, per the
; standing rule about farcalls and rRAMG/rRAMB. Deliberately left OPEN on
; return - the caller (PCPreloadCave) owns this window and closes it itself.
; Clobbers a/bc/hl.
; ============================================================
StageEventStageSprites::
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ASSERT BANK("Sprite Buffers") == 0
	xor a
	ld [rRAMB], a
	ld [sStageEventSprite6], a      ; a is still 0: default both slots to unused
	ld [sStageEventSprite7], a
	ld a, [wStageEvent]
	and STAGE_EVENT_TYPE_MASK
	ret z                           ; STAGE_EVENT_NONE - leave both at 0
	; No hideout means the generator found nowhere for the villain to go after
	; the theft, so the event must not manifest AT ALL - appearing and then
	; having nowhere to vanish to would be worse than not appearing. Gating it
	; here, on the sprite bytes, makes that one decision rather than one per
	; consumer: every later stage of the lifecycle already treats a zero sprite
	; as "this slot does not exist".
	ld a, [sStageEventHideoutX]
	cp STAGE_EVENT_NO_HIDEOUT
	ret z
	ld a, [wStageEvent]
	and STAGE_EVENT_TYPE_MASK
	dec a                           ; type is 1-based; table row is 0-based
	add a                           ; 2 bytes per row
	ld c, a
	ld b, 0
	ld hl, StageEventSpriteTable
	add hl, bc
	ld a, [hli]
	ld [sStageEventSprite6], a
	ld a, [hl]
	ld [sStageEventSprite7], a
	ret

; One row per STAGE_EVENT_* type, starting at type 1: the sprite for NPC object
; slot 6, then for slot 7. 0 = this event does not use that slot.
;
; Jessie and James are the only pair among the villains, so every other villain
; row leaves slot 7 empty; STAGE_EVENT_BOTH_GOOD is the good-NPC pair. All five
; sprites are 12-tile walking sprites that already exist with .png/.2bpp in the
; tree, and procedural maps are indoor, so the outdoor sprite-set bound that
; restricts which SPRITE_* a route may use does not apply to any of them.
;
; SUPER_NERD and ROCKET are placeholders for the Psychic and the Burglar chosen
; for flavour from sprites already on other maps; 7f may repoint them when it
; wires the trainer classes. Nothing else keys off these values.
StageEventSpriteTable:
	db SPRITE_JESSIE,        SPRITE_JAMES         ; STAGE_EVENT_JESSIE_JAMES
	db SPRITE_SUPER_NERD,    0                    ; STAGE_EVENT_PSYCHIC
	db SPRITE_ROCKET,        0                    ; STAGE_EVENT_BURGLAR
	db SPRITE_NURSE,         0                    ; STAGE_EVENT_JOY
	db SPRITE_OFFICER_JENNY, 0                    ; STAGE_EVENT_JENNY
	db SPRITE_NURSE,         SPRITE_OFFICER_JENNY ; STAGE_EVENT_BOTH_GOOD
	ASSERT NUM_STAGE_EVENT_TYPES == 6, "StageEventSpriteTable needs a row per type"

; ============================================================
; StageEventShowCaveNpcs  (Phase 7b)
; Reveals whichever of the cave's two stage-event NPC objects this event
; actually uses. Both default to OFF in ToggleableObjectStates, because the
; common case - a cave with no event - should show neither.
;
; The staged SPRITE byte is the single source of truth for "is this slot in
; use". Re-deriving it from wStageEvent's type here would be a second copy of
; the same decision, free to drift out of step with StageEventStageSprites;
; reading the byte that routine published cannot drift.
;
; Farcalled from ProceduralCave1_Script's EVENT_ENTER_ROOM setup. Reaching
; ShowObject from ROMX is safe: Predef (home/predef.asm) saves hLoadedROMBank
; on entry and restores it before returning.
; Clobbers a/bc/de/hl.
; ============================================================
StageEventShowCaveNpcs::
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ASSERT BANK("Sprite Buffers") == 0
	xor a
	ld [rRAMB], a
	ld a, [sStageEventSprite6]
	ld d, a
	ld a, [sStageEventSprite7]
	ld e, a
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ld a, d
	and a
	ret z                           ; no event armed - leave both hidden
	push de                         ; ShowObject clobbers freely
	ld a, TOGGLE_WILD_AREA_NPC_1
	ld [wToggleableObjectIndex], a
	predef ShowObject
	pop de
	ld a, e
	and a
	ret z                           ; single-NPC event
	ld a, TOGGLE_WILD_AREA_NPC_2
	ld [wToggleableObjectIndex], a
	predef ShowObject
	ret

; ============================================================
; WildAreaPickAndAssign
; INPUT: carry = forced (mandatory single door) / clear = choosable one-of-two.
; Picks a not-yet-offered-this-cycle wild type (resets after all four are offered),
; marks it in wWildAreaState + bumps the saturating count, resolves it to its entry
; map, and writes wLobbyDoor1/2StageMap. wRogueMap (the route _PickNextStage picked)
; stays on the non-wild door in the choosable case.
; Clobbers a/bc/de/hl.
; ============================================================
WildAreaPickAndAssign:
	; preserve the forced flag across the Rangerandom-heavy pick
	push af                       ; bit: carry = forced
	call WildAreaPickType         ; a = chosen type (0-3); updates wWildAreaState
	call WildAreaTypeToMap        ; a = entry map id for that type
	ld b, a                       ; b = wild entry map
	pop af                        ; restore carry = forced
	jr nc, .choosable
	; --- forced: single mandatory door (collapse both doors to the wild map) ---
	ld a, b
	ld [wLobbyDoor1StageMap], a
	ld [wLobbyDoor2StageMap], a   ; door1==door2==wild => Lobby_IsDoor2Blocked blocks door 2
	ret
.choosable:
	; --- choosable: wild on a random door, wRogueMap (route) on the other ---
	push bc                       ; save wild map (b)
	ld c, 2
	call Rangerandom              ; a = 0 (door1 = wild) or 1 (door2 = wild)
	pop bc
	and a
	jr nz, .wildDoor2
	ld a, b
	ld [wLobbyDoor1StageMap], a
	ld a, [wRogueMap]
	ld [wLobbyDoor2StageMap], a
	ret
.wildDoor2:
	ld a, [wRogueMap]
	ld [wLobbyDoor1StageMap], a
	ld a, b
	ld [wLobbyDoor2StageMap], a
	ret

; ============================================================
; WildAreaPickType
; Picks a random wild type whose "offered this cycle" bit is clear; if all four are
; already set, resets the cycle mask first (keeping the count bits). Sets the chosen
; type's bit and increments the saturating count (bits 3-4, cap 3).
; OUTPUT: a = chosen type (0-3). Clobbers a/bc/de/hl.
; ============================================================
WildAreaPickType:
	ld a, [wWildAreaState]
	ld d, a                       ; d = working state (mask + count); accumulator
	and WILD_AREA_MASK
	cp WILD_AREA_MASK
	jr nz, .haveRoom
	; all four offered this cycle -> clear their noncontiguous mask, keep count bits
	ld a, d
	and WILD_AREA_COUNT_MASK
	ld d, a
.haveRoom:
	; --- pass 1: count unoffered types ---
	ld b, 0                       ; b = unoffered count
	ld c, 0                       ; c = type iterator
.cntLoop:
	ld a, c
	cp NUM_WILD_AREA_TYPES
	jr z, .cntDone
	ld a, c
	call WildAreaMaskForType      ; a = mask for type c (preserves b/c/d/e)
	and d                         ; offered?
	jr nz, .cntSkip
	inc b
.cntSkip:
	inc c
	jr .cntLoop
.cntDone:
	; --- pick the k-th unoffered (b = unoffered count, guaranteed >=1) ---
	ld c, b
	push de                       ; protect working state (Multiply may clobber d/e)
	call Rangerandom              ; a = [0, unoffered-1]; preserves bc
	pop de
	ld c, a                       ; c = target index among unoffered
	ld b, 0                       ; b = type iterator
.pickLoop:
	ld a, b
	call WildAreaMaskForType      ; a = mask for type b (preserves b/c/d/e)
	ld e, a                       ; e = this type's mask
	and d
	jr nz, .pickSkip              ; already offered -> skip
	ld a, c
	and a
	jr z, .chosen                 ; target reached
	dec c
.pickSkip:
	inc b
	jr .pickLoop
.chosen:
	; b = chosen type, e = its mask. Set bit in d, bump count (cap 3), store.
	ld a, d
	or e
	ld d, a
	and WILD_AREA_COUNT_MASK
	cp WILD_AREA_COUNT_MASK
	jr z, .store                  ; count already 3 -> leave
	ld a, d
	add a, 1 << WILD_AREA_COUNT_SHIFT
	ld d, a
.store:
	ld a, d
	ld [wWildAreaState], a
	ld a, b                       ; return chosen type (0-3)
	ret

; a = wild type (0-3) -> a = its offered-cycle bit mask. Preserves bc/de; clobbers hl.
WildAreaMaskForType:
	push bc
	ld c, a
	ld b, 0
	ld hl, WildAreaTypeBit
	add hl, bc
	ld a, [hl]
	pop bc
	ret

; a = wild type (0-3) -> a = its entry map id (from WildAreaTypeMaps). Preserves de; clobbers bc/hl.
WildAreaTypeToMap:
	ld c, a
	ld b, 0
	ld hl, WildAreaTypeMaps
	add hl, bc
	ld a, [hl]
	ret
