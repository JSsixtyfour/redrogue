	object_const_def
	const_export FACILITY_BOSS ; = 1 (first object_event = sprite slot 1)

ProceduralFacility_Object:
	db $2E ; border block and generated black/solid void

	def_warp_events
	warp_event 19, 38, LAST_MAP, 1 ; south entry socket at generated block (9,19)
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

	; Fake item balls (slots 6-9). The placeholder positions are replaced by the
	; generator placement checkpoint; species and level are already patched at
	; every finalize from the battle-count-60 preload snapshot.
	object_event 10, 10, SPRITE_POKE_BALL, STAY, NONE, TEXT_PROCEDURALFACILITY_FAKE_BALL_1, VOLTORB, 5 | OW_POKEMON
	object_event 10, 10, SPRITE_POKE_BALL, STAY, NONE, TEXT_PROCEDURALFACILITY_FAKE_BALL_2, VOLTORB, 5 | OW_POKEMON
	object_event 10, 10, SPRITE_POKE_BALL, STAY, NONE, TEXT_PROCEDURALFACILITY_FAKE_BALL_3, VOLTORB, 5 | OW_POKEMON
	object_event 10, 10, SPRITE_POKE_BALL, STAY, NONE, TEXT_PROCEDURALFACILITY_FAKE_BALL_4, VOLTORB, 5 | OW_POKEMON

	def_warps_to PROCEDURAL_FACILITY
