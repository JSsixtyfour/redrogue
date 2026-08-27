; this function is used to display sign messages, sprite dialog, etc.
; INPUT: [hSpriteIndex] = sprite ID or [hTextID] = text ID
DisplayTextID::
	ASSERT hSpriteIndex == hTextID ; these are at the same memory location
	ldh a, [hLoadedROMBank]
	push af
	farcall DisplayTextIDInit ; initialization
	ld hl, wTextPredefFlag
	bit BIT_TEXT_PREDEF, [hl]
	res BIT_TEXT_PREDEF, [hl]
	jr nz, .skipSwitchToMapBank
	ldh a, [hCurMap]
	call SwitchToMapRomBank
.skipSwitchToMapBank
	ld a, 30 ; half a second
	ldh [hFrameCounter], a ; used as joypad poll timer
	ld hl, wCurMapTextPtr
	ld a, [hli]
	ld h, [hl]
	ld l, a ; hl = map text pointer
	ld d, $00
	ldh a, [hTextID]
	ldh [hActiveSpriteIndex], a

	dict TEXT_START_MENU,       DisplayStartMenu
	dict TEXT_SAFARI_GAME_OVER, DisplaySafariGameOverText
	dict TEXT_MON_FAINTED,      DisplayPokemonFaintedText
	dict TEXT_BLACKED_OUT,      DisplayPlayerBlackedOutText
	dict TEXT_REPEL_WORE_OFF,   DisplayRepelWoreOffText

	ld a, [wNumSprites]
	ld e, a
	ldh a, [hSpriteIndex] ; sprite ID
	cp e
	jr z, .spriteHandling
	jr nc, .skipSpriteHandling
.spriteHandling
; get the text ID of the sprite
; Shin Red import Phase 6: the UpdateSpriteFacingOffsetAndDelayMovement call that used
; to be here has been removed, matching Pokemon Yellow and shinpokered. It ran on
; whatever slot hCurrentSpriteOffset was left on by the per-frame sprite loop rather
; than the sprite being talked to, which only ever produced the 15th-sprite graphical
; glitch (and the Victory Road boulder ghost this fork previously patched around).
; NPCs still turn to face the player: that is handled by MakeNPCFacePlayer, dispatched
; from UpdateNPCSprite's face-player flag.
	push hl
	ld hl, wMapSpriteData ; NPC text entries
	ldh a, [hSpriteIndex]
	dec a
	add a
	add l
	ld l, a
	jr nc, .noCarry
	inc h
.noCarry
	inc hl
	ld a, [hl] ; a = text ID of the sprite
	pop hl
.skipSpriteHandling
; look up the address of the text in the map's text entries
	dec a
	ld e, a
	sla e
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a ; hl = address of the text
	ld a, [hl] ; a = first byte of text

; check first byte of text for special cases

MACRO dict2
	cp \1
	jr nz, .not\@
	\2
	jr AfterDisplayingTextID
.not\@
ENDM

	dict  TX_SCRIPT_MART,                    DisplayPokemartDialogue
	dict  TX_SCRIPT_POKECENTER_NURSE,        DisplayPokemonCenterDialogue
	dict  TX_SCRIPT_PLAYERS_PC,              TextScript_ItemStoragePC
	dict  TX_SCRIPT_BILLS_PC,                TextScript_BillsPC
	dict  TX_SCRIPT_POKECENTER_PC,           TextScript_PokemonCenterPC
	dict2 TX_SCRIPT_VENDING_MACHINE,         farcall VendingMachineMenu
	dict  TX_SCRIPT_CREDIT_VENDOR,           TextScript_CreditVendorMenu
	dict2 TX_SCRIPT_CABLE_CLUB_RECEPTIONIST, callfar CableClubNPC
    dict  TX_SCRIPT_ROGUE_VENDOR,            TextScript_RogueRewardMenu
    dict  TX_SCRIPT_BRIDGE_GIFT,             TextScript_BridgeGiftMenu

	call PrintText_NoCreatingTextBox
	ldh a, [hNoWaitAfterText]
	and a
	jr nz, HoldTextDisplayOpen

AfterDisplayingTextID::
	ld a, [wEnteringCableClub]
	and a
	jr nz, HoldTextDisplayOpen
	call WaitForTextScrollButtonPress

; loop to hold the dialogue box open as long as the player keeps holding down the A button
HoldTextDisplayOpen::
	call Joypad
	ldh a, [hJoyHeld]
	bit B_PAD_A, a
	jr nz, HoldTextDisplayOpen

CloseTextDisplay::
	ldh a, [hCurMap]
	call SwitchToMapRomBank
	; Enhanced GBC colour: this block is deliberately hoisted above the hWY write
	; below, matching shinpokered's reordering of the same routine.
	;
	; LoadCurrentMapView repopulates wTileMap, and the attribute rebuild derives
	; each tile's palette FROM wTileMap - so it has to run while the window is
	; still covering the screen. Writing hWY first (as vanilla does, and as this
	; routine used to) slides the window away and reveals a background whose
	; attributes still belong to whatever screen just closed. That was the cause
	; of colours changing after backing out of the slot machine, the PC, and
	; other screen-refresh menus: _CloseText existed but was never called, and
	; the ordering would have been wrong even if it had been.
	;
	; LoadCurrentMapView still ran in this routine before, but near the very end,
	; long after the reveal. It is moved here rather than duplicated.
	xor a
	ldh [hAutoBGTransferEnabled], a ; disable continuous WRAM to VRAM transfer each V-blank
	call LoadCurrentMapView
	farcall MakeAndTransferOverworldBGMapAttributes_CloseText
	ld a, $90
	ldh [hWY], a ; move the window off the screen
	call DelayFrame
	call LoadGBPal
; loop to make sprites face the directions they originally faced before the dialogue
	ld hl, wSprite01StateData2OrigFacingDirection
	ld c, NUM_SPRITESTATEDATA_STRUCTS - 1
	ld de, SPRITESTATEDATA1_LENGTH
.restoreSpriteFacingDirectionLoop
	ld a, [hl] ; x#SPRITESTATEDATA2_ORIGFACINGDIRECTION
	dec h
	ld [hl], a ; [x#SPRITESTATEDATA1_FACINGDIRECTION]
	inc h
	add hl, de
	dec c
	jr nz, .restoreSpriteFacingDirectionLoop
	ld a, BANK(InitMapSprites)
	call SetCurBank ; -2 B of HOME vs the inline ldh+ld pair
	call InitMapSprites ; reload sprite tile pattern data (since it was partially overwritten by text tile patterns)
	ld hl, wFontLoaded
	res BIT_FONT_LOADED, [hl]
	ld a, [wStatusFlags6]
	bit BIT_FLY_WARP, a
	call z, LoadPlayerSpriteGraphics
	; LoadCurrentMapView was here; it is hoisted to the top of this routine so
	; the attribute rebuild has a populated wTileMap to work from before the
	; window is slid off. shinpokered comments the trailing call out in exactly
	; the same way rather than running it twice.
	pop af
	call SetCurBank ; -2 B of HOME vs the inline ldh+ld pair
	jp UpdateSprites

DisplayPokemartDialogue::
	push hl
	ld hl, PokemartGreetingText
	call PrintText
	pop hl
	inc hl
	call LoadItemList
	ld a, PRICEDITEMLISTMENU
	ld [wListMenuID], a
	homecall DisplayPokemartDialogue_
	jp AfterDisplayingTextID

PokemartGreetingText::
	text_far _PokemartGreetingText
	text_end

LoadItemList::
	ld a, 1
	ldh [hUpdateSpritesEnabled], a
	ld a, h
	ld [wItemListPointer], a
	ld a, l
	ld [wItemListPointer + 1], a
	ld de, wItemList
.loop
	ld a, [hli]
	ld [de], a
	inc de
	cp $ff
	jr nz, .loop
	ret

DisplayPokemonCenterDialogue::
; zeroing these doesn't appear to serve any purpose
	xor a
	ldh [hItemPrice], a
	ldh [hItemPrice + 1], a
	ldh [hItemPrice + 2], a

	inc hl
	homecall DisplayPokemonCenterDialogue_
	jp AfterDisplayingTextID

DisplaySafariGameOverText::
	callfar PrintSafariGameOverText
	jp AfterDisplayingTextID

DisplayPokemonFaintedText::
	ld hl, PokemonFaintedText
	call PrintText
	jp AfterDisplayingTextID

PokemonFaintedText::
	text_far _PokemonFaintedText
	text_end

DisplayPlayerBlackedOutText::
	ld hl, PlayerBlackedOutText
	call PrintText
	ld a, [wStatusFlags6]
	res BIT_ALWAYS_ON_BIKE, a
	ld [wStatusFlags6], a
	jp HoldTextDisplayOpen

PlayerBlackedOutText::
	text_far _PlayerBlackedOutText
	text_end

DisplayRepelWoreOffText::
	ld hl, RepelWoreOffText
	call PrintText
	jp AfterDisplayingTextID

RepelWoreOffText::
	text_far _RepelWoreOffText
	text_end
