DisplayStartMenu::
	ld a, BANK(StartMenu_Pokedex)
	ldh [hLoadedROMBank], a
	ld [rROMB], a
	ld a, [wWalkBikeSurfState] ; walking/biking/surfing
	ld [wWalkBikeSurfStateCopy], a
	ld a, SFX_START_MENU
	call PlaySound

RedisplayStartMenu::
	rfarcall DrawStartMenu
	rfarcall PrintSafariZoneSteps ; print Safari Zone info, if in Safari Zone
    
    ;GBCNote - if using enhanced GBC color, add some extra delay
	ld a, [wOptions2]
	bit BIT_ENHANCED_COLORS, a
	call nz, Delay3

	call LoadGBPal	;joenote - moved this here for smoother whiteout transition
    
	call UpdateSprites
.loop
	call HandleMenuInput
	ld b, a
; check if Up pressed
	bit B_PAD_UP, a
	jr z, .checkIfDownPressed
	ldh a, [hCurrentMenuItem] ; menu selection
	and a
	jr nz, .loop
	ld a, [wLastMenuItem]
	and a
	jr nz, .loop
; if the player pressed tried to go past the top item, wrap around to the bottom
	CheckEvent EVENT_GOT_POKEDEX
	ld a, 6 ; there are 7 menu items with the pokedex, so the max index is 6
	jr nz, .wrapMenuItemId
	dec a ; there are only 6 menu items without the pokedex
.wrapMenuItemId
	ldh [hCurrentMenuItem], a
	call EraseMenuCursor
	jr .loop
.checkIfDownPressed
	bit B_PAD_DOWN, a
	jr z, .buttonPressed
; if the player pressed tried to go past the bottom item, wrap around to the top
	CheckEvent EVENT_GOT_POKEDEX
	ldh a, [hCurrentMenuItem]
	ld c, 7 ; there are 7 menu items with the pokedex
	jr nz, .checkIfPastBottom
	dec c ; there are only 6 menu items without the pokedex
.checkIfPastBottom
	cp c
	jr nz, .loop
; the player went past the bottom, so wrap to the top
	xor a
	ldh [hCurrentMenuItem], a
	call EraseMenuCursor
	jr .loop
.buttonPressed ; A, B, or Start button pressed
	call PlaceUnfilledArrowMenuCursor
	ldh a, [hCurrentMenuItem]
	ld [wBattleAndStartSavedMenuItem], a ; save current menu selection
	ld a, b
	and PAD_B | PAD_START ; was the Start button or B button pressed?
	jp nz, CloseStartMenu
	call SaveScreenTilesToBuffer2 ; copy background from wTileMap to wTileMapBackup2
	CheckEvent EVENT_GOT_POKEDEX
	ldh a, [hCurrentMenuItem]
	jr nz, .displayMenuItem
	inc a ; adjust position to account for missing pokedex menu item
.displayMenuItem
	cp 0
	jp z, StartMenu_Pokedex
	cp 1
	jp z, StartMenu_Pokemon
	cp 2
	jp z, StartMenu_Item
	cp 3
	jp z, StartMenu_TrainerInfo
	cp 4
	jp z, StartMenu_SaveReset
	cp 5
	jp z, StartMenu_Option

	; The final row is END RUN in a run, EXIT in the hub/link contexts.
	; Carry clear means NO/B: restore the selected row and menu parameters.
	rfarcall RogueStartMenuEndRun
	jp nc, RedisplayStartMenu

CloseStartMenu::
	call Joypad
	ldh a, [hJoyPressed]
	bit B_PAD_A, a
	jr nz, CloseStartMenu
	call LoadTextBoxTilePatterns
	; Reapply the SGB room colours/attributes after an external cartridge menu.
	; CGB owns a separate restoration path; DMG needs no SGB packets.
	ldh a, [hGBC]
	and a
	jr nz, .close
	ld a, [wOnSGB]
	and a
	call nz, RunDefaultPaletteCommand
.close
	jp CloseTextDisplay
