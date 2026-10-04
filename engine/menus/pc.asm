ActivatePC::
	call SaveScreenTilesToBuffer2
	ld a, SFX_TURN_ON_PC
	call PlaySound
	ld hl, TurnedOnPC1Text
	call PrintText
	call WaitForSoundToFinish
	ld hl, wMiscFlags
	set BIT_USING_GENERIC_PC, [hl]
	call LoadScreenTilesFromBuffer2
	call Delay3
PCMainMenu:
	farcall DisplayPCMainMenu
	ld hl, wMiscFlags
	set BIT_NO_MENU_BUTTON_SOUND, [hl]
	call HandleMenuInput
	bit B_PAD_B, a
	jp nz, LogOff
	ld a, [wMaxMenuItem]
	cp 2
	jr nz, .next ;if not 2 menu items (not counting log off) (2 occurs before you get the pokedex)
	ldh a, [hCurrentMenuItem]
	and a
	jp z, BillsPC    ;if current menu item id is 0, it's bills pc
	cp 1
	jr z, .playersPC ;if current menu item id is 1, it's players pc
	jp LogOff        ;otherwise, it's 2, and you're logging off
.next
	cp 3
	jr nz, .next2 ;if not 3 menu items (not counting log off) (3 occurs after you get the pokedex, before you beat the pokemon league)
	ldh a, [hCurrentMenuItem]
	and a
	jp z, BillsPC    ;if current menu item id is 0, it's bills pc
	cp 1
	jr z, .playersPC ;if current menu item id is 1, it's players pc
	cp 2
	jp z, OaksPC     ;if current menu item id is 2, it's oaks pc
	jp LogOff        ;otherwise, it's 3, and you're logging off
.next2
	ldh a, [hCurrentMenuItem]
	and a
	jp z, BillsPC    ;if current menu item id is 0, it's bills pc
	cp 1
	jr z, .playersPC ;if current menu item id is 1, it's players pc
	cp 2
	jp z, OaksPC     ;if current menu item id is 2, it's oaks pc
	cp 3
	jp z, PKMNLeague ;if current menu item id is 3, it's pkmnleague
	jp LogOff        ;otherwise, it's 4, and you're logging off
.playersPC
	ld hl, wMiscFlags
	res BIT_NO_MENU_BUTTON_SOUND, [hl]
	set BIT_USING_GENERIC_PC, [hl]
	ld a, SFX_ENTER_PC
	call PlaySound
	call WaitForSoundToFinish
	ld hl, AccessedMyPCText
	call PrintText
	farcall PlayerPC
	jr ReloadMainMenu
OaksPC:
	ld a, SFX_ENTER_PC
	call PlaySound
	call WaitForSoundToFinish
	farcall OpenOaksPC
	jr ReloadMainMenu
PKMNLeague:
	ld a, SFX_ENTER_PC
	call PlaySound
	call WaitForSoundToFinish
	farcall PKMNLeaguePC
	jr ReloadMainMenu
BillsPC:
	ld a, SFX_ENTER_PC
	call PlaySound
	call WaitForSoundToFinish
	ld hl, AccessedBillsPCText
	call PrintText
	farcall BillsPC_
ReloadMainMenu:
	xor a
	ldh [hNoWaitAfterText], a
	call ReloadMapData
	; Bill's PC replaces the follower's VRAM slot with its animated box icons.
	; Publish a swapped lead while the font context is still live, then restore
	; both halves of the follower sheet before drawing sprites on the PC menu.
	farcall FollowerPrepareMap
	call ReloadMapSpriteTilePatterns
	jp PCMainMenu
LogOff:
	ld a, SFX_TURN_OFF_PC
	call PlaySound
	call WaitForSoundToFinish
	ld hl, wMiscFlags
	res BIT_USING_GENERIC_PC, [hl]
	res BIT_NO_MENU_BUTTON_SOUND, [hl]
	ret

TurnedOnPC1Text:
	text_far _TurnedOnPC1Text
	text_end

AccessedBillsPCText:
	text_far _AccessedBillsPCText
	text_end

AccessedSomeonesPCText:
	text_far _AccessedSomeonesPCText
	text_end

AccessedMyPCText:
	text_far _AccessedMyPCText
	text_end

; removes one of the specified item ID [hItemToRemoveID] from bag (if existent)
; Recovery/Stat/Valuable items only: anything else is in no pocket and has no
; use (the legacy wBagItems list it used to be searched in is gone, 2026-10-03).
RemoveItemByID::
	farcall RemovePocketItemByID
	ret
