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
	jp FacSuperNerdFallbackGenerate  ; no subroom pad: he stands in the Facility

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

	; The Super Nerd (object slot 1) and the ball (slot 2) on their proven tiles.
	ld a, [wFacSubRec + FACSUB_REC_NERD_Y]
	add 4
	ld [wSprite01StateData2MapY], a
	ld a, [wFacSubRec + FACSUB_REC_NERD_X]
	add 4
	ld [wSprite01StateData2MapX], a
	ld a, [wFacSubRec + FACSUB_REC_BALL_Y]
	add 4
	ld [wSprite02StateData2MapY], a
	ld a, [wFacSubRec + FACSUB_REC_BALL_X]
	add 4
	ld [wSprite02StateData2MapX], a

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


; ============================================================
; The Super Nerd (Phase 4 step 3). A plain object, like the forest house's
; Money Match Gambler; he lives in the subroom, or, when a Facility got no
; subroom pad, in the Facility itself (the fallback, object slot
; FACILITY_SUPER_NERD). Both maps' texts farcall FacSuperNerdTalk, which
; starts the battle on a YES. He fights as the Gambler does, a route trainer at
; MONEY_MATCH_STEP with the ordinary AI, but it is no bet:
; BIT_MONEY_MATCH_NO_PAYOUT keeps the prize money normal. Beating him gives one
; random item, rolled the way the Facility's balls are; he stays and says his
; after line. Per Facility, in sProcFacilityItemGot (PFacPreload zeroes it;
; bit 7 is BIT_PFAC_OBJECTS_SHOWN): won, and the prize handed over (a full bag
; leaves it owed, and talking to him again retries).
; ============================================================
DEF BIT_PFAC_SUPER_NERD_WON  EQU 0
DEF BIT_PFAC_SUPER_NERD_PAID EQU 1

; From a text_asm (the caller keeps bc). Offers, and on a YES arms the battle:
; the overworld starts it once the text closes.
FacSuperNerdTalk::
	call FacSuperNerdFlags
	bit BIT_PFAC_SUPER_NERD_WON, a
	jr z, .offer
	bit BIT_PFAC_SUPER_NERD_PAID, a
	jp z, FacSuperNerdPrize         ; owed from a full bag
	ld hl, FacSuperNerdAfterText
	jp PrintText
.offer
	ld hl, FacSuperNerdOfferText
	call PrintText
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
	ld hl, FacSuperNerdDeclinedText ; he stays; talking again repeats the offer
	jp nz, PrintText
	ld a, (1 << BIT_MONEY_MATCH_ACTIVE) | (1 << BIT_MONEY_MATCH_NO_PAYOUT)
	ld [wMoneyMatchState], a
	; Started here, the way AILair starts its fight: a map trainer would need
	; an event flag to remember the win, and the event array is full.
	ld hl, wStatusFlags3
	set BIT_TALKED_TO_TRAINER, [hl]
	set BIT_PRINT_END_BATTLE_TEXT, [hl]
	ld hl, FacSuperNerdBeatenText
	ld de, FacSuperNerdWonText
	call SaveEndBattleTextPointers  ; this bank, read back after the battle
	ld a, OPP_SUPER_NERD
	ld [wCurOpponent], a
	ld a, 1                         ; his party is the roster's (MONEY_MATCH_STEP)
	ld [wTrainerNo], a
	ld [wIsTrainerBattle], a
	ld a, SCRIPT_SUPER_NERD_AFTER_BATTLE
	ld [wSafariZoneGateCurScript], a
	ret

; Every frame of the map script that hosts him. Out: carry = the battle just
; ended in a win (recorded): the caller shows its prize text. Clobbers a/hl.
FacSuperNerdSettle::
	ld a, [wSafariZoneGateCurScript]
	cp SCRIPT_SUPER_NERD_AFTER_BATTLE
	jr nz, .no
	; The overworld starts the battle on the frame wCurOpponent is set; until
	; it has run (the battle zeroes wCurOpponent) there is nothing to settle.
	ld a, [wCurOpponent]
	and a
	jr nz, .no
	xor a
	ld [wSafariZoneGateCurScript], a
	ld [wIsTrainerBattle], a
	ld hl, wStatusFlags3
	res BIT_PRINT_END_BATTLE_TEXT, [hl]
	; The overworld runs this once with $ff after an all-faint loss: the
	; blackout takes it from there.
	ldh a, [hIsInBattle]
	inc a
	jr z, .no
	call FacSubOpenSRAM
	ld hl, sProcFacilityItemGot
	set BIT_PFAC_SUPER_NERD_WON, [hl]
	call FacSubCloseSRAM
	scf
	ret
.no
	and a
	ret

; Rolls the prize the way PFacPlaceItems rolls a ball's, and gives it.
; Prints. Clobbers everything.
FacSuperNerdPrize::
	ld c, 4
	call Rangerandom
	ld [wRogueDoorSelection], a
	farcall Random_Item_Selection
	ld a, [wRogueItem]
	ld b, a
	ld c, 1
	call GiveItem                   ; the name goes to wStringBuffer
	ld hl, FacSuperNerdNoRoomText
	jr nc, .say
	call FacSubOpenSRAM
	ld hl, sProcFacilityItemGot
	set BIT_PFAC_SUPER_NERD_PAID, [hl]
	call FacSubCloseSRAM
	ld hl, FacSuperNerdGotItemText
.say
	jp PrintText

; Out: a = sProcFacilityItemGot. Clobbers hl.
FacSuperNerdFlags:
	call FacSubOpenSRAM
	ld a, [sProcFacilityItemGot]
	ld l, a
	call FacSubCloseSRAM
	ld a, l
	ret

FacSubOpenSRAM:
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ld a, BANK(sProcFacilityItemGot)
	ld [rRAMB], a
	ret

FacSubCloseSRAM:
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ret

; ------------------------------------------------------------
; The fallback: no subroom pad this Facility, so he stands in the Facility, on a
; block picked uniformly from every block that passes the pad rule
; (PFacPadBlockValid): plain floor, nothing within a block, not in the exit or a
; spinner room, and its bottom-right quadrant blocks no path. He stands on that
; quadrant, exactly where a pad's warp tile would be, and is talked to from the
; floor below it. The block is stored in the two scratch bytes the subroom
; would have used: byte 6 = FACSUB_FALLBACK | X, byte 7 = FACSUB_FALLBACK_ROW | Y.
; Byte 7 at or above NUM_FACILITY_PAD_SITES already means "no subroom pad" to
; every reader; $FF in both means no spot at all.
; ------------------------------------------------------------
DEF FACSUB_FALLBACK     EQU $80
DEF FACSUB_FALLBACK_ROW EQU $40
ASSERT FACSUB_FALLBACK_ROW >= NUM_FACILITY_PAD_SITES
DEF FACSUB_FALLBACK_TOP EQU 3   ; rows 0-2 hold the exit and the boss, as for pad sites
DEF FACSUB_FALLBACK_MAX EQU 18  ; the block's E/S/SE neighbours stay on the map

; FacSubroomGenerate's tail, SRAM bank 1 open (and left open).
FacSuperNerdFallbackGenerate:
	ld a, [sProcFacilityGenScratch + FACSUB_SCRATCH_PAD]
	cp NUM_FACILITY_PAD_SITES
	ret c                           ; a subroom pad: he lives in the subroom
	ld a, $ff
	ld [sProcFacilityGenScratch + FACSUB_SCRATCH_PIECE], a
	ld [sProcFacilityGenScratch + FACSUB_SCRATCH_PAD], a
	call FacSuperNerdScan           ; b = how many valid blocks
	ld a, b
	and a
	ret z                           ; nowhere: no Super Nerd this time
	ld c, a
	call Rangerandom
	inc a                           ; the 1-based ordinal to stop at
	ld b, a
	call FacSuperNerdScan.from      ; d/e = that block
	ld a, d
	or FACSUB_FALLBACK
	ld [sProcFacilityGenScratch + FACSUB_SCRATCH_PIECE], a
	ld a, e
	or FACSUB_FALLBACK_ROW
	ld [sProcFacilityGenScratch + FACSUB_SCRATCH_PAD], a
	ret

; Walks the candidate blocks in row order. Counting: out b = how many pass.
; .from, b = k >= 1: stops on the k-th, d/e = its block. Clobbers a/c/hl.
FacSuperNerdScan:
	ld b, $ff                       ; never reached: at most 16 x 18 blocks pass
.from
	ld e, FACSUB_FALLBACK_TOP
	ld c, 0                         ; passes so far
.row
	ld d, 1
.block
	push bc
	push de
	farcall PFacPadBlockValid       ; carry = it passes; keeps d/e
	pop de
	pop bc
	jr nc, .next
	inc c
	ld a, c
	cp b
	ret z                           ; the k-th: d/e
.next
	inc d
	ld a, d
	cp FACSUB_FALLBACK_MAX + 1
	jr c, .block
	inc e
	ld a, e
	cp FACSUB_FALLBACK_MAX + 1
	jr c, .row
	ld b, c                         ; counted them all
	ret

; PFacArmPads, every Facility load without a subroom pad; SRAM bank 1 open (and
; left open). Stands him on his tile; FacSubroomStageObjects shows him.
FacSuperNerdFallbackLoad::
	call FacSuperNerdSpot
	ret nc
	ld a, e
	add a
	add 4 + 1                       ; bottom-right quadrant, map border included
	ld [wSprite{d:FACILITY_SUPER_NERD}StateData2MapY], a
	ld a, d
	add a
	add 4 + 1
	ld [wSprite{d:FACILITY_SUPER_NERD}StateData2MapX], a
	ret

; SRAM bank 1 open. Out: carry = there is a fallback spot, d/e = its block.
; Clobbers a.
FacSuperNerdSpot:
	ld a, [sProcFacilityGenScratch + FACSUB_SCRATCH_PIECE]
	cp FACSUB_FALLBACK
	ccf
	ret nc                          ; a room piece, not a spot
	cp FACSUB_FALLBACK | (FACSUB_FALLBACK_MAX + 1)
	ret nc
	and ~FACSUB_FALLBACK & $ff
	ld d, a
	ld a, [sProcFacilityGenScratch + FACSUB_SCRATCH_PAD]
	sub FACSUB_FALLBACK_ROW
	ccf
	ret nc
	cp FACSUB_FALLBACK_MAX + 1
	ret nc
	ld e, a
	ret                             ; carry from the cp: in range

; The Facility's once-per-stage show block. The subroom's ball comes back for
; the new stage (its map is not loaded, so the flag is written directly). The
; Super Nerd is shown with a fallback spot and hidden otherwise: toggle bits
; outlive the stage, so one shown in the last Facility would stay.
; Clobbers everything.
FacSubroomStageObjects::
	ld c, TOGGLE_FACSUBROOM_BALL
	ld b, FLAG_RESET
	ld hl, wToggleableObjectFlags
	predef FlagActionPredef
	call FacSubOpenSRAM
	call FacSuperNerdSpot
	push af
	call FacSubCloseSRAM
	ld a, TOGGLE_FACILITY_SUPER_NERD
	ld [wToggleableObjectIndex], a
	pop af
	jr nc, .hide
	predef_jump ShowObject
.hide
	predef_jump HideObject

; The subroom's ball, from its text_asm (the caller keeps bc). Rolls its item
; the way PFacPlaceItems rolls a Facility ball's, gives it and hides the ball; a
; full bag leaves it there. Prints. Clobbers everything.
FacSubroomPickUpBall::
	ld c, 4
	call Rangerandom
	ld [wRogueDoorSelection], a
	farcall Random_Item_Selection
	ld a, [wRogueItem]
	ld b, a
	ld c, 1
	call GiveItem                   ; the name goes to wStringBuffer
	ld hl, FacSuperNerdNoRoomText
	jp nc, PrintText
	ld a, TOGGLE_FACSUBROOM_BALL
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld hl, FacSubroomFoundItemText
	jp PrintText

FacSubroomFoundItemText:
	text "<PLAYER> found"
	line "@"
	text_ram wStringBuffer
	text "!@"
	sound_get_item_1
	text_end

; Placeholder lines (user, 2026-10-14).
FacSuperNerdOfferText:
	text "Beat me and I'll"
	line "give you an item"
	cont "from my stash!"

	para "Ready?"
	done

FacSuperNerdDeclinedText:
	text "Scared? I'll be"
	line "right here."
	done

FacSuperNerdAfterText:
	text "Enjoy the item,"
	line "you earned it."
	done

FacSuperNerdGotItemText:
	text "<PLAYER> got"
	line "@"
	text_ram wStringBuffer
	text "!@"
	sound_get_item_1
	text_end

FacSuperNerdNoRoomText:
	text "Your BAG is full!"
	line "Come back for it."
	done

; In battle: he lost.
FacSuperNerdBeatenText:
	text ""
	para "Ugh! You win"
	line "fair and square."
	prompt

; In battle: he won.
FacSuperNerdWonText:
	text "My stash stays"
	line "with me!"
	prompt
