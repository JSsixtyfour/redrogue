; custom_functions/procedural_stage_hooks.asm
;
; Load-time procedural-stage hooks, moved OUT of home/overworld.asm's LoadMapData
; to relieve ROM0/HOME bank pressure (the inline versions overflowed ROM0). These
; are farcall'd from LoadMapData, the same pattern master uses for
; MiniBossPatchStageSprite. All four procedural Wild Areas use this dispatch.

SECTION "ProcStageHooks", ROMX

; Patch wSprite01's PICTUREID to the rolled boss's overworld-sprite category
; BEFORE InitMapSprites loads tile patterns, for the procedural cave/forest maps.
; The SPRITE_* constant was staged into SRAM by the assigned-area preload.
ProcBossPatchStageSprite::
	farcall MiniBossPatchStageSprite   ; chained here to save a HOME farcall; a map is
	                                   ; never both a miniboss stage and a procedural
	                                   ; stage, so order between them does not matter
	ldh a, [hCurMap]
	cp PROCEDURAL_CAVE_1
	jr z, .cave
	cp PROCEDURAL_FOREST
	jr z, .forest
	cp PROCEDURAL_FACILITY
	jr z, .facility
	cp SILPH_CO_DORM
	jr z, .dorm
	ret
.dorm
	farcall RoomPatchSprites
	ret
.cave
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ASSERT BANK("Sprite Buffers") == 0
	xor a
	ld [rRAMB], a
	ld a, [sProcCaveStagingBossSprite]
	ld b, a                          ; save sprite constant before closing SRAM
	jr .close
.forest
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ASSERT BANK("Sprite Buffers") == 0
	xor a
	ld [rRAMB], a
	ld a, [sProcForestBossSprite]
	ld b, a
	jr .close
.facility
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ld a, BANK(sProcFacilityStagingBuffer)
	ld [rRAMB], a
	ld a, [sProcFacilityBossSprite]
	ld b, a
.close
	; Phase 7b: the stage-event NPC sprites ride along in the SAME open-SRAM
	; window as the boss sprite, read here and installed below. They live in
	; bank 0 while the Facility's boss sprite came from bank 1, so re-select
	; bank 0 before reading them rather than inheriting whichever branch ran.
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
	ld a, b
	ld [wSprite01StateData1 + SPRITESTATEDATA1_PICTUREID], a

	; --- stage-event NPC slots: ONLY on maps that actually declare them -----
	; MEASURED BUG, 2026-09-17. This patch was originally unconditional, on the
	; reasoning that only one wild area is ever live so a stage without NPC
	; slots "has no object for the write to affect". That reasoning is wrong
	; twice, and both ways are real:
	;
	;   * FOREST - LoadMapHeader zeroes slots 01-15 and then loads only
	;     wNumSprites objects, so the forest's slots 6/7 are genuinely empty.
	;     Writing a PICTUREID into one does not hit a dormant object, it
	;     CREATES one. And sStageEventSprite6/7 are written only by
	;     PCPreloadCave, so after any cave visit with an armed event they still
	;     hold that event's sprites. Probed directly: entering the forest with
	;     $4b/$4c staged produced wNumSprites=5 with slots 6 and 7 holding
	;     $4b/$4c at MapX=0 - a phantom Jessie and James on a map that never
	;     declared them, costing two 12-tile VRAM slots.
	;   * FACILITY - worse, because there the write would LAND on something.
	;     Its slots 6-9 are the four fake item balls, so an unconditional patch
	;     would replace a pokeball's sprite with a villain's.
	;
	; So the patch is gated to the maps that own these slots. Today that is the
	; Cave alone. CONTRACT for adding another stage: it needs BOTH the object
	; slots in its object list AND a farcall to StageEventStageSprites in its
	; own preload, and only then a case here. Gating on wNumSprites instead
	; would be wrong - the Facility has nine objects and would pass.
	ldh a, [hCurMap]
	cp PROCEDURAL_CAVE_1
	ret nz
	; 0 here is not "hide it later" but "this slot does not exist":
	; LoadMapSpriteTilePatterns skips a zero PICTUREID outright, so an unarmed
	; event costs no VRAM tile-pattern slot.
	ld a, d
	ld [wSprite06StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ld a, e
	ld [wSprite07StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ret

; Procedural preload (at PALLET_TOWN entry) + per-map finalize dispatch. Runs
; after LoadTileBlockMap, before LoadTilesetTilePatternData. Uses farcall (NOT
; homecall) to reach the generators, because homecall is only valid from a HOME
; caller and this routine itself lives in ROMX.
ProcStageLoadDispatch::
	; +5 wBattleCount when the map we just LEFT (wWarpedFromWhichMap) was a wild
	; area (cave / forest / last cemetery floor). Applied here, on the destination
	; map's load, instead of via a HOME hook in the warp handler (saves ROM0). Wild
	; areas always exit to the lobby (LAST_MAP), which has no wild battles, so
	; LoadMapData won't re-run there and double-apply before the next warp clears
	; wWarpedFromWhichMap.
	ld a, [wWarpedFromWhichMap]
	cp PROCEDURAL_CAVE_1
	jr z, .addExitBattles
	cp PROCEDURAL_FOREST
	jr z, .addExitBattles
	cp PROCEDURAL_FACILITY
	jr z, .addExitBattles
	cp PROCEDURAL_CEMETERY_4
	jr nz, .noExitBattles
.addExitBattles
	ld a, [wBattleCount]
	add a, 5
	jr nc, .noExitClamp
	ld a, $ff
.noExitClamp
	ld [wBattleCount], a
.noExitBattles
	ldh a, [hCurMap]
	cp PALLET_TOWN
	jr nz, .notPalletTown
	;farcall PCPreloadCave
	;farcall PCemGenerateMaps
	;farcall PFPreloadForest
	ret                          ; PALLET_TOWN is never also a procedural map
.notPalletTown
	cp SILPH_CO_B1F
	jr nz, .notWildAreaTestEntrance
	; The temporary Credit Exchange replacement is a complete wild-area test
	; entrance, so prepare a fresh run exactly as lobby assignment would.
	;
	; POINTED AT THE CAVE 2026-09-16 (was PFacPreload / PROCEDURAL_FACILITY)
	; for visual review of the river, which PCCarveRiver only started actually
	; producing today. The other half of this switch is SilphCoB1F's warps 6
	; and 7 in data/maps/objects/SilphCoB1F.asm - BOTH must point at the same
	; stage or the door stages one kind of run and walks into another. To put
	; the Facility back, revert this farcall and those two warp_events
	; together.
	call ProcGenerationBeginDoubleSpeed
	push af
	farcall PCPreloadCave
	pop af
	call ProcGenerationEndDoubleSpeed
	ret
.notWildAreaTestEntrance
	cp SILPH_CO_DORM
	jr nz, .notDorm
	farcall RoomStampBlocks
	ret
.notDorm
	cp PROCEDURAL_CAVE_1
	jr nz, .notCave
	call ProcGenerationBeginDoubleSpeed
	push af
	farcall PCFinalizeCave
	pop af
	call ProcGenerationEndDoubleSpeed
	ret
.notCave
	cp PROCEDURAL_FOREST
	jr nz, .notForest
	call ProcGenerationBeginDoubleSpeed
	push af
	farcall PFinalizeForest
	pop af
	call ProcGenerationEndDoubleSpeed
	ret
.notForest
	cp PROCEDURAL_FACILITY
	jr nz, .notFacility
	call ProcGenerationBeginDoubleSpeed
	push af
	farcall PFacFinalize
	pop af
	call ProcGenerationEndDoubleSpeed
	ret
.notFacility
	cp PROCEDURAL_CEMETERY_1
	jr z, .cemetery
	cp PROCEDURAL_CEMETERY_2
	jr z, .cemetery
	cp PROCEDURAL_CEMETERY_3
	jr z, .cemetery
	cp PROCEDURAL_CEMETERY_4
	ret nz
.cemetery
	call ProcGenerationBeginDoubleSpeed
	push af
	farcall PCemFinalizeMap
	pop af
	call ProcGenerationEndDoubleSpeed
	ret

; Called from IndigoPlateauLobby_Script right after SelectAndPatchLobbyExit, so the
; assigned wild-area map's generator runs while the player is still in the lobby (hides
; the generation latency; without this a lobby->wild-area door warp would hit
; PCFinalize* against an un-populated SRAM staging buffer). Preloads only the one
; assigned type. No-op if neither door is a wild-area entry map.
ProcPreloadAssignedWildArea::
	ld a, [wLobbyDoor1StageMap]
	call .classify           ; 1=cave 2=forest 3=cem 4=facility, 0=not wild
	and a
	jr nz, .preload
	ld a, [wLobbyDoor2StageMap]
	call .classify
	and a
	ret z
.preload:
	dec a
	jr z, .cave
	dec a
	jr z, .forest
	dec a
	jr z, .cemetery
	jr .facility
.cemetery
	call ProcGenerationBeginDoubleSpeed
	push af
	farcall PCemGenerateMaps
	pop af
	call ProcGenerationEndDoubleSpeed
	ret
.cave:
	call ProcGenerationBeginDoubleSpeed
	push af
	farcall PCPreloadCave
	pop af
	call ProcGenerationEndDoubleSpeed
	ret
.forest:
	call ProcGenerationBeginDoubleSpeed
	push af
	farcall PFPreloadForest
	pop af
	call ProcGenerationEndDoubleSpeed
	ret
.facility:
	call ProcGenerationBeginDoubleSpeed
	push af
	farcall PFacPreload
	pop af
	call ProcGenerationEndDoubleSpeed
	ret
; a = map id -> a = 1 (cave) / 2 (forest) / 3 (cemetery_1) /
; 4 (facility) / 0 (not a wild entry map).
.classify:
	cp PROCEDURAL_CAVE_1
	jr z, .isCave
	cp PROCEDURAL_FOREST
	jr z, .isForest
	cp PROCEDURAL_CEMETERY_1
	jr z, .isCem
	cp PROCEDURAL_FACILITY
	jr z, .isFacility
	xor a
	ret
.isCave:
	ld a, 1
	ret
.isForest:
	ld a, 2
	ret
.isCem:
	ld a, 3
	ret
.isFacility:
	ld a, 4
	ret

; Run active procedural generation at the speed selected by ShinRed's CGB
; 60 fps option while preserving the caller's original CPU speed. Return $ff
; when no restoration is needed (DMG or already double), or 0 when this call
; switched a CGB from normal to double speed.
ProcGenerationBeginDoubleSpeed:
	ldh a, [hGBC]
	and a
	ld a, $ff
	ret z
	ldh a, [rKEY1]
	bit 7, a
	ld a, $ff
	ret nz
	predef SetCPUSpeed
	xor a
	ret

ProcGenerationEndDoubleSpeed:
	inc a
	ret z
	predef SingleCPUSpeed
	ret
