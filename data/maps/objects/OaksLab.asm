object_const_def
	const_export ROGUE_STARTER_POKEBALL_1
    const_export ROGUE_STARTER_POKEBALL_2
    const_export ROGUE_STARTER_POKEBALL_3

OaksLab_Object:
	db $3 ; border block

	def_warp_events
	warp_event  4, 11, LAST_MAP, 3
	warp_event  5, 11, LAST_MAP, 3

	def_bg_events

	def_object_events
    object_event  6,  3, SPRITE_POKE_BALL, STAY, NONE, TEXT_ROGUE_STARTER_POKEBALL_1
    object_event  7,  3, SPRITE_POKE_BALL, STAY, NONE, TEXT_ROGUE_STARTER_POKEBALL_2
    object_event  8,  3, SPRITE_POKE_BALL, STAY, NONE, TEXT_ROGUE_STARTER_POKEBALL_3
    
	def_warps_to OAKS_LAB
