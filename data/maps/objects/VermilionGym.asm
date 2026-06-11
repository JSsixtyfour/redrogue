	object_const_def
	const_export VERMILIONGYM_LT_SURGE
    const_export VERMILIONGYM_SAILOR
	const_export VERMILIONGYM_SUPER_NERD
    const_export VERMILIONGYM_GENTLEMAN
    const_export VERMILIONGYM_BIKER
	const_export VERMILIONGYM_GYM_GUIDE

VermilionGym_Object:
	db $3 ; border block

	def_warp_events
	warp_event  4, 17, LAST_MAP, 4
	warp_event  5, 17, LAST_MAP, 4
    warp_event  4, 0,  INDIGO_PLATEAU_LOBBY, 1
	warp_event  5, 0,  INDIGO_PLATEAU_LOBBY, 1

	def_bg_events

	def_object_events
	object_event  5,  1, SPRITE_ROCKER, STAY, DOWN, TEXT_VERMILIONGYM_LT_SURGE, OPP_LT_SURGE, 1
	object_event  2, 10, SPRITE_SAILOR, STAY, RIGHT, TEXT_VERMILIONGYM_SAILOR, OPP_SAILOR, 1
    object_event  7,  8, SPRITE_SUPER_NERD, STAY, LEFT, TEXT_VERMILIONGYM_SUPER_NERD, OPP_ROCKER, 1
    object_event  7,  6, SPRITE_GENTLEMAN, STAY, LEFT, TEXT_VERMILIONGYM_GENTLEMAN, OPP_GENTLEMAN, 1
	object_event  4,  5, SPRITE_HIKER, STAY, RIGHT, TEXT_VERMILIONGYM_BIKER, OPP_BIKER, 1
	object_event  4, 14, SPRITE_GYM_GUIDE, STAY, DOWN, TEXT_VERMILIONGYM_GYM_GUIDE

	def_warps_to VERMILION_GYM
