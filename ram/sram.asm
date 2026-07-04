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
sProcCemetaryMaps:: ds 4 * 90  ; indexed by (mapIndex*90 + row*10 + col)
sProcCemetaryBallX:: ds 4      ; pokeball block X per map
sProcCemetaryBallY:: ds 4      ; pokeball block Y per map
sProcCemetaryItem:: ds 4       ; item ID per map (for pickup)
sProcCemetaryReady:: db        ; 1 = all 4 maps generated, 0 = not ready
sProcCaveStagingEntranceY:: db
sProcCaveStagingEntranceX:: db
sProcCaveStagingExitY:: db
sProcCaveStagingExitX:: db
sProcCaveStagingBossSprite:: db    ; SPRITE_* constant for the boss, set during PCPreloadCave
sProcCaveStagingLadderID:: db      ; index into PCLadderTable (0-2), rolled during PCPreloadCave
sProcCaveStagingLadderOffset:: db  ; sub-tile remainder (0 or 1) for wWarpEntries


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
