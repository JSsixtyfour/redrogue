object_const_def
	const_export ROGUE_REWARD_POKEBALL_1
    const_export ROGUE_REWARD_POKEBALL_2
    const_export ROGUE_REWARD_POKEBALL_3

RewardRoom_Object:
	db $F ; border block

	def_warp_events
	warp_event $8, $7, LAST_MAP, 2
	warp_event $9, $7, LAST_MAP, 3

	def_bg_events

	def_object_events
	object_event  5,  5, SPRITE_POKE_BALL, STAY, NONE, TEXT_ROGUE_REWARD_POKEBALL_1
	object_event  8,  5, SPRITE_POKE_BALL, STAY, NONE, TEXT_ROGUE_REWARD_POKEBALL_2
	object_event 11,  5, SPRITE_POKE_BALL, STAY, NONE, TEXT_ROGUE_REWARD_POKEBALL_3
    
	def_warps_to OAKS_LAB
