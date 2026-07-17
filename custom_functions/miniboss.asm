; ============================================================
; Mini-boss framework (see K:\...\Red Rogue Files\MINIBOSS_FRAMEWORK.md)
;
; Lives in the "rogue" section (same object as random_stage_selection.asm), so
; it reaches _PickNextStage / _PickRandomUnvisitedStage / _StageBitInfo /
; RogueStageMapTable / PatchWarpEntry with plain calls, and MiniBossRollAndAssign
; is plain-called from SelectAndPatchLobbyExit.
;
; Transient per-selection state is packed in wRogueFlagsBitfield bits 4-7:
;   bits 4-5 = offered type (MINIBOSS_TYPE_MASK/SHIFT), bit 6 = which door,
;   bit 7 = active on the stage being entered. Persistent counters:
;   wRoutesSinceMiniBoss (escalation), wMiniBossCount (>=2 guarantee).
; ============================================================

DEF MINIBOSS_ENTRY_SIZE EQU 7
; Only Rival is rolled until Giovanni's maps get the encounter hook (Step 6).
; Raise to MINIBOSS_GIOVANNI once Giovanni's routes call MiniBossCheckActivate.
DEF MINIBOSS_MAX_ROLLABLE_TYPE EQU MINIBOSS_RIVAL

; Registry: one entry per real boss type, indexed by (type - 1).
; db OPP class, sprite id, overworld approach music, placement mode, team-select
; mode; dw allowed-map list. (Karate is added here with its own class + map
; once its FightingDojo stage exists.)
MiniBossTable:
	; MINIBOSS_RIVAL
	db OPP_RIVAL_MINIBOSS, SPRITE_BLUE, MUSIC_MEET_RIVAL, PLACE_REPLACE_5TH, TEAM_STARTER_BASED
	dw RivalMaps
	; MINIBOSS_GIOVANNI
	db OPP_GIOVANNI_MINIBOSS, SPRITE_GIOVANNI, MUSIC_MEET_RIVAL, PLACE_REPLACE_5TH, TEAM_RANDOM_3_SET
	dw GiovanniMaps

; Allowed-map lists (-1 terminated). A mini-boss only manifests on a map whose
; stage script calls MiniBossCheckActivate (the encounter hook), so keep these
; in sync with the hooked routes as Step 6 rolls out.
RivalMaps:
	; Every eligible stage minus Giovanni's maps, USS Anne, Route 24 (nugget
	; gate), and the sprite-set-incompatible outdoor routes (6/12/13/15, 5).
	db ROUTE_1          ; prototype (normally the first route, so debug-forced to test)
	db ROUTE_3
	db ROUTE_9
	db ROUTE_25
	db DIGLETTS_CAVE
	db ROCK_TUNNEL_1F
	db POKEMON_TOWER_2F
	db POKEMON_TOWER_7F
	db POWER_PLANT
	db POKEMON_MANSION_1F
	db SEAFOAM_ISLANDS_1F
	db -1
GiovanniMaps:
	db MT_MOON_1F
	db VIRIDIAN_FOREST
	db ROCKET_HIDEOUT_B1F
	db -1

; ============================================================
; MiniBossRollAndAssign
; Called from SelectAndPatchLobbyExit AFTER _PickNextStage has set wRogueMap.
; On a route-next selection past the first route, may turn ONE lobby door into a
; mini-boss stage (the other keeps the normal route) and record the offered type
; + which door in wRogueFlagsBitfield bits 4-6. No-ops (clearing the bits) on
; gym-next or the first route.
; ============================================================
MiniBossRollAndAssign::
	; clear transient bits from any prior selection
	ld hl, wRogueFlagsBitfield
	res BIT_MINIBOSS_DOOR, [hl]
	res BIT_MINIBOSS_ACTIVE, [hl]
	ld a, [hl]
	and %11001111 ; clear the type field (bits 4-5), keep the rest
	ld [hl], a
	; gate: route-next only (gym-next has a single door, no mini-boss)
	bit BIT_ROGUE_GYM_NEXT, [hl]
	ret nz
	; gate: never on the first route
	ld a, [wBattleCount]
	cp MINIBOSS_FIRST_BATTLECOUNT
	ret c
	; decide occurrence (chance / forced guarantee)
	call MiniBossShouldOccur
	jr nc, .noMiniBoss
	; pick boss type + its stage (availability-first, endless-safe)
	call MiniBossPickTypeAndStage ; carry = success, a = type, b = mini-boss map
	jr nc, .noMiniBoss
	call MiniBossAssignDoors       ; a = type, b = map -> sets door maps + bits 4-6
	xor a
	ld [wRoutesSinceMiniBoss], a
	ld hl, wMiniBossCount
	inc [hl]
	ret
.noMiniBoss
	ld hl, wRoutesSinceMiniBoss
	inc [hl]
	ret

; Returns carry set if a mini-boss should occur this route selection.
MiniBossShouldOccur:
	; forced by the >=2-per-run guarantee?
	ld a, [wMiniBossCount]
	ld b, a
	ld a, MINIBOSS_MIN_PER_RUN
	sub b
	jr z, .notForced        ; already met the minimum
	jr c, .notForced
	ld c, a                 ; c = still needed (>=1)
	call MiniBossCountBadges
	ld b, a
	ld a, MINIBOSS_TOTAL_ROUTES
	sub b                   ; a = approx routes remaining in the run
	cp c
	jr c, .forced           ; remaining < needed -> force now
	jr z, .forced           ; remaining == needed -> force
.notForced
	; escalating chance = 64 * (routesSince + 1); >=3 -> guaranteed
	ld a, [wRoutesSinceMiniBoss]
	cp 3
	jr nc, .forced
	inc a
	swap a                  ; * 16
	sla a                   ; * 32
	sla a                   ; * 64  (64, 128, or 192)
	ld b, a
	call Random             ; a = 0..255
	cp b
	ret c                   ; a < threshold -> occur (carry set)
	and a                   ; clear carry
	ret
.forced
	scf
	ret

; a = number of set bits in wObtainedBadges (0-8)
MiniBossCountBadges:
	ld a, [wObtainedBadges]
	ld b, 0
	ld c, 8
.loop
	srl a
	jr nc, .skip
	inc b
.skip
	dec c
	jr nz, .loop
	ld a, b
	ret

; Picks a boss type that still has an unvisited eligible map (weighted uniformly
; among available types); if none is available (endless mode), forces a revisit.
; Returns carry set with a = type, b = chosen mini-boss map.
MiniBossPickTypeAndStage:
	; Pass 1: count rollable types with an unvisited map
	ld b, 0                 ; b = available count
	ld c, 1                 ; c = type iterator
.availLoop
	ld a, c
	cp MINIBOSS_MAX_ROLLABLE_TYPE + 1
	jr z, .availDone
	push bc
	ld a, c
	call BossHasUnvisitedMap
	pop bc
	jr nc, .availSkip
	inc b
.availSkip
	inc c
	jr .availLoop
.availDone
	ld a, b
	and a
	jr z, .endless          ; no boss has an unvisited map
	; pick the k-th available type
	ld c, b
	call Rangerandom        ; a = [0, count-1]
	ld d, a                 ; d = target index among available
	ld c, 1                 ; c = type iterator
.pickLoop
	ld a, c
	push bc
	push de
	call BossHasUnvisitedMap
	pop de
	pop bc
	jr nc, .pickSkip
	ld a, d
	and a
	jr z, .foundType
	dec d
.pickSkip
	inc c
	jr .pickLoop
.foundType
	; c = chosen type; pick an unvisited map for it
	ld a, c
	push bc
	call PickUnvisitedMapForBoss ; b = chosen map
	ld a, b                 ; a = map
	pop bc
	ld b, a                 ; b = map (a about to become type)
	ld a, c                 ; a = type
	scf
	ret
.endless
	; every boss exhausted: pick any rollable boss, any map (ignore visited)
	ld c, MINIBOSS_MAX_ROLLABLE_TYPE
	call Rangerandom
	inc a                   ; type in [1, MAX]
	ld c, a                 ; c = type
	push bc
	call PickAnyMapForBoss  ; b = map
	ld a, b
	pop bc
	ld b, a                 ; b = map
	ld a, c                 ; a = type
	scf
	ret

; a = boss type -> carry set if any map in its list is unvisited/eligible.
BossHasUnvisitedMap:
	call GetBossMapList     ; hl -> map list
.loop
	ld a, [hl]
	inc hl
	cp -1
	jr z, .none
	push hl
	call MiniBossIsMapVisited ; a = 1 visited/ineligible, 0 pickable
	and a
	pop hl
	jr nz, .loop
	scf                     ; found a pickable map
	ret
.none
	and a
	ret

; a = boss type -> b = a random UNVISITED map from its list (caller guarantees
; at least one exists).
PickUnvisitedMapForBoss:
	call GetBossMapList
	push hl                 ; save list start for pass 2
	ld b, 0                 ; b = unvisited count
.cnt
	ld a, [hl]
	inc hl
	cp -1
	jr z, .cntDone
	push hl
	push bc
	call MiniBossIsMapVisited
	and a
	pop bc
	pop hl
	jr nz, .cnt
	inc b
	jr .cnt
.cntDone
	ld c, b
	call Rangerandom        ; a = [0, count-1]
	ld c, a                 ; c = target
	pop hl                  ; hl -> list start
.pick
	ld a, [hl]
	inc hl
	cp -1
	ret z                   ; safety
	push hl
	push bc
	push af                 ; save candidate map (a)
	call MiniBossIsMapVisited ; input a = map -> a = 0/1
	ld d, a                 ; d = visited flag
	pop af                  ; a = candidate map
	pop bc                  ; b junk, c = target
	pop hl
	ld e, a                 ; e = candidate map
	ld a, d
	and a
	jr nz, .pick            ; visited -> skip
	ld a, c
	and a
	jr z, .chosen
	dec c
	jr .pick
.chosen
	ld b, e
	ret

; a = boss type -> b = a random map from its list, IGNORING the visited set.
PickAnyMapForBoss:
	call GetBossMapList
	push hl
	ld b, 0
.cnt
	ld a, [hl]
	inc hl
	cp -1
	jr z, .cntDone
	inc b
	jr .cnt
.cntDone
	ld c, b
	call Rangerandom        ; a = [0, count-1]
	pop hl
	ld d, 0
	ld e, a
	add hl, de
	ld b, [hl]
	ret

; a = boss type -> hl = its allowed-map list pointer (from MiniBossTable).
GetBossMapList:
	dec a                   ; 1-based -> 0-based
	ld hl, MiniBossTable
	ld bc, MINIBOSS_ENTRY_SIZE
	and a
	jr z, .atEntry
	ld d, a
.mul
	add hl, bc
	dec d
	jr nz, .mul
.atEntry
	ld bc, 5                ; map-list pointer is at entry offset 5
	add hl, bc
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ret

; a = map id -> a = 1 if that map is already visited this run OR not a stage
; map (ineligible), else a = 0. Clobbers bc/de/hl.
MiniBossIsMapVisited:
	ld b, a                 ; b = target map id
	ld hl, RogueStageMapTable
	ld c, 0                 ; c = stage index
.scan
	ld a, [hli]
	cp -1
	jr z, .ineligible
	cp b
	jr z, .found
	inc c
	jr .scan
.found
	call _StageBitInfo      ; hl -> byte, b = mask (uses c = stage index)
	ld a, [hl]
	and b
	jr z, .unvisited
	ld a, 1
	ret
.unvisited
	xor a
	ret
.ineligible
	ld a, 1
	ret

; a = boss type, b = mini-boss map. Randomizes which lobby door is the mini-boss;
; the other door keeps the normal route (wRogueMap, re-picked if it collides with
; the mini-boss map). Writes wLobbyDoor1/2StageMap + bits 4-6.
MiniBossAssignDoors:
	push af                 ; save type (a)
	push bc                 ; save mini-boss map (b)
	; make sure the normal route differs from the mini-boss map
	ld a, [wRogueMap]
	cp b
	jr nz, .haveNormal
	call _PickRandomUnvisitedStage ; re-pick wRogueMap (rare collision path)
.haveNormal
	ld c, 2
	call Rangerandom        ; a = 0 (door1 = boss) or 1 (door2 = boss)
	pop bc                  ; b = mini-boss map
	pop de                  ; d = type
	ld hl, wRogueFlagsBitfield
	and a
	jr z, .door1
	set BIT_MINIBOSS_DOOR, [hl]
	ld a, [wRogueMap]
	ld [wLobbyDoor1StageMap], a
	ld a, b
	ld [wLobbyDoor2StageMap], a
	jr .setType
.door1
	res BIT_MINIBOSS_DOOR, [hl]
	ld a, b
	ld [wLobbyDoor1StageMap], a
	ld a, [wRogueMap]
	ld [wLobbyDoor2StageMap], a
.setType
	ld a, [hl]
	and %11001111 ; clear the type field (bits 4-5), keep the rest
	ld e, a
	ld a, d                 ; type (1-3)
	swap a                  ; -> bits 4-7 (type <= 3, so bits 4-5)
	and MINIBOSS_TYPE_MASK
	or e
	ld [hl], a
	ret

; ============================================================
; MiniBossCheckActivate  (called from a stage's setup script, Step 6)
; If an offered mini-boss's chosen map == the map now being entered, marks it
; active (wRogueFlagsBitfield bit 7) and returns a = boss type (1-3). Otherwise
; returns a = 0. Reward-rarity stacking keys off bit 7 (Step 7).
; ============================================================
MiniBossCheckActivate::
	ld a, [wRogueFlagsBitfield]
	and MINIBOSS_TYPE_MASK
	jr z, .none             ; no mini-boss offered this selection
	swap a                  ; type field -> low bits
	ld e, a                 ; e = offered type
	ld a, [wRogueFlagsBitfield]
	bit BIT_MINIBOSS_DOOR, a
	ld a, [wLobbyDoor1StageMap]
	jr z, .haveMap
	ld a, [wLobbyDoor2StageMap]
.haveMap
	ld b, a                 ; b = the mini-boss door's stage map
	ldh a, [hCurMap]
	cp b
	jr nz, .none            ; player entered the OTHER door's (normal) route
	ld hl, wRogueFlagsBitfield
	set BIT_MINIBOSS_ACTIVE, [hl]
	ld a, e                 ; return the boss type
	ret
.none
	xor a
	ret
