; ============================================================
; Mini-boss framework (see K:\...\Red Rogue Files\MINIBOSS_FRAMEWORK.md)
;
; Lives in the "rogue" section (same object as random_stage_selection.asm), so
; it reaches _PickNextStage / _PickRandomUnvisitedStage / _StageBitInfo /
; RogueStageMapTable / PatchWarpEntry with plain calls, and
; SpecialEncounterRollAndAssign is plain-called from SelectAndPatchLobbyExit.
;
; SpecialEncounterRollAndAssign is the unified mini-boss/wild-area roll: one
; shared roll decides whether a special occurs this lobby visit, then which
; kind (mini-boss vs. wild area, see custom_functions/wild_area_selection.asm),
; drawing from a combined budget. Transient per-selection mini-boss state is
; packed in wRogueFlagsBitfield bits 4-7:
;   bits 4-5 = offered type (MINIBOSS_TYPE_MASK/SHIFT), bit 6 = which door,
;   bit 7 = active on the stage being entered. Persistent counters:
;   wRoutesSinceSpecial (shared escalation), wMiniBossCount (>=2 guarantee),
;   wWildAreaState (wild-area no-repeat mask + >=2 guarantee count).
; ============================================================

DEF MINIBOSS_ENTRY_SIZE EQU 7
; Rival + Giovanni now both roll (Giovanni's Rocket Hideout B1F encounter hook is
; live). Raise further as more boss types get their encounter hooks.
DEF MINIBOSS_MAX_ROLLABLE_TYPE EQU MINIBOSS_GIOVANNI

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
	; ONLY maps whose stage script calls MiniBossApplyStageTrainer (the
	; encounter hook) belong here, so a door never promises a boss that can't
	; appear. Excludes Giovanni's maps, USS Anne, Route 24's nugget gate, and
	; the sprite-set-incompatible outdoor routes 6/12/13/15 and split Route 5.
	db ROUTE_1
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
	; Giovanni is indoor-only (SPRITE_GIOVANNI is in no outdoor sprite set) and
	; stays exclusive to these dungeon maps (never in RivalMaps).
	db MT_MOON_1F
	db VIRIDIAN_FOREST
	db ROCKET_HIDEOUT_B1F
	db -1

; ============================================================
; SpecialEncounterRollAndAssign  (was MiniBossRollAndAssign)
; Called from SelectAndPatchLobbyExit AFTER _PickNextStage set wRogueMap and copied it
; into both lobby doors. On a route-next selection past the first route, may turn the
; lobby into a special: a mini-boss (one door boss / one door route) OR a wild area
; (one door wild / one door route, or a single mandatory door when the >=2 guarantee
; forces it). No-ops (clearing the mini-boss transient bits) on gym-next / first route.
; Mini-boss and wild-area occurrences are mutually exclusive per lobby visit and share
; one escalation counter (wRoutesSinceSpecial) so the combined budget trends ~4/2/2.
; ============================================================
SpecialEncounterRollAndAssign::
	; clear transient mini-boss bits from any prior selection
	ld hl, wRogueFlagsBitfield
	res BIT_MINIBOSS_DOOR, [hl]
	res BIT_MINIBOSS_ACTIVE, [hl]
	ld a, [hl]
	and %11001111           ; clear type field (bits 4-5), keep the rest
	ld [hl], a
	; gate: route-next only (gym-next has one door, no special)
	bit BIT_ROGUE_GYM_NEXT, [hl]
	ret nz
	; gate: never on the first route
	ld a, [wBattleCount]
	cp MINIBOSS_FIRST_BATTLECOUNT
	ret c
	; --- compute forcing for each kind into e: bit0 = mbForced, bit1 = waForced ---
	ld e, 0
	ld a, [wMiniBossCount]
	ld b, a
	ld c, MINIBOSS_MIN_PER_RUN
	call SpecialKindForced   ; carry = must force this kind
	jr nc, .mbDone
	set 0, e
.mbDone:
	call GetWildAreaCount    ; a = wild count (bits 3-4 of wWildAreaState)
	ld b, a
	ld c, WILD_AREA_MIN_PER_RUN
	call SpecialKindForced
	jr nc, .waDone
	set 1, e
.waDone:
IF DEF(_DEBUG)
	; Debug 2 testing aid: directly force BOTH lobby doors to PROCEDURAL_CAVE_1 on
	; every eligible route-next lobby visit. Bypasses WildAreaPickAndAssign (and its
	; Rangerandom calls) entirely rather than routing through the normal roll/pick
	; path, since the random function has changed and a deterministic force through
	; that path is no longer reliable for testing. Debug-build only; off entirely
	; in release ROMs.
	ld a, [wStatusFlags6]
	bit BIT_DEBUG2_MODE, a
	jr z, .noDebugForce
	ld a, PROCEDURAL_FOREST
	ld [wLobbyDoor1StageMap], a
	ld [wLobbyDoor2StageMap], a   ; door1==door2 => Lobby_IsDoor2Blocked blocks door 2
	xor a
	ld [wRoutesSinceSpecial], a
	ret
.noDebugForce
ENDC
	; --- decide whether a special occurs, and which kind ---
	ld a, e
	and a
	jr z, .rollChance        ; neither forced -> escalating chance
	cp %00000001
	jr z, .doMiniBoss        ; only mini-boss forced
	cp %00000010
	jr z, .doWildArea        ; only wild area forced
	jr .chooseKind           ; both forced -> balance by count
.rollChance:
	call SpecialChanceOccur  ; carry = a special occurs this visit
	jr nc, .noSpecial
.chooseKind:
	; pick the kind with the lower running count; tie -> 50/50 random.
	call GetWildAreaCount
	ld c, a                  ; c = wild count
	ld a, [wMiniBossCount]
	ld b, a                  ; b = mb count
	ld a, c
	cp b
	jr c, .doWildArea        ; wild < mb -> wild
	jr nz, .doMiniBoss       ; wild > mb -> mini-boss
	ld c, 2
	call Rangerandom         ; a = 0 or 1
	and a
	jr z, .doMiniBoss
	jr .doWildArea
.noSpecial:
	ld hl, wRoutesSinceSpecial
	inc [hl]
	ret
.doMiniBoss:
	call MiniBossPickTypeAndStage ; carry = success, a = type, b = map (endless-safe)
	jr nc, .noSpecial             ; defensive; rarely taken
	call MiniBossAssignDoors      ; sets door maps + bits 4-6
	xor a
	ld [wRoutesSinceSpecial], a
	ld hl, wMiniBossCount
	inc [hl]
	ret
.doWildArea:
	; forced? (e bit1) -> mandatory single door; else choosable one-of-two
	bit 1, e
	jr z, .waChoosable
	scf                           ; carry = forced
	jr .waAssign
.waChoosable:
	and a                         ; carry clear = choosable
.waAssign:
	call WildAreaPickAndAssign    ; input carry = forced; picks type (no-repeat),
	                              ; updates wWildAreaState (mask bit + count), sets doors
	xor a
	ld [wRoutesSinceSpecial], a
	ret

; INPUT: b = current count for this kind, c = its min-per-run.
; OUTPUT: carry set if this kind must be forced now (behind schedule vs routes left).
; Mirrors the old MiniBossShouldOccur forced-guarantee arithmetic, parameterized.
; Clobbers a/b/c; preserves d/e/hl.
SpecialKindForced:
	ld a, c
	sub b                    ; needed = min - count
	jr z, .no                ; count >= min
	jr c, .no
	ld d, a                  ; d = needed (survives MiniBossCountBadges)
	call MiniBossCountBadges ; a = badges 0-8 (clobbers b/c, preserves d)
	ld b, a
	ld a, MINIBOSS_TOTAL_ROUTES
	sub b                    ; a = approx routes remaining
	cp d
	jr c, .yes               ; remaining < needed
	jr z, .yes               ; remaining == needed
.no:
	and a
	ret
.yes:
	scf
	ret

; Escalating chance that a special occurs, keyed on wRoutesSinceSpecial (64/128/192,
; guaranteed at 3). Identical curve to the old MiniBossShouldOccur escalation.
; OUTPUT: carry set = a special occurs. Clobbers a/b.
SpecialChanceOccur:
	ld a, [wRoutesSinceSpecial]
	cp 3
	jr nc, .yes
	inc a
	swap a                   ; * 16
	sla a                    ; * 32
	sla a                    ; * 64 (64, 128, or 192)
	ld b, a
	call Random              ; a = 0..255
	cp b
	ret c                    ; a < threshold -> occur (carry set)
	and a
	ret
.yes:
	scf
	ret

; OUTPUT: a = wild-area offered-count this run (bits 3-4 of wWildAreaState, 0-3).
; Clobbers a only.
GetWildAreaCount:
	ld a, [wWildAreaState]
	and WILD_AREA_COUNT_MASK
	srl a
	srl a
	srl a
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

; a = boss type (1-based) -> hl = MiniBossTable entry pointer for that type.
; Clobbers a/bc/d.
MiniBossEntryForType:
	dec a                        ; 1-based -> 0-based
	ld hl, MiniBossTable
	ld bc, MINIBOSS_ENTRY_SIZE
	and a
	ret z
	ld d, a
.mul
	add hl, bc
	dec d
	jr nz, .mul
	ret

; -> a = the current map's 5th-trainer object slot (1-based) from
; MiniBossStageSlots, or 0 if this map has no boss slot registered.
; Clobbers a/b/hl (leaves c/d/e intact for callers holding state across it).
MiniBossSlotForCurMap:
	ldh a, [hCurMap]
	ld b, a
	ld hl, MiniBossStageSlots
.scan
	ld a, [hli]
	cp -1
	jr z, .none
	cp b
	jr z, .found
	inc hl                       ; skip the slot byte
	jr .scan
.none
	xor a
	ret
.found
	ld a, [hl]
	ret

; ============================================================
; MiniBossApplyStageTrainer  (farcalled from a stage's setup script)
; Generic replacement for the per-map hardcoded trainer swap. If this map is the
; active mini-boss stage, overwrites the 5th-trainer object's wMapSpriteExtraData
; (2 bytes: OPP class + trainer number) with the rolled boss, read from the
; registry:
;   - class  = MiniBossTable[type-1] byte 0 (OPP_*_MINIBOSS)
;   - number = 1 for TEAM_STARTER_BASED, random 1-3 for TEAM_RANDOM_3_SET
; wMapSpriteExtraData is read fresh by EngageMapTrainer at engage time, so
; patching it once here at setup is sufficient; the overworld sprite is swapped
; separately by MiniBossPatchStageSprite. No-op on a non-mini-boss stage. The
; object slot per map comes from MiniBossStageSlots (same table the sprite swap
; uses), so a map is rolled out by adding one MiniBossStageSlots row + one map-
; list entry + one `farcall MiniBossApplyStageTrainer` in its setup script.
; Clobbers a/bc/de/hl (safe: farcalled from script setup).
; ============================================================
MiniBossApplyStageTrainer::
	call MiniBossCheckActivate   ; a = boss type (0 = not the mini-boss stage); sets bit 7
	and a
	ret z
	call MiniBossEntryForType    ; hl -> registry entry
	ld a, [hl]                   ; byte 0 = OPP class
	ld d, a                      ; d = OPP class (survives the slot lookup)
	ld bc, 4
	add hl, bc
	ld a, [hl]                   ; byte 4 = team-select mode
	ld e, a                      ; e = team-select mode (survives the slot lookup)
	call MiniBossSlotForCurMap   ; a = object slot (0 = none); preserves d/e
	and a
	ret z
	; hl = wMapSpriteExtraData + (slot-1)*2  (2 bytes per object: class, number)
	dec a
	add a
	ld c, a
	ld b, 0
	ld hl, wMapSpriteExtraData
	add hl, bc
	ld a, d                      ; OPP class
	ld [hli], a                  ; write class; hl -> trainer-number byte
	ld a, e                      ; team-select mode
	cp TEAM_RANDOM_3_SET
	jr z, .random3
	ld a, 1                      ; TEAM_STARTER_BASED (or default): the single team
	ld [hl], a
	ret
.random3
	push hl
	ld c, 3
	call Rangerandom             ; a = 0..2 (bc/de preserved)
	inc a                        ; -> 1..3
	pop hl
	ld [hl], a
	ret

; ============================================================
; MiniBossPatchStageSprite  (called from LoadMapData in home/overworld.asm)
; Runs on every map load, in the window between LoadMapHeader (which populates
; the sprite slots from the map's object list) and InitMapSprites (which loads
; VRAM tile patterns from each slot's PICTUREID). If the map being loaded is the
; active mini-boss stage, this repoints the 5th-trainer object's overworld sprite
; to the boss's sprite BEFORE its tiles are loaded - the same technique the
; procedural cave/forest boss system uses (the ordering is load-bearing: writing
; PICTUREID after InitMapSprites would leave the wrong tiles loaded; see
; FOREST_STATUS_AND_FIX_PLAN.md). The boss sprite is already in the map's sprite
; set (that's part of what makes the map mini-boss-eligible), so no VRAM reload is
; needed - this only points the object at an already-loaded tile slot.
;
; wMapSpriteExtraData (the trainer CLASS) is patched separately, later, by the
; route script - that's read at battle-engage time and is unaffected by this.
; Clobbers a/bc/de/hl (fine: called via farcall, InitMapSprites needs no regs).
; ============================================================
MiniBossPatchStageSprite::
	call MiniBossCheckActivate   ; a = boss type (0 = not the mini-boss stage); sets bit 7
	and a
	ret z
	call MiniBossEntryForType    ; hl -> registry entry
	inc hl                       ; byte 1 = overworld sprite id
	ld a, [hl]
	ld c, a                      ; c = boss sprite id (survives the slot lookup below)
	call MiniBossSlotForCurMap   ; a = object slot (0 = none registered for this map)
	and a
	ret z
	; wSprite<slot>StateData1PictureID = wSprite01StateData1PictureID + (slot-1)*len
	dec a
	ld hl, wSprite01StateData1PictureID
	and a
	jr z, .write
	ld b, a
	ld de, SPRITESTATEDATA1_LENGTH
.addSlot
	add hl, de
	dec b
	jr nz, .addSlot
.write
	ld a, c                      ; boss sprite id
	ld [hl], a                   ; PICTUREID of the boss's object slot
	ret

; map id -> the 5th-trainer object slot (1-based, = the object's const index in
; that map's objects file) whose sprite gets swapped to the boss. Keep in sync
; with each route's MiniBossCheckActivate hook and RivalMaps (above). -1 = end.
MiniBossStageSlots:
	; Every hooked stage's 5th trainer is object slot 5 (verified per-map).
	db ROUTE_1, 5
	db ROUTE_3, 5
	db ROUTE_9, 5
	db ROUTE_25, 5
	db DIGLETTS_CAVE, 5
	db ROCK_TUNNEL_1F, 5
	db POKEMON_TOWER_2F, 5
	db POKEMON_TOWER_7F, 5
	db POWER_PLANT, 5
	db POKEMON_MANSION_1F, 5
	db SEAFOAM_ISLANDS_1F, 5
	db MT_MOON_1F, 5
	db VIRIDIAN_FOREST, 5
	db ROCKET_HIDEOUT_B1F, 5
	db -1
