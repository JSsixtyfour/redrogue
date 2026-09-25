; custom_functions/room_decor.asm
;
; SilphCoDorm room decoration placement engine. Reads sRoomFurniture /
; sRoomDecorSlots / sRoomOwned (ram/sram.asm, "Save Data" section, bank 1)
; and applies them to the currently-loaded map: RoomStampBlocks rewrites the
; 10 configurable wOverworldMap block cells, RoomPatchSprites repoints the 8
; decoration object slots' PICTUREID/position. Both are farcall'd from
; custom_functions/procedural_stage_hooks.asm, the same load-time windows
; MiniBossPatchStageSprite/ProcStageLoadDispatch already use for identical
; reasons (relieve ROM0/HOME pressure; see project_rom0_home_pressure).
;
; wOverworldMap addressing matches procedural_cave_gen.asm's documented
; formula: wOverworldMap + MAP_BORDER + x + (y + MAP_BORDER) * (width +
; MAP_BORDER*2). SilphCoDorm is 4 blocks wide, so stride = 4+6 = 10 and the
; row-0 base is MAP_BORDER + 3*stride = 33. All 10 offsets below are that
; formula evaluated at compile time for this fixed 4x4 map.
;
; SRAM BANK DISCIPLINE (applies to room_pc.asm and room_vendor.asm too):
; every routine here that opens SRAM to reach "Save Data" (bank 1) MUST
; restore rRAMB to 0 before returning. The rest of the codebase leaves the
; bank selected at 0 as its ambient state - procedural_stage_hooks.asm sets
; it to 0 for its bank-0 reads, and UncompressSpriteData force-sets 0 on
; entry - and several routines (ClearTMBitfield, ClearKeyItemsBitfield,
; PrepareNewGameDebug's TM fill) access SRAM with only rRAMG set, inheriting
; whatever bank is current. Leaving bank 1 selected therefore silently
; redirects other code's bank-0 SRAM writes into the save area: sSpriteBuffer
; lives at $a000-$a5ff in bank 0, which in bank 1 overlaps sGameData /
; sPlayerName / sMainData at $a4f4+.

SECTION "Room", ROMX

; ============================================================
; RoomStampBlocks — write the 10 furniture-selected blocks into wOverworldMap.
; Called from ProcStageLoadDispatch, after LoadTileBlockMap and before
; LoadCurrentMapView, so the room draws correct on the very first frame.
; ============================================================
RoomStampBlocks::
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ASSERT BANK("Save Data") == 1
	ld a, 1
	ld [rRAMB], a
	ld a, [sRoomFurniture]
	ld d, a                     ; d = byte0: bits0-3 TOP, bits4-6 MIDDLE, bit7 BOTTOM
	ld a, [sRoomFurniture + 1]
	ld e, a                     ; e = byte1: bit0 PC
	xor a
	ld [rRAMB], a               ; restore the ambient bank-0 selection (see file header)
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a

	; --- TOP: cells (2,0)=+35 (3,0)=+36 (2,1)=+45 ---
	ld a, d
	and %00001111
	ld c, a
	ld b, 0
	ld hl, RoomTopBlockTable
	add hl, bc
	add hl, bc
	add hl, bc
	ld a, [hli]
	ld [wOverworldMap + 35], a
	ld a, [hli]
	ld [wOverworldMap + 36], a
	ld a, [hl]
	ld [wOverworldMap + 45], a

	; --- MIDDLE: cells (1,2)=+54 (2,2)=+55 (3,2)=+56 (1,3)=+64 ---
	ld a, d
	swap a
	and %00000111
	add a
	add a                       ; 4-byte rows (index 0-7, so no carry)
	ld c, a
	ld b, 0
	ld hl, RoomMiddleBlockTable
	add hl, bc
	ld a, [hli]
	ld [wOverworldMap + 54], a
	ld a, [hli]
	ld [wOverworldMap + 55], a
	ld a, [hli]
	ld [wOverworldMap + 56], a
	ld a, [hl]
	ld [wOverworldMap + 64], a

	; --- BOTTOM: cell (3,3)=+66 ---
	bit 7, d
	jr z, .bottomDefault
	ld a, [RoomBottomBlockTable + 1]
	jr .bottomSet
.bottomDefault
	ld a, [RoomBottomBlockTable]
.bottomSet
	ld [wOverworldMap + 66], a

	; --- PC: cells (0,0)=+33 (1,0)=+34 ---
	ld hl, RoomPCBlockTable
	bit 0, e
	jr z, .pcSet
	inc hl
	inc hl
.pcSet
	ld a, [hli]
	ld [wOverworldMap + 33], a
	ld a, [hl]
	ld [wOverworldMap + 34], a
	ret

RoomTopBlockTable: ; 10 options x 3 bytes: (2,0) (3,0) (2,1)
	db  3,  3, 15 ; 0 WALL (default)
	db  4,  3, 15 ; 1 BOOKSHELF
	db 30,  3, 15 ; 2 AWARD SHELF
	db  5,  3, 15 ; 3 WINDOW
	db 28, 29, 15 ; 4 CHALKBOARD
	db  9,  3, 15 ; 5 TV
	db  9,  3,  6 ; 6 TV + GAME
	db 25,  3, 15 ; 7 MAP
	db 19, 20, 15 ; 8 COUCH
	db 32,  3, 15 ; 9 DINOSAUR POSTER (block $20: same shape as MAP's $19)

RoomMiddleBlockTable: ; 6 options x 4 bytes: (1,2) (2,2) (3,2) (1,3)
	db 15, 15, 15, 15 ; 0 NOTHING (default)
	db 21, 22, 15, 27 ; 1 NOTE TABLE
	db  1,  2, 15, 15 ; 2 FLOWER TABLE
	db 23, 24, 15, 15 ; 3 PLAIN TABLE
	db 13, 15, 15, 15 ; 4 TV + GAME
	db 15,  7,  8, 15 ; 5 SPACESHIP (blocks $07 left, $08 right; one block right of the tables)

RoomBottomBlockTable: ; 2 options x 1 byte: (3,3)
	db 15 ; 0 NOTHING (default)
	db 26 ; 1 POTTED PLANT

RoomPCBlockTable: ; 2 options x 2 bytes: (0,0) (1,0)
	db 31, 3  ; 0 DESK (default)
	db 16, 17 ; 1 LONG DESK

; ============================================================
; RoomPatchSprites — repoint the 8 decoration object slots.
; Called from ProcBossPatchStageSprite, after LoadMapHeader and before
; InitMapSprites (same window MiniBossPatchStageSprite uses).
; ============================================================
RoomPatchSprites::
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ASSERT BANK("Save Data") == 1
	ld a, 1
	ld [rRAMB], a
	ld a, [sRoomFurniture]
	ld d, a
	ld a, [sRoomFurniture + 1]
	ld e, a
	xor a
	ld [rRAMB], a               ; restore the ambient bank-0 selection (see file header)
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	; d = furniture byte0 (bits0-3 TOP, bits4-6 MIDDLE, bit7 BOTTOM)
	; e = furniture byte1 (bit0 PC) — kept live in d/e for the whole routine;
	; RoomApplyEnabledSlot/RoomWriteSlot never touch d or e.

	; --- slot 1: BEDSIDE, always live, (1,6) ---
	ld hl, wSprite01StateData1
	ld b, 1
	ld c, 6
	ld a, 1
	call RoomApplyEnabledSlot

	; --- slot 2: BOTTOM, always live, (6,7) ---
	ld hl, wSprite02StateData1
	ld b, 6
	ld c, 7
	ld a, 2
	call RoomApplyEnabledSlot

	; --- slot 3: TOP, always live; (5,1) if TOP=COUCH(8) else (6,1) ---
	ld a, d
	and %00001111
	cp 8
	ld b, 6
	jr nz, .top3
	ld b, 5
.top3
	ld hl, wSprite03StateData1
	ld c, 1
	ld a, 3
	call RoomApplyEnabledSlot

	; --- slot 4: MIDDLE #1, always live; (2,4) if MIDDLE=FLOWER(2)/PLAIN(3),
	; (3,4) beside the ship if MIDDLE=SPACESHIP(5), else (4,4) ---
	ld a, d
	swap a
	and %00000111
	ld b, 4
	cp 2
	jr z, .mid1Narrow
	cp 3
	jr z, .mid1Narrow
	cp 5
	jr nz, .mid1_4
	ld b, 3
	jr .mid1_4
.mid1Narrow
	ld b, 2
.mid1_4
	ld hl, wSprite04StateData1
	ld c, 4
	ld a, 4
	call RoomApplyEnabledSlot

	; --- slot 5: MIDDLE #2, live only if MIDDLE=FLOWER(2)/PLAIN(3) at (5,4),
	; or MIDDLE=SPACESHIP(5) at (3,5) ---
	ld hl, wSprite05StateData1
	ld a, d
	swap a
	and %00000111
	cp 2
	jr z, .mid2Live
	cp 3
	jr z, .mid2Live
	cp 5
	jr z, .mid2Ship
	xor a
	call RoomWriteSlot
	jr .slot6
.mid2Ship
	ld b, 3
	ld c, 5
	jr .mid2Apply
.mid2Live
	ld b, 5
	ld c, 4
.mid2Apply
	ld a, 5
	call RoomApplyEnabledSlot
.slot6

	; --- slot 6: MIDDLE #3, live only if MIDDLE=FLOWER(2)/PLAIN(3); (5,5) ---
	ld hl, wSprite06StateData1
	ld a, d
	swap a
	and %00000111
	cp 2
	jr z, .mid3Live
	cp 3
	jr z, .mid3Live
	xor a
	call RoomWriteSlot
	jr .slot7
.mid3Live
	ld b, 5
	ld c, 5
	ld a, 6
	call RoomApplyEnabledSlot
.slot7

	; --- slot 7: PC #1, always live; (1,0) if PC=LONG DESK(1) else (1,1) ---
	; The default MUST NOT be (0,1): that is the PC's own bg_event tile in
	; data/maps/objects/SilphCoDorm.asm, and a decoration there would sit on
	; top of the PC interaction point.
	ld hl, wSprite07StateData1
	bit 0, e
	jr z, .pc7Default
	ld b, 1
	ld c, 0
	jr .pc7Set
.pc7Default
	ld b, 1
	ld c, 1
.pc7Set
	ld a, 7
	call RoomApplyEnabledSlot

	; --- slot 8: PC #2, live only if PC=LONG DESK(1); (2,0) ---
	ld hl, wSprite08StateData1
	bit 0, e
	jr nz, .pc8Live
	xor a
	jp RoomWriteSlot
.pc8Live
	ld b, 2
	ld c, 0
	ld a, 8
	jp RoomApplyEnabledSlot

; ============================================================
; RoomApplyEnabledSlot — a furniture-enabled slot's SRAM lookup + dispatch.
; INPUT: a = 1-based slot number (1-8), b = tile x, c = tile y,
;        hl = wSpriteNNStateData1 base for this slot.
; Reads sRoomDecorSlots[a-1]; 0 clears the slot, else patches PICTUREID and
; position via RoomWriteSlot. Preserves d,e.
; ============================================================
RoomApplyEnabledSlot:
	push hl                     ; [spriteBase]
	push bc                     ; [spriteBase, xy]
	dec a
	ld c, a
	ld b, 0
	ld hl, sRoomDecorSlots
	add hl, bc
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ASSERT BANK("Save Data") == 1
	ld a, 1
	ld [rRAMB], a
	ld a, [hl]                  ; a = decoration id (0-21)
	ld c, a                     ; stash across the SRAM close (c's old value,
	                            ; the sRoomDecorSlots offset, is no longer needed)
	xor a
	ld [rRAMB], a               ; restore the ambient bank-0 selection (see file header)
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ld a, c                     ; a = decoration id, SRAM closed
	and a
	jr z, .empty
	dec a
	ld c, a
	ld b, 0
	ld hl, DecorationSpriteTable
	add hl, bc
	ld a, [hl]                  ; a = SPRITE_* id
	pop bc                      ; [spriteBase]
	pop hl                      ; []
	jp RoomWriteSlot
.empty
	pop bc                      ; [spriteBase]
	pop hl                      ; []
	xor a
	jp RoomWriteSlot

DecorationSpriteTable: ; indexed by (decoration id - 1)
	db SPRITE_MONSTER      ; 1 CHARMELEON
	db SPRITE_BIRD         ; 2 PIDGEY
	db SPRITE_OMANYTE_DECO ; 3 OMANYTE
	db SPRITE_VOLTORB_DECO ; 4 VOLTORB
	db SPRITE_FAIRY        ; 5 CLEFAIRY
	db SPRITE_CHANSEY      ; 6 CHANSEY
	db SPRITE_SNORLAX_DECO ; 7 SNORLAX
	db SPRITE_PIKACHU      ; 8 PIKACHU
	db SPRITE_POKEDEX      ; 9 POKEDEX (still)
	db SPRITE_OLD_AMBER    ; 10 OLD AMBER (still)
	db SPRITE_SEEL         ; 11 SEEL
	db SPRITE_DODUO        ; 12 DODUO
	db SPRITE_PSYDUCK      ; 13 PSYDUCK
	db SPRITE_NIDORINO     ; 14 NIDORINO
	db SPRITE_KABUTO       ; 15 KABUTO
	db SPRITE_SPEAROW      ; 16 SPEAROW
	db SPRITE_CUBONE       ; 17 CUBONE
	db SPRITE_ARTICUNO     ; 18 ARTICUNO
	db SPRITE_ZAPDOS       ; 19 ZAPDOS
	db SPRITE_MOLTRES      ; 20 MOLTRES
	db SPRITE_MEWTWO       ; 21 MEWTWO
	db SPRITE_FEAROW       ; 22 FEAROW
	db SPRITE_KANGASKHAN   ; 23 KANGASKHAN
	db SPRITE_LAPRAS       ; 24 LAPRAS
	db SPRITE_MACHOP       ; 25 MACHOP
	db SPRITE_MEW          ; 26 MEW
	db SPRITE_NIDORAN_F    ; 27 NIDORAN_F
	db SPRITE_PIDGEY       ; 28 PIDGEY
	db SPRITE_SLOWPOKE     ; 29 SLOWPOKE
	db SPRITE_VAPOREON     ; 30 VAPOREON
	db SPRITE_BULBASAUR    ; 31 BULBASAUR
	db SPRITE_CLEFAIRY     ; 32 CLEFAIRY
	db SPRITE_JIGGLYPUFF   ; 33 JIGGLYPUFF
	db SPRITE_MACHOKE      ; 34 MACHOKE
	db SPRITE_MEOWTH       ; 35 MEOWTH
	db SPRITE_MR_MIME      ; 36 MR_MIME
	db SPRITE_NIDORAN_M    ; 37 NIDORAN_M
	db SPRITE_ODDISH       ; 38 ODDISH
	db SPRITE_PIDGEOT      ; 39 PIDGEOT
	db SPRITE_POLIWRATH    ; 40 POLIWRATH
	db SPRITE_SANDSHREW    ; 41 SANDSHREW
	db SPRITE_SEEL2        ; 42 SEEL2
	db SPRITE_JOLTEON      ; 43 JOLTEON
	db SPRITE_FLAREON      ; 44 FLAREON
	db SPRITE_WIGGLYTUFF   ; 45 WIGGLYTUFF
DEF NUM_ROOM_DECORATIONS EQU 45
ASSERT @ - DecorationSpriteTable == NUM_ROOM_DECORATIONS

; ============================================================
; RoomWriteSlot — the actual struct writer.
; INPUT: a = SPRITE_* id (0 = clear/disable), hl = wSpriteNNStateData1 base,
;        b = tile x, c = tile y (b,c only read if a != 0).
; a=0 mirrors LoadMapObjects' own blanket-disable pattern (PICTUREID=0,
; IMAGEINDEX=$ff, MOVEMENTSTATUS=0) so a furniture-disabled slot never
; leaks a ghost sprite - a nonzero PICTUREID alone is enough for
; InitMapSprites to allocate it a VRAM slot and render it.
; Clobbers a, hl.
; ============================================================
RoomWriteSlot:
	and a
	jr z, .disable
	ld [hl], a                  ; StateData1 PICTUREID
	inc h                       ; -> StateData2, same slot (StateData2 base is
	                            ; StateData1 base + $100 for every slot alike,
	                            ; see ram/wram.asm's paired ASSERTs - this only
	                            ; changes h; l still holds this slot's
	                            ; low-byte offset and must be ADDED to, not
	                            ; overwritten, or this lands in the wrong slot)
	ld a, l
	add SPRITESTATEDATA2_MAPY
	ld l, a
	ld a, c                     ; tile y
	add 4
	ld [hli], a                 ; MAPY, hl -> MAPX
	ld a, b                     ; tile x
	add 4
	ld [hl], a                  ; MAPX
	ret
.disable
	xor a
	ld [hl], a                  ; PICTUREID = 0
	inc l                       ; -> MOVEMENTSTATUS
	ld [hl], a                  ; MOVEMENTSTATUS = 0
	inc l                       ; -> IMAGEINDEX
	ld a, $ff
	ld [hl], a                  ; IMAGEINDEX = $ff
	ret

; ============================================================
; RoomClearState — zero all 14 bytes of room state. TRUE NEW GAME ONLY.
;
; Mandatory, not defensive: SRAM powers up as $FF, and ClearAllSRAMBanks
; (engine/menus/save.asm) explicitly *fills* it with $FF rather than zeroing -
; the same reason InitPlayerData already calls ClearTMBitfield ("so SRAM $FF
; default doesn't grant all TMs") and ClearKeyItemsBitfield. For this feature
; $FF is worse than a wrong-but-legal value: sRoomFurniture $FF gives a TOP
; index of 15 against a 10-entry table and a MIDDLE index of 7 against a
; 6-entry one, and sRoomDecorSlots $FF gives decoration id 255 -> index 254
; into a 21-entry DecorationSpriteTable. All three are out-of-bounds ROM
; reads that stamp garbage blocks and load garbage sprite ids.
;
; All-zero is the intended default state: default furniture, nothing placed,
; nothing owned. No inputs, so safe to farcall.
; ============================================================
RoomClearState::
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ASSERT BANK("Save Data") == 1
	ld a, 1
	ld [rRAMB], a
	; Cleared as one contiguous 14-byte run, so the three must stay adjacent
	; and in this order in ram/sram.asm - same hazard the sKeyItemsBitfield /
	; sKeyItemTiers pairing is commented against there.
	ASSERT sRoomDecorSlots == sRoomFurniture + 2
	ASSERT sRoomOwned == sRoomDecorSlots + 8
	ld hl, sRoomFurniture
	ld b, 14                     ; 2 furniture + 8 slots + 4 owned
	xor a
.clearLoop
	ld [hli], a
	dec b
	jr nz, .clearLoop
	ld hl, sRoomOwnedExt         ; owned bits 32-63, kept apart (see ram/sram.asm)
	ld [hli], a                  ; a is still 0
	ld [hli], a
	ld [hli], a
	ld [hl], a
	ld [rRAMB], a               ; restore the ambient bank-0 selection (see file header)
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ret

; ============================================================
; RoomGrantAllPieces — debug-only: own every room piece. No inputs (safe to
; farcall — a farcall clobbers a via Bankswitch's first instruction).
; ============================================================
RoomGrantAllPieces::
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ASSERT BANK("Save Data") == 1
	ld a, 1
	ld [rRAMB], a
	ld a, $ff
	ld [sRoomOwned], a
	ld [sRoomOwned + 1], a
	ld [sRoomOwned + 2], a
	ld [sRoomOwned + 3], a
	ld hl, sRoomOwnedExt
	ld [hli], a
	ld [hli], a
	ld [hli], a
	ld [hl], $1f                 ; bits 0-60 = all 61 pieces; the last ext byte needs bits 56-60
	xor a
	ld [rRAMB], a               ; restore the ambient bank-0 selection (see file header)
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ret
