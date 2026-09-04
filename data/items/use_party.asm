; items which bring up the party menu when used
UsableItems_PartyMenu:
	db MOON_STONE
	db ANTIDOTE
	db BURN_HEAL
	db ICE_HEAL
	db AWAKENING
	db PARLYZ_HEAL
	db FULL_RESTORE
	db MAX_POTION
	db HYPER_POTION
	db SUPER_POTION
	db POTION
	db FIRE_STONE
	db THUNDER_STONE
	db WATER_STONE
	db HP_UP
	db PROTEIN
	db IRON
	db CARBOS
	db CALCIUM
	db RARE_CANDY
	db LEAF_STONE
	db FULL_HEAL
	db REVIVE
	db MAX_REVIVE
	db FRESH_WATER
	db SODA_POP
	db LEMONADE
	db X_ATTACK
	db X_DEFEND
	db X_SPEED
	db X_SPECIAL
	db PP_UP
	db ETHER
	db MAX_ETHER
	db ELIXER
	db MAX_ELIXER
; Shin Red import Phase 11. Both open the party menu (they share
; ItemUseMedicine's picker), so they MUST be listed here: an item in neither
; this array nor UsableItems_CloseMenu falls through to StartMenu_Item's bare
; `call UseItem / jp ItemMenuLoop`, which never runs
; GBPalWhiteOutWithDelay3 + RestoreScreenTilesAndReloadTilePatterns. The party
; menu's tile patterns then stay in VRAM and hUpdateSpritesEnabled stays $ff,
; so the map/bag render with garbage mon tiles and the player sprite stops
; updating until the party menu is opened and closed again.
	db M_GENE
	db M_TOME
; The three added evolution stones MUST be listed here. Every stone opens the
; party menu, and an item that does so while missing from this list skips the
; graphics restore on exit - the party menu's tile patterns stay in VRAM and
; hUpdateSpritesEnabled stays $ff, so the map and bag render with garbage mon
; tiles and the player sprite stops updating until the party menu is reopened.
	db SUN_STONE
	db DUSK_STONE
	db ICE_STONE
	db -1 ; end
