; custom_functions/procedural_CEMETERY_gen.asm
;
; Procedural cemetery generator for PROCEDURAL_CEMETERY_1-4.
; Four maps, each 10x9 blocks = 90 bytes, stored in SRAM bank 0.
;
; Per-map: 75% procedural (scatter tombstones on floor cells),
;          25% premade (copy matching PokemonTower floor verbatim).
;
; Tombstone blocks replacing floor (block 54 or 14):
;   76,78,79,81,82,23,19,77,80,101-106
;
; Warp positions (tile coords, always fixed, confirmed with user):
;   Maps 1,3: entrance (3,9) left, exit (18,9) right
;   Map  2  : entrance (18,9) right, exit (3,9) left
;   Map  4  : entrance (18,9) right, exit (9,16) south

SECTION "ProceduralCemeteryGen", ROMX

DEF CEMAP_WIDTH   EQU 10
DEF CEMAP_HEIGHT  EQU 9
DEF CEMAP_SIZE    EQU CEMAP_WIDTH * CEMAP_HEIGHT ; 90 bytes
DEF CEMAP_STRIDE  EQU CEMAP_WIDTH + 6           ; = 16 (width + MAP_BORDER*2)
DEF CEMAP_BASE    EQU 3 + 3 * CEMAP_STRIDE      ; = 51 (wOverworldMap interior offset)

DEF CEMAP_FLOOR_1 EQU 14  ; floor block in ProceduralCemetery1.blk
DEF CEMAP_FLOOR_2 EQU 54  ; floor block in PokemonTower floors / ProceduralCemetery2.blk

DEF CEMAP_NUM_TOMBSTONES EQU 30  ; tombstones scattered per procedural map

; wBuffer scratch (never conflicts - cemetery runs at map load time only)
DEF wCemMapIndex    EQU 0  ; 0-3, which of the 4 maps is currently being generated
DEF wCemTryX        EQU 1
DEF wCemTryY        EQU 2
DEF wCemIsProcedural EQU 3 ; 1 = procedural floor, 0 = premade (for staircase patch)
DEF wCemEntX        EQU 4  ; entrance inner col for path carve
DEF wCemEntY        EQU 5  ; entrance inner row
DEF wCemExX         EQU 6  ; exit inner col
DEF wCemExY         EQU 7  ; exit inner row
DEF wCemPrefabIndex EQU 19 ; which of the NUM_PREFABS rows was picked, premade maps only

; ============================================================
; PCemMapToIndex
; INPUT: hCurMap
; OUTPUT: a = 0-3 for PROCEDURAL_CEMETERY_1/2/3/4
; Explicit lookup needed because map IDs aren't consecutive
; ($6C = VICTORY_ROAD_1F sits between cemetery 3 and 4).
; ============================================================

;; simplify by reordering stages?
PCemMapToIndex:
	ldh a, [hCurMap]
	cp PROCEDURAL_CEMETERY_4
	ld a, 3
	ret z
	ldh a, [hCurMap]
	sub PROCEDURAL_CEMETERY_1
	ret

; ============================================================
; PCemGetMapBase
; OUTPUT: hl = base SRAM address of current map's 90 bytes
; wCemMapIndex must be set. SRAM must be enabled.
; ============================================================
PCemGetMapBase:
	ld hl, sProcCemeteryMaps
	ld a, [wBuffer + wCemMapIndex]
	and a
	ret z
	ld b, a
.loop
	ld de, CEMAP_SIZE
	add hl, de
	dec b
	jr nz, .loop
	ret

; ============================================================
; PCemGetCellHL
; INPUT: [wBuffer+wCemTryX/Y], [wBuffer+wCemMapIndex]
; OUTPUT: hl = SRAM address of that cell. SRAM must be enabled.
; ============================================================
PCemGetCellHL:
	call PCemGetMapBase
	ld a, [wBuffer + wCemTryY]
	and a
	jr z, .doneY
	ld b, a
.rowLoop
	ld de, CEMAP_WIDTH
	add hl, de
	dec b
	jr nz, .rowLoop
.doneY
	ld a, [wBuffer + wCemTryX]
	ld e, a
	ld d, 0
	add hl, de
	ret

; ============================================================
; PCemIsFloor: Z set if current cell is floor (block 14 or 54)
; INPUT: a = block value
; ============================================================
PCemIsFloor:
	cp CEMAP_FLOOR_1
	ret z
	cp CEMAP_FLOOR_2
	ret

; ============================================================
; PCemGenerateMaps
; Lazy generation: just resets per-run state. Each floor is
; generated on first entry (PCemFinalizeMap checks the ready bit).
; Called (via homecall) on Pallet Town entry.
; ============================================================
PCemGenerateMaps::
	; enable SRAM bank 0
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ASSERT BANK("Sprite Buffers") == 0
	xor a
	ld [rRAMB], a

	; clear ready bits (all 4 floors need fresh generation)
	; and per-run item-collected flags and used-prefab tracking
	xor a
	ld [sProcCemeteryReady], a
	ld [sProcCemeteryItemGot], a
	ld [sProcCemeteryUsedPrefabs], a
	ld [sProcCemeteryUsedPrefabs+1], a

	; close SRAM
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a

	; set wild battle budget for the entire cemetery run (10 + wBattleCount/5)
	ld a, [wBattleCount]
	ld b, 0
.cemBudgetDiv
	cp 5
	jr c, .cemBudgetDone
	sub 5
	inc b
	jr .cemBudgetDiv
.cemBudgetDone
	ld a, b
	add a, 10
	jr nc, .cemBudgetNoClamp
	ld a, 255
.cemBudgetNoClamp
	ld [wProcCemWildBudget], a
	; clear calmed events for fresh run
	ResetEvent EVENT_PC_CEM_BUDGET_ENDED
	ResetEvent EVENT_PC_CEM_CALMED_SHOWN
	; Clear the shared boss-beaten flag so a boss beaten in a PRIOR wild area
	; (cave/forest set the same EVENT_BEAT_PC_BOSS) doesn't make the cemetery
	; skip its own boss. Cave (PCPreloadCave) and forest (PFPreloadForest) both
	; do this in their preload; the cemetery was missing it.
	ResetEvent EVENT_BEAT_PC_BOSS
	; Roll the cemetery's OWN boss species + ghost move now. Previously the
	; cemetery boss read wRoguePokemon1 as if the CAVE's PCRollBoss (inside
	; PCPreloadCave) had populated it - true only under the old all-preload-at-
	; Pallet-Town flow. The per-type wild-area door preload runs only
	; PCemGenerateMaps, so the cemetery must roll its own boss, exactly like the
	; forest's PFRollBoss. Persisted to SRAM (see PCemRollBoss) because wild
	; battles clobber wRoguePokemon1 before the floor-4 engage.
	call PCemRollBoss
	ret

; ============================================================
; PCemRollBoss
; Rolls the cemetery boss species + its ghost move, persisting both to SRAM
; (and wRoguePokemon1). Mirrors the cave's PCRollBoss / forest's PFRollBoss so
; the cemetery is self-sufficient regardless of how it's reached. The species
; excludes the Gastly line (it becomes a GHOST *variant* of a non-ghost species,
; via func_ghost_variant.asm, applied to the battle enemy + gifted mon later).
; SRAM is closed on entry (PCemGenerateMaps closed it before this call); opened
; here only for the two stores. Clobbers a/bc/de/hl.
; ============================================================
PCemRollBoss:
	farcall PCGetBossLevel            ; sets wCurEnemyLevel before the species pick
	ld b, 60                          ; boss rarity bump (matches PCRollBoss)
	farcall PCRollMonClass            ; c = rarity class, biased by wBattleCount
	farcall Random_Pokemon_Selection  ; d = species
	ld a, d
	ld [wRoguePokemon1], a
	call PCemAvoidGhostBoss           ; reroll if it landed on Gastly/Haunter/Gengar
	; roll the ghost move -> b (0=LICK, 1=NIGHT_SHADE, 2=CONFUSE_RAY)
	ld c, 3
	call Rangerandom                  ; a = 0..2 (Rangerandom preserves bc)
	ld c, a
	ld b, 0
	ld hl, PCemGhostMoves
	add hl, bc
	ld a, [hl]
	ld b, a                           ; b = ghost move id (survives the SRAM writes)
	; persist species (wRoguePokemon1) + move (b) to SRAM
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	xor a
	ld [rRAMB], a
	ld a, [wRoguePokemon1]
	ld [sProcCemeteryBossSpecies], a
	ld a, b
	ld [sProcCemeteryBossMove], a
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ret

PCemGhostMoves:
	db LICK        ; 0
	db NIGHT_SHADE ; 1
	db CONFUSE_RAY ; 2

; ============================================================
; PCemRestoreBossSpecies
; Restores wRoguePokemon1 from the SRAM-persisted cemetery boss species. Wild
; battles clobber wRoguePokemon1 (random_pokemon_selection.asm) between the
; preload roll and the floor-4 engage, so the boss script calls this right
; before it reads the species (both the battle trigger and the join offer).
; farcall'd from ProceduralCemetery4.asm. Clobbers a/b.
; ============================================================
PCemRestoreBossSpecies::
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	xor a
	ld [rRAMB], a
	ld a, [sProcCemeteryBossSpecies]
	ld b, a
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ld a, b
	ld [wRoguePokemon1], a
	ret

; ============================================================
; PCemApplyGhostBoss
; Flags the mon at [de] as the cemetery ghost boss: sets the ghost-variant bit
; (func_ghost_variant.asm), forces MON_TYPE2 = GHOST, and writes the rolled ghost
; move (sProcCemeteryBossMove) into move slot 4 with its base PP. Takes the struct
; base in DE (not HL) so callers can reach it across a farcall (Bankswitch clobbers
; hl, preserves de - same reason IsGhostVariant takes de). Works for any mon struct
; (wEnemyMon / wPartyMonN / wBoxMonN - MON_MOVES/PP/CATCH_RATE/TYPE2 share offsets).
; Clobbers a/bc/hl (preserves de).
; ============================================================
PCemApplyGhostBoss::
	; ghost-variant flag = bit 0 of MON_CATCH_RATE
	ld hl, MON_CATCH_RATE
	add hl, de
	set 0, [hl]                   ; BIT_GHOST_VARIANT (func_ghost_variant.asm)
	; secondary type -> GHOST
	ld hl, MON_TYPE2
	add hl, de
	ld [hl], GHOST
	; read the rolled ghost move id from SRAM -> c
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	xor a
	ld [rRAMB], a
	ld a, [sProcCemeteryBossMove]
	ld c, a                       ; c = ghost move id
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	; write the move into slot 4 (MON_MOVES + 3)
	ld hl, MON_MOVES + 3
	add hl, de
	ld [hl], c
	; look up the move's base PP (Moves struct byte 5) via FarCopyData, a HOME
	; routine. It MUST be a HOME-based far read: this function runs in ROMX bank
	; 06, so doing the bank switch inline here (call SetCurBank / read / restore)
	; swaps the very bank the CPU is executing from out from under it - the next
	; instruction runs from BANK(Moves), landing in unrelated facility code
	; (PFacScanForBall) and crashing. FarCopyData does the switch from HOME where
	; it's safe. Destination is wBuffer: the plan flagged that as a landmine
	; because wBuffer is cemetery-GENERATION scratch, but PCemApplyGhostBoss only
	; ever runs from the battle hook / gift hook, never during generation, so a
	; transient write-then-immediate-read here is safe.
	push de                       ; save struct base
	ld a, c
	dec a
	ld hl, Moves
	ld bc, MOVE_LENGTH
	call AddNTimes                ; hl -> the move's 6-byte struct (Moves bank)
	ld de, wBuffer
	ld a, BANK(Moves)
	call FarCopyData              ; wBuffer[0..5] = move struct (HOME-safe switch)
	ld a, [wBuffer + 5]           ; base PP
	pop de                        ; restore struct base
	ld hl, MON_PP + 3
	add hl, de
	ld [hl], a
	ret

; ============================================================
; PCemMaybeApplyGhostBoss
; Enemy-side hook, farcall'd from the tail of LoadEnemyMonData (core.asm). If the
; enemy load that just happened is the cemetery boss battle (wProcCemBossBattle set
; by the boss trigger), turn the enemy into the ghost boss and clear the one-shot
; flag so floor-4 wild encounters are unaffected. No-op otherwise. Clobbers a/bc/hl.
; ============================================================
PCemMaybeApplyGhostBoss::
	ld a, [wProcCemBossBattle]
	and a
	ret z
	xor a
	ld [wProcCemBossBattle], a    ; one-shot: only the boss mon, not later wild loads
	ld de, wEnemyMon
	jp PCemApplyGhostBoss

; ============================================================
; PCemApplyGhostToGivenMon
; Given-mon hook, farcall'd from the join offer after GivePokemon. Locates the mon
; that was just added (last party slot, or last box slot if the party was full -
; wAddedToParty distinguishes) and applies the same ghost variant + move, so the
; gifted boss is identical to the one just fought and keeps it through box/trade/
; save (the flag lives in the struct's catch-rate byte, the move in a real slot).
; Clobbers a/bc/de/hl.
; ============================================================
PCemApplyGhostToGivenMon::
	ld a, [wAddedToParty]
	and a
	jr z, .box
	ld a, [wPartyCount]
	dec a
	ld hl, wPartyMon1
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes                ; hl -> the new party mon's struct
	jr .haveStruct
.box
	ld a, [wBoxCount]
	dec a
	ld hl, wBoxMon1
	ld bc, BOXMON_STRUCT_LENGTH
	call AddNTimes                ; hl -> the new box mon's struct
.haveStruct
	ld d, h
	ld e, l
	jp PCemApplyGhostBoss

; ============================================================
; PCemGenerateOneMap
; Generates one 90-byte map. SRAM must be enabled.
; ============================================================
PCemGenerateOneMap:
	; Debug selector (wProcCemDebugMode) can force a specific style; see
	; CEMETERY_DESIGN_LAPTOP.md Section 5i. 1/2/4 force procedural, 3
	; forces prefab, anything else uses the normal 25% prefab roll.
	ld a, [wProcCemDebugMode]
	cp 3
	jr z, .premade
	and a
	jr nz, .procedural        ; any nonzero mode except 3 -> procedural
	; mode 0 (normal): 50% premade, 50% procedural
	ld c, 2
	call Rangerandom
	and a
	jr nz, .procedural
.premade
	xor a
	ld [wBuffer + wCemIsProcedural], a
	call PCemCopyPremadeTemplate
	call PCemDecorateWalls
	call PCemPlaceAuthoredBall
	call PCemRollItem
	ret
.procedural
	ld a, 1
	ld [wBuffer + wCemIsProcedural], a
	call PCemCopyBaseTemplate
	call PCemFillGraves           ; place grave plots (or rows in debug mode 2)
	call PCemDecorateWalls        ; decorate wall/edge tiles
	call PCemRollItem             ; roll item now (needs wCemMapIndex, no floor needed)
	call PCemMarchPath            ; carve guaranteed path, save ball X/Y to SRAM
	ret

; PCemPrefabTable row layout: 5 bytes per entry (bank, lo, hi, ballX,
; ballY). Ball positions are hand-picked per prefab (a floor cell near
; the center, clear of the stair-patched cells) rather than found by a
; runtime random scan.
DEF PREFAB_ENTRY_SIZE EQU 5
DEF NUM_PREFABS       EQU 11

; ============================================================
; PCemCopyPremadeTemplate
; Picks a random prefab from an 11-entry pool (7 hand-authored "Drop"
; layouts + 4 Pokemon Tower floors) and copies it in. No longer indexed
; by floor: PCemPlaceStaircases patches col1/col9/(4,8) into whatever
; got blitted, and all 11 prefabs are verified (cell-level, against the
; actual cemetery.bst collision data) to connect entrance to exit under
; that patch on every one of the 4 floors - see
; CEMETERY_DESIGN_LAPTOP.md Section 5e.
; ============================================================
PCemCopyPremadeTemplate:
	; pick a random prefab from the pool that hasn't been used yet this
	; run (sProcCemeteryUsedPrefabs). At most 4 of the 11 are ever used
	; (one per floor), so this always finds a free one quickly; capped
	; defensively so a corrupted bitmask can't hang generation.
	ld d, 32                    ; retry budget
.rollPrefab
	ld c, NUM_PREFABS
	call Rangerandom
	ld [wBuffer + wCemPrefabIndex], a
	call PCemPrefabBitMaskHL    ; hl -> tracking byte, b = bitmask
	ld a, [hl]
	and b
	jr z, .prefabFree           ; bit clear = not used yet
	dec d
	jr nz, .rollPrefab
.prefabFree
	; mark it used
	ld a, [wBuffer + wCemPrefabIndex]
	call PCemPrefabBitMaskHL
	ld a, [hl]
	or b
	ld [hl], a

	call PCemPrefabRowHL   ; hl -> this prefab's table row (clobbers de - see below)
	ld a, [hli]  ; a = bank
	ld c, [hl]
	inc hl
	ld b, [hl]   ; bc = source address (lo in c, hi in b)
	; PCemGetMapBase also clobbers a/b/de, so stash bank+source on the
	; stack before computing dest. (Bug fixed 2026-07-16: dest used to be
	; computed into de FIRST, then PCemPrefabRowHL's own de-clobbering
	; loop stomped it for every prefab index except 0 - only DropA ever
	; copied to the right place, and everything else silently corrupted
	; RAMG via a stray write into $0000-$1FFF, taking SRAM down with it.)
	push af      ; save bank
	push bc      ; save source address
	call PCemGetMapBase   ; hl = dest base
	ld d, h
	ld e, l      ; de = dest
	pop hl       ; hl = source address
	pop af       ; a = bank
	ld bc, CEMAP_SIZE
	jp FarCopyData2

; INPUT: a = prefab index (0-10)
; OUTPUT: hl -> byte in sProcCemeteryUsedPrefabs holding this index's bit,
;         b = bitmask (1 << local bit within that byte). Clobbers a, c.
PCemPrefabBitMaskHL:
	ld hl, sProcCemeteryUsedPrefabs
	cp 8
	jr c, .lowByte
	sub 8
	inc hl
.lowByte
	ld c, a
	ld b, 1
	inc c
.shiftLoop
	dec c
	jr z, .shifted
	sla b
	jr .shiftLoop
.shifted
	ret

; hl -> PCemPrefabTable[wCemPrefabIndex * PREFAB_ENTRY_SIZE]
PCemPrefabRowHL:
	ld hl, PCemPrefabTable
	ld a, [wBuffer + wCemPrefabIndex]
	and a
	ret z
	ld b, a
	ld de, PREFAB_ENTRY_SIZE
.rowLoop
	add hl, de
	dec b
	jr nz, .rowLoop
	ret

PCemPrefabTable:
	db BANK(PCemDropA_Blocks),   LOW(PCemDropA_Blocks),   HIGH(PCemDropA_Blocks),   5, 4
	db BANK(PCemDropB_Blocks),   LOW(PCemDropB_Blocks),   HIGH(PCemDropB_Blocks),   5, 2
	db BANK(PCemDropC_Blocks),   LOW(PCemDropC_Blocks),   HIGH(PCemDropC_Blocks),   5, 4
	db BANK(PCemDropD_Blocks),   LOW(PCemDropD_Blocks),   HIGH(PCemDropD_Blocks),   4, 3
	db BANK(PCemDropE_Blocks),   LOW(PCemDropE_Blocks),   HIGH(PCemDropE_Blocks),   5, 4
	db BANK(PCemDropF_Blocks),   LOW(PCemDropF_Blocks),   HIGH(PCemDropF_Blocks),   3, 5
	db BANK(PCemDropG_Blocks),   LOW(PCemDropG_Blocks),   HIGH(PCemDropG_Blocks),   5, 3
	db BANK(PCemTower3F_Blocks), LOW(PCemTower3F_Blocks), HIGH(PCemTower3F_Blocks), 5, 3
	db BANK(PCemTower4F_Blocks), LOW(PCemTower4F_Blocks), HIGH(PCemTower4F_Blocks), 3, 4
	db BANK(PCemTower5F_Blocks), LOW(PCemTower5F_Blocks), HIGH(PCemTower5F_Blocks), 5, 4
	db BANK(PCemTower6F_Blocks), LOW(PCemTower6F_Blocks), HIGH(PCemTower6F_Blocks), 5, 3

PCemDropA_Blocks:   INCBIN "maps/ProceduralCemeteryDropA.blk"
PCemDropB_Blocks:   INCBIN "maps/ProceduralCemeteryDropB.blk"
PCemDropC_Blocks:   INCBIN "maps/ProceduralCemeteryDropC.blk"
PCemDropD_Blocks:   INCBIN "maps/ProceduralCemeteryDropD.blk"
PCemDropE_Blocks:   INCBIN "maps/ProceduralCemeteryDropE.blk"
PCemDropF_Blocks:   INCBIN "maps/ProceduralCemeteryDropF.blk"
PCemDropG_Blocks:   INCBIN "maps/ProceduralCemeteryDropG.blk"
PCemTower5F_Blocks: INCBIN "maps/PokemonTower5F.blk"
PCemTower4F_Blocks: INCBIN "maps/PokemonTower4F.blk"
PCemTower3F_Blocks: INCBIN "maps/PokemonTower3F.blk"
PCemTower6F_Blocks: INCBIN "maps/PokemonTower6F.blk"

; ============================================================
; PCemCopyBaseTemplate
; All 4 floors share one base template. Per-floor geometry (entry/exit
; stair blocks, south-exit block) is patched in post-blit by
; PCemPlaceStaircases from PCemFloorGeometry - see Section 5g of
; CEMETERY_DESIGN_LAPTOP.md. The old floor-4 template
; (ProceduralCemetery2.blk) differed from this one only at the two
; blocks the patch overwrites anyway; everything else was cosmetic
; wall-art variation.
; ============================================================
PCemCopyBaseTemplate:
	call PCemGetMapBase
	ld d, h
	ld e, l
	ld a, BANK(PCemBaseTemplate1)
	ld hl, PCemBaseTemplate1
	ld bc, CEMAP_SIZE
	jp FarCopyData2

PCemBaseTemplate1: INCBIN "maps/ProceduralCemetery1.blk"

; ============================================================
; PCemScatterTombstones
; Replaces CEMAP_NUM_TOMBSTONES floor cells with tombstones.
; Skips cells near warp staircase positions.
; ============================================================
PCemScatterTombstones:
	ld b, CEMAP_NUM_TOMBSTONES  ; load number of tombstones
.scatter
	push bc ; preserve bc
	ld c, CEMAP_WIDTH           ; load the width of map to get a random number with a maximum of the entire width
	call Rangerandom
	ld [wBuffer + wCemTryX], a  ; write x coordinate to try location
	ld c, CEMAP_HEIGHT          ; load the height of map to get a random number with a maximum of the entire height
	call Rangerandom
	ld [wBuffer + wCemTryY], a  ; write y coordinate to try location
	call PCemInWarpZone
	jr nz, .skip
	call PCemGetCellHL
	ld a, [hl]
	call PCemIsFloor
	jr nz, .skip
	; pick random tombstone block
	push hl
	ld c, NUM_CEMDECO_FLOOR     ; number of potential tombstone tiles
	call Rangerandom
	ld hl, PCemFloorTombstoneTable
	ld e, a
	ld d, 0
	add hl, de                  ; add offset to find tile location
	ld a, [hl]                  ; load tile
	pop hl
	ld [hl], a                  ; save tile to x,y location
.skip
	pop bc                      ; restore bc
	dec b                       ; decrease count to end loop
	jr nz, .scatter ; falls through when hits CEMAP_NUM_TOMBSTONES
	ret

; Wall tiles that carving must never replace with floor.
; These define the room structure and decoration anchor points.
PCemProtectedWallTable:
	db 6, 7, 10, 28, 29, 30, 32, 57
DEF NUM_PROTECTED_WALLS EQU 8

; PCemIsProtectedWall: a = cell value. Z if protected, NZ if carveable.
PCemIsProtectedWall:
	ld hl, PCemProtectedWallTable
	ld b, NUM_PROTECTED_WALLS
.loop
	cp [hl]
	ret z              ; Z = in protected list, do not carve
	inc hl
	dec b
	jr nz, .loop
	or 1               ; NZ = not protected, safe to carve
	ret

PCemFloorTombstoneTable:
	db 76, 78, 79, 81, 82, 23, 19, 77, 80, 101, 102, 103, 104, 105, 106
DEF NUM_CEMDECO_FLOOR EQU 15

; ============================================================
; PCemInWarpZone
; NZ if (TryX,TryY) is in a margin zone around any warp staircase.
; Z if safe to place tombstone.
; Staircase margin cols 0-2 (left) and cols 7-9 (right), rows 3-5.
; South staircase (map 3 only): cols 3-5, rows 7-8.
; ============================================================
PCemInWarpZone:
	ld a, [wBuffer + wCemTryX]
	ld b, a
	ld a, [wBuffer + wCemTryY]
	ld c, a
	; left staircase zone: cols 0-2, rows 3-5
	ld a, b
	cp 3
	jr nc, .notLeft
	ld a, c
	cp 3
	jr c, .notLeft
	cp 6
	jr c, .inZone
.notLeft
	; right staircase zone: cols 7-9, rows 3-5
	ld a, b
	cp 7
	jr c, .notRight
	ld a, c
	cp 3
	jr c, .notRight
	cp 6
	jr c, .inZone
.notRight
	; south staircase (map 3): cols 3-5, rows 7-8
	ld a, [wBuffer + wCemMapIndex]
	cp 3
	jr nz, .safe
	ld a, b
	cp 3
	jr c, .safe
	cp 6
	jr nc, .safe
	ld a, c
	cp 7
	jr c, .safe
.inZone
	or 1        ; NZ = in zone
	ret
.safe
	xor a       ; Z = safe
	ret

; ============================================================
; PCemPlaceAuthoredBall
; Reads this prefab's hand-picked ballX/ballY (PCemPrefabTable, offsets
; 3-4 of the row) and saves it as the ball position. Replaces the old
; 100-try random floor scan now that every prefab's ball spot is
; authored - see CEMETERY_DESIGN_LAPTOP.md Section 5e.
; ============================================================
PCemPlaceAuthoredBall:
	call PCemPrefabRowHL
	ld de, 3
	add hl, de
	ld a, [hli]
	ld [wBuffer + wCemTryX], a
	ld a, [hl]
	ld [wBuffer + wCemTryY], a
	call PCemSaveBallPos
	ret

; ============================================================
; PCemDecorateWalls
; Replaces eligible wall/feature tiles with decorative variants.
; SRAM must be enabled. Runs on both premade and procedural maps.
; Each eligible tile has a 1-in-4 chance of being decorated.
; ============================================================
PCemDecorateWalls:
	call PCemGetMapBase     ; hl = SRAM base
	ld b, CEMAP_SIZE        ; 90 cells
.decoScan
	push bc
	push hl
	ld a, [hl]
	call PCemDecoLookup     ; c = variant count, de = variant table; Z if no match
	jr z, .decoSkip
	; 25% chance
	push de
	push bc
	ld c, 4
	call Rangerandom
	pop bc
	pop de
	and a
	jr nz, .decoSkip
	; pick random variant: c = count, e = base offset
	push de                 ; save de (e=base offset, d=0)
	call Rangerandom        ; 0..c-1
	pop de                  ; restore base offset into e
	add a, e                ; final index = base_offset + random
	ld hl, PCemWallDecoVariants
	ld e, a
	ld d, 0
	add hl, de              ; hl = PCemWallDecoVariants + final_index
	ld a, [hl]              ; selected variant block
	pop hl                  ; restore cell address
	ld [hl], a
	jr .decoNext
.decoSkip
	pop hl
.decoNext
	inc hl
	pop bc
	dec b
	jr nz, .decoScan
	ret

; PCemDecoLookup: given block value in a, return Z if no deco match.
; If match (NZ): c = variant count, e = base offset into PCemWallDecoVariants, d=0.
; Clobbers a,b,c,d,e,hl. Preserves incoming a in d during search.
PCemDecoLookup:
	ld hl, PCemWallDecoTable
	ld d, a                 ; d = incoming block value (preserved across table scan)
.lookupLoop
	ld a, [hli]             ; a = source block from table
	cp $ff                  ; end of table? (checks TABLE byte, not incoming value)
	jr z, .noMatch
	ld b, a                 ; b = source block
	ld c, [hl]              ; c = variant count
	inc hl
	ld e, [hl]              ; e = base offset into PCemWallDecoVariants
	inc hl
	ld a, d                 ; restore incoming block value
	cp b                    ; match?
	jr z, .matched
	jr .lookupLoop
.noMatch
	xor a                   ; Z = no match
	ret
.matched
	ld d, 0                 ; de = (0, base_offset)
	or 1                    ; NZ = matched
	ret

; Table: source_block, variant_count, offset_into_PCemWallDecoVariants
PCemWallDecoTable:
	db 29, 3,  0   ; → 98, 86, 85
	db 28, 1,  3   ; → 83
	db 30, 1,  4   ; → 84
	db 32, 3,  5   ; → 95, 89, 88
	db  7, 1,  8   ; → 97
	db  6, 3,  9   ; → 99, 100, 91
	db 10, 1, 12   ; → 96
	db 57, 3, 13   ; → 90, 94, 87
	db $ff

PCemWallDecoVariants:
	db 98, 86, 85   ; offsets 0-2  (for block 29)
	db 83           ; offset  3    (for block 28)
	db 84           ; offset  4    (for block 30)
	db 95, 89, 88   ; offsets 5-7  (for block 32)
	db 97           ; offset  8    (for block 7)
	db 99, 100, 91  ; offsets 9-11 (for block 6)
	db 96           ; offset  12   (for block 10)
	db 90, 94, 87   ; offsets 13-15 (for block 57)

; 7 bytes per floor: col1_block, col9_block, south(4,8)_block, entX, entY, exX, exY.
; entX/Y/exX/Y are unused until PCemMarchPath replaces the carve algorithms
; (CEMETERY_DESIGN_LAPTOP.md Section 5g) but are defined now so this table
; only needs to be written once.
PCemFloorGeometry:
	db 17, 18, 28,  2, 4,  8, 4   ; floor 1: W entry, E exit
	db 21, 22, 28,  8, 4,  2, 4   ; floor 2: E entry, W exit
	db 17, 18, 28,  2, 4,  8, 4   ; floor 3: W entry, E exit
	db 57, 22, 48,  8, 4,  4, 7   ; floor 4: E entry, S exit, W wall
DEF CEMGEO_SIZE EQU 7

; ============================================================
; PCemPlaceStaircases
; Writes entrance/exit/south-exit blocks into wOverworldMap after blit,
; sourced from PCemFloorGeometry. Deterministic from map index — no
; SRAM needed. Applies to all maps (procedural and premade) — wBuffer
; is unreliable across map loads so we can't check wCemIsProcedural
; here. All base/premade maps share the same floor geometry (row 4
; cols 1/9, block (4,8)) so the patch is safe for all of them.
; ============================================================
PCemPlaceStaircases:
	; hl -> PCemFloorGeometry[mapIndex * CEMGEO_SIZE]
	ld hl, PCemFloorGeometry
	ld a, [wBuffer + wCemMapIndex]
	and a
	jr z, .gotRow
	ld de, CEMGEO_SIZE
.addRow
	add hl, de
	dec a
	jr nz, .addRow
.gotRow

	ld a, [hli]                ; col1 block
	ld b, a
	ld a, [hli]                ; col9 block
	ld c, a
	ld a, [hl]                 ; south-exit (4,8) block
	ld e, a

	ld hl, wOverworldMap + CEMAP_BASE + 4 * CEMAP_STRIDE + 1
	ld [hl], b
	ld hl, wOverworldMap + CEMAP_BASE + 4 * CEMAP_STRIDE + 9
	ld [hl], c
	ld hl, wOverworldMap + CEMAP_BASE + 8 * CEMAP_STRIDE + 4
	ld [hl], e
	ret

; ============================================================
; Grave placement. Runs after the base template is copied and before
; the path march, so the march carves floor back over any graves in
; its way (guaranteeing connectivity). Everything here only ever
; writes onto floor cells (PCemWriteGrave checks), so the octagon
; frame is never touched. See CEMETERY_DESIGN_LAPTOP.md Section 6a.
; SRAM must be enabled.
; ============================================================

; Grave blocks: mostly solid (82) with a few half-graves for texture.
PCemGraveBlockTable:
	db 82, 82, 82, 82, 76, 79, 80, 81
DEF NUM_GRAVE_BLOCKS EQU 8

; Four grave plots: x0, x1, y0, y1. All cells lie inside the octagon.
PCemPlotTable:
	db 3, 4, 2, 3
	db 6, 7, 2, 3
	db 3, 4, 5, 6
	db 6, 7, 5, 6
DEF NUM_PLOTS EQU 4

DEF wCemPX0 EQU 15
DEF wCemPX1 EQU 16
DEF wCemPY0 EQU 17
DEF wCemPY1 EQU 18

; PCemFillGraves: default is a DENSE fill (every octagon cell becomes a
; grave; the march then carves the single winding trail through it, so the
; room reads as a packed graveyard with one clear path rather than an open
; field). Debug mode 2 instead uses the sparse 4-plot layout for
; comparison. See CEMETERY_DESIGN_LAPTOP.md Section 6a.
PCemFillGraves:
	ld a, [wProcCemDebugMode]
	cp 2
	jp z, PCemPlaceGravePlots
	; fall through to the dense fill

; PCemFillAll: grave every interior row 1-7 across the octagon
; (PCemWriteGrave clips to floor cells, so no per-row extent is needed).
PCemFillAll:
	ld a, 1
	ld [wBuffer + wCemTryY], a
.rowLoop
	call PCemFillOneRow
	ld a, [wBuffer + wCemTryY]
	inc a
	ld [wBuffer + wCemTryY], a
	cp 8
	jr nz, .rowLoop
	ret

; Write a random grave block at the cursor, but only onto a floor cell.
PCemWriteGrave:
	call PCemGetCellHL
	ld a, [hl]
	call PCemIsFloor
	ret nz
	push hl
	ld c, NUM_GRAVE_BLOCKS
	call Rangerandom
	ld hl, PCemGraveBlockTable
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hl]
	pop hl
	ld [hl], a
	ret

; PCemPlaceGravePlots: fill each of the 4 plots with ~6/7 probability.
PCemPlaceGravePlots:
	ld hl, PCemPlotTable
	ld b, NUM_PLOTS
.plotLoop
	push bc
	ld a, [hli]
	ld [wBuffer + wCemPX0], a
	ld a, [hli]
	ld [wBuffer + wCemPX1], a
	ld a, [hli]
	ld [wBuffer + wCemPY0], a
	ld a, [hli]
	ld [wBuffer + wCemPY1], a
	push hl
	ld c, 7
	call Rangerandom
	and a
	call nz, PCemFillOnePlot
	pop hl
	pop bc
	dec b
	jr nz, .plotLoop
	ret

; Fill the rectangle [PX0..PX1] x [PY0..PY1] with graves (floor cells only).
PCemFillOnePlot:
	ld a, [wBuffer + wCemPY0]
	ld [wBuffer + wCemTryY], a
.row
	ld a, [wBuffer + wCemPX0]
	ld [wBuffer + wCemTryX], a
.col
	call PCemWriteGrave
	ld a, [wBuffer + wCemTryX]
	ld hl, wBuffer + wCemPX1
	cp [hl]
	jr nc, .rowEnd
	inc a
	ld [wBuffer + wCemTryX], a
	jr .col
.rowEnd
	ld a, [wBuffer + wCemTryY]
	ld hl, wBuffer + wCemPY1
	cp [hl]
	ret nc
	inc a
	ld [wBuffer + wCemTryY], a
	jr .row

PCemFillOneRow:
	ld a, 2
	ld [wBuffer + wCemTryX], a
.col
	call PCemWriteGrave
	ld a, [wBuffer + wCemTryX]
	cp 8
	ret z
	inc a
	ld [wBuffer + wCemTryX], a
	jr .col

; wBuffer scratch used by the march (offsets 8-14). Slots 8/9 were
; wCemStepCount/wCemItemDone under the old carve algorithms.
DEF wCemBallCol    EQU 8   ; column at which to drop the item ball (4-7)
DEF wCemBallSaved  EQU 9   ; 1 once the ball position has been captured
DEF wCemStepDir    EQU 10  ; +1 or -1: X march direction toward exit
DEF wCemExtLo      EQU 11  ; current column's min walkable row
DEF wCemExtHi      EQU 12  ; current column's max walkable row
DEF wCemWanderDir  EQU 13  ; +1 or -1: vertical wander direction this column
DEF wCemWanderCnt  EQU 14  ; remaining vertical wander steps this column

; Per-column floor extent (minY, maxY), indexed by (col - 2). Cols 2-8.
; This is the octagon from CEMETERY_DESIGN_LAPTOP.md Section 2; it is the
; single source of truth for where the path may go.
PCemColExtent:
	db 3, 5   ; col 2
	db 2, 6   ; col 3
	db 1, 7   ; col 4
	db 1, 7   ; col 5
	db 1, 7   ; col 6
	db 2, 6   ; col 7
	db 3, 5   ; col 8

; hl -> PCemFloorGeometry row for the current floor (wCemMapIndex).
PCemGeometryRowHL:
	ld hl, PCemFloorGeometry
	ld a, [wBuffer + wCemMapIndex]
	and a
	ret z
	ld de, CEMGEO_SIZE
.rowLoop
	add hl, de
	dec a
	jr nz, .rowLoop
	ret

; Load entX/entY/exX/exY (geometry offsets 3-6) into wBuffer scratch.
PCemLoadGeometry:
	call PCemGeometryRowHL
	inc hl
	inc hl
	inc hl                     ; skip col1/col9/south blocks
	ld a, [hli]
	ld [wBuffer + wCemEntX], a
	ld a, [hli]
	ld [wBuffer + wCemEntY], a
	ld a, [hli]
	ld [wBuffer + wCemExX], a
	ld a, [hl]
	ld [wBuffer + wCemExY], a
	ret

; Carve the current cursor cell (wCemTryX/Y) to floor. Clobbers a,b,d,e,hl.
PCemWriteFloor:
	call PCemGetCellHL
	ld [hl], CEMAP_FLOOR_1
	ret

; Load the current cursor column's extent into wCemExtLo/Hi.
PCemLoadColExtent:
	ld a, [wBuffer + wCemTryX]
	sub 2
	add a, a                   ; (col-2)*2
	ld e, a
	ld d, 0
	ld hl, PCemColExtent
	add hl, de
	ld a, [hli]
	ld [wBuffer + wCemExtLo], a
	ld a, [hl]
	ld [wBuffer + wCemExtHi], a
	ret

; ============================================================
; PCemMarchPath
; Carves a guaranteed-connected path from the inner entrance to the
; inner exit. Marches one column at a time toward the exit (monotonic
; in X), wandering 0-2 cells vertically within each column's extent.
; When a narrower column is entered, Y is first clamped into the new
; extent, carving the cells passed through in the OLD column so the
; path stays continuous and never leaves the octagon. No connectivity
; check or cleanup is ever needed. See Section 5a.
; SRAM must be enabled.
; ============================================================
PCemMarchPath:
	call PCemLoadGeometry
	; roll ball column 4-7 (subset of columns every floor's march visits)
	ld c, 4
	call Rangerandom
	add a, 4
	ld [wBuffer + wCemBallCol], a
	xor a
	ld [wBuffer + wCemBallSaved], a
	; step direction: +1 if exX > entX, else -1 (never equal)
	ld a, [wBuffer + wCemEntX]
	ld b, a
	ld a, [wBuffer + wCemExX]
	cp b
	jr nc, .stepPos
	ld a, -1
	jr .storeStep
.stepPos
	ld a, 1
.storeStep
	ld [wBuffer + wCemStepDir], a
	; cursor = entrance, carve it
	ld a, [wBuffer + wCemEntX]
	ld [wBuffer + wCemTryX], a
	ld a, [wBuffer + wCemEntY]
	ld [wBuffer + wCemTryY], a
	call PCemWriteFloor
.marchLoop
	; done marching horizontally once cursor reaches the exit column
	ld a, [wBuffer + wCemTryX]
	ld hl, wBuffer + wCemExX
	cp [hl]
	jr z, .vertical
	; advance one column toward the exit
	ld a, [wBuffer + wCemStepDir]
	ld b, a
	ld a, [wBuffer + wCemTryX]
	add a, b
	ld [wBuffer + wCemTryX], a
	call PCemLoadColExtent
	call PCemClampYIntoExtent  ; carve old column while clamping Y
	call PCemWriteFloor        ; carve the new column cell
	call PCemWander            ; 0-2 vertical steps within the extent
	; capture the ball position the first time we reach the ball column
	ld a, [wBuffer + wCemTryX]
	ld hl, wBuffer + wCemBallCol
	cp [hl]
	jr nz, .marchLoop
	ld a, [wBuffer + wCemBallSaved]
	and a
	jr nz, .marchLoop
	call PCemSaveBallPos
	ld a, 1
	ld [wBuffer + wCemBallSaved], a
	jr .marchLoop
.vertical
	; run straight to the exit row, carving (exX, y)
	ld a, [wBuffer + wCemTryY]
	ld hl, wBuffer + wCemExY
	cp [hl]
	jr z, .afterVertical
	jr c, .vIncY
	ld a, [wBuffer + wCemTryY]
	dec a
	ld [wBuffer + wCemTryY], a
	call PCemWriteFloor
	jr .vertical
.vIncY
	ld a, [wBuffer + wCemTryY]
	inc a
	ld [wBuffer + wCemTryY], a
	call PCemWriteFloor
	jr .vertical
.afterVertical
	; fallback ball position if the ball column was somehow never hit
	ld a, [wBuffer + wCemBallSaved]
	and a
	ret nz
	call PCemSaveBallPos
	ret

; Clamp cursor Y into [wCemExtLo, wCemExtHi], carving each cell passed
; through in the OLD column (curX - stepDir). Only one of the two loops
; ever runs. Cursor X is restored to the new column on exit.
PCemClampYIntoExtent:
	ld a, [wBuffer + wCemTryX]  ; remember new column
	push af
	ld a, [wBuffer + wCemStepDir]
	ld b, a
	ld a, [wBuffer + wCemTryX]
	sub b
	ld [wBuffer + wCemTryX], a  ; cursor X = old column
.clampDown
	ld a, [wBuffer + wCemTryY]
	ld hl, wBuffer + wCemExtLo
	cp [hl]
	jr nc, .clampUp            ; curY >= lo
	inc a
	ld [wBuffer + wCemTryY], a
	call PCemWriteFloor
	jr .clampDown
.clampUp
	ld a, [wBuffer + wCemTryY]
	ld hl, wBuffer + wCemExtHi
	cp [hl]
	jr z, .clampDone
	jr c, .clampDone          ; curY <= hi
	dec a
	ld [wBuffer + wCemTryY], a
	call PCemWriteFloor
	jr .clampUp
.clampDone
	pop af
	ld [wBuffer + wCemTryX], a  ; restore cursor X = new column
	ret

; Wander cursor Y 0-2 cells in one random direction, staying within
; [wCemExtLo, wCemExtHi], carving each cell. Stops early at an extent edge.
PCemWander:
	ld c, 3
	call Rangerandom           ; 0-2 steps
	ld [wBuffer + wCemWanderCnt], a
	and a
	ret z
	ld c, 2
	call Rangerandom           ; 0 = up, 1 = down
	and a
	ld b, 1
	jr nz, .haveDir
	ld b, -1
.haveDir
	ld a, b
	ld [wBuffer + wCemWanderDir], a
.wLoop
	ld a, [wBuffer + wCemWanderCnt]
	and a
	ret z
	ld a, [wBuffer + wCemTryY]
	ld b, a
	ld a, [wBuffer + wCemWanderDir]
	add a, b                   ; nextY = curY + dir
	ld hl, wBuffer + wCemExtLo
	cp [hl]
	ret c                      ; nextY < lo, stop
	ld hl, wBuffer + wCemExtHi
	cp [hl]
	jr z, .wOK
	ret nc                     ; nextY > hi, stop
.wOK
	ld [wBuffer + wCemTryY], a  ; commit nextY (a still holds it)
	call PCemWriteFloor
	ld a, [wBuffer + wCemWanderCnt]
	dec a
	ld [wBuffer + wCemWanderCnt], a
	jr .wLoop

PCemSaveBallPos:
	ld hl, sProcCemeteryBallX
	ld a, [wBuffer + wCemMapIndex]
	ld e, a
	ld d, 0
	add hl, de
	ld a, [wBuffer + wCemTryX]
	ld [hl], a
	ld hl, sProcCemeteryBallY
	add hl, de
	ld a, [wBuffer + wCemTryY]
	ld [hl], a
	ret

; ============================================================
; PCemRollItem: rolls a random item for this map's pokeball.
; Stores in sProcCemeteryItem[mapIndex].
; ============================================================
PCemRollItem:
	ld c, 4
	call Rangerandom
	ld [wRogueDoorSelection], a
	farcall Random_Item_Selection   ; result in wRogueItem
	; Random_Item_Selection can roll a TM, which routes through HasTMHM
	; (custom_functions/tm_bag.asm). HasTMHM ends by DISABLING SRAM
	; (xor a / ld [rRAMG],a) - so on a TM roll it leaves SRAM off, and every
	; remaining SRAM write in generation (the item byte below, PCemMarchPath's
	; carved path + ball pos, PCemFinalizeMap's blit source + ready bit) would
	; hit open bus -> blocky map that "self-heals" on re-entry. Re-assert SRAM
	; enable here. rBMODE/rRAMB are untouched by HasTMHM, only rRAMG needs it.
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, [wRogueItem]
	ld hl, sProcCemeteryItem
	ld b, a
	ld a, [wBuffer + wCemMapIndex]
	ld e, a
	ld d, 0
	add hl, de
	ld a, b
	ld [hl], a
	ret

DEF wCemGhostRetry EQU 20   ; scratch retry counter for PCemAvoidGhostBoss

; ============================================================
; PCemAvoidGhostBoss
; Cemetery-only exclusion: the cemetery's boss must never be Gastly,
; Haunter, or Gengar. Rerolls wRoguePokemon1 (using the same class-roll
; PCRollBoss itself uses) if the shared cave/cemetery boss roll landed
; on one of them. Called once, only for floor 4 (the boss floor), from
; PCemFinalizeMap's lazy-generation branch.
; ============================================================
PCemAvoidGhostBoss:
	ld a, 20
	ld [wBuffer + wCemGhostRetry], a
.checkLoop
	ld a, [wRoguePokemon1]
	cp GASTLY
	jr z, .reroll
	cp HAUNTER
	jr z, .reroll
	cp GENGAR
	jr z, .reroll
	ret                          ; not a banned species, done
.reroll
	ld a, [wBuffer + wCemGhostRetry]
	dec a
	ld [wBuffer + wCemGhostRetry], a
	ret z                        ; retry budget exhausted, accept whatever we have
	ld b, 60                     ; same boss rarity bump PCRollBoss uses
	farcall PCRollMonClass       ; c = rarity class, biased by wBattleCount
	farcall Random_Pokemon_Selection ; -> d = species
	ld a, d
	ld [wRoguePokemon1], a
	jr .checkLoop

; ============================================================
; PCemFinalizeMap
; Called when loading a PROCEDURAL_CEMETERY_N map.
; Blits 90-byte map from SRAM into wOverworldMap, patches pokeball
; sprite position, and loads item into wRogueItem.
; ============================================================
PCemFinalizeMap::
	; enable SRAM bank 0
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	xor a
	ld [rRAMB], a

	; which map? 0-3 (not consecutive IDs, must use explicit lookup)
	call PCemMapToIndex
	ld [wBuffer + wCemMapIndex], a

	; Lazy generation: generate this floor now if its ready bit is not set.
	; Bit N of sProcCemeteryReady = floor N has been generated.
	; Spreads cost across floor entries instead of all at Pallet Town entry.
	; Compute mask = 1 << mapIndex using B as shift count (not bitwise AND).
	ld c, a                    ; c = mapIndex (0-3)
	ld b, 1                    ; b = mask, start at bit 0
	ld a, c
	and a                      ; test if mapIndex == 0 (sets Z if c==0)
	jr z, .cemGotMask
.cemShiftMask
	sla b                      ; b <<= 1
	dec c
	jr nz, .cemShiftMask
.cemGotMask                    ; b = (1 << mapIndex)
	ld a, [sProcCemeteryReady]
	and b
	jr nz, .cemAlreadyReady    ; bit set = already generated
	; generate this floor now
	call PCemGenerateOneMap
	; Floor 4 is the boss floor. The boss species is no longer adjusted here:
	; it is rolled (Gastly line already excluded) and persisted to SRAM at
	; preload by PCemRollBoss, and restored into wRoguePokemon1 by
	; PCemRestoreBossSpecies right before the battle/offer (wild battles clobber
	; wRoguePokemon1 in between). Nothing floor-4-specific to do at generation.
	; set ready bit (recompute mask — PCemGenerateOneMap may clobber b/c)
	ld a, [wBuffer + wCemMapIndex]
	ld c, a
	ld b, 1
	and c                      ; test if mapIndex == 0
	jr z, .cemSetBit
.cemSetShift
	sla b
	dec c
	jr nz, .cemSetShift
.cemSetBit
	ld a, [sProcCemeteryReady]
	or b
	ld [sProcCemeteryReady], a
.cemAlreadyReady

	; get SRAM source for this map
	call PCemGetMapBase
	; blit row by row (10 bytes/row, skip 6-byte border gap on dest)
	ld de, wOverworldMap + CEMAP_BASE
	ld b, CEMAP_HEIGHT
.blitRowLoop
	push bc
	ld c, CEMAP_WIDTH
.blitColLoop
	ld a, [hli]
	ld [de], a
	inc de
	dec c
	jr nz, .blitColLoop
	ld a, e
	add a, CEMAP_STRIDE - CEMAP_WIDTH
	ld e, a
	jr nc, .blitNoCarry
	inc d
.blitNoCarry
	pop bc
	dec b
	jr nz, .blitRowLoop

	; place staircase tiles (deterministic from map index, no SRAM needed)
	call PCemPlaceStaircases

	; load item into wRogueItem for pickup
	ld hl, sProcCemeteryItem
	ld a, [wBuffer + wCemMapIndex]
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hl]
	ld [wRogueItem], a

	; close SRAM before patching WRAM sprite state
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a

	; re-enable SRAM to read ball position
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	xor a
	ld [rRAMB], a

	ld hl, sProcCemeteryBallX
	ld a, [wBuffer + wCemMapIndex]
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hl]
	ld b, a             ; b = ball block X
	ld hl, sProcCemeteryBallY
	add hl, de
	ld a, [hl]
	ld c, a             ; c = ball block Y

	; close SRAM
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ld [rRAMG], a

	; patch pokeball sprite (slot 1 = wSprite01StateData2MapY)
	; formula: block * 2 + 4 (confirmed same origin offset as cave pokeballs)
	ld hl, wSprite01StateData2MapY
	ld a, c
	add a, a
	add a, 4
	ld [hli], a          ; MapY
	ld a, b
	add a, a
	add a, 4
	ld [hl], a           ; MapX
	ret

; ============================================================
; PCemRefreshBall
; Shows or hides the slot-1 pokeball for the current cemetery floor,
; based on sProcCemeteryItemGot. Called from each of the 4 cemetery
; scripts on fresh EVENT_ENTER_ROOM entry.
;
; PCemFinalizeMap places the ball's sprite position on every load and
; already computes the correct show/hide state, but EVENT_ENTER_ROOM
; is reset on every warp (home/overworld.asm's WarpFound2), so the map
; scripts also run their own "fresh entry" setup after LoadMapData -
; and were unconditionally calling ShowObject there, undoing
; FinalizeMap's hide every time. This is the fix: the scripts farcall
; here instead, which makes the same show/hide decision FinalizeMap
; would have made. See CEMETERY_DESIGN_LAPTOP.md Section 4b.
; ============================================================
PCemRefreshBall::
	; enable SRAM to read the collected bitfield
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	xor a
	ld [rRAMB], a

	call PCemMapToIndex        ; a = floor index 0-3
	ld b, a
	; compute bit mask = 1 << floorIndex
	ld c, 1
	and a
	jr z, .gotMask
.shiftMask
	sla c
	dec a
	jr nz, .shiftMask
.gotMask
	ld a, [sProcCemeteryItemGot]
	and c                      ; Z if this floor's item not yet collected

	; close SRAM before the predef calls
	push af
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ld [rRAMG], a
	pop af

	; look up toggle constant for this floor
	push af
	ld hl, PCemToggleTable
	ld e, b
	ld d, 0
	add hl, de
	ld a, [hl]
	ld [wToggleableObjectIndex], a
	pop af
	jr nz, .collected
	predef ShowObject
	ret
.collected
	predef HideObject
	ret

PCemToggleTable:
	db TOGGLE_CEMETERY_1_POKEBALL
	db TOGGLE_CEMETERY_2_POKEBALL
	db TOGGLE_CEMETERY_3_POKEBALL
	db TOGGLE_CEMETERY_4_POKEBALL

; ============================================================
; IsCemeteryMap
; Returns Z clear if current map is one of the 4 cemetery maps.
; Preserves all registers except flags/a.
; ============================================================
IsCemeteryMap::
	ldh a, [hCurMap]
	cp PROCEDURAL_CEMETERY_1
	jr z, .isCemetery
	cp PROCEDURAL_CEMETERY_2
	jr z, .isCemetery
	cp PROCEDURAL_CEMETERY_3
	jr z, .isCemetery
	cp PROCEDURAL_CEMETERY_4
	jr z, .isCemetery
	xor a              ; Z set = not a cemetery map
	ret
.isCemetery
	xor a
	inc a              ; Z clear = is a cemetery map
	ret
