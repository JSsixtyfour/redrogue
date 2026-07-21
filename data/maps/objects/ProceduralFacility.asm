	object_const_def
	const_export FACILITY_BOSS ; = 1 (first object_event = sprite slot 1)

ProceduralFacility_Object:
	db 46 ; border block (facility void/solid tile, player-area never uses this - see procedural_facility_gen.asm)

	def_warp_events
	warp_event 19, 34, LAST_MAP, 1 ; tile coords = block (9,17) = cell (4,8), the generator's
	                               ; HuntAndKill entrance cell (same as forest)
	warp_event  1,  0, LAST_MAP, 1 ; exit left tile  - runtime-patched to (4*exitI+2, 0)
	warp_event  2,  0, LAST_MAP, 1 ; exit right tile - runtime-patched to (4*exitI+3, 0)

	def_bg_events
	bg_event 19, 35, TEXT_PROCEDURALFACILITY_SIGN

	def_object_events
	; Boss pokemon first (slot 1) so toggle-table lookup via hActiveSpriteIndex
	; hits slot 1 after battle and HideObject works correctly via EndTrainerBattle.
	; Species (PINSIR) and level below are placeholders patched at runtime by
	; the facility generator (custom_functions/procedural_facility_gen.asm) via
	; wMapSpriteExtraData. Position is also runtime-patched to the exit.
	object_event 18, 38, SPRITE_MONSTER, STAY, DOWN, TEXT_PROCEDURALFACILITY_BOSS, PINSIR, 5 | OW_POKEMON

	; 4 wild area pokeballs (slots 2-5) - random item per dead-end target.
	; Position runtime-patched via wSprite0{N}StateData2MapY/MapX.
	object_event 10, 10, SPRITE_POKE_BALL, STAY, NONE, TEXT_PROCEDURALFACILITY_WILD_AREA_POKEBALL_1, 0
	object_event 10, 10, SPRITE_POKE_BALL, STAY, NONE, TEXT_PROCEDURALFACILITY_WILD_AREA_POKEBALL_2, 0
	object_event 10, 10, SPRITE_POKE_BALL, STAY, NONE, TEXT_PROCEDURALFACILITY_WILD_AREA_POKEBALL_3, 0
	object_event 10, 10, SPRITE_POKE_BALL, STAY, NONE, TEXT_PROCEDURALFACILITY_WILD_AREA_POKEBALL_4, 0

	def_warps_to PROCEDURAL_FACILITY
