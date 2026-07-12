SECTION "Sprite Buffers", SRAM

sSpriteBuffer0:: ds SPRITEBUFFERSIZE
sSpriteBuffer1:: ds SPRITEBUFFERSIZE
sSpriteBuffer2:: ds SPRITEBUFFERSIZE

	ds $100

sHallOfFame:: ds HOF_TEAM * HOF_TEAM_CAPACITY


SECTION "Save Data", SRAM

	ds $479 ; was $591; 112 bytes carved for sFusionDiagBuf below

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
