; custom_functions/room_vendor.asm
;
; The Credit Exchange's third vendor (CREDIT_VENDOR_ROOMS) - sells room
; furniture/decoration pieces for Credits (wPlayerCoins). Reuses
; custom_functions/room_pc.asm's RoomDrawPickList for both the category and
; item pickers, and ram/sram.asm's sRoomOwned bitfield as the source of
; truth for what's already owned. Deliberately does not reuse
; engine/events/credit_mart.asm's item-based purchase flow (LoadCreditPriceOf
; CurItem, GiveItem, etc.) since room pieces are not real items - only the
; generic, non-item-specific pieces (HasEnoughCoins, predef SubBCDPredef) are
; shared.
;
; Piece ids (0-60) match the owned bit layout exactly: 0-7 = TOP options
; 1-8, 8 = LONG DESK, 9-12 = MIDDLE options 1-4, 13 = POTTED PLANT,
; 14-24 = decorations 1-11, 25 = TOP 9 (DINOSAUR POSTER), 26 = MIDDLE 5
; (SPACESHIP), 27-60 = decorations 12-45 (32+ live in sRoomOwnedExt).
; Later pieces take the next free bit rather than renumbering, so owned
; bits in existing saves keep their meaning; each category's
; *Ids table maps its rows to bits. The four defaults (WALL/DESK/NOTHING/
; NOTHING) are option 0 of each category and are never sold - always free.

SECTION "Room Vendor", ROMX

DEF ROOM_VENDOR_TOP    EQU 0
DEF ROOM_VENDOR_MIDDLE EQU 1
DEF ROOM_VENDOR_DESK   EQU 2
DEF ROOM_VENDOR_PLANT  EQU 3
DEF ROOM_VENDOR_PALS   EQU 4

; ============================================================
; RoomVendorMenu — farcall'd from engine/events/credit_mart.asm's
; CreditVendorMenu when hTextID resolves to CREDIT_VENDOR_ROOMS.
; ============================================================
RoomVendorMenu::
	ld hl, wStatusFlags5
	set BIT_NO_TEXT_DELAY, [hl]
	call SaveScreenTilesToBuffer2

.menu
	call LoadScreenTilesFromBuffer2
	; 2-row-spaced category entries; see room_pc.asm's RoomPC for why this
	; bit's sense (inverted from its name) can't be assumed clear on entry.
	ldh a, [hUILayoutFlags]
	res BIT_DOUBLE_SPACED_MENU, a
	ldh [hUILayoutFlags], a
	hlcoord 0, 0
	ld b, 10
	ld c, 14
	call TextBoxBorder
	call UpdateSprites
	hlcoord 2, 2
	ld de, .TopString
	call PlaceString
	hlcoord 2, 4
	ld de, .MiddleString
	call PlaceString
	hlcoord 2, 6
	ld de, .DeskString
	call PlaceString
	hlcoord 2, 8
	ld de, .PlantString
	call PlaceString
	hlcoord 2, 10
	ld de, .PalsString
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
	jr nz, .exit
	ldh a, [hCurrentMenuItem]
	cp ROOM_VENDOR_TOP
	jr nz, .notTop
	ld hl, RoomVendorTopNames
	ld de, RoomVendorTopPrices
	ld bc, RoomVendorTopIds
	call RoomVendorCategory
	jp .menu
.notTop
	cp ROOM_VENDOR_MIDDLE
	jr nz, .notMiddle
	ld hl, RoomVendorMiddleNames
	ld de, RoomVendorMiddlePrices
	ld bc, RoomVendorMiddleIds
	call RoomVendorCategory
	jp .menu
.notMiddle
	cp ROOM_VENDOR_DESK
	jr nz, .notDesk
	ld hl, RoomVendorDeskNames
	ld de, RoomVendorDeskPrices
	ld bc, RoomVendorDeskIds
	call RoomVendorCategory
	jp .menu
.notDesk
	cp ROOM_VENDOR_PLANT
	jr nz, .notPlant
	ld hl, RoomVendorPlantNames
	ld de, RoomVendorPlantPrices
	ld bc, RoomVendorPlantIds
	call RoomVendorCategory
	jp .menu
.notPlant
	; ROOM_VENDOR_PALS
	ld hl, RoomVendorPalsNames
	ld de, RoomVendorPalsPrices
	ld bc, RoomVendorPalsIds
	call RoomVendorCategory
	jp .menu
.exit
	ld hl, wStatusFlags5
	res BIT_NO_TEXT_DELAY, [hl]
	ret

.TopString:    db "TOP@"
.MiddleString: db "MIDDLE@"
.DeskString:   db "DESK@"
.PlantString:  db "PLANT@"
.PalsString:   db "PALS@"

; ============================================================
; RoomVendorCategory — show one category's pieces, handle the purchase.
; INPUT: hl = name table (dw per piece), de = price table (bcd2 per piece),
;        bc = piece-id table (a count byte, then one sRoomOwned bit per piece).
; This category state lives at wBuffer + 8..13, clear of RoomDrawPickList's
; + 0..6 (RoomDrawEntries' scratch plus RoomSetPickListOpts' row and
; description pointer). Sharing + 4..6 drew these lists at the owned-bit
; base's row and printed price bytes as descriptions.
; ============================================================
RoomVendorCategory:
	ld a, e
	ld [wBuffer + 10], a
	ld a, d
	ld [wBuffer + 11], a         ; price table pointer
	ld a, c
	ld [wBuffer + 12], a
	ld a, b
	ld [wBuffer + 13], a         ; piece-id table pointer
	ld a, [bc]
	ld b, a                      ; b = piece count
	push hl
	push bc
	hlcoord 0, 0
	ld b, 12
	ld c, 16                     ; wide enough for "DINOSAUR POSTER" (15 chars from col 2)
	call TextBoxBorder
	call UpdateSprites
	ld hl, 0                     ; no description box
	ld a, 2
	call RoomSetPickListOpts
	pop bc
	pop hl
	call RoomDrawPickList
	ret c                        ; cancelled
	ld [wBuffer + 8], a          ; category-relative index
	ld a, [wBuffer + 12]
	ld l, a
	ld a, [wBuffer + 13]
	ld h, a
	inc hl                       ; skip the count byte
	ld a, [wBuffer + 8]
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hl]
	ld [wBuffer + 9], a          ; piece id
	ld c, a
	call RoomIsPieceOwned
	jr nc, .notOwned
	ld hl, .AlreadyOwnedText
	jp PrintText
.notOwned
	ld a, [wBuffer + 10]
	ld l, a
	ld a, [wBuffer + 11]
	ld h, a                      ; hl = price table base
	ld a, [wBuffer + 8]
	add a
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hli]
	ldh [hCoins], a
	ld a, [hl]
	ldh [hCoins + 1], a
	call HasEnoughCoins
	jr c, .notEnough
	ld hl, .ConfirmText
	call PrintText
	call YesNoChoice              ; saves/restores its own screen tiles
	ldh a, [hCurrentMenuItem]
	and a
	ret nz                        ; declined
	ld hl, hCoins + 1
	ld de, wPlayerCoins + 1
	ld c, 2
	predef SubBCDPredef
	ld a, [wBuffer + 9]
	call RoomSetPieceOwned
	ld a, SFX_PURCHASE
	call PlaySoundWaitForCurrent
	call WaitForSoundToFinish
	ld hl, .BoughtText
	jp PrintText
.notEnough
	ld hl, .NotEnoughText
	jp PrintText

.AlreadyOwnedText:
	text_far _RoomVendorAlreadyOwnedText
	text_waitbutton
	text_end
.ConfirmText:
	text_far _RoomVendorConfirmText
	text_end
.BoughtText:
	text_far _RoomVendorBoughtText
	text_waitbutton
	text_end
.NotEnoughText:
	text_far _RoomVendorNotEnoughText
	text_waitbutton
	text_end

; ============================================================
; RoomIsPieceOwned — INPUT: c = piece id (0-60). OUTPUT: carry set if owned.
; RoomSetPieceOwned — INPUT: a = piece id (0-60). Sets the owned bit.
; Both address sRoomOwned (ram/sram.asm, "Save Data" section, bank 1) as a
; byte-index/bit-index pair via RoomBitMasks rather than a shift loop.
; ============================================================
RoomIsPieceOwned:
	ld a, c
	and %00000111
	ld e, a
	ld d, 0
	push de                      ; [bitIndex]
	ld a, c
	srl a
	srl a
	srl a                        ; a = byte index (0-7)
	call RoomOwnedByteAddr
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ASSERT BANK("Save Data") == 1
	ld a, 1
	ld [rRAMB], a
	ld a, [hl]                   ; a = the byte
	ld b, a                      ; stash across the SRAM close
	xor a
	ld [rRAMB], a               ; restore the ambient bank-0 selection (see file header)
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	pop de                       ; de = {0, bitIndex}
	ld hl, RoomBitMasks
	add hl, de
	ld a, [hl]                   ; a = bit mask
	and b
	ret z                        ; not owned - carry already clear (AND resets it)
	scf
	ret

RoomSetPieceOwned:
	ld c, a
	and %00000111
	ld e, a
	ld d, 0
	push de                      ; [bitIndex]
	ld a, c
	srl a
	srl a
	srl a                        ; a = byte index (0-7)
	call RoomOwnedByteAddr
	pop de
	push hl                      ; [byteAddr]
	ld hl, RoomBitMasks
	add hl, de
	ld a, [hl]                   ; a = bit mask
	pop hl                       ; hl = byteAddr
	ld b, a
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ASSERT BANK("Save Data") == 1
	ld a, 1
	ld [rRAMB], a
	ld a, [hl]
	or b
	ld [hl], a
	xor a
	ld [rRAMB], a               ; restore the ambient bank-0 selection (see file header)
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ret

; a = owned byte index (0-7) -> hl = its SRAM address. Clobbers a, de.
; Bytes 0-3 are sRoomOwned; bytes 4-7 (piece ids 32-63) are sRoomOwnedExt,
; which ram/sram.asm keeps apart so no other SRAM field had to move.
RoomOwnedByteAddr:
	ld hl, sRoomOwned
	cp 4
	jr c, .gotBase
	sub 4
	ld hl, sRoomOwnedExt
.gotBase
	ld e, a
	ld d, 0
	add hl, de
	ret

RoomBitMasks:
	db %00000001, %00000010, %00000100, %00001000
	db %00010000, %00100000, %01000000, %10000000

; ============================================================
; Category data: names + bcd2 prices + piece ids, one row per piece.
; ============================================================
RoomVendorTopNames:
	dw .Bookshelf, .AwardShelf, .Window, .Chalkboard, .Tv, .TvGame, .Map, .Couch, \
	   .DinoPoster
.Bookshelf:  db "BOOKSHELF@"
.AwardShelf: db "AWARD SHELF@"
.Window:     db "WINDOW@"
.Chalkboard: db "CHALKBOARD@"
.Tv:         db "TV@"
.TvGame:     db "TV/GAME@"
.Map:        db "MAP@"
.Couch:      db "COUCH@"
.DinoPoster: db "DINOSAUR POSTER@"
RoomVendorTopPrices:
	bcd2 10
	bcd2 15
	bcd2 10
	bcd2 15
	bcd2 20
	bcd2 30
	bcd2 10
	bcd2 25
	bcd2 15
RoomVendorTopIds:
	db 9
	db 0, 1, 2, 3, 4, 5, 6, 7, 25

RoomVendorMiddleNames:
	dw .NoteTable, .FlowerTable, .PlainTable, .TvGame, .Spaceship
.NoteTable:   db "NOTE TABLE@"
.FlowerTable: db "FLOWER TABLE@"
.PlainTable:  db "PLAIN TABLE@"
.TvGame:      db "TV/GAME@"
.Spaceship:   db "SPACESHIP@"
RoomVendorMiddlePrices:
	bcd2 15
	bcd2 15
	bcd2 10
	bcd2 25
	bcd2 25
RoomVendorMiddleIds:
	db 5
	db 9, 10, 11, 12, 26

RoomVendorDeskNames:
	dw .LongDesk
.LongDesk: db "LONG DESK@"
RoomVendorDeskPrices:
	bcd2 20
RoomVendorDeskIds:
	db 1
	db 8

RoomVendorPlantNames:
	dw .PottedPlant
.PottedPlant: db "POTTED PLANT@"
RoomVendorPlantPrices:
	bcd2 5
RoomVendorPlantIds:
	db 1
	db 13

RoomVendorPalsNames:
	dw .Charmeleon, .Pidgey, .Omanyte, .Voltorb, .Clefairy, .Chansey, \
	   .Snorlax, .Pikachu, .Pokedex, .OldAmber, .Seel, .Doduo, .Psyduck, \
	   .Nidorino, .Kabuto, .Spearow, .Cubone, .Articuno, .Zapdos, .Moltres, .Mewtwo, \
	   .Fearow, .Kangaskhan, .Lapras, .Machop, .Mew, .NidoranF, .Pidgey2, .Slowpoke, \
	   .Vaporeon, .Bulbasaur, .Clefairy2, .Jigglypuff, .Machoke, .Meowth, .MrMime, \
	   .NidoranM, .Oddish, .Pidgeot, .Poliwrath, .Sandshrew, .Seel2, .Jolteon, \
	   .Flareon, .Wigglytuff
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
.Doduo:      db "DODUO@"
.Psyduck:    db "PSYDUCK@"
.Nidorino:   db "NIDORINO@"
.Kabuto:     db "KABUTO@"
.Spearow:    db "SPEAROW@"
.Cubone:     db "CUBONE@"
.Articuno:   db "ARTICUNO@"
.Zapdos:     db "ZAPDOS@"
.Moltres:    db "MOLTRES@"
.Mewtwo:     db "MEWTWO@"
.Fearow:     db "FEAROW@"
.Kangaskhan: db "KANGASKHAN@"
.Lapras:     db "LAPRAS@"
.Machop:     db "MACHOP@"
.Mew:        db "MEW@"
.NidoranF:   db "NIDORAN F@"
.Pidgey2:    db "PIDGEY@"
.Slowpoke:   db "SLOWPOKE@"
.Vaporeon:   db "VAPOREON@"
.Bulbasaur:  db "BULBASAUR@"
.Clefairy2:  db "CLEFAIRY@"
.Jigglypuff: db "JIGGLYPUFF@"
.Machoke:    db "MACHOKE@"
.Meowth:     db "MEOWTH@"
.MrMime:     db "MR. MIME@"
.NidoranM:   db "NIDORAN M@"
.Oddish:     db "ODDISH@"
.Pidgeot:    db "PIDGEOT@"
.Poliwrath:  db "POLIWRATH@"
.Sandshrew:  db "SANDSHREW@"
.Seel2:      db "SEEL@"
.Jolteon:    db "JOLTEON@"
.Flareon:    db "FLAREON@"
.Wigglytuff: db "WIGGLYTUFF@"
; Tiered by how rare the Pokemon is: 10 common basics, 15 uncommon, 20 evolved
; and fossils, 25 prized, 30 rare, 40 legendary birds, 50 Mewtwo and Mew.
RoomVendorPalsPrices:
	bcd2 20 ; CHARMELEON
	bcd2 10 ; PIDGEY
	bcd2 20 ; OMANYTE
	bcd2 10 ; VOLTORB
	bcd2 15 ; CLEFAIRY
	bcd2 25 ; CHANSEY
	bcd2 30 ; SNORLAX
	bcd2 25 ; PIKACHU
	bcd2 10 ; POKEDEX
	bcd2 25 ; OLD AMBER
	bcd2 15 ; SEEL
	bcd2 10 ; DODUO
	bcd2 10 ; PSYDUCK
	bcd2 20 ; NIDORINO
	bcd2 20 ; KABUTO
	bcd2 10 ; SPEAROW
	bcd2 15 ; CUBONE
	bcd2 40 ; ARTICUNO
	bcd2 40 ; ZAPDOS
	bcd2 40 ; MOLTRES
	bcd2 50 ; MEWTWO
	bcd2 20 ; FEAROW
	bcd2 25 ; KANGASKHAN
	bcd2 30 ; LAPRAS
	bcd2 10 ; MACHOP
	bcd2 50 ; MEW
	bcd2 10 ; NIDORAN F
	bcd2 10 ; PIDGEY
	bcd2 15 ; SLOWPOKE
	bcd2 25 ; VAPOREON
	bcd2 15 ; BULBASAUR
	bcd2 15 ; CLEFAIRY
	bcd2 15 ; JIGGLYPUFF
	bcd2 20 ; MACHOKE
	bcd2 10 ; MEOWTH
	bcd2 15 ; MR. MIME
	bcd2 10 ; NIDORAN M
	bcd2 10 ; ODDISH
	bcd2 20 ; PIDGEOT
	bcd2 20 ; POLIWRATH
	bcd2 10 ; SANDSHREW
	bcd2 15 ; SEEL2
	bcd2 25 ; JOLTEON
	bcd2 25 ; FLAREON
	bcd2 20 ; WIGGLYTUFF
RoomVendorPalsIds:
	db 45
	db 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24
	db 27, 28, 29, 30, 31, 32, 33, 34, 35, 36
	db 37, 38, 39, 40, 41, 42, 43, 44
	db 45, 46, 47, 48, 49, 50, 51, 52, 53, 54
	db 55, 56, 57, 58, 59, 60
