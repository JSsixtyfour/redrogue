; custom_functions/facility_subroom.asm
;
; The Facility's subroom (PROCEDURAL_SUBROOMS_PLAN Phase 4). The map
; (PROCEDURAL_FACILITY_SUBROOM) is black void; each Facility rolls one of the
; generator's own full-room pieces, and every load stamps it, centred, puts the
; pad on that piece's landing spot and stands the residents on the tiles
; tools/facility_subroom.py proved for it.
;
; Opens its own section, pinned to $3F in layout.link; farcall-only.

SECTION "Facility Subroom", ROMX

INCLUDE "data/maps/facility_subroom_pieces.asm"

; The rolled piece and the Facility pad site leading here. sProcFacilityGenScratch's
; bytes 0-7 held the ball coordinates until PFacFinalize's .ballSave; the pads
; keep 0-1 and the spinner 2-5, and 6-7 are free from there on.
DEF FACSUB_SCRATCH_PIECE EQU 6
DEF FACSUB_SCRATCH_PAD   EQU 7 ; = PFAC_SUBROOM_PAD (procedural_facility_gen.asm)

DEF FACSUB_STRIDE_BLOCKS EQU FACSUB_MAP_W + 6 ; wOverworldMap row, border included

; One piece record (FACSUB_PIECE_STRIDE bytes), copied to wBuffer + 1 by
; FacSubroomLoad: wBuffer + 0 is FarCopyData's bank byte.
RSRESET
DEF FACSUB_REC_PAYLOAD RW 1
DEF FACSUB_REC_W       RB 1
DEF FACSUB_REC_H       RB 1
DEF FACSUB_REC_X       RB 1
DEF FACSUB_REC_Y       RB 1
DEF FACSUB_REC_LANDING RB 1
DEF FACSUB_REC_NERD_X  RB 1
DEF FACSUB_REC_NERD_Y  RB 1
DEF FACSUB_REC_BALL_X  RB 1
DEF FACSUB_REC_BALL_Y  RB 1
ASSERT _RS == FACSUB_PIECE_STRIDE
DEF wFacSubRec EQUS "(wBuffer + 1)"
DEF wFacSubPad EQUS "(wBuffer + 1 + FACSUB_PIECE_STRIDE)" ; the pad site, during the load

; PFacFinalize's first visit, after the pads and before the bake. SRAM bank 1 is
; open and stays open. Clobbers a/bc/de/hl.
FacSubroomGenerate::
	ld a, [FacSubroomPicks]
	ld c, a
	call Rangerandom
	ld e, a
	ld d, 0
	ld hl, FacSubroomPicks + 1
	add hl, de
	ld a, [hl]
	ld [sProcFacilityGenScratch + FACSUB_SCRATCH_PIECE], a
	ret

; PFacArmPads, every Facility load, SRAM bank 1 open (and left open).
; Out: e = the rolled piece's landing, its 0-based warp in the subroom.
; Clobbers a/hl (d = 0).
FacSubroomLanding::
	ld a, [sProcFacilityGenScratch + FACSUB_SCRATCH_PIECE]
	call FacSubroomPieceRecord
	ld de, FACSUB_REC_LANDING
	add hl, de
	ld e, [hl]
	ret

; In: a = the stored piece. Out: hl = its row in FacSubroomPieces. A value that
; was never rolled (an older save) means the first piece. Clobbers a/de.
FacSubroomPieceRecord:
	cp FACSUB_NUM_PIECES
	jr c, .pieceOK
	xor a
.pieceOK
	ASSERT FACSUB_PIECE_STRIDE == 11
	ld l, a
	ld h, 0
	ld d, h
	ld e, l
	add hl, hl
	add hl, hl
	add hl, de                      ; 5a
	add hl, hl                      ; 10a
	add hl, de                      ; 11a
	ld de, FacSubroomPieces
	add hl, de
	ret

; ProcStageLoadDispatch, every load of the subroom: after LoadTileBlockMap filled
; wOverworldMap from the void .blk, before the view is drawn.
FacSubroomLoad::
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ld a, BANK(sProcFacilityGenScratch)
	ld [rRAMB], a
	ld a, [sProcFacilityGenScratch + FACSUB_SCRATCH_PAD]
	ld [wFacSubPad], a
	ld a, [sProcFacilityGenScratch + FACSUB_SCRATCH_PIECE]
	ld b, a
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ld a, b
	call FacSubroomPieceRecord
	ld de, wFacSubRec
	ld bc, FACSUB_PIECE_STRIDE
	call CopyData

	; The Super Nerd (object slot 1) on his proven tile.
	ld a, [wFacSubRec + FACSUB_REC_NERD_Y]
	add 4
	ld [wSprite01StateData2MapY], a
	ld a, [wFacSubRec + FACSUB_REC_NERD_X]
	add 4
	ld [wSprite01StateData2MapX], a

	; The piece, row by row from its own bank.
	ld a, [wFacSubRec + FACSUB_REC_Y]
	ld c, a
	ld a, [wFacSubRec + FACSUB_REC_X]
	call .blockAddr
	ld d, h
	ld e, l
	ld hl, wFacSubRec + FACSUB_REC_PAYLOAD
	ld a, [hli]
	ld h, [hl]
	ld l, a
.row
	; FarCopyData leaves hl on the next payload row; de steps a whole map row.
	push de
	ld a, [wFacSubRec + FACSUB_REC_W]
	ld c, a
	ld b, 0
	ld a, BANK(PFacRoomDescriptors)
	call FarCopyData
	pop de
	ld a, e
	add FACSUB_STRIDE_BLOCKS
	ld e, a
	jr nc, .noCarry
	inc d
.noCarry
	ld a, [wFacSubRec + FACSUB_REC_H]
	dec a
	ld [wFacSubRec + FACSUB_REC_H], a
	jr nz, .row

	; The pad on this piece's landing spot.
	ld a, [wFacSubRec + FACSUB_REC_LANDING]
	add a
	ld e, a
	ld d, 0
	ld hl, FacSubroomLandings
	add hl, de
	ld a, [hli]
	ld c, [hl]
	call .blockAddr
	ld [hl], FACSUB_PAD_BLOCK

	; Only that landing's warp leaves: the others sit on plain floor, and a
	; departure Y of $FF can never match the player. Their arrival tiles stay
	; (the ROM warp table), which is what lets one map serve every piece. The
	; one kept leads back onto the Facility pad that led here, as a pad pair
	; does (its ROM destination, the Facility entrance, stays if there is none).
	ASSERT FACSUB_NUM_LANDINGS <= 32
	ld hl, wWarpEntries
	ld a, [wFacSubRec + FACSUB_REC_LANDING]
	ld c, a
	ld b, 0
.disarm
	ld a, b
	cp c
	jr z, .keep
	ld [hl], $ff                    ; departure Y
	jr .next
.keep
	ld a, [wFacSubPad]
	cp NUM_FACILITY_PAD_SITES
	jr nc, .next
	add FACILITY_FIRST_PAD_WARP
	inc hl
	inc hl
	ld [hld], a                     ; destination warp (0-based): that pad site
	dec hl
.next
	ld de, 4
	add hl, de
	inc b
	ld a, b
	cp FACSUB_NUM_LANDINGS
	jr nz, .disarm
	ret

; a = block x, c = block y -> hl = its wOverworldMap byte. Clobbers b.
.blockAddr
	add 3
	push af
	ld a, c
	add 3
	ld l, a
	ld h, 0
	ld c, a
	ld b, h
	ASSERT FACSUB_STRIDE_BLOCKS == 17
	add hl, hl
	add hl, hl
	add hl, hl
	add hl, hl
	add hl, bc
	pop af
	ld c, a
	add hl, bc
	ld bc, wOverworldMap
	add hl, bc
	ret
