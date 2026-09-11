	object_const_def
	const_export ECRUTEAKGYM_MORTY
	const_export ECRUTEAKGYM_COOLTRAINER_M1
	const_export ECRUTEAKGYM_COOLTRAINER_M2
	const_export ECRUTEAKGYM_COOLTRAINER_M3
	const_export ECRUTEAKGYM_COOLTRAINER_M4
	const_export ECRUTEAKGYM_GYM_GUIDE

EcruteakGym_Object:
	db $3 ; border block

	def_warp_events
	warp_event  4, 13, WARP_NO_RETURN, 3
	warp_event  5, 13, WARP_NO_RETURN, 3
	warp_event  4, 0,  INDIGO_PLATEAU_LOBBY, 1
	warp_event  5, 0,  INDIGO_PLATEAU_LOBBY, 1

	def_bg_events

	def_object_events
; No Johto leader overworld art exists. SPRITE_CHANNELER fits Mortys Ghost-type,
; mystic-medium demeanor better than any generic trainer sprite.
	object_event  4,  1, SPRITE_CHANNELER, STAY, DOWN, TEXT_ECRUTEAKGYM_MORTY, OPP_MORTY, 1
	object_event  3,  7, SPRITE_COOLTRAINER_M, STAY, RIGHT, TEXT_ECRUTEAKGYM_COOLTRAINER_M1, OPP_JR_TRAINER_M, 1
	object_event  6,  6, SPRITE_COOLTRAINER_M, STAY, LEFT, TEXT_ECRUTEAKGYM_COOLTRAINER_M2, OPP_JR_TRAINER_M, 2
	object_event  3,  5, SPRITE_COOLTRAINER_M, STAY, RIGHT, TEXT_ECRUTEAKGYM_COOLTRAINER_M3, OPP_JR_TRAINER_M, 3
	object_event  6,  4, SPRITE_COOLTRAINER_M, STAY, LEFT, TEXT_ECRUTEAKGYM_COOLTRAINER_M4, OPP_JR_TRAINER_M, 4
	object_event  7, 10, SPRITE_GYM_GUIDE, STAY, DOWN, TEXT_ECRUTEAKGYM_GYM_GUIDE

	def_warps_to ECRUTEAK_GYM
