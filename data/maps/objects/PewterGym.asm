	object_const_def
	const_export PEWTERGYM_BROCK
	const_export PEWTERGYM_YOUNGSTER
    const_export PEWTERGYM_HIKER
    const_export PEWTERGYM_COOLTRAINER_M
	const_export PEWTERGYM_GYM_GUIDE

PewterGym_Object:
	db $3 ; border block

	def_warp_events
	warp_event  4, 13, WARP_NO_RETURN, 3
	warp_event  5, 13, WARP_NO_RETURN, 3
    warp_event  4, 0,  INDIGO_PLATEAU_LOBBY, 1
    warp_event  5, 0,  INDIGO_PLATEAU_LOBBY, 1

	def_bg_events

	def_object_events
	object_event  4,  1, SPRITE_SUPER_NERD, STAY, DOWN, TEXT_PEWTERGYM_BROCK, OPP_BROCK, 1
	object_event  3,  7, SPRITE_YOUNGSTER, STAY, RIGHT, TEXT_PEWTERGYM_YOUNGSTER, OPP_YOUNGSTER, 1
	object_event  6,  6, SPRITE_HIKER, STAY, LEFT, TEXT_PEWTERGYM_HIKER, OPP_HIKER, 1
	object_event  6,  4, SPRITE_COOLTRAINER_M, STAY, LEFT, TEXT_PEWTERGYM_COOLTRAINER_M, OPP_JR_TRAINER_M, 1
	object_event  7, 10, SPRITE_GYM_GUIDE, STAY, DOWN, TEXT_PEWTERGYM_GYM_GUIDE

	def_warps_to PEWTER_GYM
