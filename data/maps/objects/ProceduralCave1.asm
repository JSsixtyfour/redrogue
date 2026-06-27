ProceduralCave1_Object:
	db 46 ; border block (solid_wall, confirmed impassable in both classification passes)

	def_warp_events
	warp_event 19, 38, LAST_MAP, 1 ; tile coords = block (9,19), matches generator's hardcoded entrance
	warp_event 15, 15, LAST_MAP, 1

	def_bg_events

	def_object_events
	; 4 wild area pokeballs - random item per dead-end target, see
	; custom_functions/procedural_cave_gen.asm's GenerateProceduralCave.
	; Placeholder coords (arbitrary, inside the map) - the generator
	; runtime-patches wSprite0{N}StateData2MapY/MapX to the real dead-end
	; tile position for each, the same proven pattern as the exit warp's
	; wWarpEntries patch. These become sprite slots 1-4 (first 4 declared
	; objects) - see engine/overworld/toggleable_objects.asm's
	; IsObjectHidden and engine/events/pick_up_item.asm's RandomPickUpItem.
	object_event 10, 10, SPRITE_POKE_BALL, STAY, NONE, TEXT_PROCEDURALCAVE1_WILD_AREA_POKEBALL_1, 0
	object_event 10, 10, SPRITE_POKE_BALL, STAY, NONE, TEXT_PROCEDURALCAVE1_WILD_AREA_POKEBALL_2, 0
	object_event 10, 10, SPRITE_POKE_BALL, STAY, NONE, TEXT_PROCEDURALCAVE1_WILD_AREA_POKEBALL_3, 0
	object_event 10, 10, SPRITE_POKE_BALL, STAY, NONE, TEXT_PROCEDURALCAVE1_WILD_AREA_POKEBALL_4, 0

	; Boss pokemon - mirrors the vanilla legendary-bird pattern (e.g.
	; PowerPlant's Zapdos: `object_event 4, 5, SPRITE_BIRD, STAY, UP,
	; TEXT_POWERPLANT_ZAPDOS, ZAPDOS, 50 | OW_POKEMON`, confirmed still
	; intact in our own data/maps/objects/PowerPlant.asm despite that map
	; being heavily modified elsewhere) - the OW_POKEMON flag bit ($80, on
	; the level byte) makes engine/overworld/home/trainers.asm's
	; EngageMapTrainer treat the "trainer class" slot as a real species and
	; start a WILD battle at the given level instead of looking up a
	; trainer's party. Confirmed Zapdos/the PowerPlant Voltorbs need NO
	; TrainerHeader entry for this - it's driven purely by this object's
	; compiled byte data, not the sight-engagement system.
	;
	; FIXED POSITION FOR TESTING (2026-06-26, explicit user request): tile
	; (18,38), directly in front of the static entrance warp (19,38) - no
	; runtime position patch needed since this is declared statically, same
	; reasoning as why the entrance itself never needed one.
	;
	; Species (0) and level (0 | OW_POKEMON) below are placeholders -
	; GenerateProceduralCave patches wMapSpriteExtraData for this sprite's
	; slot (5th declared object_event here) with a freshly-rolled random
	; species + an appropriate level each time the cave generates. Sprite
	; is a generic SPRITE_BIRD placeholder for now - matching the rolled
	; species' actual appearance is a separate, not-yet-implemented step
	; (see [[redrogue-procedural-cave]]).
	object_event 18, 38, SPRITE_BIRD, STAY, RIGHT, TEXT_PROCEDURALCAVE1_BOSS, 0, 0 | OW_POKEMON

	def_warps_to PROCEDURAL_CAVE_1
