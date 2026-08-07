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
sProcCemeteryBossSpecies:: db  ; cemetery boss species, rolled at preload (PCemGenerateMaps).
                                ; Persisted here because wRoguePokemon1 is shared scratch that
                                ; wild battles clobber (random_pokemon_selection.asm) between
                                ; preload and the floor-4 boss engage; restored via
                                ; PCemRestoreBossSpecies right before the battle + join offer.
                                ; Mirrors the forest's sProcForestBossSpecies.
sProcCemeteryBossMove:: db     ; the boss's ghost move (LICK/NIGHT_SHADE/CONFUSE_RAY), rolled
                                ; once at preload so the battle enemy and the gifted mon match.
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


; Procedural facility: 20x20 block map staged here at warp-in time. Same layout
; as cave/forest (600-byte stride buffer). Lives in its OWN SRAM section (not the
; bank-0 "Sprite Buffers" one) because cave+cemetery+forest already fill bank 0 -
; this floats into a bank with room (1-3). Regenerable, so ClearAllSRAMBanks
; wiping it is harmless (PFacPreload refills it next Pallet Town entry). Only one
; procedural system runs at a time. Unlike cave/forest, the base map is
; floor-filled (block 14) and the generator autotiles every wall cell, so no
; generic fill block survives inside the player area (border block 46 only ever
; appears in the map's border ring).
SECTION "Procedural Facility SRAM", SRAM, BANK[1]

sProcFacilityStagingBuffer:: ds 600 ; PFAC_BASE+(PFAC_SIZE-1)*PFAC_STRIDE+PFAC_SIZE = 595 used
sProcFacilityExitI:: db            ; 0-8: which cell along the exit edge is the exit
sProcFacilityExitEdge:: db         ; 0=N (default), 1=W, 2=E; zeroed every Pallet Town
                                   ; entry by PFacPreload, W/E debug-only
sProcFacilityBaked:: db            ; non-zero = buffer holds finished baked map
sProcFacilityBossSpecies:: db      ; wRoguePokemon1 saved at Pallet Town entry
sProcFacilityBossSprite:: db       ; SPRITE_* overworld category (PCGetBossOWSprite),
                                   ; patched into wSprite01 PICTUREID BEFORE InitMapSprites
sProcFacilityBallXY:: ds 8         ; Y0,X0,Y1,X1,Y2,X2,Y3,X3 in tile coords (block*2+4)
sProcFacilityBallItems:: ds 4      ; item ID per pokeball
sProcFacilityItemGot:: db          ; bit N = pokeball N collected this run
sProcFacilitySignVariant:: db      ; 0=items text, 1=boss text; rolled once at Pallet
                                   ; Town entry (PFacPreload), stable for the run
sProcFacilityPalette:: db          ; 0=PowerPlant (PAL_ROUTE/green), 1=Mansion
                                   ; (PAL_CINNABAR/red); rolled at Pallet Town entry,
                                   ; read by SetPal_Overworld's FACILITY case (step 9)
sProcFacilityAlgoForce:: db        ; debug: facility ships Rooms/Dungeon only, but keep
                                   ; a force byte for parity with forest's selector
; Generation-time scratch — NEVER use wOverworldMap's border padding (same hazard
; as forest). Reused across non-concurrent generation phases.
sProcFacilityGenScratch:: ds 81

; Packed wall-room tessellation (redesign v2, see Red Rogue Files/
; 1-i-need-you-foamy-otter.md): every grown room is tracked here as it's placed
; (X,Y,W,H,role), 5 bytes/room, so later growths can pick a parent wall and
; overlap-check against everything placed so far. No Parent field - a room's
; doorway to its parent is punched into the map at growth time, so the spanning
; tree lives in the map itself, not in this table. Room count lives in WRAM
; (wPFacRoomCount, same as the old 6-byte-record model). role: 0=entry, 1=item,
; 2=exit, 3=plain.
sProcFacilityRoomBuf:: ds 240 ; 48 rooms x 5 bytes


SECTION "Save Data", SRAM

	ds $450 ; was $591; 112 bytes carved for sFusionDiagBuf below, 4 bytes carved for sKeyItemTiers below,
	        ; 1 byte sElementPrismType + 2 sPrismCartridges + 34 sTurnRewindBuf (Key Item Effects)

; Diagonal tile save buffer for sprite fusion.
; Holds the 7 diagonal tiles (col==row) from species_a's 2bpp interleaved
; output (sSpriteBuffer1+2), saved before species_b overwrites them.
; 7 tiles * 16 bytes = 112 bytes.
sFusionDiagBuf:: ds 112

; TM/HM ownership bitfield for the roguelike run.
; Bit N = owned: bits 0-49 = TM01-TM50, bits 50-54 = HM01-HM05.
; Cleared at run reset. Saved across power cycles.
sTMBitfield:: ds 7

; Key items pocket.
; sKeyItemsBitfield: paired own+active bits for each key item.
;   Bit 0 = LEFTOVERS owned, bit 1 = LEFTOVERS active (in bag)
;   Bit 2 = PP_TONIC owned,  bit 3 = PP_TONIC active
;   Bit 4 = KO_DEFIANCE owned, bit 5 = KO_DEFIANCE active
;   Bit 6 = EXP_ALL owned,  bit 7 = EXP_ALL active
; Active = item is in the bag and usable. Max 3 active at once.
; GiveItem auto-activates if slots available; PC WITHDRAW/DEPOSIT for manual swap.
sKeyItemsBitfield:: ds 4    ; only byte 0 is used; extra bytes cost nothing

; Key item upgrade tiers: 2 bits per item, 16 items, tier 0-3.
; Same bit ordering as sKeyItemsBitfield (item N -> bits 2N, 2N+1).
; SRAM so upgrades persist across runs and blackouts.
; MUST stay immediately after sKeyItemsBitfield: ClearKeyItemsBitfield
; (custom_functions/key_item_pocket.asm) zeroes both as one 8-byte run on new
; game. Separating them would leave tiers holding stale SRAM, which reads as
; "already maxed" and hides items from the Credit Exchange upgrade vendor.
sKeyItemTiers:: ds 4

; ELEMENT PRISM's chosen type (see KEY_ITEM_EFFECTS_PLAN_PC.md). $FF = not yet
; chosen. SRAM so the choice survives run reset and blackout, like key-item
; ownership. The prism's tier needs no separate storage - it is key item
; index 14 in sKeyItemTiers above.
sElementPrismType:: db

; ELEMENT PRISM cartridges the player has unlocked: 1 bit per selectable type,
; indexed by position in PrismTypeList (custom_functions/element_prism.asm),
; so 15 bits in 2 bytes. Gym leaders, the Elite Four and the Champion each
; grant their signature type's cartridge on defeat; the player equips one at
; the PC. SRAM because cartridges persist across runs and blackouts, exactly
; like key-item ownership - accumulating them over several runs is the point.
sPrismCartridges:: ds 2

; TURN REWIND snapshot: the active player mon's HP/PP/status/stat-mods/battle
; status only (not a full battle-state snapshot - see
; KEY_ITEM_EFFECTS_PLAN_PC.md §5 for why the reduced scope is sound).
; Written once per turn on move commit; a single buffer is sufficient because
; restoring only ever undoes the most recent turn. Byte 0 doubles as the
; "no snapshot yet this battle" sentinel ($ff).
sTurnRewindBuf:: ds 34

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
