	object_const_def
	const_export SAFFRONGYM_SABRINA
	const_export SAFFRONGYM_CHANNELER1
	const_export SAFFRONGYM_YOUNGSTER1
	const_export SAFFRONGYM_CHANNELER2
	const_export SAFFRONGYM_YOUNGSTER2
	const_export SAFFRONGYM_GYM_GUIDE

SaffronGym_Object:
	db $2e ; border block

	def_warp_events
	warp_event  8, 17, LAST_MAP, 3      ; 1
	warp_event  9, 17, LAST_MAP, 3      ; 2
	warp_event  1,  3, SAFFRON_GYM, 18; 3
	warp_event  5,  3, SAFFRON_GYM, 21; 4
	warp_event  1,  5, SAFFRON_GYM, 18 ; 5
	warp_event  5,  5, SAFFRON_GYM, 23; 6
	warp_event  8, 0,  LAST_MAP, 3      ; 7
	warp_event  9, 0,  LAST_MAP, 3      ; 8
	warp_event  1, 11, SAFFRON_GYM, 6; 9
	warp_event  5, 11, SAFFRON_GYM, 14; 10
	warp_event  1, 15, SAFFRON_GYM, 31; 11
	warp_event  5, 15, SAFFRON_GYM, 24; 12
	warp_event  1, 17, SAFFRON_GYM, 29; 13
	warp_event  5, 17, SAFFRON_GYM, 22; 14 - left off
	warp_event  9,  9, SAFFRON_GYM, 27; 15
	warp_event 11,  9, SAFFRON_GYM, 4; 16
	warp_event  9, 11, SAFFRON_GYM, 8; 17
	warp_event 11,  5, SAFFRON_GYM, 5; 18
	warp_event 11, 11, SAFFRON_GYM, 5 ; 19
	warp_event 11, 15, SAFFRON_GYM, 32 ; 20
	warp_event 15,  3, SAFFRON_GYM, 4; 21
	warp_event 19,  3, SAFFRON_GYM, 14; 22
	warp_event 15,  5, SAFFRON_GYM, 6 ; 23
	warp_event 19,  5, SAFFRON_GYM, 12 ; 24
	warp_event 15,  9, SAFFRON_GYM, 21 ; 25
	warp_event 19,  9, SAFFRON_GYM, 30 ; 26
	warp_event 15, 11, SAFFRON_GYM, 15 ; 27
	warp_event 19, 11, SAFFRON_GYM, 7 ; 28
	warp_event 15, 15, SAFFRON_GYM, 13 ; 29
	warp_event 19, 15, SAFFRON_GYM, 20 ; 30
	warp_event 15, 17, SAFFRON_GYM, 11 ; 31
	warp_event 19, 17, SAFFRON_GYM, 20 ; 32

	def_bg_events

	def_object_events
	object_event 10,  1, SPRITE_GIRL, STAY, DOWN, TEXT_SAFFRONGYM_SABRINA, OPP_SABRINA, 1
	object_event  3, 14, SPRITE_CHANNELER, STAY, DOWN, TEXT_SAFFRONGYM_CHANNELER1, OPP_CHANNELER, 1
	object_event 17,  2, SPRITE_YOUNGSTER, STAY, DOWN, TEXT_SAFFRONGYM_YOUNGSTER1, OPP_PSYCHIC_TR, 1
	object_event  3,  2, SPRITE_CHANNELER, STAY, DOWN, TEXT_SAFFRONGYM_CHANNELER2, OPP_CHANNELER, 1
	object_event 17, 14, SPRITE_YOUNGSTER, STAY, DOWN, TEXT_SAFFRONGYM_YOUNGSTER2, OPP_PSYCHIC_TR, 1
	object_event 10, 15, SPRITE_GYM_GUIDE, STAY, DOWN, TEXT_SAFFRONGYM_GYM_GUIDE

	def_warps_to SAFFRON_GYM
