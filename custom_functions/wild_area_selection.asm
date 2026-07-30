; custom_functions/wild_area_selection.asm
; Wild-area door layer for the unified special-encounter roll (see miniboss.asm's
; SpecialEncounterRollAndAssign). No-repeat rotation over the 3 rollable types
; (Cave/Forest/Cemetery; Facility shelved), tracked in wWildAreaState.

; type id (0-2) -> lobby door ENTRY map id. Cemetery enters at floor 1.
WildAreaTypeMaps:
	db PROCEDURAL_CAVE_1      ; WILD_AREA_CAVE
	db PROCEDURAL_FOREST      ; WILD_AREA_FOREST
	db PROCEDURAL_CEMETERY_1  ; WILD_AREA_CEMETERY

; type id (0-2) -> its offered-this-cycle bit mask.
WildAreaTypeBit:
	db %001                   ; WILD_AREA_CAVE
	db %010                   ; WILD_AREA_FOREST
	db %100                   ; WILD_AREA_CEMETERY

; ============================================================
; WildAreaPickAndAssign
; INPUT: carry = forced (mandatory single door) / clear = choosable one-of-two.
; Picks a not-yet-offered-this-cycle wild type (resets the cycle when all 3 offered),
; marks it in wWildAreaState + bumps the saturating count, resolves it to its entry
; map, and writes wLobbyDoor1/2StageMap. wRogueMap (the route _PickNextStage picked)
; stays on the non-wild door in the choosable case.
; Clobbers a/bc/de/hl.
; ============================================================
WildAreaPickAndAssign:
	; preserve the forced flag across the Rangerandom-heavy pick
	push af                       ; bit: carry = forced
	call WildAreaPickType         ; a = chosen type (0-2); updates wWildAreaState
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
; Picks a random wild type whose "offered this cycle" bit is clear; if all 3 are
; already set, resets the cycle mask first (keeping the count bits). Sets the chosen
; type's bit and increments the saturating count (bits 3-4, cap 3).
; OUTPUT: a = chosen type (0-2). Clobbers a/bc/de/hl.
; ============================================================
WildAreaPickType:
	ld a, [wWildAreaState]
	ld d, a                       ; d = working state (mask + count); accumulator
	and WILD_AREA_MASK
	cp WILD_AREA_MASK
	jr nz, .haveRoom
	; all 3 offered this cycle -> reset the low-3 mask, keep the count bits
	ld a, d
	and WILD_AREA_COUNT_MASK
	ld d, a
.haveRoom:
	; --- pass 1: count unoffered types (clear low-3 bits) ---
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
	ld a, b                       ; return chosen type (0-2)
	ret

; a = wild type (0-2) -> a = its offered-cycle bit mask. Preserves bc/de; clobbers hl.
WildAreaMaskForType:
	push bc
	ld c, a
	ld b, 0
	ld hl, WildAreaTypeBit
	add hl, bc
	ld a, [hl]
	pop bc
	ret

; a = wild type (0-2) -> a = its entry map id (from WildAreaTypeMaps). Preserves de; clobbers bc/hl.
WildAreaTypeToMap:
	ld c, a
	ld b, 0
	ld hl, WildAreaTypeMaps
	add hl, bc
	ld a, [hl]
	ret
