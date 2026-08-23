; custom_functions/procedural_stage_hooks.asm
;
; Load-time procedural-stage hooks, moved OUT of home/overworld.asm's LoadMapData
; to relieve ROM0/HOME bank pressure (the inline versions overflowed ROM0). These
; are farcall'd from LoadMapData, the same pattern master uses for
; MiniBossPatchStageSprite. Facility is shelved: its (unreachable) branches are
; intentionally omitted here; see the comments to re-enable.

SECTION "ProcStageHooks", ROMX

; Patch wSprite01's PICTUREID to the rolled boss's overworld-sprite category
; BEFORE InitMapSprites loads tile patterns, for the procedural cave/forest maps.
; The SPRITE_* constant was staged into SRAM at Pallet Town entry.
ProcBossPatchStageSprite::
	farcall MiniBossPatchStageSprite   ; chained here to save a HOME farcall; a map is
	                                   ; never both a miniboss stage and a procedural
	                                   ; stage, so order between them does not matter
	ldh a, [hCurMap]
	cp PROCEDURAL_CAVE_1
	jr z, .cave
	cp PROCEDURAL_FOREST
	jr z, .forest
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
.close
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ld a, b
	ld [wSprite01StateData1 + SPRITESTATEDATA1_PICTUREID], a
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
	; SHELVED facility preload: farcall PFacPreload
	ret                          ; PALLET_TOWN is never also a procedural map
.notPalletTown
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
	; SHELVED facility finalize: cp PROCEDURAL_FACILITY / farcall PFacFinalize
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
	call .classify           ; a mapped to 1=cave 2=forest 3=cem, 0=not wild
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
	; cemetery
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
; a = map id -> a = 1 (cave) / 2 (forest) / 3 (cemetery_1) / 0 (not a wild entry map).
.classify:
	cp PROCEDURAL_CAVE_1
	jr z, .isCave
	cp PROCEDURAL_FOREST
	jr z, .isForest
	cp PROCEDURAL_CEMETERY_1
	jr z, .isCem
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
