	object_const_def
	const_export FUCHSIAGYM_KOGA
	const_export FUCHSIAGYM_ROCKER1
	const_export FUCHSIAGYM_ROCKER2
	const_export FUCHSIAGYM_ROCKER3
	const_export FUCHSIAGYM_ROCKER4
	const_export FUCHSIAGYM_GYM_GUIDE

FuchsiaGym_Object:
	db $3 ; border block

	def_warp_events
	warp_event  4, 17, LAST_MAP, 6
	warp_event  5, 17, LAST_MAP, 6
	warp_event  4, 0,  INDIGO_PLATEAU_LOBBY, 1
	warp_event  5, 0,  INDIGO_PLATEAU_LOBBY, 1

	def_bg_events

	def_object_events
	object_event  5,  2, SPRITE_KOGA, STAY, DOWN, TEXT_FUCHSIAGYM_KOGA, OPP_KOGA, 1
	object_event  7, 11, SPRITE_ROCKER, STAY, RIGHT, TEXT_FUCHSIAGYM_ROCKER1, OPP_JUGGLER, 1
	object_event  2,  9, SPRITE_ROCKER, STAY, DOWN, TEXT_FUCHSIAGYM_ROCKER2, OPP_JUGGLER, 1
	object_event  5,  5, SPRITE_ROCKER, STAY, LEFT, TEXT_FUCHSIAGYM_ROCKER3, OPP_JUGGLER, 1
	object_event  8,  6, SPRITE_ROCKER, STAY, DOWN, TEXT_FUCHSIAGYM_ROCKER4, OPP_TAMER, 1
	object_event  7, 15, SPRITE_GYM_GUIDE, STAY, DOWN, TEXT_FUCHSIAGYM_GYM_GUIDE

	def_warps_to FUCHSIA_GYM
