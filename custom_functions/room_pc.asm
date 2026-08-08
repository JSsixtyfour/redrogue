; custom_functions/room_pc.asm
;
; The SilphCoDorm room PC: KEY ITEMS / FURNITURE / DECORATIONS / HALL OF FAME
; / LOG OFF. Modelled on engine/menus/players_pc.asm's structure (TextBoxBorder
; + PlaceString + HandleMenuInput cursor struct) and PlayerPCCartridgeSwap's
; farcall-out/return-to-menu template for each option. FURNITURE/DECORATIONS
; option lists reuse RoomDrawPickList (a small single-spaced list renderer;
; the shared bag/vendor list system is item-id-based and doesn't fit a
; non-item option space without fabricating fake item entries).
;
; On log off, RoomStampBlocks + RoomPatchSprites re-apply the (possibly
; changed) state; the actual redraw is left to CloseTextDisplay, which always
; runs InitMapSprites + LoadCurrentMapView afterwards. See the comment at
; .logOff for why no explicit ReloadMapData is needed. Refresh is
; unconditional rather than dirty-flag-gated because WRAM0 has 0 free bytes
; for a flag and it costs nothing at once-per-visit.

SECTION "Room PC", ROMX

DEF ROOM_PC_KEY_ITEMS   EQU 0
DEF ROOM_PC_FURNITURE   EQU 1
DEF ROOM_PC_DECORATIONS EQU 2
DEF ROOM_PC_HOF         EQU 3
DEF ROOM_PC_LOGOFF_NOHOF EQU 3
DEF ROOM_PC_LOGOFF_HOF   EQU 4

; ============================================================
; RoomPC — entry point, farcalled from SilphCoDorm's PC bg_event text_asm.
; ============================================================
RoomPC::
	ld hl, wStatusFlags5
	set BIT_NO_TEXT_DELAY, [hl]
	call SaveScreenTilesToBuffer2

.menu
	call LoadScreenTilesFromBuffer2
	; 2-row-spaced entries: BIT_DOUBLE_SPACED_MENU must be CLEAR (its sense is
	; inverted from its name - see RoomDrawPickList). A prior visit to a
	; single-spaced picker sets it, so it can't be assumed clear on re-entry.
	ldh a, [hUILayoutFlags]
	res BIT_DOUBLE_SPACED_MENU, a
	ldh [hUILayoutFlags], a
	ld a, [wNumHoFTeams]
	and a
	ld a, ROOM_PC_LOGOFF_NOHOF
	jr z, .noHof
	ld a, ROOM_PC_LOGOFF_HOF
.noHof
	ld [wMaxMenuItem], a
	push af
	hlcoord 0, 0
	pop af
	add a                        ; (maxMenuItem+1) rows * 2 (double-spaced) + 2 border
	add 2
	ld b, a
	ld c, 12
	call TextBoxBorder
	call UpdateSprites
	hlcoord 2, 2
	ld de, .KeyItemsString
	call PlaceString
	hlcoord 2, 4
	ld de, .FurnitureString
	call PlaceString
	hlcoord 2, 6
	ld de, .DecorationsString
	call PlaceString
	ld a, [wNumHoFTeams]
	and a
	jr z, .noHofLabel
	hlcoord 2, 8
	ld de, .HallOfFameString
	call PlaceString
	hlcoord 2, 10
	ld de, .LogOffString
	call PlaceString
	jr .inputSetup
.noHofLabel
	hlcoord 2, 8
	ld de, .LogOffString
	call PlaceString
.inputSetup
	xor a
	ldh [hCurrentMenuItem], a
	ld hl, wTopMenuItemY
	ld a, 2
	ld [hli], a                  ; wTopMenuItemY
	dec a
	ld [hli], a                  ; wTopMenuItemX
	inc hl                       ; skip wTileBehindCursor
	ld a, [wMaxMenuItem]
	ld [hli], a                  ; wMaxMenuItem (re-store, already set above)
	ld a, PAD_A | PAD_B
	ld [hli], a                  ; wMenuWatchedKeys
	xor a
	ld [hl], a                   ; wMenuWatchMovingOutOfBounds
	ld hl, wListScrollOffset
	ld [hli], a
	ld [hl], a
	call HandleMenuInput
	call PlaceUnfilledArrowMenuCursor
	bit B_PAD_B, a
	jr nz, .logOff
	ldh a, [hCurrentMenuItem]
	cp ROOM_PC_KEY_ITEMS
	jr nz, .notKeyItems
	ld hl, wMiscFlags
	set BIT_USING_GENERIC_PC, [hl]
	farcall PlayerPC
	res BIT_USING_GENERIC_PC, [hl]
	jp .menu
.notKeyItems
	cp ROOM_PC_FURNITURE
	jr nz, .notFurniture
	call RoomFurnitureMenu
	jp .menu
.notFurniture
	cp ROOM_PC_DECORATIONS
	jr nz, .notDecorations
	call RoomDecorationsMenu
	jp .menu
.notDecorations
	ld a, [wNumHoFTeams]
	and a
	jr z, .logOff                ; HALL OF FAME slot doesn't exist without a HoF entry
	farcall PKMNLeaguePC
	jp .menu
.logOff
	call LoadScreenTilesFromBuffer2
	ld hl, wStatusFlags5
	res BIT_NO_TEXT_DELAY, [hl]
	; Re-apply room state so the changes are visible on the way out. Only the
	; STATE needs updating here, not the screen: RoomPC is farcalled from a
	; text_asm, and CloseTextDisplay (home/text_script.asm) already runs
	; InitMapSprites + LoadCurrentMapView + UpdateSprites once this text script
	; ends - InitMapSprites reloads tile patterns from the PICTUREIDs
	; RoomPatchSprites just wrote, and LoadCurrentMapView rebuilds the screen
	; from the wOverworldMap bytes RoomStampBlocks just wrote. Calling
	; ReloadMapData/ReloadMapSpriteTilePatterns on top of that would only add a
	; second redundant LCD off/on cycle.
	; Unconditional rather than dirty-flag-gated: WRAM0 has 0 free bytes, and
	; this runs once per PC visit, so the cost is irrelevant.
	farcall RoomStampBlocks
	farcall RoomPatchSprites
	ret

.KeyItemsString:
	db "KEY ITEMS@"
.FurnitureString:
	db "FURNITURE@"
.DecorationsString:
	db "DECORATIONS@"
.HallOfFameString:
	db "HALL OF FAME@"
.LogOffString:
	db "LOG OFF@"

; ============================================================
; RoomFurnitureMenu — TOP / MIDDLE / PC / BOTTOM category select, then an
; option picker per category. Writes sRoomFurniture directly.
; ============================================================
DEF ROOM_FURN_TOP    EQU 0
DEF ROOM_FURN_MIDDLE EQU 1
DEF ROOM_FURN_PC     EQU 2
DEF ROOM_FURN_BOTTOM EQU 3

RoomFurnitureMenu:
	call LoadScreenTilesFromBuffer2
	; 2-row-spaced entries; see the note in RoomPC about this bit's inverted
	; sense and why it can't be assumed clear on entry.
	ldh a, [hUILayoutFlags]
	res BIT_DOUBLE_SPACED_MENU, a
	ldh [hUILayoutFlags], a
	hlcoord 0, 0
	ld b, 10
	ld c, 10
	call TextBoxBorder
	call UpdateSprites
	hlcoord 2, 2
	ld de, .TopString
	call PlaceString
	hlcoord 2, 4
	ld de, .MiddleString
	call PlaceString
	hlcoord 2, 6
	ld de, .PcString
	call PlaceString
	hlcoord 2, 8
	ld de, .BottomString
	call PlaceString
	xor a
	ldh [hCurrentMenuItem], a
	ld hl, wTopMenuItemY
	ld a, 2
	ld [hli], a
	dec a
	ld [hli], a
	inc hl
	ld a, 3
	ld [hli], a
	ld a, PAD_A | PAD_B
	ld [hli], a
	xor a
	ld [hl], a
	ld hl, wListScrollOffset
	ld [hli], a
	ld [hl], a
	call HandleMenuInput
	call PlaceUnfilledArrowMenuCursor
	bit B_PAD_B, a
	ret nz
	ldh a, [hCurrentMenuItem]
	cp ROOM_FURN_TOP
	jr nz, .notTop
	call LoadScreenTilesFromBuffer2
	hlcoord 0, 0
	ld b, 10
	ld c, 14
	call TextBoxBorder
	call UpdateSprites
	ld hl, RoomTopNameTable
	ld b, 9
	call RoomDrawPickList
	ret c
	call RoomWriteFurnitureTop
	ret
.notTop
	cp ROOM_FURN_MIDDLE
	jr nz, .notMiddle
	call LoadScreenTilesFromBuffer2
	hlcoord 0, 0
	ld b, 6
	ld c, 14
	call TextBoxBorder
	call UpdateSprites
	ld hl, RoomMiddleNameTable
	ld b, 5
	call RoomDrawPickList
	ret c
	call RoomWriteFurnitureMiddle
	ret
.notMiddle
	cp ROOM_FURN_PC
	jr nz, .notPc
	call LoadScreenTilesFromBuffer2
	hlcoord 0, 0
	ld b, 4
	ld c, 14
	call TextBoxBorder
	call UpdateSprites
	ld hl, RoomPcNameTable
	ld b, 2
	call RoomDrawPickList
	ret c
	call RoomWriteFurniturePc
	ret
.notPc
	; ROOM_FURN_BOTTOM
	call LoadScreenTilesFromBuffer2
	hlcoord 0, 0
	ld b, 4
	ld c, 14
	call TextBoxBorder
	call UpdateSprites
	ld hl, RoomBottomNameTable
	ld b, 2
	call RoomDrawPickList
	ret c
	call RoomWriteFurnitureBottom
	ret

.TopString:
	db "TOP@"
.MiddleString:
	db "MIDDLE@"
.PcString:
	db "PC@"
.BottomString:
	db "BOTTOM@"

RoomTopNameTable:
	dw .Wall, .Bookshelf, .AwardShelf, .Window, .Chalkboard, .Tv, .TvGame, .Map, .Couch
.Wall:        db "WALL@"
.Bookshelf:   db "BOOKSHELF@"
.AwardShelf:  db "AWARD SHELF@"
.Window:      db "WINDOW@"
.Chalkboard:  db "CHALKBOARD@"
.Tv:          db "TV@"
.TvGame:      db "TV/GAME@"
.Map:         db "MAP@"
.Couch:       db "COUCH@"

RoomMiddleNameTable:
	dw .Nothing, .NoteTable, .FlowerTable, .PlainTable, .TvGame
.Nothing:     db "NOTHING@"
.NoteTable:   db "NOTE TABLE@"
.FlowerTable: db "FLOWER TABLE@"
.PlainTable:  db "PLAIN TABLE@"
.TvGame:      db "TV/GAME@"

RoomPcNameTable:
	dw .Desk, .LongDesk
.Desk:     db "DESK@"
.LongDesk: db "LONG DESK@"

RoomBottomNameTable:
	dw .Nothing, .PottedPlant
.Nothing:      db "NOTHING@"
.PottedPlant:  db "POTTED PLANT@"

; a = selected option (0-8); writes into sRoomFurniture byte0 bits0-3
RoomWriteFurnitureTop:
	ld c, a
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ASSERT BANK("Save Data") == 1
	ld a, 1
	ld [rRAMB], a
	ld a, [sRoomFurniture]
	and %11110000
	or c
	ld [sRoomFurniture], a
	xor a
	ld [rRAMB], a               ; restore the ambient bank-0 selection (see file header)
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ret

; a = selected option (0-4); writes into sRoomFurniture byte0 bits4-6
RoomWriteFurnitureMiddle:
	ld c, a
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ASSERT BANK("Save Data") == 1
	ld a, 1
	ld [rRAMB], a
	ld a, c
	swap a                        ; option << 4 (option is 0-4, fits in a nibble)
	ld c, a
	ld a, [sRoomFurniture]
	and %10001111
	or c
	ld [sRoomFurniture], a
	xor a
	ld [rRAMB], a               ; restore the ambient bank-0 selection (see file header)
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ret

; a = selected option (0-1); writes into sRoomFurniture byte0 bit7
RoomWriteFurnitureBottom:
	ld c, a
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ASSERT BANK("Save Data") == 1
	ld a, 1
	ld [rRAMB], a
	ld a, [sRoomFurniture]
	and %01111111
	ld b, a
	ld a, c
	and a
	jr z, .storeBottom
	set 7, b
.storeBottom
	ld a, b
	ld [sRoomFurniture], a
	xor a
	ld [rRAMB], a               ; restore the ambient bank-0 selection (see file header)
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ret

; a = selected option (0-1); writes into sRoomFurniture byte1 bit0
RoomWriteFurniturePc:
	ld c, a
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ASSERT BANK("Save Data") == 1
	ld a, 1
	ld [rRAMB], a
	ld a, [sRoomFurniture + 1]
	and %11111110
	or c
	ld [sRoomFurniture + 1], a
	xor a
	ld [rRAMB], a               ; restore the ambient bank-0 selection (see file header)
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ret

; ============================================================
; RoomDecorationsMenu — BEDSIDE / BOTTOM / TOP / MIDDLE / PC area select.
; MIDDLE/PC may resolve to more than one live slot depending on furniture;
; when so, a small "SPOT 1/2/3" picker runs first. Writes sRoomDecorSlots.
; ============================================================
DEF ROOM_DECOR_BEDSIDE EQU 0
DEF ROOM_DECOR_BOTTOM  EQU 1
DEF ROOM_DECOR_TOP     EQU 2
DEF ROOM_DECOR_MIDDLE  EQU 3
DEF ROOM_DECOR_PC      EQU 4

RoomDecorationsMenu:
	call LoadScreenTilesFromBuffer2
	; 2-row-spaced entries; see the note in RoomPC about this bit's inverted
	; sense and why it can't be assumed clear on entry.
	ldh a, [hUILayoutFlags]
	res BIT_DOUBLE_SPACED_MENU, a
	ldh [hUILayoutFlags], a
	hlcoord 0, 0
	ld b, 12
	ld c, 10
	call TextBoxBorder
	call UpdateSprites
	hlcoord 2, 2
	ld de, .BedsideString
	call PlaceString
	hlcoord 2, 4
	ld de, .BottomString
	call PlaceString
	hlcoord 2, 6
	ld de, .TopString
	call PlaceString
	hlcoord 2, 8
	ld de, .MiddleString
	call PlaceString
	hlcoord 2, 10
	ld de, .PcString
	call PlaceString
	xor a
	ldh [hCurrentMenuItem], a
	ld hl, wTopMenuItemY
	ld a, 2
	ld [hli], a
	dec a
	ld [hli], a
	inc hl
	ld a, 4
	ld [hli], a
	ld a, PAD_A | PAD_B
	ld [hli], a
	xor a
	ld [hl], a
	ld hl, wListScrollOffset
	ld [hli], a
	ld [hl], a
	call HandleMenuInput
	call PlaceUnfilledArrowMenuCursor
	bit B_PAD_B, a
	ret nz
	ldh a, [hCurrentMenuItem]
	cp ROOM_DECOR_BEDSIDE
	jr nz, .notBedside
	ld a, 0
	jp RoomPickDecorationForSlot
.notBedside
	cp ROOM_DECOR_BOTTOM
	jr nz, .notBottom
	ld a, 1
	jp RoomPickDecorationForSlot
.notBottom
	cp ROOM_DECOR_TOP
	jr nz, .notTop
	ld a, 2
	jp RoomPickDecorationForSlot
.notTop
	cp ROOM_DECOR_MIDDLE
	jr nz, .notMiddle
	jp RoomDecorMiddleSpotPicker
.notMiddle
	; ROOM_DECOR_PC
	jp RoomDecorPcSpotPicker

.BedsideString: db "BEDSIDE@"
.BottomString:  db "BOTTOM@"
.TopString:     db "TOP@"
.MiddleString:  db "MIDDLE@"
.PcString:      db "PC@"

; Reads sRoomFurniture's MIDDLE field; 1 live slot (index 3) unless
; FLOWER(2)/PLAIN(3), which have 3 (indices 3,4,5) and need a spot picker.
RoomDecorMiddleSpotPicker:
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ASSERT BANK("Save Data") == 1
	ld a, 1
	ld [rRAMB], a
	ld a, [sRoomFurniture]
	swap a
	and %00000111
	ld c, a
	xor a
	ld [rRAMB], a               ; restore the ambient bank-0 selection (see file header)
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ld a, c
	cp 2
	jr z, .threeSpots
	cp 3
	jr z, .threeSpots
	ld a, 3
	jp RoomPickDecorationForSlot
.threeSpots
	call LoadScreenTilesFromBuffer2
	hlcoord 0, 0
	ld b, 8
	ld c, 10
	call TextBoxBorder
	call UpdateSprites
	ld hl, RoomThreeSpotNameTable
	ld b, 3
	call RoomDrawPickList
	ret c
	add 3                          ; slot index 3, 4 or 5
	jp RoomPickDecorationForSlot

; Reads sRoomFurniture's PC field; 1 live slot (index 6) unless LONG DESK(1),
; which has 2 (indices 6,7) and needs a spot picker.
RoomDecorPcSpotPicker:
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ASSERT BANK("Save Data") == 1
	ld a, 1
	ld [rRAMB], a
	ld a, [sRoomFurniture + 1]
	and 1
	ld c, a
	xor a
	ld [rRAMB], a               ; restore the ambient bank-0 selection (see file header)
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ld a, c
	and a
	jr nz, .twoSpots
	ld a, 6
	jp RoomPickDecorationForSlot
.twoSpots
	call LoadScreenTilesFromBuffer2
	hlcoord 0, 0
	ld b, 6
	ld c, 10
	call TextBoxBorder
	call UpdateSprites
	ld hl, RoomTwoSpotNameTable
	ld b, 2
	call RoomDrawPickList
	ret c
	add 6                          ; slot index 6 or 7
	jp RoomPickDecorationForSlot

RoomThreeSpotNameTable:
	dw .Spot1, .Spot2, .Spot3
.Spot1: db "SPOT 1@"
.Spot2: db "SPOT 2@"
.Spot3: db "SPOT 3@"

RoomTwoSpotNameTable:
	dw .Spot1, .Spot2
.Spot1: db "SPOT 1@"
.Spot2: db "SPOT 2@"

; INPUT: a = sRoomDecorSlots index (0-7). Shows the 11-decoration + NONE
; picker and writes the choice back to that slot.
RoomPickDecorationForSlot:
	push af
	call LoadScreenTilesFromBuffer2
	hlcoord 0, 0
	ld b, 14
	ld c, 14
	call TextBoxBorder
	call UpdateSprites
	ld hl, RoomDecorationNameTable
	ld b, 12
	call RoomDrawPickList
	jr c, .cancelled
	; a = 0 (NONE) or 1-11 (decoration id) - RoomDrawPickList's index already
	; matches sRoomDecorSlots' own encoding (0=empty, 1-11=decoration).
	; Stash it in e (survives the slot-index pop and bc rebuild below - the
	; SRAM-open sequence and the bc/hl addressing math never touch e).
	ld e, a
	pop af                        ; a = slot index
	ld c, a
	ld b, 0
	ld hl, sRoomDecorSlots
	add hl, bc                    ; hl = sRoomDecorSlots + slot index
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ASSERT BANK("Save Data") == 1
	ld a, 1
	ld [rRAMB], a
	ld a, e                       ; a = decoration id
	ld [hl], a
	xor a
	ld [rRAMB], a               ; restore the ambient bank-0 selection (see file header)
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ret
.cancelled
	pop af
	ret

RoomDecorationNameTable:
	dw .None, .Charmeleon, .Pidgey, .Omanyte, .Voltorb, .Clefairy, .Chansey, \
	   .Snorlax, .Pikachu, .Pokedex, .OldAmber, .Seel
.None:       db "NONE@"
.Charmeleon: db "CHARMELEON@"
.Pidgey:     db "PIDGEY@"
.Omanyte:    db "OMANYTE@"
.Voltorb:    db "VOLTORB@"
.Clefairy:   db "CLEFAIRY@"
.Chansey:    db "CHANSEY@"
.Snorlax:    db "SNORLAX@"
.Pikachu:    db "PIKACHU@"
.Pokedex:    db "POKEDEX@"
.OldAmber:   db "OLD AMBER@"
.Seel:       db "SEEL@"

; ============================================================
; RoomDrawPickList — a small single-spaced list picker.
; INPUT: hl = pointer to a table of dw string-pointers, b = entry count.
; OUTPUT: carry set if B pressed (cancelled); else carry clear and a = the
;         0-based selected index. Draws starting at screen (2,2), inside a
;         box the caller has already drawn. Single-spaced (BIT_DOUBLE_SPACED
;         _MENU cleared) so up to ~14 entries fit on one screen - the
;         largest list here (12) fits comfortably, so no scrolling support
;         is implemented.
; ============================================================
RoomDrawPickList:
	call RoomDrawEntries
	xor a
	ldh [hCurrentMenuItem], a
	ld hl, wTopMenuItemY
	ld a, 2
	ld [hli], a
	dec a
	ld [hli], a
	inc hl
	ld a, [wBuffer + 3]
	ld [hli], a                  ; wMaxMenuItem
	ld a, PAD_A | PAD_B
	ld [hli], a
	xor a
	ld [hl], a
	ld hl, wListScrollOffset
	ld [hli], a
	ld [hl], a
	; BIT_DOUBLE_SPACED_MENU's sense is inverted from its name: CLEAR gives a
	; 2-row cursor stride, SET gives 1-row (see PlaceMenuCursor,
	; home/window.asm). This list is drawn 1 row per entry, so the bit must
	; be SET here to match.
	ldh a, [hUILayoutFlags]
	set BIT_DOUBLE_SPACED_MENU, a
	ldh [hUILayoutFlags], a
	call HandleMenuInput
	call PlaceUnfilledArrowMenuCursor
	bit B_PAD_B, a
	jr nz, .cancelled
	ldh a, [hCurrentMenuItem]
	and a
	ret
.cancelled
	scf
	ret

; INPUT: hl = table pointer, b = entry count. Draws single-spaced, screen
; (2,2) downward. Uses wBuffer (transient, this call only) to track the
; remaining-count/row-index since de/hl/bc are all needed for the walk
; itself. Also stashes entry count-1 for RoomDrawPickList's wMaxMenuItem.
RoomDrawEntries:
	ld a, b
	dec a
	ld [wBuffer + 3], a
	ld a, b
	ld [wBuffer], a
	xor a
	ld [wBuffer + 1], a
.loop
	ld a, [hli]
	ld e, a
	ld a, [hli]
	ld d, a                      ; de = string pointer for this entry
	push hl                      ; save table pointer
	ld a, [wBuffer + 1]
	ld [wBuffer + 2], a
	hlcoord 2, 2
.addRowLoop
	ld a, [wBuffer + 2]
	and a
	jr z, .posReady
	dec a
	ld [wBuffer + 2], a
	push de
	ld de, SCREEN_WIDTH
	add hl, de
	pop de
	jr .addRowLoop
.posReady
	call PlaceString
	pop hl                       ; restore table pointer
	ld a, [wBuffer + 1]
	inc a
	ld [wBuffer + 1], a
	ld a, [wBuffer]
	dec a
	ld [wBuffer], a
	jr nz, .loop
	ret
