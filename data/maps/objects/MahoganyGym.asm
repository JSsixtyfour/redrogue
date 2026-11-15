	object_const_def
	const_export MAHOGANYGYM_PRYCE
	const_export MAHOGANYGYM_COOLTRAINER_M
	const_export MAHOGANYGYM_COOLTRAINER_F
	const_export MAHOGANYGYM_HIKER
	const_export MAHOGANYGYM_GYM_GUIDE

MahoganyGym_Object:
	db $3 ; border block

	def_warp_events
	warp_event  4, 13, WARP_NO_RETURN, 3
	warp_event  5, 13, WARP_NO_RETURN, 3
	warp_event  4, 0,  INDIGO_PLATEAU_LOBBY, 1
	warp_event  5, 0,  INDIGO_PLATEAU_LOBBY, 1

	def_bg_events

	def_object_events
; No Johto leader overworld art exists. SPRITE_GRAMPS fits Pryces elderly
; Ice-type gym leader design.
	object_event  5,  2, SPRITE_GRAMPS, STAY, DOWN, TEXT_MAHOGANYGYM_PRYCE, OPP_PRYCE, 1
	object_event  7,  4, SPRITE_COOLTRAINER_M, STAY, LEFT, TEXT_MAHOGANYGYM_COOLTRAINER_M, OPP_COOLTRAINER_M, 2
	object_event  3,  6, SPRITE_COOLTRAINER_F, STAY, RIGHT, TEXT_MAHOGANYGYM_COOLTRAINER_F, OPP_COOLTRAINER_F, 3
	object_event  5,  9, SPRITE_HIKER, STAY, LEFT, TEXT_MAHOGANYGYM_HIKER, OPP_HIKER, 4
	object_event  6, 11, SPRITE_GYM_GUIDE, STAY, DOWN, TEXT_MAHOGANYGYM_GYM_GUIDE

	def_warps_to MAHOGANY_GYM
