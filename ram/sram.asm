SECTION "Sprite Buffers", SRAM

sSpriteBuffer0:: ds SPRITEBUFFERSIZE
sSpriteBuffer1:: ds SPRITEBUFFERSIZE
sSpriteBuffer2:: ds SPRITEBUFFERSIZE

	ds $100

sHallOfFame:: ds HOF_TEAM * HOF_TEAM_CAPACITY

; Cave generation staging buffer - written at Pallet-Town-entry by PCPreloadCave
; (custom_functions/procedural_cave_gen.asm), read at warp-in by PCFinalizeCave.
; Lives here because this is regenerable data (ClearAllSRAMBanks wiping it is
; harmless - PCPreloadCave will just refill it next Pallet-Town-entry), and SRAM
; bank 0 has ~1960 bytes free after the sprite/HoF data above.
sProcCaveStagingBuffer:: ds 600

; Procedural cemetery: four 10x9 maps concatenated (4x90=360 bytes) plus
; one pokeball position (X,Y) and one item per map. Lives in the same bank
; as the cave buffer since only one system runs at a time.
sProcCemeteryMaps:: ds 4 * 90  ; indexed by (mapIndex*90 + row*10 + col)
sProcCemeteryBallX:: ds 4      ; pokeball block X per map
sProcCemeteryBallY:: ds 4      ; pokeball block Y per map
sProcCemeteryItem:: ds 4       ; item ID per map (for pickup)
sProcCemeteryReady:: db        ; bit N = floor N has been generated (lazy per-map)
sProcCemeteryItemGot:: db      ; bit N = floor N item has been collected; cleared on new generation
sProcCemeteryUsedPrefabs:: dw  ; bit N = prefab N (PCemPrefabTable) already used this run;
                                ; at most 4 bits ever set (one per floor), cleared per-run
sProcCaveStagingEntranceY:: db
sProcCaveStagingEntranceX:: db
sProcCaveStagingExitY:: db
sProcCaveStagingExitX:: db
sProcCaveStagingBossSprite:: db    ; SPRITE_* constant for the boss, set during PCPreloadCave
sProcCaveStagingLadderID:: db      ; index into PCLadderTable (0-2), rolled during PCPreloadCave
sProcCaveStagingLadderOffset:: db  ; sub-tile remainder (0 or 1) for wWarpEntries
sProcCaveSignVariant:: db          ; 0=items text, 1=boss text; rolled in PCRollBoss
sProcCaveEntranceWarpID:: db       ; 1/3/4/5 = bottom/top/left/right; patched into source wWarpEntries
sProcCaveBallsStaged:: db          ; non-zero = ball positions/items already rolled
sProcCaveBallXY:: ds 8             ; X,Y interleaved for each of the 4 pokeballs
sProcCaveBallItems:: ds 4          ; item ID for each pokeball
sProcCaveBaked:: db                ; non-zero = staging buffer holds FINISHED tiles

; Procedural forest maze: 20x20 block map staged here at warp-in time.
; Separate from cave staging buffer so cave→forest→cave bouncing doesn't
; require cave regeneration. 400 bytes = 20*20 blocks.
sProcForestStagingBuffer:: ds 600  ; same as cave: stride layout needs PF_BASE+(PF_SIZE-1)*PF_STRIDE+PF_SIZE = 595
sProcForestExitI:: db              ; 0-8: which cell (col for N, row for W/E) is
                                   ; the exit, along whichever edge sProcForestExitEdge
                                   ; selects
sProcForestExitEdge:: db           ; 0=N (default), 1=W, 2=E. Debug: set in BGB
                                   ; after Pallet Town entry, before warping in.
                                   ; Zeroed (0=N) every Pallet Town entry by
                                   ; PFPreloadForest — W/E are debug-only, never
                                   ; part of normal random generation.
sProcForestRiverSide:: db          ; 0=left, 1=right, $FF=not a river run (exit
                                   ; roll then uses the normal unconstrained pick)
sProcForestBaked:: db              ; non-zero = buffer holds finished baked maze
sProcForestBossSpecies:: db        ; wRoguePokemon1 saved at Pallet Town entry
sProcForestBossSprite:: db         ; SPRITE_* overworld category (PCGetBossOWSprite),
                                   ; patched into wSprite01's PICTUREID BEFORE
                                   ; InitMapSprites loads tiles — same pattern as
                                   ; cave's sProcCaveStagingBossSprite. Without this,
                                   ; water species load land-sprite tiles/palette
                                   ; (confirmed bug: Tentacool showed as land monster).
sProcForestBallXY:: ds 8           ; Y0,X0,Y1,X1,Y2,X2,Y3,X3 in tile coords (block*2+4)
sProcForestBallItems:: ds 4        ; item ID per pokeball
sProcForestItemGot:: db            ; bit N = pokeball N collected this run
sProcForestSignVariant:: db        ; 0=items text, 1=boss text — rolled once at
                                   ; Pallet Town entry (PFPreloadForest), stable
                                   ; for the run. Same mechanism as cave's
                                   ; sProcCaveSignVariant.
; Debug: set to 1-4 in debugger to force specific algo (0=random).
; 1=Sidewinder 2=BinaryTree 3=Backtracker 4=HuntAndKill. Persists in SRAM.
sProcForestAlgoForce:: db
; Generation-time scratch — NEVER use wOverworldMap's border padding for this
; (confirmed hazard: corrupts the live map, causes trainer-! on pokeballs, crashes).
; Dual-purpose, safe because these never run concurrently:
;   - PFBacktracker: 81-byte packed (col|row<<4) cell coordinate stack
;   - PFScanForBall: 8 bytes ball X/Y + 4 bytes per-ball reservoir counters (runs
;     AFTER the algorithm phase, so reusing Backtracker's stack space is safe)
; SRAM stays open (RAMG_SRAM_ENABLE) for the whole first-visit generation window
; specifically so this buffer is reachable without an open/close dance — SRAM
; enable only gates $A000-$BFFF, it has zero effect on WRAM (wOverworldMap,
; wBuffer), so leaving it open during algorithm execution is safe.
sProcForestGenScratch:: ds 81
                                   ; (autotile/decor/river/ladder already applied),
                                   ; so re-entry just blits instead of re-running
                                   ; the whole pipeline


SECTION "Save Data", SRAM

	ds $598

sGameData::
sPlayerName::  ds NAME_LENGTH
sMainData::    ds wMainDataEnd - wMainDataStart
sSpriteData::  ds wSpriteDataEnd - wSpriteDataStart
sPartyData::   ds wPartyDataEnd - wPartyDataStart
sCurBoxData::  ds wBoxDataEnd - wBoxDataStart
sTileAnimations:: db
; current map id - hCurMap lives in HRAM (not in the saved wMainData block), so
; it must be saved/restored explicitly like hTileAnimations above, or Continue
; loads with hCurMap=0 and InitOutsideMapSprites loads the wrong sprite set
sCurMap:: db
sGameDataEnd::
sMainDataCheckSum:: db


; The PC boxes will not fit into one SRAM bank,
; so they use multiple SECTIONs
DEF box_n = 0
MACRO boxes
	REPT \1
		DEF box_n += 1
	sBox{d:box_n}:: ds wBoxDataEnd - wBoxDataStart
	ENDR
ENDM

SECTION "Saved Boxes 1", SRAM

; sBox1 - sBox6
	boxes 6
sBank2AllBoxesChecksum:: db
sBank2IndividualBoxChecksums:: ds 6

SECTION "Saved Boxes 2", SRAM

; sBox7 - sBox12
	boxes 6
sBank3AllBoxesChecksum:: db
sBank3IndividualBoxChecksums:: ds 6

; All 12 boxes fit within 2 SRAM banks
	ASSERT box_n == NUM_BOXES, \
		"boxes: Expected {d:NUM_BOXES} total boxes, got {d:box_n}"

ENDSECTION
