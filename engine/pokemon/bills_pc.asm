DisplayPCMainMenu::
	xor a
	ldh [hAutoBGTransferEnabled], a
	call SaveScreenTilesToBuffer2
	ld a, [wNumHoFTeams]
	and a
	jr nz, .leaguePCAvailable
	CheckEvent EVENT_GOT_POKEDEX
	jr z, .noOaksPC
	ld a, [wNumHoFTeams]
	and a
	jr nz, .leaguePCAvailable
	hlcoord 0, 0
	ld b, 8
	ld c, 14
	jr .next
.noOaksPC
	hlcoord 0, 0
	ld b, 6
	ld c, 14
	jr .next
.leaguePCAvailable
	hlcoord 0, 0
	ld b, 10
	ld c, 14
.next
	call TextBoxBorder
	call UpdateSprites
	ld a, 3
	ld [wMaxMenuItem], a
	hlcoord 2, 2
	ld de, BillsPCText
.next2
	call PlaceString
	hlcoord 2, 4
	ld de, wPlayerName
	call PlaceString
	ld l, c
	ld h, b
	ld de, PlayersPCText
	call PlaceString
	CheckEvent EVENT_GOT_POKEDEX
	jr z, .noOaksPC2
	hlcoord 2, 6
	ld de, OaksPCText
	call PlaceString
	ld a, [wNumHoFTeams]
	and a
	jr z, .noLeaguePC
	ld a, 4
	ld [wMaxMenuItem], a
	hlcoord 2, 8
	ld de, PKMNLeaguePCText
	call PlaceString
	hlcoord 2, 10
	ld de, LogOffPCText
	jr .next3
.noLeaguePC
	hlcoord 2, 8
	ld de, LogOffPCText
	jr .next3
.noOaksPC2
	ld a, $2
	ld [wMaxMenuItem], a
	hlcoord 2, 6
	ld de, LogOffPCText
.next3
	call PlaceString
	ld a, PAD_A | PAD_B
	ld [wMenuWatchedKeys], a
	ld a, 2
	ld [wTopMenuItemY], a
	ld a, 1
	ld [wTopMenuItemX], a
	xor a
	ldh [hCurrentMenuItem], a
	ld [wLastMenuItem], a
	ld a, 1
	ldh [hAutoBGTransferEnabled], a
	ret

SomeonesPCText:   db "SOMEONE's PC@"
BillsPCText:      db "BILL's PC@"
PlayersPCText:    db "'s PC@"
OaksPCText:       db "PROF.OAK's PC@"
PKMNLeaguePCText: db "<PKMN>LEAGUE@"
LogOffPCText:     db "LOG OFF@"

DEF BILLS_PC_BOX_COLUMNS EQU 5
DEF BILLS_PC_BOX_ROWS    EQU 4

; Yume's 5x4 BG-icon storage screen, reconciled with Red Rogue's compact box
; representation. Party slots are 0..5 and box slots are 6..25. Box mutations
; continue through MoveMon/RemovePokemon so fusion and variant data follow the
; established project paths and wBoxSpecies remains compact and $ff-terminated.
BillsPC_::
	ld hl, wStatusFlags5
	set BIT_NO_TEXT_DELAY, [hl]
	xor a
	ld [wParentMenuItem], a
	inc a ; MONSTER_NAME
	ld [wNameListType], a
	call LoadHpBarAndStatusTilePatterns

	ld a, [wListScrollOffset]
	push af
	ldh a, [hUpdateSpritesEnabled]
	push af
	xor a
	ldh [hUpdateSpritesEnabled], a

	ld a, [wMiscFlags]
	bit BIT_USING_GENERIC_PC, a
	jr nz, .loadGrid
	ld a, SFX_TURN_ON_PC
	call PlaySound
	ld hl, SwitchOnText
	call PrintText

.loadGrid
	call GBPalWhiteOutWithDelay3
	call ClearScreen
	; DisplayChangeBoxMenu marks non-empty boxes with tile $78.
	ld hl, vChars2 tile $78
	ld de, PokeballTileGraphics
	lb bc, BANK(PokeballTileGraphics), 1
	call CopyVideoData
	xor a
	ldh [hCurrentMenuItem], a
	ld [wLastMenuItem], a
	ld [wPartyAndBillsPCSavedMenuItem], a
	call RedrawBillsPCBoxScreen
	call WaitBillsPCButtonsReleased

.inputLoop
	call JoypadLowSensitivity
	ldh a, [hJoy5]
	and a
	jr z, .inputLoop
	ld b, a
	bit B_PAD_B, b
	jp nz, ExitBillsPC
	bit B_PAD_START, b
	jr nz, .changeBox
	bit B_PAD_A, b
	jr nz, .chooseMon
	bit B_PAD_LEFT, b
	jr nz, .left
	bit B_PAD_RIGHT, b
	jr nz, .right
	bit B_PAD_UP, b
	jr nz, .up
	bit B_PAD_DOWN, b
	jr z, .inputLoop
	call MoveBillsPCCursorDown
	jr .inputLoop

.up
	call MoveBillsPCCursorUp
	jr .inputLoop

.left
	call MoveBillsPCCursorLeft
	jr .inputLoop

.right
	call MoveBillsPCCursorRight
	jr .inputLoop

.changeBox
	ld a, SFX_PRESS_AB
	call PlaySound
	ldh a, [hCurrentMenuItem]
	push af
	ld hl, wStatusFlags5
	res BIT_NO_TEXT_DELAY, [hl]
	farcall ChangeBox
	ld hl, wStatusFlags5
	set BIT_NO_TEXT_DELAY, [hl]
	pop af
	ldh [hCurrentMenuItem], a
	ld [wLastMenuItem], a
	ld [wPartyAndBillsPCSavedMenuItem], a
	call RedrawBillsPCBoxScreen
	call WaitBillsPCButtonsReleased
	jr .inputLoop

.chooseMon
	ldh a, [hCurrentMenuItem]
	cp PARTY_LENGTH
	jp c, .partyActionMenu
	sub PARTY_LENGTH
	call BillsPCBoxSlotHasMon
	jp z, .emptyBoxSlot

	; Box submenu: WITHDRAW / STATS / RELEASE / CANCEL.
	ldh a, [hCurrentMenuItem]
	ld [wPartyAndBillsPCSavedMenuItem], a
	call DrawBillsPCSelectedCursor
	hlcoord 9, 9
	lb bc, 7, 9
	call TextBoxBorder
	hlcoord 11, 10
	ld de, WithdrawPCText
	call PlaceString
	hlcoord 11, 12
	ld de, StatsPCText
	call PlaceString
	hlcoord 11, 14
	ld de, ReleasePCText
	call PlaceString
	hlcoord 11, 16
	ld de, CancelPCText
	call PlaceString
	ld hl, wTopMenuItemY
	ld a, 10
	ld [hli], a
	ld a, 10
	ld [hli], a
	xor a
	ldh [hCurrentMenuItem], a
	inc hl ; wTileBehindCursor
	ld a, 3
	ld [hli], a ; wMaxMenuItem
	ld a, PAD_A | PAD_B
	ld [hli], a ; wMenuWatchedKeys
	xor a
	ld [hl], a ; wLastMenuItem
	call HandleMenuInput
	ld b, a
	ldh a, [hCurrentMenuItem]
	ld c, a
	ld a, [wPartyAndBillsPCSavedMenuItem]
	ldh [hCurrentMenuItem], a
	ld [wLastMenuItem], a
	bit B_PAD_B, b
	jp nz, .redrawAfterChoice
	ld a, c
	and a
	jr nz, .boxStatsOption
	call WithdrawBillsPCSelectedBoxMon
	jp .redrawAfterChoice

.boxStatsOption
	dec a
	jr nz, .boxReleaseOption
	ld a, [wPartyAndBillsPCSavedMenuItem]
	sub PARTY_LENGTH
	call BillsPCBoxSlotHasMon
	jp z, .redrawAfterChoice
	ld [wCurPartySpecies], a
	ld a, c
	ldh [hWhichPokemon], a
	ld a, BOX_DATA
	ld [wMonDataLocation], a
	call ClearSprites
	predef StatusScreen
	predef StatusScreen2
	ld a, [wPartyAndBillsPCSavedMenuItem]
	ldh [hCurrentMenuItem], a
	ld [wLastMenuItem], a
	jp .redrawAfterChoice

.boxReleaseOption
	dec a
	jp nz, .redrawAfterChoice
	call ReleaseBillsPCSelectedBoxMon
	jp .redrawAfterChoice

.emptyBoxSlot
	call WaitBillsPCButtonsReleased
	xor a
	ldh [hFrameCounter], a
	jp .inputLoop

.partyActionMenu
	; Party submenu: DEPOSIT / STATS / CANCEL.
	ldh a, [hCurrentMenuItem]
	ld [wPartyAndBillsPCSavedMenuItem], a
	call DrawBillsPCSelectedCursor
	hlcoord 9, 11
	lb bc, 5, 9
	call TextBoxBorder
	hlcoord 11, 12
	ld de, DepositPCText
	call PlaceString
	hlcoord 11, 14
	ld de, StatsPCText
	call PlaceString
	hlcoord 11, 16
	ld de, CancelPCText
	call PlaceString
	ld hl, wTopMenuItemY
	ld a, 12
	ld [hli], a
	ld a, 10
	ld [hli], a
	xor a
	ldh [hCurrentMenuItem], a
	inc hl ; wTileBehindCursor
	ld a, 2
	ld [hli], a ; wMaxMenuItem
	ld a, PAD_A | PAD_B
	ld [hli], a ; wMenuWatchedKeys
	xor a
	ld [hl], a ; wLastMenuItem
	call HandleMenuInput
	ld b, a
	ldh a, [hCurrentMenuItem]
	ld c, a
	ld a, [wPartyAndBillsPCSavedMenuItem]
	ldh [hCurrentMenuItem], a
	ld [wLastMenuItem], a
	bit B_PAD_B, b
	jr nz, .redrawAfterChoice
	ld a, c
	and a
	jr nz, .partyStatsOption
	call DepositBillsPCSelectedPartyMon
	jr .redrawAfterChoice

.partyStatsOption
	dec a
	jr nz, .redrawAfterChoice
	ld a, [wPartyAndBillsPCSavedMenuItem]
	ldh [hWhichPokemon], a
	ld c, a
	ld b, 0
	ld hl, wPartySpecies
	add hl, bc
	ld a, [hl]
	ld [wCurPartySpecies], a
	xor a ; PLAYER_PARTY_DATA
	ld [wMonDataLocation], a
	call ClearSprites
	predef StatusScreen
	predef StatusScreen2
	ld a, [wPartyAndBillsPCSavedMenuItem]
	ldh [hCurrentMenuItem], a
	ld [wLastMenuItem], a

.redrawAfterChoice
	call RedrawBillsPCBoxScreen
	call WaitBillsPCButtonsReleased
	jp .inputLoop

ExitBillsPC:
	call GBPalWhiteOutWithDelay3
	ld hl, wMiscFlags
	res BIT_NO_MENU_BUTTON_SOUND, [hl]
	call ReloadTilesetTilePatterns
	call LoadScreenTilesFromBuffer2
	call RunDefaultPaletteCommand
	call GBPalNormal

	ld a, [wMiscFlags]
	bit BIT_USING_GENERIC_PC, a
	jr nz, .restoreState
	ld a, SFX_TURN_OFF_PC
	call PlaySound
	call WaitForSoundToFinish

.restoreState
	xor a
	ldh [hCurrentMenuItem], a
	ld [wLastMenuItem], a
	ld [wPartyAndBillsPCSavedMenuItem], a
	ldh [hWhichPokemon], a
	ld [wPlayerMonNumber], a
	ld [wMonDataLocation], a

	pop af
	ldh [hUpdateSpritesEnabled], a
	pop af
	ld [wListScrollOffset], a
	ld hl, wStatusFlags5
	res BIT_NO_TEXT_DELAY, [hl]
	ret

RedrawBillsPCBoxScreen:
	call RedrawBillsPCBoxScreenCommon
	call DrawBillsPCCursor
	jr FinishRedrawingBillsPCBoxScreen

RedrawBillsPCBoxScreenForSelectedMessage:
	call PrepareBillsPCSelectedRedraw
	jr FinishRedrawingBillsPCBoxScreen

PrepareBillsPCSelectedRedraw:
	call RedrawBillsPCBoxScreenCommon
	call DrawBillsPCCursorOnly
	call DrawBillsPCSelectedCursor
	jp ClearBillsPCInfoText

RedrawBillsPCBoxScreenCommon:
	xor a
	ldh [hAutoBGTransferEnabled], a
	call LoadBillsPCBoxIconTilePatterns
	call ClearScreen
	call ClearSprites

	; Boxed-mon 5x4 grid and lower information text box.
	hlcoord 3, 0
	lb bc, 8, 15
	call TextBoxBorder
	hlcoord 0, 12
	lb bc, 4, 18
	call TextBoxBorder
	hlcoord 10, 0
	ld de, BillsPCChangeBoxText
	call PlaceString
	call DrawBillsPCPartyMons
	jp DrawBillsPCBoxMons

FinishRedrawingBillsPCBoxScreen:
	ld a, 1
	ldh [hAutoBGTransferEnabled], a
	call ApplyBillsPCBoxPalette
	jp Delay3

ApplyBillsPCBoxPalette:
	; InitCGBPalettes transforms base colors through the live DMG registers.
	; Initial entry follows a whiteout (rBGP = $00), while message redraws follow
	; text rendering (rBGP = $e4). Normalize the register without transferring
	; the previous CGB palette, which would create a visible one-frame flash.
	ld a, %11100100
	ldh [rBGP], a
	; The palette bank is effectively full, so keep these screen-specific
	; packets with Bill's PC and copy them to WRAM before crossing banks.
	ld hl, BillsPCPalPacket
	ld de, wTextBoxBuffer
	ld bc, BillsPCBlkPacketEnd - BillsPCPalPacket
	call CopyData
	; Bankswitch destroys hl but preserves de. The palette-bank wrapper restores
	; the fixed palette pointer while this carries the following ATTR_BLK packet.
	ld de, wTextBoxBuffer + (BillsPCPalPacketEnd - BillsPCPalPacket)
	farcall SendBillsPCPackets
	jp GBPalNormal

BillsPCPalPacket:
	db $51 ; PAL_SET, one 16-byte packet
	dw PAL_GRAYMON, PAL_BILLS_PC, PAL_GRAYMON, PAL_GRAYMON
	ds 7, 0
BillsPCPalPacketEnd:

BillsPCBlkPacket:
	db $22, 3 ; ATTR_BLK, three data sets
	db %011, 0, 00,00, 19,17
	db %011, 5, 01,00, 02,11
	db %011, 5, 05,01, 18,08
	ds 12, 0
BillsPCBlkPacketEnd:

WaitBillsPCButtonsReleased:
	call Joypad
	ldh a, [hJoyHeld]
	and PAD_A | PAD_B | PAD_START
	jr nz, WaitBillsPCButtonsReleased
	xor a
	ldh [hJoy5], a
	ldh [hJoyPressed], a
	ret

MoveBillsPCCursorUp:
	ldh a, [hCurrentMenuItem]
	cp PARTY_LENGTH
	jr nc, .notParty
	and a
	ret z
	dec a
	ldh [hCurrentMenuItem], a
	jp DrawBillsPCCursor
.notParty
	sub PARTY_LENGTH
	cp BILLS_PC_BOX_COLUMNS
	ret c
	sub BILLS_PC_BOX_COLUMNS
	add PARTY_LENGTH
	ldh [hCurrentMenuItem], a
	jr DrawBillsPCCursor

MoveBillsPCCursorDown:
	ldh a, [hCurrentMenuItem]
	cp PARTY_LENGTH
	jr nc, .notParty
	inc a
	ld b, a
	ld a, [wPartyCount]
	cp b
	ret z
	ret c
	ld a, b
	ldh [hCurrentMenuItem], a
	jr DrawBillsPCCursor
.notParty
	sub PARTY_LENGTH
	cp MONS_PER_BOX - BILLS_PC_BOX_COLUMNS
	ret nc
	add PARTY_LENGTH + BILLS_PC_BOX_COLUMNS
	ldh [hCurrentMenuItem], a
	jr DrawBillsPCCursor

MoveBillsPCCursorLeft:
	ldh a, [hCurrentMenuItem]
	cp PARTY_LENGTH
	ret c
	sub PARTY_LENGTH
	call GetBillsPCBoxRowAndColumn
	and a
	jr z, .firstColumn
	ldh a, [hCurrentMenuItem]
	dec a
	ldh [hCurrentMenuItem], a
	jr DrawBillsPCCursor
.firstColumn
	ld a, [wPartyCount]
	dec a
	cp b
	jr nc, .gotPartyRow
	ld b, a
.gotPartyRow
	ld a, b
	ldh [hCurrentMenuItem], a
	jr DrawBillsPCCursor

MoveBillsPCCursorRight:
	ldh a, [hCurrentMenuItem]
	cp PARTY_LENGTH
	jr c, .party
	sub PARTY_LENGTH
	call GetBillsPCBoxRowAndColumn
	cp BILLS_PC_BOX_COLUMNS - 1
	ret z
	ldh a, [hCurrentMenuItem]
	inc a
	ldh [hCurrentMenuItem], a
	jr DrawBillsPCCursor
.party
	cp BILLS_PC_BOX_ROWS
	ret nc
	ld c, a
	ld b, 0
	ld hl, BillsPCBoxRowStartMenuItems
	add hl, bc
	ld a, [hl]
	ldh [hCurrentMenuItem], a
	jr DrawBillsPCCursor

BillsPCBoxRowStartMenuItems:
	db PARTY_LENGTH
	db PARTY_LENGTH + BILLS_PC_BOX_COLUMNS
	db PARTY_LENGTH + BILLS_PC_BOX_COLUMNS * 2
	db PARTY_LENGTH + BILLS_PC_BOX_COLUMNS * 3

; Input: a = box slot 0..19. Output: b = row, a = column.
GetBillsPCBoxRowAndColumn:
	ld b, 0
.loop
	cp BILLS_PC_BOX_COLUMNS
	ret c
	sub BILLS_PC_BOX_COLUMNS
	inc b
	jr .loop

DrawBillsPCCursor:
	call DrawBillsPCCursorOnly
	jr DrawBillsPCInfoText

DrawBillsPCCursorOnly:
	ld a, [wLastMenuItem]
	call GetBillsPCCursorCoord
	ld [hl], ' '
	ldh a, [hCurrentMenuItem]
	call GetBillsPCCursorCoord
	ld [hl], '▶'
	ldh a, [hCurrentMenuItem]
	ld [wLastMenuItem], a
	ld [wPartyAndBillsPCSavedMenuItem], a
	ret

DrawBillsPCSelectedCursor:
	ld a, [wPartyAndBillsPCSavedMenuItem]
	call GetBillsPCCursorCoord
	ld [hl], '▷'
	ret

DrawBillsPCInfoText:
	call ClearBillsPCInfoText
	hlcoord 1, 14
	ld de, BillsPCWhatToDoText
	call PlaceString
	ldh a, [hCurrentMenuItem]
	cp PARTY_LENGTH
	jr c, .partyMon
	sub PARTY_LENGTH
	call BillsPCBoxSlotHasMon
	ret z
	ld a, c
	ldh [hWhichPokemon], a
	ld hl, wBoxMonNicks
	call DrawBillsPCHoveredMonName
	ld hl, wBoxMons
	ld bc, BOXMON_STRUCT_LENGTH
	ldh a, [hWhichPokemon]
	call AddNTimes
	ld bc, MON_BOX_LEVEL
	add hl, bc
	ld a, [hl]
	jr .drawLevel
.partyMon
	ld c, a
	ld b, 0
	ld hl, wPartySpecies
	add hl, bc
	ld a, [hl]
	cp $ff
	ret z
	ld a, c
	ldh [hWhichPokemon], a
	ld hl, wPartyMonNicks
	call DrawBillsPCHoveredMonName
	ld hl, wPartyMons
	ld bc, PARTYMON_STRUCT_LENGTH
	ldh a, [hWhichPokemon]
	call AddNTimes
	ld bc, MON_LEVEL
	add hl, bc
	ld a, [hl]
.drawLevel
	ld [wLoadedMonLevel], a
	hlcoord 15, 10
	jp PrintLevel

DrawBillsPCHoveredMonName:
	ldh a, [hWhichPokemon]
	call SkipFixedLengthTextEntries
	ld d, h
	ld e, l
	hlcoord 5, 10
	jp PlaceString

ClearBillsPCInfoText:
	hlcoord 1, 13
	lb bc, 4, 18
	call ClearScreenArea
	hlcoord 4, 10
	lb bc, 2, 15
	jp ClearScreenArea

DepositBillsPCSelectedPartyMon:
	ld a, [wPartyCount]
	dec a
	ld hl, CantDepositLastMonText
	jp z, PrintBillsPCSelectedMessageNoName
	ld a, [wBoxCount]
	cp MONS_PER_BOX
	ld hl, BoxFullText
	jp nc, PrintBillsPCSelectedMessageNoName

	ld a, [wPartyAndBillsPCSavedMenuItem]
	ldh [hWhichPokemon], a
	ld hl, wPartyMonNicks
	call CopyBillsPCMonNameToStringBuffer
	ldh a, [hWhichPokemon]
	ld c, a
	ld b, 0
	ld hl, wPartySpecies
	add hl, bc
	ld a, [hl]
	ld [wCurPartySpecies], a
	ld a, PARTY_TO_BOX
	ld [wMoveMonType], a
	call MoveMon
	xor a
	ld [wRemoveMonFromBox], a
	call RemovePokemon

	; Clamp the party cursor if the removed mon was its last visible slot.
	ldh a, [hCurrentMenuItem]
	ld b, a
	ld a, [wPartyCount]
	dec a
	cp b
	jr nc, .partyCursorValid
	ldh [hCurrentMenuItem], a
.partyCursorValid
	call BuildBillsPCBoxNumString

	; Hide the newly appended box entry for the first animation redraw.
	ld a, [wBoxCount]
	dec a
	ld c, a
	ld b, 0
	ld hl, wBoxSpecies
	add hl, bc
	ld a, [hl]
	push hl
	push af
	ld [hl], $ff
	ld a, SFX_WITHDRAW_DEPOSIT
	call PlaySound
	call RedrawBillsPCBoxScreenForSelectedMessage
	pop af
	pop hl
	ld [hl], a
	call RedrawBillsPCBoxScreenForSelectedMessage
	ld hl, MonWasStoredText
	jp PrintBillsPCMessageAfterRedraw

WithdrawBillsPCSelectedBoxMon:
	ld a, [wPartyCount]
	cp PARTY_LENGTH
	ld hl, CantTakeMonText
	jp nc, PrintBillsPCSelectedMessageNoName
	ld a, [wPartyAndBillsPCSavedMenuItem]
	sub PARTY_LENGTH
	ldh [hWhichPokemon], a
	call BillsPCBoxSlotHasMon
	ld hl, NoMonText
	jp z, PrintBillsPCSelectedMessageNoName
	ld [wCurPartySpecies], a
	ld hl, wBoxMonNicks
	call CopyBillsPCMonNameToStringBuffer
	xor a ; BOX_TO_PARTY
	ld [wMoveMonType], a
	call MoveMon
	ld a, 1
	ld [wRemoveMonFromBox], a
	call RemovePokemon

	; Hide the newly appended party entry for the first animation redraw.
	ld a, [wPartyCount]
	dec a
	ld c, a
	ld b, 0
	ld hl, wPartySpecies
	add hl, bc
	ld a, [hl]
	push hl
	push af
	ld [hl], $ff
	ld a, SFX_WITHDRAW_DEPOSIT
	call PlaySound
	call RedrawBillsPCBoxScreenForSelectedMessage
	pop af
	pop hl
	ld [hli], a
	ld [hl], $ff
	call RedrawBillsPCBoxScreenForSelectedMessage
	ld hl, MonIsTakenOutText
	jr PrintBillsPCMessageAfterRedraw

ReleaseBillsPCSelectedBoxMon:
	ld a, [wPartyAndBillsPCSavedMenuItem]
	sub PARTY_LENGTH
	ldh [hWhichPokemon], a
	call BillsPCBoxSlotHasMon
	ld hl, NoMonText
	jr z, PrintBillsPCSelectedMessageNoName
	ld [wCurPartySpecies], a
	ld hl, wBoxMonNicks
	call CopyBillsPCMonNameToStringBuffer
	ld hl, OnceReleasedText
	call PrintBillsPCSelectedMessage
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
	ld a, [wPartyAndBillsPCSavedMenuItem]
	ldh [hCurrentMenuItem], a
	ld [wLastMenuItem], a
	ret nz
	; YesNoChoice uses hWhichPokemon, so recover the box slot from the
	; persistent grid selection before looking up and removing the mon.
	ld a, [wPartyAndBillsPCSavedMenuItem]
	sub PARTY_LENGTH
	ldh [hWhichPokemon], a
	call BillsPCBoxSlotHasMon
	push af
	ld hl, wBoxMonNicks
	call CopyBillsPCMonNameToStringBuffer
	ld a, 1
	ld [wRemoveMonFromBox], a
	call RemovePokemon
	call WaitForSoundToFinish
	pop af
	call PlayCry
	ld hl, MonWasReleasedText
	jr PrintBillsPCSelectedMessage

PrintBillsPCSelectedMessageNoName:
	push hl
	call RedrawBillsPCBoxScreenForSelectedMessage
	pop hl
	jp PrintText

PrintBillsPCSelectedMessage:
	push hl
	call RedrawBillsPCBoxScreenForSelectedMessage
	call RestoreBillsPCMessageString
	pop hl
	jp PrintText

PrintBillsPCMessageAfterRedraw:
	push hl
	call RestoreBillsPCMessageString
	pop hl
	jp PrintText

RestoreBillsPCMessageString:
	ld de, wNameBuffer
	jp CopyToStringBuffer

; Input: a = compact box slot. Output: c = slot, a = species, z if empty.
BillsPCBoxSlotHasMon:
	ld c, a
	ld b, 0
	ld hl, wBoxCount
	cp [hl]
	jr nc, .empty
	ld hl, wBoxSpecies
	add hl, bc
	ld a, [hl]
	and a
	ret
.empty
	xor a
	ret

CopyBillsPCMonNameToStringBuffer:
	ldh a, [hWhichPokemon]
	call GetPartyMonName
	ld de, wNameBuffer
	jp CopyToStringBuffer

BuildBillsPCBoxNumString:
	ld hl, wBoxNumString
	ld a, [wCurrentBoxNum]
	and BOX_NUM_MASK
	cp 9
	jr c, .singleDigit
	sub 9
	ld [hl], '1'
	inc hl
	add '0'
	jr .store
.singleDigit
	add '1'
.store
	ld [hli], a
	ld [hl], '@'
	ret

DrawBillsPCPartyMons:
	ld hl, wPartySpecies
	ld b, 0
.loop
	ld a, [hli]
	cp $ff
	ret z
	ld [wCurPartySpecies], a
	push hl
	push bc
	farcall GetCurPartyMonSpriteID
	pop bc
	ld c, e
	ld a, b
	ld hl, BillsPCPartyIconCoords
	call GetBillsPCIconCoord
	ld a, c
	call PlaceBillsPCBoxIcon
	pop hl
	inc b
	jr .loop

DrawBillsPCBoxMons:
	ld hl, wBoxSpecies
	ld b, 0
.loop
	ld a, [hli]
	cp $ff
	ret z
	ld [wCurPartySpecies], a
	push hl
	push bc
	farcall GetCurPartyMonSpriteID
	pop bc
	ld c, e
	ld a, b
	ld hl, BillsPCBoxIconCoords
	call GetBillsPCIconCoord
	ld a, c
	call PlaceBillsPCBoxIcon
	pop hl
	inc b
	jr .loop

GetBillsPCCursorCoord:
	cp PARTY_LENGTH
	jr c, .party
	sub PARTY_LENGTH
	ld hl, BillsPCBoxCursorCoords
	jr GetBillsPCIconCoord
.party
	ld hl, BillsPCPartyCursorCoords
	; fallthrough

; Input: a = table index. Output: hl = BG coord.
GetBillsPCIconCoord:
	add a
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ret

; Place a 2x2 mon icon into BG tiles. Input: a = first tile, hl = top-left.
PlaceBillsPCBoxIcon:
	ld [hli], a
	inc a
	ld [hl], a
	ld de, SCREEN_WIDTH - 1
	add hl, de
	inc a
	ld [hli], a
	inc a
	ld [hl], a
	ret

BillsPCPartyIconCoords:
	dwcoord 1,  0
	dwcoord 1,  2
	dwcoord 1,  4
	dwcoord 1,  6
	dwcoord 1,  8
	dwcoord 1, 10

BillsPCPartyCursorCoords:
	dwcoord 0,  1
	dwcoord 0,  3
	dwcoord 0,  5
	dwcoord 0,  7
	dwcoord 0,  9
	dwcoord 0, 11

BillsPCBoxCursorCoords:
	dwcoord  4,  2
	dwcoord  7,  2
	dwcoord 10,  2
	dwcoord 13,  2
	dwcoord 16,  2
	dwcoord  4,  4
	dwcoord  7,  4
	dwcoord 10,  4
	dwcoord 13,  4
	dwcoord 16,  4
	dwcoord  4,  6
	dwcoord  7,  6
	dwcoord 10,  6
	dwcoord 13,  6
	dwcoord 16,  6
	dwcoord  4,  8
	dwcoord  7,  8
	dwcoord 10,  8
	dwcoord 13,  8
	dwcoord 16,  8

BillsPCBoxIconCoords:
	dwcoord  5,  1
	dwcoord  8,  1
	dwcoord 11,  1
	dwcoord 14,  1
	dwcoord 17,  1
	dwcoord  5,  3
	dwcoord  8,  3
	dwcoord 11,  3
	dwcoord 14,  3
	dwcoord 17,  3
	dwcoord  5,  5
	dwcoord  8,  5
	dwcoord 11,  5
	dwcoord 14,  5
	dwcoord 17,  5
	dwcoord  5,  7
	dwcoord  8,  7
	dwcoord 11,  7
	dwcoord 14,  7
	dwcoord 17,  7

MACRO load_bills_pc_box_icon
	ld de, \1 tile \2
	ld hl, vChars2 tile (\3 << 2)
	lb bc, BANK(\1), 4
	call CopyVideoData
ENDM

MACRO load_bills_pc_box_symmetric_icon
	ld de, \1 tile \2
	ld hl, vChars2 tile (\3 << 2)
	lb bc, BANK(\1), 1
	call CopyVideoData
	ld de, \1 tile \2
	ld hl, vChars2 tile ((\3 << 2) + 1)
	ld a, BANK(\1)
	call CopyFlippedBillsPCBoxIconTile
	ld de, \1 tile (\2 + 1)
	ld hl, vChars2 tile ((\3 << 2) + 2)
	lb bc, BANK(\1), 1
	call CopyVideoData
	ld de, \1 tile (\2 + 1)
	ld hl, vChars2 tile ((\3 << 2) + 3)
	ld a, BANK(\1)
	call CopyFlippedBillsPCBoxIconTile
ENDM

; Load all 12 species icon categories as BG tiles. Chansey extends Yume's 44
; tiles to 48, occupying tile IDs $00-$2f and preserving Red Rogue's icon set.
LoadBillsPCBoxIconTilePatterns:
	load_bills_pc_box_icon MonsterSprite, 12, ICON_MON
	load_bills_pc_box_icon PokeBallSprite, 0, ICON_BALL
	load_bills_pc_box_icon FossilSprite, 0, ICON_HELIX
	load_bills_pc_box_icon FairySprite, 12, ICON_FAIRY
	load_bills_pc_box_icon BirdSprite, 12, ICON_BIRD
	load_bills_pc_box_icon SeelSprite, 0, ICON_WATER
	load_bills_pc_box_symmetric_icon BugIconFrame2, 0, ICON_BUG
	load_bills_pc_box_symmetric_icon PlantIconFrame2, 0, ICON_GRASS
	load_bills_pc_box_symmetric_icon SnakeIconFrame1, 0, ICON_SNAKE
	load_bills_pc_box_symmetric_icon QuadrupedIconFrame1, 0, ICON_QUADRUPED
	load_bills_pc_box_icon PikachuSprite, 12, ICON_PIKACHU
	load_bills_pc_box_icon ChanseySprite, 0, ICON_CHANSEY
	ret

; Copy one icon tile through existing text scratch while reversing each row.
; Input: a = source bank, de = source tile, hl = destination VRAM tile.
CopyFlippedBillsPCBoxIconTile:
	push hl
	ld h, d
	ld l, e
	ld de, wTextBoxBuffer
	ld bc, TILE_SIZE
	call FarCopyData
	ld hl, wTextBoxBuffer
	ld b, TILE_SIZE
.loop
	ld a, [hl]
	push hl
	ld e, a
	and $f
	ld hl, BillsPCBoxReversedNibbles
	add l
	ld l, a
	adc h
	sub l
	ld h, a
	ld a, [hl]
	swap a
	ld d, a
	ld a, e
	swap a
	and $f
	ld hl, BillsPCBoxReversedNibbles
	add l
	ld l, a
	adc h
	sub l
	ld h, a
	ld a, [hl]
	or d
	pop hl
	ld [hli], a
	dec b
	jr nz, .loop
	pop hl
	ld de, wTextBoxBuffer
	ldh a, [hLoadedROMBank]
	ld b, a
	ld c, 1
	jp CopyVideoData

BillsPCBoxReversedNibbles:
	db $0, $8, $4, $c, $2, $a, $6, $e
	db $1, $9, $5, $d, $3, $b, $7, $f

BillsPCChangeBoxText: db "START:BOX@"
BillsPCWhatToDoText: db "Choose a <PKMN>.@"
DepositPCText:       db "DEPOSIT@"
WithdrawPCText:      db "WITHDRAW@"
StatsPCText:         db "STATS@"
ReleasePCText:       db "RELEASE@"
CancelPCText:        db "CANCEL@"

SwitchOnText:
	text_far _SwitchOnText
	text_end

MonWasStoredText:
	text_far _MonWasStoredText
	text_end

CantDepositLastMonText:
	text_far _CantDepositLastMonText
	text_end

BoxFullText:
	text_far _BoxFullText
	text_end

MonIsTakenOutText:
	text_far _MonIsTakenOutText
	text_end

NoMonText:
	text_far _NoMonText
	text_end

CantTakeMonText:
	text_far _CantTakeMonText
	text_end

OnceReleasedText:
	text_far _OnceReleasedText
	text_end

MonWasReleasedText:
	text_far _MonWasReleasedText
	text_end

CableClubLeftGameboy::
	ldh a, [hSerialConnectionStatus]
	cp USING_EXTERNAL_CLOCK
	ret z
	ld a, [wSpritePlayerStateData1FacingDirection]
	cp SPRITE_FACING_RIGHT
	ret nz
	ldh a, [hCurMap]
	cp TRADE_CENTER
	ld a, LINK_STATE_START_TRADE
	jr z, .next
	inc a ; LINK_STATE_START_BATTLE
.next
	ld [wLinkState], a
	call EnableAutoTextBoxDrawing
	tx_pre_jump JustAMomentText

CableClubRightGameboy::
	ldh a, [hSerialConnectionStatus]
	cp USING_INTERNAL_CLOCK
	ret z
	ld a, [wSpritePlayerStateData1FacingDirection]
	cp SPRITE_FACING_LEFT
	ret nz
	ldh a, [hCurMap]
	cp TRADE_CENTER
	ld a, LINK_STATE_START_TRADE
	jr z, .next
	inc a ; LINK_STATE_START_BATTLE
.next
	ld [wLinkState], a
	call EnableAutoTextBoxDrawing
	tx_pre_jump JustAMomentText

JustAMomentText::
	text_far _JustAMomentText
	text_end

UnusedOpenBillsPC: ; unreferenced
	ld a, [wSpritePlayerStateData1FacingDirection]
	cp SPRITE_FACING_UP
	ret nz
	call EnableAutoTextBoxDrawing
	tx_pre_jump OpenBillsPCText

OpenBillsPCText::
	script_bills_pc
