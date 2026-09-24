	; Must match the object_event order below: toggleable_objects.asm keys
	; TOGGLE_SS_ANNE_B1F_CAPTAIN on SSANNEB1F_CAPTAIN as a slot number.
	object_const_def
	const_export SSANNEB1F_JR_TRAINER_M3
	const_export SSANNEB1F_JR_TRAINER_M4
	const_export SSANNEB1F_JR_TRAINER_M5
	const_export SSANNEB1F_JR_TRAINER_M6
	const_export SSANNEB1F_JR_TRAINER_M7
	const_export SSANNEB1F_POKE_BALL
	const_export SSANNEB1F_ROGUE_REWARD_POKEBALL_1
	const_export SSANNEB1F_ROGUE_REWARD_POKEBALL_2
	const_export SSANNEB1F_ROGUE_REWARD_POKEBALL_3
	const_export SSANNEB1F_ROGUE_TRADE_NPC
	const_export SSANNEB1F_CAPTAIN
	const_export SSANNEB1F_SAILOR

SSAnneB1F_Object:
	db $c ; border block

	def_warp_events
	warp_event 27,  5, WARP_NO_RETURN, 1
	warp_event 23,  3, SS_ANNE_B1F_ROOMS, 9
	warp_event 19,  3, SS_ANNE_B1F_ROOMS, 7
	warp_event 15,  3, SS_ANNE_B1F_ROOMS, 5
	warp_event 11,  3, SS_ANNE_B1F_ROOMS, 3
	warp_event  7,  3, SS_ANNE_B1F_ROOMS, 1
	warp_event  2,  4, INDIGO_PLATEAU_LOBBY, 1

	def_bg_events

	def_object_events
	; Slots 1-5 are padding so slots 6-10 match the rogue stage convention
	; (random item, reward balls 1-3, trade NPC; see IsObjectHidden). B1F's real
	; trainers live in SSAnneB1FRooms. They stand below the 8-row map, so
	; CheckSpriteAvailability's screen test never draws them.
	object_event  0, 32, SPRITE_COOLTRAINER_M, STAY, DOWN, TEXT_SSANNEB1F_JR_TRAINER_M3
	object_event  0, 32, SPRITE_COOLTRAINER_M, STAY, DOWN, TEXT_SSANNEB1F_JR_TRAINER_M4
	object_event  0, 32, SPRITE_COOLTRAINER_M, STAY, DOWN, TEXT_SSANNEB1F_JR_TRAINER_M5
	object_event  0, 32, SPRITE_COOLTRAINER_M, STAY, DOWN, TEXT_SSANNEB1F_JR_TRAINER_M6
	object_event  0, 32, SPRITE_COOLTRAINER_M, STAY, DOWN, TEXT_SSANNEB1F_JR_TRAINER_M7
	object_event 21,  4, SPRITE_POKE_BALL, STAY, NONE, TEXT_SSANNEB1F_RANDOM, 0
	object_event  5,  5, SPRITE_POKE_BALL, STAY, NONE, TEXT_SSANNEB1F_ROGUE_REWARD_POKEBALL_1
	object_event  7,  5, SPRITE_POKE_BALL, STAY, NONE, TEXT_SSANNEB1F_ROGUE_REWARD_POKEBALL_2
	object_event  9,  5, SPRITE_POKE_BALL, STAY, NONE, TEXT_SSANNEB1F_ROGUE_REWARD_POKEBALL_3
	object_event  5,  5, SPRITE_SUPER_NERD, STAY, DOWN, TEXT_SSANNEB1F_ROGUE_TRADE_NPC
	object_event  2,  5, SPRITE_CAPTAIN, STAY, LEFT, TEXT_SSANNEB1F_CAPTAIN
	object_event  3,  4, SPRITE_SAILOR, STAY, LEFT, TEXT_SSANNEB1F_SAILOR

	def_warps_to SS_ANNE_B1F
