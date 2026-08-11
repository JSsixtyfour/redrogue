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
	; Descriptions in the text box, through the same PrintBagInfoText cursor
	; hook the option lists use. Two tables, because HALL OF FAME existing
	; shifts LOG OFF's menu index.
	ld hl, RoomPCDescTable
	ld a, [wNumHoFTeams]
	and a
	jr z, .descTableSet
	ld hl, RoomPCDescTableHoF
.descTableSet
	ld a, 2
	call RoomSetPickListOpts
	ld hl, wBagPocketsFlags
	set BIT_ROOM_DESC_BOX, [hl]
	call RoomPrintDescription
	call HandleMenuInput
	ld hl, wBagPocketsFlags
	res BIT_ROOM_DESC_BOX, [hl] ; leaves a alone - it still holds the keys pressed
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
	; Erase the menu box back to the plain text-box screen, and give the
	; VBlank transfer its full three frames to land. AutoBgMapTransfer moves
	; only one third of wTileMap per frame, so doing anything else here before
	; Delay3 leaves the box half-erased on screen.
	call LoadScreenTilesFromBuffer2
	call Delay3
	ld hl, wStatusFlags5
	res BIT_NO_TEXT_DELAY, [hl]
	; Re-apply room state so the changes are visible on the way out.
	; Unconditional rather than dirty-flag-gated: WRAM0 has 0 free bytes, and
	; this runs once per PC visit, so the cost is irrelevant.
	farcall RoomStampBlocks
	farcall RoomPatchSprites
	; Take the window off-screen before anything below rewrites wTileMap, for
	; the same one-third-per-frame reason as above.
	ld a, SCREEN_HEIGHT_PX
	ldh [hWY], a
	call DelayFrame
	; CloseTextDisplay's own InitMapSprites is NOT sufficient here, which is
	; what made freshly-placed decorations render black or as the previous
	; occupant. It runs with BIT_FONT_LOADED still set, and in that mode
	; LoadMapSpriteTilePatterns takes .skipFirstLoad and reloads only the
	; UPPER half of each sprite's VRAM slot (the walking frames) - the text
	; engine only clobbers that half, so restoring it is all vanilla needs.
	; Decorations are STAY sprites drawn purely from the still frames in the
	; LOWER half, which therefore kept whatever PICTUREID occupied the slot at
	; map load. Worse for the 4-tile stills (POKEDEX / OLD AMBER): those take
	; .skipSecondLoad as well, so nothing at all is loaded for them.
	; ReloadMapSpriteTilePatterns clears BIT_FONT_LOADED and reloads both
	; halves with the LCD off, i.e. exactly the load the map-entry path does -
	; which is why re-entering the room always looked correct.
	call ReloadMapSpriteTilePatterns
	; The blocks need RedrawMapView, not LoadCurrentMapView. LoadCurrentMapView
	; only refills wTileMap, which the VBlank transfer sends to vBGMap1 - the
	; WINDOW. The overworld the player sees once the window is hidden is
	; vBGMap0, and nothing writes that except RedrawRowOrColumn (while walking)
	; and RedrawMapView. That is why stamped furniture used to block movement
	; immediately (collision reads wTileMap) yet stay invisible until the
	; player scrolled the map, and why opening any text box appeared to fix it
	; (the window comes back up showing the correct wTileMap).
	farcall RedrawMapView
	call UpdateSprites
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
; Menu order is top-of-room downward: PC, TOP, MIDDLE, BOTTOM. The dispatch
; chain below tests by constant, not by position, so only these values and the
; PlaceString order need to agree.
DEF ROOM_FURN_PC     EQU 0
DEF ROOM_FURN_TOP    EQU 1
DEF ROOM_FURN_MIDDLE EQU 2
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
	ld de, .PcString
	call PlaceString
	hlcoord 2, 4
	ld de, .TopString
	call PlaceString
	hlcoord 2, 6
	ld de, .MiddleString
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
	ld hl, RoomTopDescTable
	ld a, 2
	call RoomSetPickListOpts
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
	ld hl, RoomMiddleDescTable
	ld a, 2
	call RoomSetPickListOpts
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
	ld hl, RoomPcDescTable
	ld a, 2
	call RoomSetPickListOpts
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
	ld hl, RoomBottomDescTable
	ld a, 2
	call RoomSetPickListOpts
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

; Description tables, one dw per entry, parallel to the name tables above.
; Two lines of at most 18 characters, joined by <NEXT>; they are drawn at
; (1,14) and (1,16) inside the standard text box by RoomPrintDescription.

; RoomPC's own top menu. HALL OF FAME only appears once the player has a Hall
; of Fame entry, and its presence pushes LOG OFF from index 3 to 4, so the two
; layouts need separate index tables over the same strings.
RoomPCDescTable:
	dw .KeyItems, .Furniture, .Decorations, .LogOff
.KeyItems:    db "Store or take back<NEXT>your KEY ITEMS.@"
.Furniture:   db "Rearrange the room<NEXT>and its fixtures.@"
.Decorations: db "Set out dolls and<NEXT>keepsakes on show.@"
.HallOfFame:  db "Look back on your<NEXT>past CHAMPIONS.@"
.LogOff:      db "Close the PC.@"

RoomPCDescTableHoF:
	dw RoomPCDescTable.KeyItems, RoomPCDescTable.Furniture, \
	   RoomPCDescTable.Decorations, RoomPCDescTable.HallOfFame, \
	   RoomPCDescTable.LogOff

RoomTopDescTable:
	dw .Wall, .Bookshelf, .AwardShelf, .Window, .Chalkboard, .Tv, .TvGame, \
	   .Map, .Couch
.Wall:        db "Bare wall. Nothing<NEXT>hung up here.@"
.Bookshelf:   db "A shelf stuffed<NEXT>with old books.@"
.AwardShelf:  db "Shows off badges<NEXT>and trophies.@"
.Window:      db "A window with a<NEXT>view outside.@"
.Chalkboard:  db "A wide board for<NEXT>notes and plans.@"
.Tv:          db "A television set<NEXT>up on the wall.@"
.TvGame:      db "A TV with a game<NEXT>console below it.@"
.Map:         db "A KANTO map pinned<NEXT>to the wall.@"
.Couch:       db "A long couch built<NEXT>into the wall.@"

RoomMiddleDescTable:
	dw .Nothing, .NoteTable, .FlowerTable, .PlainTable, .TvGame
.Nothing:     db "Leave the middle<NEXT>of the room open.@"
.NoteTable:   db "A table piled with<NEXT>notes and papers.@"
.FlowerTable: db "A table set with a<NEXT>vase of flowers.@"
.PlainTable:  db "A plain table with<NEXT>room for three.@"
.TvGame:      db "A TV and console<NEXT>set on the floor.@"

RoomPcDescTable:
	dw .Desk, .LongDesk
.Desk:     db "A small desk that<NEXT>holds just the PC.@"
.LongDesk: db "A wide desk with<NEXT>space to display.@"

RoomBottomDescTable:
	dw .Nothing, .PottedPlant
.Nothing:     db "Leave the corner<NEXT>of the room bare.@"
.PottedPlant: db "A leafy plant in<NEXT>a heavy clay pot.@"

RoomDecorationDescTable:
	dw .None, .Charmeleon, .Pidgey, .Omanyte, .Voltorb, .Clefairy, .Chansey, \
	   .Snorlax, .Pikachu, .Pokedex, .OldAmber, .Seel
.None:       db "Clear this spot.@"
.Charmeleon: db "A plush CHARMELEON<NEXT>with a sewn flame.@"
.Pidgey:     db "A soft PIDGEY doll<NEXT>with a bent wing.@"
.Omanyte:    db "A plush OMANYTE.<NEXT>The shell spirals.@"
.Voltorb:    db "A round VOLTORB<NEXT>toy. It smells new.@"
.Clefairy:   db "A CLEFAIRY plush<NEXT>with a star back.@"
.Chansey:    db "A CHANSEY doll<NEXT>with a felt pouch.@"
.Snorlax:    db "A huge SNORLAX<NEXT>pillow for naps.@"
.Pikachu:    db "A PIKACHU plush<NEXT>with worn cheeks.@"
.Pokedex:    db "A display POKEDEX,<NEXT>just for show.@"
.OldAmber:   db "A replica OLD<NEXT>AMBER. A keepsake.@"
.Seel:       db "A plush SEEL with<NEXT>stitched flippers.@"

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
; Same top-of-room-downward order as RoomFurnitureMenu; BEDSIDE has no
; furniture counterpart so it trails the four shared areas.
DEF ROOM_DECOR_PC      EQU 0
DEF ROOM_DECOR_TOP     EQU 1
DEF ROOM_DECOR_MIDDLE  EQU 2
DEF ROOM_DECOR_BOTTOM  EQU 3
DEF ROOM_DECOR_BEDSIDE EQU 4

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
	ld de, .PcString
	call PlaceString
	hlcoord 2, 4
	ld de, .TopString
	call PlaceString
	hlcoord 2, 6
	ld de, .MiddleString
	call PlaceString
	hlcoord 2, 8
	ld de, .BottomString
	call PlaceString
	hlcoord 2, 10
	ld de, .BedsideString
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
	ld hl, 0                     ; spot pickers get no description box
	ld a, 2
	call RoomSetPickListOpts
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
	ld hl, 0                     ; spot pickers get no description box
	ld a, 2
	call RoomSetPickListOpts
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
	; 12 entries is one row too many to sit above the text box at its usual
	; start row, so this list alone starts on row 1 and its box is full width,
	; ending at row 13 - flush against the text box's first text row (14) and
	; covering the box's own top border so the two read as one frame.
	hlcoord 0, 0
	ld b, 12
	ld c, 18
	call TextBoxBorder
	call UpdateSprites
	ld hl, RoomDecorationDescTable
	ld a, 1
	call RoomSetPickListOpts
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
	ld a, [wBuffer + 6]
	ld [hli], a                  ; wTopMenuItemY = the list's first entry row
	ld a, 1
	ld [hli], a                  ; wTopMenuItemX
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
	; Descriptions, if this list has a table: BIT_ROOM_DESC_BOX routes
	; PrintBagInfoText - which HandleMenuInput_ farcalls on every cursor move -
	; to RoomPrintDescription. Draw the first entry's text by hand, since the
	; hook only fires once the cursor actually moves.
	ld a, [wBuffer + 4]
	ld b, a
	ld a, [wBuffer + 5]
	or b
	jr z, .noDescriptions
	ld hl, wBagPocketsFlags
	set BIT_ROOM_DESC_BOX, [hl]
	call RoomPrintDescription
.noDescriptions
	call HandleMenuInput
	ld hl, wBagPocketsFlags
	res BIT_ROOM_DESC_BOX, [hl] ; leaves a alone - it still holds the keys pressed
	call PlaceUnfilledArrowMenuCursor
	bit B_PAD_B, a
	jr nz, .cancelled
	ldh a, [hCurrentMenuItem]
	and a
	ret
.cancelled
	scf
	ret

; ============================================================
; RoomSetPickListOpts — per-list options for the next RoomDrawPickList call.
; INPUT: hl = description string-pointer table (0 = no description box),
;        a  = screen row the first entry is drawn on.
; Passed through wBuffer because RoomDrawPickList already needs hl and b for
; the name table itself; wBuffer + 0..3 are RoomDrawEntries' own scratch.
; ============================================================
RoomSetPickListOpts:
	ld [wBuffer + 6], a
	ld a, l
	ld [wBuffer + 4], a
	ld a, h
	ld [wBuffer + 5], a
	ret

; ============================================================
; RoomPrintDescription — draw the highlighted entry's description into the
; standard text box. Called through PrintBagInfoText (custom_functions/
; tm_bag.asm) while BIT_ROOM_DESC_BOX is set, i.e. on every cursor move, and
; once directly by RoomDrawPickList for the initial entry.
;
; The box itself is the one DisplayTextIDInit already drew for the PC's
; bg_event and that every menu here restores via LoadScreenTilesFromBuffer2,
; so only rows 14-16 need clearing. Strings are two 18-char lines joined by
; <NEXT>, which steps down 2 rows while BIT_SINGLE_SPACED_LINES is clear.
; ============================================================
RoomPrintDescription::
	hlcoord 1, 14
	ld b, 3
	ld c, SCREEN_WIDTH - 2
	call ClearScreenArea
	ld a, [wBuffer + 4]
	ld l, a
	ld a, [wBuffer + 5]
	ld h, a
	ldh a, [hCurrentMenuItem]
	add a                        ; dw-sized table entries
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hli]
	ld e, a
	ld d, [hl]
	hlcoord 1, 14
	jp PlaceString

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
	ld a, [wBuffer + 6]          ; first entry's row
	ld hl, wBuffer + 1
	add [hl]                     ; + this entry's index
	ld [wBuffer + 2], a
	hlcoord 2, 0
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
