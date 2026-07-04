object_const_def
    const_export WILD_AREA_BOSS ; = 1 (first object_event = sprite slot 1)

ProceduralCave1_Object:
	db 46 ; border block (solid_wall, confirmed impassable in both classification passes)

	def_warp_events
	warp_event 19, 38, LAST_MAP, 1 ; tile coords = block (9,19), matches generator's hardcoded entrance
	warp_event 15, 15, LAST_MAP, 1

	def_bg_events

	def_object_events
	; Boss pokemon first (slot 1) so toggle-table lookup via hActiveSpriteIndex
	; hits slot 1 after battle and HideObject works correctly via EndTrainerBattle.
	; Species (PINSIR) and level below are placeholders patched at runtime by
	; PCPlaceBoss (custom_functions/procedural_cave_gen.asm) via wMapSpriteExtraData.
	; Position is also runtime-patched to the exit ladder in PCFinalizeCave.
	; SPRITE_MONSTER is the most common follower-sprite category (~60% of all species).
	; Dynamic per-species sprite loading requires the follower branch's LoadFollowerSprite
	; to force-write tiles into the boss's VRAM slot - deferred until that branch merges.
	object_event 18, 38, SPRITE_MONSTER, STAY, DOWN, TEXT_PROCEDURALCAVE1_BOSS, PINSIR, 5 | OW_POKEMON

	; 4 wild area pokeballs (slots 2-5) - random item per dead-end target.
	; Position runtime-patched by PCPlaceWildAreaItems via wSprite0{N}StateData2MapY/MapX.
	; Standard toggle mechanism (toggleable_objects_for table) handles visibility.
	object_event 10, 10, SPRITE_POKE_BALL, STAY, NONE, TEXT_PROCEDURALCAVE1_WILD_AREA_POKEBALL_1, 0
	object_event 10, 10, SPRITE_POKE_BALL, STAY, NONE, TEXT_PROCEDURALCAVE1_WILD_AREA_POKEBALL_2, 0
	object_event 10, 10, SPRITE_POKE_BALL, STAY, NONE, TEXT_PROCEDURALCAVE1_WILD_AREA_POKEBALL_3, 0
	object_event 10, 10, SPRITE_POKE_BALL, STAY, NONE, TEXT_PROCEDURALCAVE1_WILD_AREA_POKEBALL_4, 0

	def_warps_to PROCEDURAL_CAVE_1
