	object_const_def
	const_export GOLDENRODGYM_WHITNEY
	const_export GOLDENRODGYM_COOLTRAINER_M2
	const_export GOLDENRODGYM_COOLTRAINER_M3
	const_export GOLDENRODGYM_COOLTRAINER_M4
	const_export GOLDENRODGYM_GYM_GUIDE

GoldenrodGym_Object:
	db $3 ; border block

	def_warp_events
	warp_event  2, 17, WARP_NO_RETURN, 3
	warp_event  3, 17, WARP_NO_RETURN, 3
	warp_event  8,  0,  INDIGO_PLATEAU_LOBBY, 1
	warp_event  9,  0,  INDIGO_PLATEAU_LOBBY, 1

	def_bg_events

	def_object_events
; No Johto leader overworld art exists. SPRITE_GIRL reads closest to Whitney.
	object_event  8,  3, SPRITE_GIRL, STAY, DOWN, TEXT_GOLDENRODGYM_WHITNEY, OPP_WHITNEY, 1
	object_event 17,  4, SPRITE_COOLTRAINER_M, STAY, LEFT, TEXT_GOLDENRODGYM_COOLTRAINER_M2, OPP_JR_TRAINER_M, 2
	object_event 13, 12, SPRITE_COOLTRAINER_M, STAY, RIGHT, TEXT_GOLDENRODGYM_COOLTRAINER_M3, OPP_JR_TRAINER_M, 3
	object_event  9,  6, SPRITE_COOLTRAINER_M, STAY, LEFT, TEXT_GOLDENRODGYM_COOLTRAINER_M4, OPP_JR_TRAINER_M, 4
	object_event  5, 15, SPRITE_GYM_GUIDE, STAY, DOWN, TEXT_GOLDENRODGYM_GYM_GUIDE

	def_warps_to GOLDENROD_GYM
