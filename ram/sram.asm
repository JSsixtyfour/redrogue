SECTION "Sprite Buffers", SRAM

sSpriteBuffer0:: ds SPRITEBUFFERSIZE
sSpriteBuffer1:: ds SPRITEBUFFERSIZE
sSpriteBuffer2:: ds SPRITEBUFFERSIZE

	ds $100

sHallOfFame:: ds HOF_TEAM * HOF_TEAM_CAPACITY


SECTION "Save Data", SRAM

	ds $591 ; was $291; 784 bytes could be carved for sFusionSpriteA0/A1 below

; Sprite fusion: hold species_a's aligned 1bpp planes while species_b loads.
; Only used by LoadFusedFrontSprite (custom_functions/func_fusion_sprite.asm).
;sFusionSpriteA0:: ds SPRITEBUFFERSIZE ; species_a MSB plane (392 bytes)
;sFusionSpriteA1:: ds SPRITEBUFFERSIZE ; species_a LSB plane (392 bytes)

; TM/HM ownership bitfield for the roguelike run.
; Bit N = owned: bits 0-49 = TM01-TM50, bits 50-54 = HM01-HM05.
; Cleared at run reset. Saved across power cycles.
sTMBitfield:: ds 7

; Key items pocket ownership bitfield. Persists through death and new runs;
; only cleared on a true new game (ClearKeyItemsBitfield in InitPlayerData).
; Bit assignments (must remain stable once save data exists):
;   0 = LEFTOVERS, 1 = PP_TONIC, 2 = KO_DEFIANCE, 3 = EXP_ALL
;   4-7 reserved (Mom's Allowance, First Aid Kit, etc.)
;   8-31 reserved (per-type attack boosters)
sKeyItemsBitfield:: ds 4

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
